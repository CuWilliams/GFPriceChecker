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

### Changed
- Development has ended. Budget 2026 proposes a flat $1,000 celiac claim under the Medical
  Expense Tax Credit, so 1.0 will not be submitted to the App Store. The repository is open
  source under the MIT License (`LICENSE`), and the README and `claude.md` say so. Any further
  TestFlight upload only keeps the beta from expiring.
- The gfpricechecker.com domain is not renewed past December 29, 2026, so the website and
  support@gfpricechecker.com end with it. The README points to the archived website repository
  instead. The Settings screen's support link is left in the code, which is no longer developed.

---

## [1.0.0-build.11] - 2026-10-31

Tester notes are in [`docs/RELEASE_NOTES_BUILD_11.md`](docs/RELEASE_NOTES_BUILD_11.md).

### Changed
- **A new app icon.** Bold "GF" letters over a check, in the existing brand blue, white and sky
  blue: a flat redraw of the wordmark's "GF" and swoosh, which stays as it is on the launch
  screen, onboarding and the PDF cover. The asset catalog moves to Xcode's single-size format
  with dark and tinted variants for iOS 18 Home Screens, replacing eleven per-size PNGs with three
  1024px images. The letters are Manrope ExtraBold converted to outlines, so the font is not
  bundled; `docs/brand/AppIcon.svg` is the master and `docs/brand/render-app-icon.swift`
  regenerates the PNGs.
