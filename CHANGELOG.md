# Changelog

Release history for the **GF PriceChecker iOS app**.

Changes to the marketing website are tracked separately in the
[website repository](https://github.com/CuWilliams/GFPriceChecker.github.io).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Versioning

The app carries two numbers, both set in `GFPriceChecker.xcodeproj/project.pbxproj` and read at
runtime by the About screen in `Views/Settings/SettingsView.swift`:

- **`MARKETING_VERSION`** (`CFBundleShortVersionString`) — the version a user sees. `1.0`.
- **`CURRENT_PROJECT_VERSION`** (`CFBundleVersion`) — the build number. Increments on every
  TestFlight upload, and App Store Connect rejects a repeat.

Until 1.0 reaches the App Store, every build is a pre-release of it, and tags say so:
`v1.0.0-build.9` is build 9 of an unshipped `1.0.0`. These sort correctly and leave the bare
`v1.0.0` for the App Store release itself. After that, ordinary semantic versioning on
`MARKETING_VERSION`.

- **Minor** (`1.0.0` → `1.1.0`) — a new capability, or a substantive change to an existing one.
- **Patch** (`1.1.0` → `1.1.1`) — fixes and corrections with no new capability.
- **Major** — a change in what the app is for, or a data model users cannot migrate across.

Every TestFlight upload is a release and gets a tag. Work that merges to `main` without an upload
belongs under `[Unreleased]` until one happens.

To cut a release: move the `[Unreleased]` entries below into a new version heading, bump
`CURRENT_PROJECT_VERSION` in both app-target configurations, write the TestFlight "What to Test"
notes as `docs/RELEASE_NOTES_BUILD_<n>.md`, then tag `main` and publish a matching GitHub Release
so the two don't drift apart.

```
git tag -a v1.0.0-build.9 -m "Build 9 — short description of the release"
git push origin v1.0.0-build.9
gh release create v1.0.0-build.9 --title "Build 9 (v1.0) - Short description" \
  --notes-file docs/RELEASE_NOTES_BUILD_9.md --prerelease
```

`docs/RELEASE_NOTES_BUILD_*.md` is a separate document with a separate audience: it is written for
testers and pasted into TestFlight. This changelog is written for the people working on the repo.
Neither replaces the other.

---

## [Unreleased]

Nothing yet.

---

## [1.0.0-build.9] - 2026-09-14

Nine pull requests, none of which had a build behind them. Build 8 shipped in July; the
purchase-quantity work merged in August and sat unreleased, and the scripted demo pipeline's first
three stages landed in September.

### Added
- **Purchase quantity on product pairs** ([#37](https://github.com/CuWilliams/GFPriceChecker/pull/37)).
  Buying three of the same gluten-free product meant re-running the photo and OCR capture three
  times. A pair now carries a count. The per-unit figures keep their meaning — `differential` and
  the unit-price rates still describe a single unit, because three loaves cost the same per gram —
  and totals go through new `extendedDifferential` / `extendedNormalizedDifferential` properties.
  Every aggregation in `ReportViewModel`, `CSVExportService` and `PDFGeneratorService` was
  converted, both exports gained a Qty column, averages are now per unit purchased rather than per
  pair, and the library list carries an `xN` badge. Quantity is editable from the manual entry and
  edit form; guided capture saves 1.
- **A capture flow that runs without a camera**
  ([#50](https://github.com/CuWilliams/GFPriceChecker/pull/50)). `DocumentScannerView` now chooses
  between the real scanner and `SubstituteScannerView`, so both capture flows can be completed in
  the Simulator. Device behaviour is unchanged and all three call sites are untouched. Adds
  `SampleScanImages` (DEBUG, drawn with Core Graphics — nothing binary in the repo) and
  `ScannerImageProvider`, the hook a demo script will drive.
- **Simulator seeding from a scrubbed dataset**
  ([#52](https://github.com/CuWilliams/GFPriceChecker/pull/52)). `Tools/Demo/scrub_backup.py` turns
  a real device backup into a publishable one — placeholder settings, chain-only store names,
  redrawn receipt images, regenerated OCR text — and verifies its own output, scanning every string
  for the shapes personal information takes. `Tools/Demo/seed.sh` plus `Dev/DemoSeed.swift` put the
  Simulator into that state in one command. The 28 MB dataset is committed.
- **`CaptureFlowViewModel`** ([#53](https://github.com/CuWilliams/GFPriceChecker/pull/53)). The flow
  state and handlers lifted out of `ProductCaptureFlowView`, which drops from 986 to 516 lines and
  now only draws. Services sit behind injectable closures, so a test can run a whole capture with
  canned OCR results and no Vision framework.
- **Backup round-trip and schema-canary tests**
  ([#35](https://github.com/CuWilliams/GFPriceChecker/pull/35)). `DataBackupService` hand-duplicates
  the model's field list into its DTOs, and a mismatch fails silently — it compiles, it ships, and
  the loss surfaces only when a user restores. That had already happened once, to unit pricing. The
  canaries reflect over the model and trip the moment a property is declared.

### Changed
- **Minimum iOS version is now 18.0**, down from 26.0
  ([#55](https://github.com/CuWilliams/GFPriceChecker/pull/55)). Zero source changes were needed —
  the audit found no `@available` gates, no Liquid Glass API and no SwiftData schema versioning to
  unwind. An appearance pass over 24 screenshots, with an iOS 26 control on the same device model,
  found iOS 18 a sound render target: nothing truncates or overlaps. iOS 26 devices are unaffected,
  since Liquid Glass is gated on the linked SDK.
- The PDF transaction table's headers, column widths and row data were three parallel arrays
  duplicated across two methods, and are now shared constants
  ([#37](https://github.com/CuWilliams/GFPriceChecker/pull/37)).
- `SampleScanImages` draws its receipt in two columns by default, the way receipts actually print,
  rather than in the single-space layout that existed only to keep the old parser working
  ([#54](https://github.com/CuWilliams/GFPriceChecker/pull/54)).

### Fixed
- **Receipt totals are found on normally-printed receipts**
  ([#54](https://github.com/CuWilliams/GFPriceChecker/pull/54), fixes
  [#51](https://github.com/CuWilliams/GFPriceChecker/issues/51)). `extractTotal` required the word
  "TOTAL" and a `$`-prefixed amount on the same OCR line. Real receipts satisfy neither half — they
  print the amount bare, right-aligned into a second column that Vision returns as a separate
  observation — so every scan of an ordinary receipt silently skipped the total prefill. The `$` is
  now optional and a label with no amount falls through one line, accepted only if that line is
  nothing but an amount. A `nonTotalLabels` guard stops `TOTAL SAVINGS 3.40` claiming the total now
  that a bare amount qualifies.
- **The CSV export preview clipped its own header and footer**
  ([#56](https://github.com/CuWilliams/GFPriceChecker/pull/56)). It capped itself at a 200pt height
  but scrolled only horizontally, so the header row was sliced through the middle and
  `... and 62 more rows` was unreachable. The cap is gone; the row count was already bounded
  elsewhere, and a fixed height re-clips at larger Dynamic Type sizes anyway.
- **The tax year rendered as "2,026"**
  ([#56](https://github.com/CuWilliams/GFPriceChecker/pull/56)). `SwiftUI.Text` reads a string
  literal as a `LocalizedStringKey`, which formats an interpolated `Int` with the locale's grouping
  separator, putting "No products for 2,026" on screen. Not an obscure state — an empty library
  leaves the year picker on the current year, so it was the first thing a new user saw on the
  Reports tab.

### Documentation
- **Removed claims the app does not support**
  ([#57](https://github.com/CuWilliams/GFPriceChecker/pull/57)). `README.md` and `claude.md` both
  described the exports as compliant with the tax agency. The website dropped that class of claim
  in its v1.2.0 release and the app's interface had agency references stripped in April 2026; the
  docs were the last place still making it. Both now say what the app does — it documents price
  differences — and leave what a user does with those records at tax time between them and their
  accountant. `claude.md` gained a Content Conventions section, with the grep sweep to run before
  merging copy changes, so it cannot drift back.
- `README.md` rewritten against what the project actually is: it was the December 2025 original and
  stale nearly throughout, naming iOS 17, Swift 6, a `Models/Category.swift` that does not exist,
  Xcode 15, and placeholder author details.
- `EXECUTION_PLAN.md` archived to `docs/archive/`, `docs/DEVELOPMENT_HISTORY.md` now states where it
  stops, and four byte-identical duplicate app icons removed — with the asset catalog repointed at
  the originals first, since it referenced the duplicates for four of its fifteen entries
  ([#57](https://github.com/CuWilliams/GFPriceChecker/pull/57)).

---

## [1.0.0-build.8] - 2026-07-23

Size capture merged into product review, plus two data-loss fixes
([#33](https://github.com/CuWilliams/GFPriceChecker/pull/33)). Tester-facing notes for this build
are in [`docs/RELEASE_NOTES_BUILD_8.md`](docs/RELEASE_NOTES_BUILD_8.md).

### Changed
- The product scan review screen is one continuous screen with a "Step 1 of 3" indicator, instead
  of jumping on its own to a second size-entry form once a name and price were picked. Scan results
  stay visible throughout. Size remains optional.

### Fixed
- Deleting a product pair now deletes its photos. Deleted pairs were leaving image files on the
  device that nothing ever reclaimed.
- Backups no longer lose unit pricing. Export and restore was silently dropping every product's
  size and unit of measure, reducing restored records to package price only and wiping the Unit
  Price Differential. Backups from build 7 and earlier still import; those records simply have no
  size data to restore.

---

## Earlier builds

Builds 1-7 predate this changelog. Their development is narrated in
[`docs/DEVELOPMENT_HISTORY.md`](docs/DEVELOPMENT_HISTORY.md), Phases 1-6 and Sessions 1-27, which
covers the app from its first commit in December 2025 to the public TestFlight beta in January 2026.

[Unreleased]: https://github.com/CuWilliams/GFPriceChecker/compare/v1.0.0-build.9...HEAD
[1.0.0-build.9]: https://github.com/CuWilliams/GFPriceChecker/compare/v1.0.0-build.8...v1.0.0-build.9
[1.0.0-build.8]: https://github.com/CuWilliams/GFPriceChecker/releases/tag/v1.0.0-build.8
