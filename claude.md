# GFPriceChecker - Development Guide

**iOS app to track gluten-free vs regular product price differentials for Canadian tax deductions**

---

## Project Overview

GFPriceChecker helps Canadian celiac patients track the price difference between gluten-free and
regular products, so the incremental cost is documented if they claim it as a medical expense. The
app provides:

- Product pair tracking (GF vs Regular) with price differential calculation
- Document scanning with OCR for automatic price extraction
- Receipt verification, so every tracked product has a real purchase behind it
- PDF and CSV exports of a year's records

**Canada only.** The app exists for Canadian tax rules, ships in English only, and formats money as
CAD. Don't plan, test or write tester instructions for other countries' regions or locales. Build
11's notes asked testers to set their phone to France, which was wasted effort. Write
machine-readable output, such as CSV numbers, in a fixed format anyway, because that is about the
file, not the user.

**Current Status:** Public TestFlight beta since January 2026. 1.0 App Store submission is the
current milestone — see issue #49 and the issues it is blocked by.

---

## Tech Stack

- **Xcode:** 26.1.1
- **Swift:** 5.0 language mode (`SWIFT_VERSION = 5.0`), Xcode 26 toolchain
- **iOS Target:** 18.0+
- **UI Framework:** SwiftUI
- **Persistence:** SwiftData
- **OCR:** Vision framework (VNRecognizeTextRequest, VNDetectRectanglesRequest)
- **Document Scanning:** VisionKit (VNDocumentCameraViewController)
- **PDF Generation:** PDFKit + Core Graphics
- **Architecture:** MVVM

---

## Project Structure

```
GFPriceChecker/
├── Models/
│   ├── ProductPair.swift       # Core data model (GF vs Regular product)
│   └── Receipt.swift           # Receipt verification model
├── ViewModels/
│   ├── CaptureFlowViewModel.swift  # Product capture flow state and logic
│   └── ReportViewModel.swift       # Dashboard year selection; totals come from GFCore
├── Views/
│   ├── Library/                # Product browsing and management
│   │   ├── ProductPairListView.swift
│   │   ├── ProductPairDetailView.swift
│   │   └── ReceiptDetailView.swift
│   ├── CaptureFlow/            # Product and receipt capture workflows
│   │   ├── ProductCaptureFlowView.swift
│   │   ├── ReceiptCaptureView.swift
│   │   └── ManualProductEntryView.swift
│   ├── Reports/                # Tax summary and export
│   │   ├── SummaryDashboardView.swift
│   │   └── ExportView.swift
│   ├── Settings/
│   │   └── SettingsView.swift
│   ├── Onboarding/
│   │   └── OnboardingView.swift
│   └── Components/             # Reusable UI components
│       ├── RectangleSelectorView.swift
│       └── OCRTextSelectorView.swift
├── Services/
│   ├── OCRService.swift        # Vision text + rectangle requests, mapped to GFCore values
│   ├── ImageStorageService.swift   # Local image storage + thumbnails
│   ├── CSVExportService.swift  # Itemized CSV generation
│   ├── PDFGeneratorService.swift   # Professional PDF tax reports
│   └── DataBackupService.swift # Backup <-> SwiftData, Base64 images, settings; schema is GFCore's
├── Utilities/
│   ├── AppSettings.swift       # @AppStorage user preferences
│   ├── ErrorHandler.swift      # Centralized error handling
│   ├── ValidationRules.swift   # GFCore's Validation in AppError, with the app's messages
│   ├── ConfidenceIndicatorView.swift  # OCR confidence UI
│   └── ImageViewer.swift       # Zoomable image viewer component
└── Resources/
    └── AppLogo.swift           # App branding for PDF reports

Packages/GFCore/                # Local Swift package: the platform-independent core
├── Package.swift               # swift-tools 6.0, iOS 18 / macOS 15
├── Sources/GFCore/
│   ├── Pricing/
│   │   ├── SizeUnit.swift      # SizeUnit, UnitPriceBasis
│   │   ├── PricingInputs.swift # Every PRODUCT_DEFINITION.md §3 formula, size back-calculation
│   │   └── SizeTextParser.swift  # Size and unit-price parsing of OCR text
│   ├── Reporting/
│   │   ├── ReportRow.swift     # One pair as the reports see it
│   │   ├── ReportCalculator.swift  # ReportTotals, year/range filters, category and month groups
│   │   └── DateRangePreset.swift   # Export date-range presets (raw values are persisted)
│   ├── CSV/
│   │   └── CSVExporter.swift   # Columns, machine number/date formats, escaping
│   ├── ReceiptParsing/
│   │   └── ReceiptParser.swift # Store, date, line items, total; fuzzy matching via MatchCandidate
│   ├── PriceRanking/
│   │   ├── RecognizedText.swift  # RecognizedText and NormalizedRect, the core's CGRect
│   │   ├── PriceRanking.swift  # PriceMatch.rankingScore, thresholds, price regex, name heuristic
│   │   └── TextOrdering.swift  # Reading order for tap-to-select lists and receipt text
│   ├── Validation/
│   │   └── Validation.swift    # Input limits and rules, returning ValidationError
│   └── Backup/
│       ├── BackupSchema.swift  # BackupData and its DTOs: the shared JSON contract (§7)
│       └── BackupFormat.swift  # Coders, version gate, decimals as strings
└── Tests/GFCoreTests/          # Swift Testing, run with `swift test` on macOS
    ├── VectorTests.swift       # Runs every cross-platform vector file
    └── Vectors/                # Vendored from shared-docs; never edit here

scripts/sync-vectors.sh         # Vendors the vectors from shared-docs; --check fails on drift
.githooks/pre-push              # Runs sync-vectors.sh --check
```

