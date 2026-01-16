# GFPriceChecker - Development Guide

**iOS app to track gluten-free vs regular product price differentials for Canadian tax deductions**

---

## Project Overview

GFPriceChecker helps Canadian celiac patients track the price difference between gluten-free and regular products for medical expense tax deductions (CRA Line 33099). The app provides:

- Product pair tracking (GF vs Regular) with price differential calculation
- Document scanning with OCR for automatic price extraction
- Receipt verification for CRA audit compliance
- Professional PDF and CSV tax reports

**Current Status:** Production-ready MVP, field trials in progress

---

## Tech Stack

- **Xcode:** 26.1.1
- **Swift:** 6.0 (strict concurrency enabled)
- **iOS Target:** 26.0+
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
│   └── ReportViewModel.swift   # Tax report calculations
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
│   ├── OCRService.swift        # Vision framework text + rectangle detection
│   ├── ReceiptParserService.swift  # Receipt parsing with fuzzy matching
│   ├── ImageStorageService.swift   # Local image storage + thumbnails
│   ├── CSVExportService.swift  # CRA-compliant CSV generation
│   ├── PDFGeneratorService.swift   # Professional PDF tax reports
│   └── DataBackupService.swift # JSON backup/restore with Base64 images
├── Utilities/
│   ├── AppSettings.swift       # @AppStorage user preferences
│   ├── ErrorHandler.swift      # Centralized error handling
│   ├── ValidationRules.swift   # Data validation logic
│   ├── ConfidenceIndicatorView.swift  # OCR confidence UI
│   └── ImageViewer.swift       # Zoomable image viewer component
└── Resources/
    └── AppLogo.swift           # App branding for PDF reports
```

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
- `differential: Decimal` (computed: gfPrice - nonGFPrice)
- `reportingDate: Date` (computed: receipt?.purchaseDate ?? createdDate)

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

### 1. SwiftUI Presentation Timing Issues

**Problem:** SwiftUI batches state updates, causing sheets/alerts to present before state commits.

**Solution: State Trigger Pattern**
```swift
@State private var selectedData: Data?
@State private var trigger = 0

Button {
    selectedData = data  // Set data
    trigger += 1         // Increment trigger
}

.onChange(of: trigger) { old, new in
    if new > 0 {
        showingSheet = true  // Present after state commits
    }
}
```

**When to Use:**
- Sheet content depends on state variables
- Alert buttons need to trigger async operations
- Image viewers showing dynamic content

**Examples in Codebase:**
- `ProductPairDetailView.swift` (image viewer)
- `ExportView.swift` (PDF export warning flow)

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

### 3. Async/Await with Swift Operators

**Problem:** Swift's `&&` and `||` use autoclosures which don't support async/await.

```swift
// ❌ Wrong - compiler error
if condition && await asyncFunction() { }

// ✅ Correct - nested if statements
if condition {
    if await asyncFunction() { }
}
```

**Example:** `ExportView.swift` (unverified products check)

---

### 4. Error Handling & Validation

**Centralized Error Types:**
- `Utilities/ErrorHandler.swift` - AppError enum with user-friendly messages
- `Utilities/ValidationRules.swift` - Data validation (price, name, date)

**Pattern:**
```swift
let result = ValidationRules.validatePrice(price, fieldName: "GF Price")
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

### 5. OCR Enhancements

#### Spatial Analysis for Price Detection
**File:** `Services/OCRService.swift`

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

### 6. Accessibility Standards

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

## Key Features

### ✅ Implemented

**Phase 1: Foundation**
- ProductPair and Receipt SwiftData models
- Decimal precision for currency
- Model container with error handling

**Phase 2: Library Views**
- ProductPairListView with filters (All/Verified/Unverified)
- ProductPairDetailView with image display
- ReceiptDetailView with zoomable images
- Full CRUD operations (Create, Read, Update, Delete)

**Phase 3: Camera & OCR**
- Document scanning (VisionKit)
- OCR text extraction (Vision framework)
- Price detection with spatial analysis
- Product name extraction
- Rectangle detection for shelf tags
- Decimal inference for prices
- Confidence-based visual feedback
- Guided product capture workflow
- Manual entry fallback

**Phase 4: Receipt Verification**
- Receipt scanning with OCR
- Fuzzy product matching (Levenshtein distance, Jaccard similarity)
- Multi-line receipt format support (Costco-style)
- Bulk selection controls
- Smart date filtering
- Auto-match acceptance
- Receipt image display in PDF reports

**Phase 5: Export & Reporting**
- Tax summary dashboard with Swift Charts
- Year-based filtering
- CSV export (CRA-compliant formatting)
- PDF export with receipt images
- Multi-page PDF with cover page, summary statistics, transaction details
- Unverified products section in PDF
- Three export methods: Save to Files, Share, Email

**Phase 6: Polish & Testing**
- Data backup/restore (JSON with Base64 images)
- Clear all data functionality
- Error handling infrastructure
- Accessibility (VoiceOver, Dynamic Type)
- Onboarding flow with camera permissions
- App logo/branding
- Swift 6 compliance (zero warnings)

---

### ⏸️ Deferred (Post-MVP)

**Category Management** (originally Session 7)
- Custom category creation
- Category color coding
- Predefined category list expansion

**Performance Optimization** (originally Session 22)
- Lazy image loading for large datasets
- PDF generation background threading
- SwiftData query optimization
- Memory profiling for 200+ products
- Deferred until field trials generate real-world usage data

**Additional Error Handling**
- Service layer error handling (remaining services)
- View layer error states (remaining views)
- Comprehensive error scenario testing

**Additional Accessibility**
- Chart accessibility with audio graphs
- Color contrast audit (WCAG 2.1 AA)
- Touch target size audit (44x44 minimum)
- High Contrast mode support

---

## Development Guidelines

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
- Never use string interpolation for localized currency (deprecated in Swift 6)

### Swift 6 Compliance
- Use `nonisolated` for file system operations
- Add `any` keyword to protocol types used as values
- Avoid `appendInterpolation` for localized strings

### Testing Strategy
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

**Detailed Implementation History:** See `docs/DEVELOPMENT_HISTORY.md`

**Sessions 1-27:**
- Sessions 1-6: Foundation and Library Views
- Sessions 8-12: Camera and OCR Integration
- Sessions 13-16: Receipt Verification and Testing
- Sessions 16-18: Export and Reporting
- Sessions 19-23: Polish and Testing
- Session 24: App Icon and Code Cleanup
- Session 25: OCR Enhancements and Receipt Images
- Session 26: Critical Bug Fixes
- Session 27: Rectangle-Based OCR and Decimal Inference

---

*This documentation is maintained by Claude Code to guide ongoing development and session work.*