- **The CSV export matches the spec, and the size-adjusted figure has its proper name**
  ([#66](https://github.com/CuWilliams/GFPriceChecker/issues/66)). The CSV's numbers and dates
  were formatted in the device locale, so a phone with its region set to France or Germany wrote
  `7,99` and split every price into two columns. They are now `en_US_POSIX`: `.` decimals, no
  grouping, Latin digits. A French-Canadian device was never affected — the app ships only an
  English localization, so iOS resolves fr-CA to `en_CA` — which is why the issue's own example
  could not reproduce it. Unit prices follow `PRODUCT_DEFINITION.md` §4 ($/100 g for grams,
  $/unit otherwise) at 4 places instead of raw $/g at 2, with a new **Unit Price Basis** column
  saying which. `normalizedDifferential` is a dollar amount per package, not a rate, and is now
  labelled **Size-Adjusted Differential** in the CSV, PDF, dashboard, export screen, library,
  detail and capture views; `CaptureFlowViewModel.unitPriceDifferential` is now
  `normalizedDifferential`. The PDF's table cells format money from `Decimal`, where they went
  through `Double` and could drop a cent (6.255 printed as 6.25). The column list in shared-docs
  §6 is updated to match.
- **Money rounds half-up everywhere.** `PRODUCT_DEFINITION.md` §3 makes the rule half-up, away
  from zero, but iOS's currency formatters round half-even, so $0.465 showed as $0.46. GFCore's
  `.cad` style replaces every currency format in the views and the PDF, and the CSV's number
  formatter uses `.halfUp`.
- **The platform-independent core moved into the `GFCore` package** (Track F,
  [#67](https://github.com/CuWilliams/GFPriceChecker/issues/67)–[#71](https://github.com/CuWilliams/GFPriceChecker/issues/71)).
  Pricing, reporting, CSV, receipt parsing, OCR price ranking, validation and the backup schema
  now live in a Foundation-only local Swift package tested with `swift test`, and the duplicated
  arithmetic in the app is deleted. `VectorTests` runs shared-docs' cross-platform vectors, and
  `scripts/sync-vectors.sh --check` guards the vendored copy from the pre-push hook. Apart from
  the changes listed here, the app behaves as before.

### Fixed
- **Receipt totals ignored quantity, and missing size data showed as $0.00**
  ([#65](https://github.com/CuWilliams/GFPriceChecker/issues/65)). `Receipt.totalDifferential`
  summed the per-unit `differential`, so a receipt with a quantity above 1 under-reported; it now
  sums `extendedDifferential`, and `ReceiptDetailView` shows the extended figure on each row and
  formats its amounts as CAD currency rather than by interpolation. The size-adjusted total was
  `nil` in the export preview but zero on the dashboard and in the PDF, against
  `PRODUCT_DEFINITION.md` §3; `ReportViewModel.calculateTotalNormalizedDifferential` is now the one
  static implementation, returns `nil` when nothing can be normalized, and every surface shows "—".
  `SpecConformanceTests` pins the spec's $5.63 worked example.
- **The dashboard's size-adjusted average showed $0.00 without size data**
  ([#75](https://github.com/CuWilliams/GFPriceChecker/issues/75)). #65 made the total `nil`, but the
  Tax Summary's average card still fell back to zero. `StatisticCardDecimal.value` is now optional,
  `SummaryDashboardView.displayAmount` renders `nil` as "—", and VoiceOver reads "not available".
  `SpecConformanceTests` pins it.
- **CSV fields with Windows line breaks went out unquoted**
  ([#66](https://github.com/CuWilliams/GFPriceChecker/issues/66)). Swift treats `\r\n` as one
  `Character`, so `contains("\n")` and `contains("\r")` were both false for a note whose only line
  breaks were `\r\n`, and the note broke the row. Escaping now scans Unicode scalars.

- **Contact Support writes to `support@gfpricechecker.com`**
  ([#62](https://github.com/CuWilliams/GFPriceChecker/issues/62)). Settings → About → Contact
  Support opened `mailto:support@gfpricechecker.app`, an address published nowhere else; the
  README listed `gfpricechecker@gmail.com`. Both now use the one address, which the website moves
  to in the same change.
- **Validation messages named the wrong problem**
  ([#82](https://github.com/CuWilliams/GFPriceChecker/issues/82)). Every size, length and email
  failure rode on `AppError.invalidProductName`, so users saw "GF size must be greater than zero
  cannot be empty" with the suggestion "Please enter a product name." `invalidSize`,
  `textTooLong` and `invalidEmail` now carry their own messages and recovery suggestions.
- **Price and size text with trailing junk was accepted**
  ([#84](https://github.com/CuWilliams/GFPriceChecker/issues/84)). `Decimal(string:)` reads the
  longest number at the start and ignores the rest, so "12.99abc" validated as 12.99 and "1,5" as
  1. GFCore's `PlainDecimal` now requires the whole string to be a plain number (optional leading
  minus, ASCII digits, at most one point); prices allow at most 2 places. Backup decimals use the
  same rule, and every existing backup string already matches it.

### Removed
- **Console logging of user data in release builds**
  ([#49](https://github.com/CuWilliams/GFPriceChecker/issues/49)). 75 of the app's 83 `print()`
  calls ran in every build, and many wrote store names, purchase dates, receipt totals and product
  names to the device console — for an app whose whole position is that nothing leaves the device.
  Step-by-step traces and success messages (all of `OCRService`'s, the receipt pipeline's, the PDF
  generator's) are deleted outright. The handful that reported a real failure with no other
  outlet — image storage, the document scanner, product OCR, saving or deleting in the library —
  now go through `ErrorHandler.shared.log(_:context:)`, which already existed, prints only under
  `#if DEBUG`, and until now had no callers. Failures already surfaced to the user in an alert
  lost their duplicate print. The eight `print()` calls left are all inside `#if DEBUG`.

---

## [1.0.0-build.10] - 2026-09-20

Upload metadata only. No source file changed and the app behaves exactly as build 9 does. Tester
notes are in [`docs/RELEASE_NOTES_BUILD_10.md`](docs/RELEASE_NOTES_BUILD_10.md), which says plainly
that there is no new functionality to test, then re-carries build 9's outstanding test items —
build 10 is what a new or external tester now lands on, and thin notes would tell them there is
nothing to do.

### Added
- **Export compliance is declared in the project**
  ([#59](https://github.com/CuWilliams/GFPriceChecker/issues/59)).
  `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in both app-target configurations, so App
  Store Connect stops prompting interactively on every upload. `NO` is not a judgement call here:
  a sweep for `URLSession`, `Network`, `NWConnection`, `CryptoKit`, `CommonCrypto`, `SecKey` and
  `https://` across `GFPriceChecker/` returns nothing at all. The key is a build setting because
  `GENERATE_INFOPLIST_FILE = YES` and the project has no `Info.plist` file to put it in.
- **A privacy manifest** ([#59](https://github.com/CuWilliams/GFPriceChecker/issues/59)).
  `GFPriceChecker/PrivacyInfo.xcprivacy` declares `NSPrivacyTracking` false with no tracking
  domains and no collected data types, which is what an app with no networking collects. Exactly
  one required-reason API category is tripped — `NSPrivacyAccessedAPICategoryUserDefaults`, reason
  `CA92.1`, for the `@AppStorage` preferences in `Utilities/AppSettings.swift`, which are this
  app's own and shared with nothing. Without the manifest, Apple returns ITMS-91053 "Missing API
  declaration" warnings at upload.

  The other four categories were audited and none applies. In particular the file-timestamp
  category does not: the only `resourceValues` call in `ImageStorageService` reads `.fileSizeKey`,
  and file *size* appears on none of Apple's five lists — a correction to an earlier guess made on
  [#49](https://github.com/CuWilliams/GFPriceChecker/issues/49).

  `GFPriceChecker/` is a `PBXFileSystemSynchronizedRootGroup`, so the file needed no target
  membership edit. It was confirmed present inside the built `.app` rather than assumed, because a
  privacy manifest that misses the bundle fails silently — which is the whole failure this guards
  against.

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

[Unreleased]: https://github.com/CuWilliams/GFPriceChecker/compare/v1.0.0-build.11...HEAD
[1.0.0-build.11]: https://github.com/CuWilliams/GFPriceChecker/compare/v1.0.0-build.10...v1.0.0-build.11
[1.0.0-build.10]: https://github.com/CuWilliams/GFPriceChecker/compare/v1.0.0-build.9...v1.0.0-build.10
[1.0.0-build.9]: https://github.com/CuWilliams/GFPriceChecker/compare/v1.0.0-build.8...v1.0.0-build.9
[1.0.0-build.8]: https://github.com/CuWilliams/GFPriceChecker/releases/tag/v1.0.0-build.8