### GFCore and its boundary rule

`Packages/GFCore` is where the app's arithmetic and other platform-independent behaviour live,
so they can be tested without a simulator and shared with a future Android app. It is added to
the Xcode project as an `XCLocalSwiftPackageReference` and linked to the app target. Track F
(`docs/SHARED_CORE.md`) moved it in area by area, and with Stage 2 done it holds `Pricing`,
`Reporting`, `CSV`, `ReceiptParsing`, `PriceRanking`, `Validation` and `Backup`.

**Boundary rule: GFCore imports Foundation only.** No SwiftUI, UIKit, SwiftData, Vision,
PDFKit, CoreGraphics or `NSPredicate`. Anything that needs one of those stays in the app, and
the app adapts its types to the core's at the edge: `ProductPair.pricing` builds a
`PricingInputs`, and the model's computed properties forward to it. `OCRService` maps each
`VNRecognizedTextObservation` to a `RecognizedText` and hands the rest to the core.
`DataBackupService` maps SwiftData models, image files and `AppSettings` to the core's backup
DTOs, and leaves the coders and version gate to `BackupFormat`.

- A local package does not inherit `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and
  swift-tools 6.0 builds it in Swift 6 language mode. Its types are nonisolated; make them
  `Sendable` value types.
- Declarations the app uses must be `public`.
- The app has `MemberImportVisibility` on, so a file that only *uses* a GFCore type's members
  still needs `import GFCore`.

---

## Core Data Models

### ProductPair
**File:** `Models/ProductPair.swift`

Stores gluten-free and regular product comparison data.

**Key Properties:**
- `gfProductName`, `gfPrice`, `gfSize`, `gfImageUUID`, `gfOCRConfidence`
- `nonGFProductName`, `nonGFPrice`, `nonGFSize`, `nonGFImageUUID`, `nonGFOCRConfidence`
- `category`, `notes`, `createdDate`
- `receipt: Receipt?` (optional relationship)
- `pricing: PricingInputs` (computed): the prices, sizes and quantity handed to GFCore.
  `differential`, the unit prices, `normalizedDifferential` and the `extended*` figures all
  forward to it; the model has no arithmetic of its own
- `reportingDate: Date` (computed: receipt?.purchaseDate ?? createdDate)
- `reportRow: ReportRow` (computed): the pair as GFCore's `ReportCalculator` and
  `CSVExporter` see it. Every total, grouping and CSV line — dashboard, export preview, CSV,
  PDF cover, subtotals and grand total — is computed over these, so they cannot disagree

**Design Decisions:**
- **Decimal for currency:** Avoids floating-point errors (critical for tax calculations)
- **OCR confidence:** Float 0.0-1.0 to track extraction reliability
- **Optional fields:** Supports manual entry without photos
- **Reporting date logic:** Uses receipt date if verified, otherwise creation date

### Receipt
**File:** `Models/Receipt.swift`

One-to-many relationship: one receipt can verify multiple ProductPairs.

**Key Properties:**
- `purchaseDate`, `storeName`, `totalAmount`
- `receiptImageUUID` (stored via ImageStorageService)
- `extractedOCRText` (raw OCR for debugging)
- `productPairs: [ProductPair]` (inverse relationship)

---

## Established Patterns & Best Practices

### 1. SwiftUI & Swift Concurrency Gotchas

**Sheets present before their state commits.** SwiftUI batches state updates, so a sheet whose
content reads `selectedData` can open before the assignment lands. Drive presentation off a
separate trigger:

```swift
@State private var selectedData: Data?
@State private var trigger = 0

