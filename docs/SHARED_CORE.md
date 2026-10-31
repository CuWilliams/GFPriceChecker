# Shared Domain Core (GFCore) — Plan and Audit

**Goal:** move the app's platform-independent behaviour into a Foundation-only Swift package,
`GFCore`. That covers the differential arithmetic, reporting, CSV, receipt parsing, OCR price
ranking, validation and the backup schema. Pin the package's behaviour with language-neutral
test vectors in shared-docs, so that a future Android app can share it. Android can either
compile GFCore with the Swift SDK for Android, or reimplement it in Kotlin and pass the same
vectors.

**Status:** Stage 1 complete. 1a (#65) fixed audit items 1, 5 and 6 below; 1b (#66) fixed
items 2, 3 and 4. Item 2's fr-CA example was wrong: an English-only app resolves fr-CA to
`en_CA`, which writes `.`, so no Canadian locale hit it. The fixed machine format stays because a
CSV should not depend on the device locale at all, but the app is Canada-only and non-Canadian
regions are out of scope for testing.
Stage 2 is complete: 2a (#67) created `Packages/GFCore` and moved `Pricing` into it. 2b (#68)
moved `Reporting` and `CSV`. Every row of the duplication table below is now resolved: the
dashboard, export preview, CSV, PDF and `Receipt.totalDifferential` all read `ReportTotals`, and
the PDF prints its grand-total line at last. `ReportReconciliationTests` runs the demo dataset
through each surface and checks they agree. It found one gap the spec didn't settle: the CSV
rounds each row's size-adjusted figure to the cent, so on the demo dataset that column sums to
$355.57 against the $355.58 the PDF and dashboard show. Resolved: a total rounds the final sum,
not the rows, which is what `ReportTotals` already does. PRODUCT_DEFINITION.md §3 now says so,
and the test pins it.
2c (#69) moved `ReceiptParsing` and `PriceRanking`. `OCRService` now holds only the Vision
requests and the mapping to `RecognizedText`. `ReceiptParserService` is deleted rather than
kept as a singleton, because nothing platform-bound was left in it, and callers use
`ReceiptParser` directly. `TextOrdering` carries the reading order, so the two orders now sit
side by side: the tap-to-select list sorts by a box's centre, and receipt text sorts by its
origin. Vision's iOS 18 Swift API has its own `RecognizedText` and `NormalizedRect`, so
`OCRService` writes the core's as `GFCore.RecognizedText` and `GFCore.NormalizedRect`. Every parser now has tests, and they turned up four gaps, each pinned by a "Known gap"
test for #36 and #22 to flip:
on a product-first receipt with several items, the look-behind pass pairs each price with the
name *below* it. The discount keyword `off` rejects "COFFEE". Abbreviations expand inside
words, so "snacks" becomes "snacookies". And the Levenshtein fallback in name matching is
unreachable: the Jaccard branch returns first whenever either name has a word. That fallback
would also trap on an empty string (`for i in 1...m`), so it needs a guard before anything
reaches it. All four were moved unchanged, under the fix-first rule.
2d (#70) moved `Validation` and the `Backup` schema. The rules return a core `ValidationError`
that says what is wrong, and the app's `AppError.init(_: ValidationError)` keeps every message
as it was. That includes a gap the new tests pin for a later fix: most messages ride on
`AppError.invalidProductName`, which appends "cannot be empty", so an oversized note reads
"Notes are too long (max 1000 characters) cannot be empty". Email validation uses `Regex`,
and it agrees with the old `NSPredicate` on everything tested except two ICU case-folding
quirks (`ſ` and the Kelvin sign `K` matching `[A-Z]`), which it now rejects. Date checks
take `now` and a `Calendar`. `BackupFormat` holds the coders, the `"1.0"` version gate and
the decimal-string conversions, and `ProductPairBackup.effectiveQuantity` the legacy
`quantity ?? 1` rule. `BackupFormatTests` decodes both `Tools/Demo` datasets and a
pre-quantity backup with the core alone, and the demo dataset totals $278.03 and $355.58,
as before.
Stage 3 is complete (#71). The vectors are in shared-docs under `gfpricechecker/vectors/`,
with a README of their conventions, and PRODUCT_DEFINITION.md §8 makes them normative.
`VectorTests` runs every file against the vendored copy, and fails if a file is added that it
does not run. Writing them settled one more thing the spec had left open: rounding is half-even,
as iOS's formatters have always done, so $0.465 shows as $0.46. §3 now says so, and several
vectors sit on a half cent to hold any platform to it. Behaviour pinned only as a known gap,
above, is kept out of the vectors so it does not become a rule. `scripts/sync-vectors.sh`
updates the copy, and `--check` runs from the tracked `.githooks/pre-push`.
This document grounds Track F and records the audit that sized it.
The issues under the **Shared Core (GFCore)** milestone track progress, and this document
explains the reasoning behind them.

**Context:** this track runs before the 1.0 App Store submission (#49). The audit found that the
iOS app departs from
[`PRODUCT_DEFINITION.md`](https://github.com/CuWilliams/shared-docs/blob/main/gfpricechecker/PRODUCT_DEFINITION.md)
in ways that change exported numbers, so the fixes in Stage 1 matter for 1.0 regardless of
Android.

---

## 1. Decisions

- **Swift core plus test vectors, not Kotlin Multiplatform.** The tested Swift code stays where it
  is and the iOS build gets no Gradle toolchain. The vectors are the contract either way, so the
  Android implementation choice can be made later.
- **Fix first, then extract.** Behaviour fixes land in their own PRs, so the extraction PRs only
  move code that is already correct. A PR that does both makes a moved line impossible to tell
  from a changed one.
- **Each stage is a PR that can be merged on its own and leaves `main` shippable.**

**Out of scope:** SwiftData models, Vision/VisionKit calls, PDF drawing, image storage,
navigation (Track B stage 4, #42), Swift 6 language mode, and lifting `ReceiptCaptureView` into
a view model.

---

## 2. What the audit found (2026-10-30, `main` at d4f8e11)

### The logic is concentrated but bound to platform types

- The formulas are computed properties on `@Model ProductPair` (`Models/ProductPair.swift:143–203`).
  Every consumer takes `[ProductPair]`, so every test that touches arithmetic needs an in-memory
  `ModelContainer`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes every app-target type `@MainActor`.
  A local package does not inherit that setting. Its types start nonisolated, which suits value
  types that conform to `Sendable`.
- `ReceiptParserService` has almost no coupling: only `ProductMatchResult.productPair` refers to
  the model. `OCRService` has its scoring math written inline in loops over
  `VNRecognizedTextObservation`, so it needs `(text, confidence, box)` values pulled out of it.
- `ValidationRules` is pure apart from `validateEmail`, which uses `NSPredicate`, and it returns
  `AppError`, which carries user-facing strings.
- The backup DTOs (`DataBackupService.swift:31–92`) are pure Codable types and can move as they
  are.

### Where iOS breaks PRODUCT_DEFINITION.md

A shared core would copy these over unless they are fixed first:

1. `Receipt.totalDifferential` (`Models/Receipt.swift:69`) sums the per-unit `differential` rather
   than `extendedDifferential`. `ReceiptDetailView.swift:95` then shows the total through string
   interpolation.
2. The CSV's number and date formatting follows the device locale (`CSVExportService.swift:155,162`).
   Under fr-CA the decimal separator becomes `,`, which breaks the file.
3. The CSV's unit price columns (`CSVExportService.swift:133–136`) are raw $/g rounded to two
   places, where §4 calls for $/100 g. The column headed "Unit Price Differential" actually holds
   `normalizedDifferential`, the per-package figure, not the rate. The app uses that misleading
   label everywhere, and `CaptureFlowViewModel.unitPriceDifferential` repeats it.
4. The PDF formats money through `Double` (`PDFGeneratorService.swift:1123–1137`).
5. When no product has size data, the normalized total is `nil` in `ExportView:117` but `0` in
   `ReportViewModel` and the PDF.
6. Nothing asserts the spec's worked example: GF $7.99 / 400 g vs regular $3.99 / 675 g gives $5.63.

The receipt fuzzy matching (Levenshtein and Jaccard), which the spec calls behaviour worth
copying, has no production callers and no tests. Wiring it up belongs to #36 and #22. Stage 2
brings it under test. Done in 2c (#69).

### Duplicated arithmetic

All resolved in 2b (#68), except the last row, resolved in 2a (#67). The locations are as
found by the audit, before either.

| Computation | Locations |
|---|---|
| Sum of `extendedDifferential` | `ReportViewModel:67`, `CSVExportService:213`, `PDFGeneratorService:1334` and inline at 645, 755, 1004, `ExportView:116` |
| Normalized total and excluded count | `ReportViewModel:103`, `PDFGeneratorService:1341` and inline at 643, 753, `ExportView:117` — **since #65, all call the static `ReportViewModel.calculateTotalNormalizedDifferential`** |
| Category grouping | `ReportViewModel:135,150`, `PDFGeneratorService:418–430` |
| Monthly grouping | `ReportViewModel:181,200`, `PDFGeneratorService:473–487` |
| Year filter | `ReportViewModel:38,48`, `ExportView:~108`, `DateRangePreset` in `AppSettings` |
| Differential formulas | `ProductPair:143–177`, `CaptureFlowViewModel:505–520` |

### Test coverage

There are no tests for `extractStoreName`, `extractDate`, `extractLineItems`, `matchProducts`,
Levenshtein or Jaccard, `rankingScore` on its own, CSV escaping and number formatting, most of
`ValidationRules`, `DateRangePreset`, or `Receipt.totalDifferential`. There are no
cross-platform fixtures anywhere. The closest thing is `Tools/Demo/demo-dataset.json`, which is a
real backup-format file.

2c (#69) added tests for the parsers, matching, Levenshtein, Jaccard and `rankingScore`, in
`ReceiptParserTests`, `ProductMatchingTests` and `PriceRankingTests`. 2d (#70) added
`ValidationTests`, covering every rule, and `BackupFormatTests`.

---

## 3. Stages

### Stage 1: Spec conformance (current structure)

Each fix gets a Swift Testing test, and each test is shown to fail before its fix.

- `Receipt.totalDifferential` sums extended figures and is shown with
  `.formatted(.currency(code: "CAD"))`.
- The CSV writes numbers and dates as machine formats (`en_US_POSIX`, no grouping separator).
- The CSV unit price columns follow §4. The column holding `normalizedDifferential`, the matching
  label in the UI and the `CaptureFlowViewModel` property all take the spec's name. If the column
  list changes, §6 of PRODUCT_DEFINITION.md is updated too.
- The PDF formats money as Decimal.
- Every place follows the spec's rule that missing size data means no value.
- The worked example is asserted.

### Stage 2: The `GFCore` package

`Packages/GFCore` is a local package (swift-tools 6.0, iOS 18 / macOS 15), added to the Xcode
project as an `XCLocalSwiftPackageReference`. **Boundary rule:** it imports Foundation only. No
SwiftUI, UIKit, SwiftData, Vision, PDFKit, CoreGraphics or `NSPredicate`.

| Area | Moved from | Shape in core |
|---|---|---|
| `Pricing` | `SizeUnit` and formulas in `ProductPair.swift:14–35,143–203`; parsing and back-calculation in `CaptureFlowViewModel.swift:373–520` | A `PricingInputs` value struct |
| `Reporting` | `ReportViewModel.swift:38–258`, PDF grouping and totals, `ExportView:108–118`, `DateRangePreset` | `ReportCalculator` over `[ReportRow]`, with an explicit `Calendar` |
| `CSV` | `CSVExportService.swift` | `CSVExporter.generate(rows:) -> String` |
| `ReceiptParsing` | `ReceiptParserService.swift` | Same logic, matching against a `MatchCandidate` value |
| `PriceRanking` | `OCRService.swift:15–129,194,257–293,450–533` (math and regexes only) | Functions over `RecognizedText(text, confidence, box)` |
| `Validation` | `ValidationRules.swift` | A core `ValidationError` enum that the app maps to `AppError`. Email validation uses `Regex` |
| `Backup` | DTOs and coder configuration in `DataBackupService.swift` | Codable schema and the version gate |

App-side adapters keep the call sites stable:

- `ProductPair` gets `pricing: PricingInputs` and `reportRow: ReportRow`, and its existing computed
  properties forward to the core.
- `ReportViewModel`, `PDFGeneratorService`, `ExportView` and `CSVExportService` become thin
  wrappers. **The duplicated sums and grouping are deleted, not kept.**
- The PDF gets its grand-total line. `drawGrandTotals` is reachable only from
  `drawTransactionPages`, which nothing calls (found in #65), so the report has never printed
  one. Wire it into `drawTransactionAndReceiptPages` from the core's totals, and delete
  `drawTransactionPages`.
- `OCRService` maps `VNRecognizedTextObservation` to `RecognizedText`.
- The singletons stay for now. Only the logic inside them moves.

Pure tests move to `Packages/GFCore/Tests` and run with `swift test` on macOS, with no simulator.
Tests that need SwiftData or Vision stay in `GFPriceCheckerTests`.

### Stage 3: Cross-platform test vectors

- The source of truth is `shared-docs/gfpricechecker/vectors/`, holding `pricing.json`,
  `reporting.json`, `csv.json`, `receipt-parsing.json`, `price-ranking.json`, `validation.json`
  and `backup/`. Every file is plain input and expected output, with decimals written as strings.
- A copy is vendored at `Packages/GFCore/Tests/GFCoreTests/Vectors/`. `scripts/sync-vectors.sh`
  copies it over, and `--check` fails if the two differ.
- PRODUCT_DEFINITION.md declares the vectors normative.

---

## 4. Execution

There is one issue per session, under the **Shared Core (GFCore)** milestone, as sub-issues of
the Track F epic. Dependencies are recorded with GitHub's blocked-by links.

| Issue | Covers | Depends on |
|---|---|---|
| 1a | Receipt total, missing-size rule, worked example | — |
| 1b | CSV locale and unit columns, PDF Decimal formatting, label rename | — |
| 2a | Package scaffold, `Pricing`, `ProductPair` adapter, boundary rule in `claude.md` | 1a |
| 2b | `Reporting` and `CSV`, removing duplicates, reconciliation test | 2a, 1b |
| 2c | `ReceiptParsing` and `PriceRanking`, tests for the untested parsers | 2a |
| 2d | `Validation` and the `Backup` schema | 2a |
| 3 | Vectors in shared-docs, vendored copy, sync check | 2b, 2c, 2d |

**In each session:**

1. Read this document and the issue.
2. Branch as `claude/issue-N-<slug>-<id>`.
3. Prove each new test fails before its fix.
4. Finish green with a zero-warning build.
5. Open a PR that says `Closes #N`.

Documentation updates are part of each issue's acceptance criteria.

**Interaction with Track B:** finish 1b before pipeline stages 5–7 (#43–45) record anything,
because the label rename changes what's on screen. Otherwise the two tracks barely overlap.

---

## 5. Verification, across the whole track

- `cd Packages/GFCore && swift test` passes.
- The app test suite passes. The command is in `claude.md` under Testing Strategy.
- A reconciliation test checks that, for the demo dataset, the CSV, report and PDF totals are
  equal.
- `DataBackupRoundTripTests` still passes, including the legacy import. Importing
  `demo-dataset.json` gives the same totals before and after.
- No reductions over `extendedDifferential` remain in `PDFGeneratorService` or `ExportView`.
- On a device: export the CSV and PDF, open the CSV in Numbers, and check the renamed labels. Do a TestFlight build after Stage 2, before submitting 1.0.