Button {
    selectedData = data  // Set data
    trigger += 1         // Increment trigger
}

.onChange(of: trigger) { _, new in
    if new > 0 { showingSheet = true }  // Present after state commits
}
```

Use it when sheet content depends on state, when an alert button starts async work, or for
image viewers showing dynamic content. See `ProductPairDetailView.swift`, `ExportView.swift`.

**`&&` and `||` take autoclosures, so neither side can `await`.**

```swift
if condition && await asyncFunction() { }     // ❌ compiler error
if condition { if await asyncFunction() { } } // ✅ nest instead
```

See `ExportView.swift` (unverified products check).

---

### 2. Security-Scoped File Access

**Problem:** iOS file import fails with permission errors when reading async.

**Solution: Read Synchronously Before Async Boundary**
```swift
guard url.startAccessingSecurityScopedResource() else { return }

let data: Data
do {
    data = try Data(contentsOf: url)  // Read while we have permission
} catch { ... }

url.stopAccessingSecurityScopedResource()

// Process data asynchronously
Task { @MainActor in
    try await processData(data)
}
```

**Rule:** File must be read synchronously while security access is active.

**Example:** `SettingsView.swift` (data import)

---

### 3. Error Handling & Validation

**Centralized Error Types:**
- `Utilities/ErrorHandler.swift` - AppError enum with user-friendly messages
- `Utilities/ValidationRules.swift` - Data validation (price, name, size, quantity, notes).
  The rules are GFCore's `Validation`, which returns a `ValidationError` naming what is
  wrong; `AppError.init(_: ValidationError)` turns that into the app's message

**Pattern:**
```swift
let result = ValidationRules.validatePriceString(priceText, fieldName: "GF Price")
switch result {
case .success:
    // Proceed
case .failure(let error):
    // Show user-friendly error.recoverySuggestion
}
```

**Examples:**
- `ManualProductEntryView.swift` (form validation)
- `CSVExportService.swift`, `PDFGeneratorService.swift` (data validation before export)

---

### 4. OCR Enhancements

#### Spatial Analysis for Price Detection
**File:** `Packages/GFCore/Sources/GFCore/PriceRanking/PriceRanking.swift` (the Vision request
is in `Services/OCRService.swift`)

Ranks price candidates by:
- Font size (50% weight) - larger text likely actual price
- Vertical position (30% weight) - higher on shelf tag
- Has "$" prefix (10% weight)
- OCR confidence (10% weight)

**Auto-selects if:** Top candidate quality ≥ 0.85 OR only one candidate exists

**Prompts user if:** Multiple candidates with quality < 0.85

#### Rectangle-Based OCR Filtering
**File:** `Views/Components/RectangleSelectorView.swift`

- Vision framework rectangle detection (shelf price tags)
- Tap-to-select UI with visual overlays
- Falls back to full-image OCR if skipped/failed
- Aspect ratio tuned for Canadian grocery shelf tags (0.3-1.0)

#### Decimal Inference
**File:** `Views/Components/OCRTextSelectorView.swift`

- Detects 3+ digit values without decimals (e.g., "1299")
- Suggests currency format ("$12.99")
- Confirmation alert with accept/reject options
- Only applies during price selection phase

---

### 5. Accessibility Standards

**VoiceOver Support:**
- All interactive elements have `.accessibilityLabel()` and `.accessibilityHint()`
- Decorative images use `.accessibilityHidden(true)`
- Grouped elements use `.accessibilityElement(children: .combine)`

**Dynamic Type:**
- All text uses system font styles (`.title`, `.body`, `.caption`)
- Layouts use flexible containers (VStack, HStack, ScrollView)
- No fixed font sizes

**Examples:**
- `ProductPairListView.swift`
- `ManualProductEntryView.swift`
- `OnboardingView.swift`

---

### 6. Flow State Belongs in a ViewModel

`ProductCaptureFlowView` was 986 lines with ~35 `@State` properties and its handlers as
private view methods — untestable and undriveable. `ViewModels/CaptureFlowViewModel.swift`
is the result of lifting that out. Follow the same shape for the flows still holding their
own state: `ReceiptCaptureView` (17 `@State`) and `ExportView` (18).

**Inject services, don't call singletons.** A `Dependencies` struct of closures standing in
for `OCRService` and `ImageStorageService` is what lets a test run a whole capture with
canned OCR results and no Vision framework. Note the init signature:

```swift
// ✅ Optional, resolved inside
init(dependencies: Dependencies? = nil) { self.dependencies = dependencies ?? .live }

// ❌ Won't compile: a default argument is evaluated in the CALLER's isolation,
//    and `.live` is @MainActor
init(dependencies: Dependencies = .live) { ... }
```

**Derive once.** The finalize preview and `saveProductPair` each had their own copy of the
unit-price back-calculation, so the two could disagree. Computed properties on the view
model (`gfSizeValue`, `normalizedDifferential`) are now the single source.

---

## Key Features

### ✅ Implemented

Product pairs with `Decimal` currency and full CRUD; VisionKit document scanning with Vision
OCR (spatial price ranking, rectangle-based shelf-tag filtering, decimal inference); receipt
verification with fuzzy matching (Levenshtein, Jaccard) and Costco-style multi-line parsing;
tax summary dashboard, itemized CSV, and multi-page PDF with receipt images; JSON
backup/restore; onboarding, VoiceOver and Dynamic Type; a clean build with zero warnings.

How each of those arrived is in `docs/DEVELOPMENT_HISTORY.md`, Phases 1-6.

---

### ⏸️ Deferred (Post-MVP)

- **Category management:** custom categories, colour coding, a longer predefined list
- **Performance:** lazy image loading, background PDF generation, SwiftData query tuning, and
  memory profiling for 200+ products — held until beta usage produces real numbers
- **Error handling:** the remaining services and view-layer error states
- **Accessibility:** chart audio graphs, WCAG 2.1 AA contrast audit, 44x44 touch-target audit,
  High Contrast mode

---

## Content Conventions

**The source for these is
[`gfpricechecker/CONTENT_CONVENTIONS.md`](https://github.com/CuWilliams/shared-docs/blob/main/gfpricechecker/CONTENT_CONVENTIONS.md)
in the shared-docs repo**, which governs this app, the website, and any future Android app. It
also carries the shared vocabulary and the platform-independent
[`PRODUCT_DEFINITION.md`](https://github.com/CuWilliams/shared-docs/blob/main/gfpricechecker/PRODUCT_DEFINITION.md).
Change it there, not here. What follows is the short version, because the first rule is legal
exposure and you should not have to open another repo to find out about it.

### Don't claim tax compliance

The app carries no Canada Revenue Agency branding, and agency references and specific tax line
numbers were stripped out of the interface in April 2026. Tracking price differences is what the
app does; what a user does with those records at tax time is between them and their accountant.
The website removed the same class of claim in its v1.2.0 release — and this app's docs went on
making it for months afterwards, which is exactly why the rule now lives in one place.

- Explaining the Medical Expense Tax Credit as context for why the app exists is fair and useful.
- Never describe the app's exports as CRA-compliant, approved, accepted, or endorsed — not in the
  interface, not in `README.md`, and not in this file.
- Never promise anyone a deduction.

Before merging copy or documentation changes, sweep for regressions:

```bash
# Quote the --include patterns: zsh expands them as globs otherwise.
grep -rn "CRA\|Tax Compliant\|tax compliance\|Line 33099" \
  --include='*.swift' --include='*.md' .
```

Every surviving hit should be explanatory context or a historical record that admits its date —
`docs/DEVELOPMENT_HISTORY.md` and `docs/archive/` narrate what the app was at the time of writing
and are left as written.

---

## Development Guidelines

### User Preferences
- **Claude runs the automated tests** - see [Testing Strategy](#testing-strategy) below. This
  project overrides the global default of "the user runs tests."
- **The user still does the device/UI testing** - anything needing the camera, real receipts,
  or a look at the actual screens stays with the user.

### SwiftData Best Practices
- Use `@Model` macro for persistence
- Decimal type supported natively in SwiftData
- UUID auto-generated for unique identification
- Use `.onDelete()` for cascade deletion

### OCR Best Practices
- Always provide confidence thresholds (0.7+ for product names, 0.6+ for prices)
- Use bounding boxes for spatial analysis
- Provide manual override options for low confidence
- Guide users to photograph shelf price tags for best results

### Image Storage
- JPEG compression at 0.7-0.8 quality for balance
- Generate thumbnails (max 200px width) for list views
- Store images with UUID filenames in Documents/products/ and Documents/receipts/
- Clean up orphaned images on ProductPair/Receipt deletion

### Currency Formatting
- Always use `Decimal` type for prices
- Format display: `.formatted(.currency(code: "CAD"))`
- Never use string interpolation for localized currency

### Concurrency

The project is **not** in Swift 6 language mode. `SWIFT_VERSION = 5.0` at all six build
configurations, so data-race safety is diagnosed as warnings, not errors. What is on is two
Xcode 26 toolchain defaults:

- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — **types are `@MainActor` unless they say
  otherwise**, which is why so little in this codebase carries an explicit annotation.

Both are compile-time settings that back-deploy; neither constrains the deployment target.
Moving to Swift 6 language mode is a separate piece of work nobody has costed.

House rules that follow from the MainActor default:

- Mark file system operations `nonisolated` so they don't hop to the main actor
- Add `any` to protocol types used as values
- Avoid `appendInterpolation` for localized strings

### Testing Strategy

**Claude is authorized to build and run the automated tests in this project.** This is a
deliberate project-level override of the global "user runs tests" default.

**GFCore's tests run first and need no simulator:**

```bash
cd Packages/GFCore && swift test
```

The pure arithmetic and parsing tests live there. Tests that need SwiftData, UIKit or Vision
stay in `GFPriceCheckerTests`.

**The cross-platform test vectors are normative and live in shared-docs**, under
[`gfpricechecker/vectors/`](https://github.com/CuWilliams/shared-docs/tree/main/gfpricechecker/vectors).
Every implementation must pass them. `VectorTests` runs the copy vendored at
`Packages/GFCore/Tests/GFCoreTests/Vectors/`, so never edit that copy; change a vector in
shared-docs, then bring it across:

```bash
scripts/sync-vectors.sh           # copy shared-docs' vectors over the vendored copy
scripts/sync-vectors.sh --check   # exit 1 if they differ (2 if shared-docs is missing)
git config core.hooksPath .githooks   # once per clone: pre-push runs --check
```

The script expects shared-docs cloned next to this repo; set `SHARED_DOCS` to point elsewhere.
A behaviour change that moves a vector's expected value is a product change: it goes through
shared-docs first. Known gaps pinned by a "Known gap" test stay out of the vectors.

Working invocation for the app (scheme resolves from local `xcuserdata`; no shared scheme is
committed):

```bash
xcodebuild test -scheme GFPriceChecker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:GFPriceCheckerTests
```

**`-parallel-testing-enabled NO` is not optional here.** Without it xcodebuild clones a
second simulator and the run dies with "Unable to boot device due to insufficient system
resources" before a single test executes.

**Keep the `OS=` in the destination.** Without it xcodebuild looks for the device on the
newest installed runtime, and fails with "Unable to find a device matching the provided
destination specifier" when that runtime has no iPhone 17 Pro, as iOS 27.0 does not.

Drop `-only-testing:` to include the UI test target. Now that the deployment target is 18.0,
any runtime from iOS 18.0 up is a valid destination — pick one that matches what you are
verifying. A full run takes several minutes; raise the Bash timeout and run it in the
background. `xcodebuild`'s output is long — filter it, and note that **Swift Testing emits no
"Test case" lines**, so grep for `"✘|✔|Test run with|TEST (SUCCEEDED|FAILED)|error:"`.

Failures worth digging into are easiest to read from the result bundle:

```bash
xcrun xcresulttool get test-results tests --path <path>.xcresult
```

Expectations when writing tests:

- **Swift Testing**, not XCTest (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`).
- Mark suites `@MainActor` when touching `@MainActor` services, and `.serialized` when they
  share a singleton such as `DataBackupService.shared` or `AppSettings.shared` — Swift
  Testing runs tests in parallel by default.
- Use in-memory containers: `ModelConfiguration(isStoredInMemoryOnly: true)`. **Hold the
  `ModelContainer` alive for as long as you use its context** — letting it deallocate tears
  down the store and traps inside SwiftData on the next fetch.
- `GFPriceCheckerTests` is a `PBXFileSystemSynchronizedRootGroup`, so new test files are
  picked up automatically with no `project.pbxproj` edit.
- **Prove a new test can fail.** Break the thing it guards, watch it go red, revert, confirm
  green. A test that passes for the wrong reason is worse than no test.

Still the user's to do, since they need a device or a human eye:

- Preview code for Xcode canvas testing
- Sample data demonstrates all field types
- Test with VoiceOver enabled
- Test with Dynamic Type at largest size (AX5)

---

## Known Limitations

1. **OCR Accuracy:**
   - Depends on image quality (lighting, clarity, angle)
   - Confidence thresholds may need real-world tuning
   - Multi-line receipt format detection assumes price on line immediately following product name

2. **Receipt Parsing:**
   - Fuzzy matching tuned for Canadian grocery stores (Loblaws, Sobeys, Metro, Costco)
   - May need adjustments for other retailers

3. **Image Viewer:**
   - Basic zoom implementation (could add viewport constraints, rotation)

4. **Export:**
   - PDF generation is synchronous (acceptable for MVP dataset sizes <100 products)
   - Backup files can be large with many images (Base64 increases size by ~33%)

5. **Performance:**
   - Optimized for MVP dataset sizes (0-100 products)
   - No profiling yet for 200+ products with images

6. **Data Privacy:**
   - All data stored locally (no cloud sync)
   - Tax ID stored in @AppStorage (not encrypted)
   - Backup files contain unencrypted data

7. **Simulator:**
   - `VNDocumentCameraViewController` presents a sheet that never returns an image in the
     Simulator, so `DocumentScannerView` falls back to `SubstituteScannerView` there — an
     image from the photo library, or from `SampleScanImages` in DEBUG. The choice is made
     inside `DocumentScannerView`, so all three call sites get it and device behaviour is
     unchanged. Set Xcode's run destination to a Simulator to see it at all.
   - **`VNDocumentCameraViewController.isSupported` is not the signal for this.** On iOS 26 /
     Xcode 26.1.1 it returns `true` in the Simulator. The fallback keys off
     `targetEnvironment(simulator)`, and `isSupported` is consulted only on a device.
     `DocumentScannerSourceTests` pins both facts.
   - The substitute hands the image through untouched, skipping the real scanner's edge
     detection and perspective correction. How well OCR copes with a skewed or badly lit
     photograph still needs a device.

---

## Git Workflow

**Main Branch:** `main`
**Feature Branches:** `claude/[feature-description]-[sessionId]`

**Commit Message Style:**
- Imperative mood ("Add feature" not "Added feature")
- Descriptive and concise
- Include co-authorship: `Co-Authored-By: Claude <noreply@anthropic.com>`

**Pull Request Workflow:**
1. Create feature branch
2. Implement and test
3. Clean build with zero warnings
4. Create PR to main with summary of changes
5. Merge after review

---

## Reference Documentation

**Detailed Implementation History:** See `docs/DEVELOPMENT_HISTORY.md` — Phases 1-6 and Sessions 1-27, one section each.

**Shared across repos:** [CuWilliams/shared-docs](https://github.com/CuWilliams/shared-docs) —
`gfpricechecker/` holds the content conventions and the platform-independent product definition
(data model, differential arithmetic, export formats) shared with the website and any future
Android app; `meta/` holds the CLAUDE.md template, checklist and health-check script that used to
live in this repo's `docs/`. Change shared documents there, not here.

**Scripted Demo Pipeline:** See `docs/SCRIPTED_DEMO_PIPELINE.md` — the plan and feasibility audit for generating the website's instructional videos from scripts the app plays against itself, so a new build regenerates the media set instead of needing a re-shoot. Read it before touching the capture flows, `DocumentScannerView`, or navigation structure: several of its stages are refactors of those, and it records why.

**Shared Domain Core:** See `docs/SHARED_CORE.md` — the plan and audit for moving the arithmetic, reporting, exports, receipt parsing, validation and backup schema into the Foundation-only `GFCore` package, pinned by cross-platform test vectors in shared-docs so a future Android app can share it (Track F). Read it before touching any of those areas. It lists where the app currently departs from `PRODUCT_DEFINITION.md` and where the arithmetic is duplicated.

---

*This documentation is maintained by Claude Code to guide ongoing development and session work.*
