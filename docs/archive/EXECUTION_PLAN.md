> **Archived — historical record.** This is the session-by-session plan used to build the app to
> its TestFlight MVP between December 2025 and January 2026. All six phases were completed and the
> app has changed considerably since; several of its claims no longer hold. It is kept as a record
> of how the app was originally constructed, and it does **not** describe the app as it stands
> today or what shipping 1.0 now requires.
>
> **Do not work from the TestFlight checklist in Session 25.** It is superseded — the iPhone 15 Pro
> screenshot target in particular is wrong, and App Store screenshots now come out of the scripted
> demo pipeline. The current launch checklist lives in issue #49.
>
> For current documentation see [README.md](../../README.md) and [claude.md](../../claude.md).
> For what happened during these sessions, see
> [DEVELOPMENT_HISTORY.md](../DEVELOPMENT_HISTORY.md).

# GFPriceChecker - Complete Execution Plan

**Version:** 1.0  
**Last Updated:** December 27, 2024  
**Target:** MVP for TestFlight  
**Estimated Timeline:** 20-25 focused sessions

---

## How to Use This Document

Each **Session** below is designed for one focused work period with Claude Code (1-2 hours).

**Session Structure:**
1. **Objective** - What you're building
2. **Context for Claude Code** - What to tell Claude Code
3. **Files to Create/Modify** - What will change
4. **Acceptance Criteria** - How to know it worked
5. **Testing Steps** - How to verify
6. **Commit Message** - What to write when committing

**Work Pattern:**
1. Read session objective
2. Open Claude Code
3. Provide context from session
4. Let Claude Code implement
5. Test thoroughly
6. Commit if successful
7. Move to next session

---

## PHASE 1: FOUNDATION (Sessions 1-3)

**Goal:** Set up data models and core architecture

---

### Session 1: Data Models - ProductPair

**Objective:** Create the core SwiftData model for storing GF/non-GF product pairs

**Context for Claude Code:**
```
I'm building GFPriceChecker, an iOS app to track price differentials between 
gluten-free and regular products for tax purposes.

I need to create a SwiftData model called ProductPair that stores:
- UUID identifier
- Created date
- Gluten-free product: name, price, size (optional), image data (optional)
- Non-gluten-free product: name, price, size (optional), image data (optional)  
- Category (optional string)
- Notes (optional string)
- Receipt verification status (boolean)
- OCR confidence scores for both products (Float, 0-1 range)

The model should have:
- A computed property 'differential' that returns (gfPrice - nonGFPrice)
- Proper Swift decimal handling for currency
- @Model macro for SwiftData
- Sensible default values

Please create Models/ProductPair.swift following SwiftData best practices.
```

**Files to Create:**
- `Models/ProductPair.swift`

**Acceptance Criteria:**
- [ ] File compiles without errors
- [ ] Model uses `@Model` macro correctly
- [ ] All properties have appropriate types
- [ ] Differential computed property works
- [ ] Prices use `Decimal` type (not Double)

**Testing Steps:**
1. Build project (Cmd+B) - should succeed
2. In `ProductPair.swift`, add preview code:
```swift
#Preview {
    let sample = ProductPair(
        gfProductName: "Udi's GF Bread",
        gfPrice: 6.99,
        nonGFProductName: "Wonder Bread",
        nonGFPrice: 3.49
    )
    return Text("Differential: $\(sample.differential)")
}
```
3. Click preview in Xcode - should show differential

**Commit Message:**
```
Add ProductPair SwiftData model with price differential calculation
```

---

### Session 2: Data Models - Receipt

**Objective:** Create Receipt model and establish relationship with ProductPair

**Context for Claude Code:**
```
I need a SwiftData model called Receipt that stores:
- UUID identifier  
- Purchase date
- Store name (optional)
- Receipt image data (optional)
- Total amount (optional Decimal)
- Extracted OCR text (optional String)

This model should have a one-to-many relationship with ProductPair 
(one receipt can verify multiple product pairs).

Update ProductPair to include optional @Relationship to Receipt.

Create Models/Receipt.swift and update Models/ProductPair.swift with relationship.
```

**Files to Create/Modify:**
- `Models/Receipt.swift` (new)
- `Models/ProductPair.swift` (add relationship)

**Acceptance Criteria:**
- [ ] Receipt model compiles
- [ ] Relationship properly defined
- [ ] Can associate multiple ProductPairs with one Receipt
- [ ] No circular dependency issues

**Testing Steps:**
1. Build project (Cmd+B)
2. Create preview with sample data showing relationship
3. Verify no compilation errors

**Commit Message:**
```
Add Receipt model with ProductPair relationship
```

---

### Session 3: Model Container Setup

**Objective:** Configure SwiftData model container in app entry point

**Context for Claude Code:**
```
Update GFPriceCheckerApp.swift to:
1. Import SwiftData
2. Configure modelContainer with ProductPair and Receipt models
3. Add error handling for model container initialization
4. Ensure container is available throughout app via environment

Also update ContentView.swift to:
1. Add @Environment(\.modelContext) for accessing SwiftData
2. Update preview to include modelContainer
```

**Files to Modify:**
- `GFPriceCheckerApp.swift`
- `ContentView.swift`

**Acceptance Criteria:**
- [ ] App launches without errors
- [ ] SwiftData container properly initialized
- [ ] Preview shows tab bar

**Testing Steps:**
1. Clean build (Cmd+Shift+K)
2. Build and run (Cmd+R)
3. App should launch showing three tabs
4. No console errors related to SwiftData

**Commit Message:**
```
Configure SwiftData model container for ProductPair and Receipt
```

---

## PHASE 2: MANUAL DATA ENTRY (Sessions 4-7)

**Goal:** Build UI for manually adding/editing product pairs before OCR

---

### Session 4: Product Pair List View

**Objective:** Create a view to display all product pairs

**Context for Claude Code:**
```
Create Views/Library/ProductPairListView.swift that:
- Uses @Query to fetch all ProductPairs from SwiftData
- Displays list of product pairs showing:
  * GF product name
  * Price differential (formatted as currency)
  * Category badge (if set)
  * Verification status indicator (checkmark if receipt verified)
- Sorts by created date (newest first)
- Shows empty state when no products exist
- Uses SwiftUI List with proper styling

Make it visually clean and professional.
```

**Files to Create:**
- `Views/Library/ProductPairListView.swift`

**Files to Modify:**
- `ContentView.swift` (replace "Library" Text with ProductPairListView())

**Acceptance Criteria:**
- [ ] List view displays correctly
- [ ] Empty state shows when no data
- [ ] SwiftData query works
- [ ] Proper currency formatting

**Testing Steps:**
1. Run app
2. Navigate to Library tab
3. Should see empty state
4. Add sample data in preview to verify list rendering

**Commit Message:**
```
Add ProductPair list view with empty state
```

---

### Session 5: Manual Product Entry Form

**Objective:** Create form to manually add new product pair

**Context for Claude Code:**
```
Create Views/CaptureFlow/ManualProductEntryView.swift that provides a form with:

Section 1: Gluten-Free Product
- Product name (TextField)
- Price (TextField with currency formatting)
- Size (TextField, optional)
- Category picker (with common categories + custom option)

Section 2: Non-Gluten-Free Equivalent  
- Product name (TextField)
- Price (TextField with currency formatting)
- Size (TextField, optional)

Section 3: Optional
- Notes (TextEditor)

Buttons:
- Cancel (dismiss sheet)
- Save (validate and save to SwiftData)

Validation:
- Product names required
- Prices required and must be valid decimals > 0
- Show inline error messages

Use proper form styling, navigation, and accessibility labels.
```

**Files to Create:**
- `Views/CaptureFlow/ManualProductEntryView.swift`

**Files to Modify:**
- `Views/Library/ProductPairListView.swift` (add + button to show sheet)

**Acceptance Criteria:**
- [ ] Form displays correctly
- [ ] All fields editable
- [ ] Validation works
- [ ] Saves to SwiftData successfully
- [ ] Sheet dismisses after save

**Testing Steps:**
1. Run app, go to Library tab
2. Tap + button
3. Fill in form with sample data
4. Tap Save
5. Should see new item in list
6. Verify differential calculates correctly

**Commit Message:**
```
Add manual product entry form with validation
```

---

### Session 6: Product Detail View & Edit

**Objective:** View and edit existing product pairs

**Context for Claude Code:**
```
Create Views/Library/ProductPairDetailView.swift that:
- Accepts a ProductPair binding
- Displays all product information in organized sections
- Shows product images (if available, placeholder if not)
- Displays calculated differential prominently
- Has Edit button that presents ManualProductEntryView in edit mode
- Has Delete button with confirmation alert
- Proper navigation structure

Also update ManualProductEntryView to support edit mode:
- Accept optional ProductPair parameter
- Pre-populate fields if editing existing
- Update existing record instead of creating new
```

**Files to Create:**
- `Views/Library/ProductPairDetailView.swift`

**Files to Modify:**
- `Views/Library/ProductPairListView.swift` (make rows tappable, navigate to detail)
- `Views/CaptureFlow/ManualProductEntryView.swift` (add edit mode support)

**Acceptance Criteria:**
- [ ] Can tap list item to see detail
- [ ] Detail view shows all information
- [ ] Edit button works
- [ ] Can modify existing product pair
- [ ] Delete works with confirmation
- [ ] Navigation works smoothly

**Testing Steps:**
1. Create a product pair
2. Tap it in list
3. Verify detail view shows correctly
4. Tap Edit, modify values, save
5. Verify changes persist
6. Test delete functionality

**Commit Message:**
```
Add product detail view with edit and delete capabilities
```

---

### Session 7: Category Management

**Objective:** Allow users to create and manage custom categories

**Context for Claude Code:**
```
Create a simple category management system:

1. Create Models/Category.swift:
   - @Model class with name and colorHex properties
   - Predefined categories: Bread, Pasta, Flour, Crackers, Cookies, Cereal, Pizza, Sauce

2. Create Views/Library/CategoryManagerView.swift:
   - List of categories
   - Add new category
   - Delete categories (except predefined)
   - Color picker for each category

3. Update ManualProductEntryView:
   - Category picker uses actual Category objects
   - Shows color indicator next to category name

4. Update ProductPairListView:
   - Show category color badge on each item
```

**Files to Create:**
- `Models/Category.swift`
- `Views/Library/CategoryManagerView.swift`

**Files to Modify:**
- `GFPriceCheckerApp.swift` (add Category to modelContainer)
- `Views/CaptureFlow/ManualProductEntryView.swift` (use Category model)
- `Views/Library/ProductPairListView.swift` (show category colors)
- `ContentView.swift` (add settings/gear icon to access CategoryManagerView)

**Acceptance Criteria:**
- [ ] Can create custom categories
- [ ] Categories persist
- [ ] Color indicators display correctly
- [ ] Can assign category to products
- [ ] Predefined categories exist on first launch

**Testing Steps:**
1. Launch app
2. Create a product with "Bread" category
3. Go to category manager
4. Add custom category "Snacks" with blue color
5. Create product with "Snacks" category
6. Verify colors show in list

**Commit Message:**
```
Add category management with color coding
```

---

## PHASE 3: CAMERA & OCR (Sessions 8-12)

**Goal:** Implement photo capture and text extraction

---

### Session 8: Image Storage Service

**Objective:** Create service to efficiently store and retrieve photos

**Context for Claude Code:**
```
Create Services/ImageStorageService.swift that:
- Saves UIImage to app's Documents directory
- Generates unique filename (UUID)
- Creates thumbnail version (max 200px wide) for list display
- Retrieves full image by UUID
- Retrieves thumbnail by UUID
- Deletes image and thumbnail by UUID
- Handles errors gracefully
- Uses async/await pattern

Best practices:
- Compress images to reasonable size (JPEG at 0.7 quality)
- Store in organized subdirectories (products/, receipts/)
- Return nil if image not found (not crash)
```

**Files to Create:**
- `Services/ImageStorageService.swift`

**Acceptance Criteria:**
- [ ] Can save UIImage and get UUID back
- [ ] Can retrieve saved image
- [ ] Thumbnail generation works
- [ ] File cleanup works
- [ ] No memory leaks

**Testing Steps:**
1. Build project
2. Create test in preview:
   - Save sample image
   - Retrieve it
   - Verify it displays
3. Check app Documents folder to see saved files

**Commit Message:**
```
Add image storage service with thumbnail generation
```

---

### Session 9: Document Scanner Integration

**Objective:** Integrate VisionKit for professional document scanning

**Context for Claude Code:**
```
Create Views/CaptureFlow/DocumentScannerView.swift that:
- Uses VisionKit's DocumentCameraViewController
- Wrapped in UIViewControllerRepresentable for SwiftUI
- Handles delegate callbacks
- Returns captured image to parent view
- Includes cancel functionality
- Proper error handling

The scanner should:
- Auto-detect document edges
- Provide professional camera UI
- Support multiple capture modes
- Return high-quality image
```

**Files to Create:**
- `Views/CaptureFlow/DocumentScannerView.swift`

**Acceptance Criteria:**
- [ ] Scanner UI appears correctly
- [ ] Can capture document
- [ ] Image returns to SwiftUI view
- [ ] Cancel works properly
- [ ] No crashes

**Testing Steps:**
1. Run on physical device (simulator limited for camera)
2. Trigger scanner
3. Point at document
4. Verify edge detection works
5. Capture and verify image returns

**Commit Message:**
```
Integrate VisionKit document scanner for photo capture
```

---

### Session 10: OCR Service - Text Extraction

**Objective:** Create service using Vision framework to extract text from images

**Context for Claude Code:**
```
Create Services/OCRService.swift that:

Function 1: extractText(from: UIImage) async throws -> [VNRecognizedTextObservation]
- Uses Vision framework's VNRecognizeTextRequest
- Recognition level: accurate
- Language: English
- Returns all text observations with bounding boxes

Function 2: findPrices(in: UIImage) async throws -> [PriceMatch]
- Extracts text
- Searches for price patterns: $X.XX, $XX.XX, $XXX.XX
- Returns array of PriceMatch struct with: amount (Decimal), confidence (Float), boundingBox

Function 3: findProductName(in: UIImage) async throws -> String?
- Extracts text from top 30% of image (where product names usually are)
- Returns most prominent text string
- Returns nil if confidence < 0.7

Error handling for:
- Invalid image
- No text detected
- Low confidence results

Include proper struct definitions for return types.
```

**Files to Create:**
- `Services/OCRService.swift`

**Acceptance Criteria:**
- [ ] Can extract text from product label image
- [ ] Price detection works with test images
- [ ] Confidence scores returned
- [ ] Handles images with no text
- [ ] Async/await pattern correct

**Testing Steps:**
1. Take photo of product label with phone
2. Run OCR on it
3. Print detected text and prices
4. Verify accuracy with sample images
5. Test edge cases (blurry image, no text)

**Commit Message:**
```
Add Vision framework OCR service with price detection
```

---

### Session 11: Product Capture Flow with OCR

**Objective:** Create guided flow to capture GF and non-GF products using camera + OCR

**Context for Claude Code:**
```
Create Views/CaptureFlow/ProductCaptureFlowView.swift that:

Step 1: Introduction
- Explain process: "Capture GF product, then regular equivalent, then receipt"
- [Start] button

Step 2: Capture GF Product
- Show DocumentScannerView
- After capture, run OCR
- Show loading indicator during OCR

Step 3: Review GF Product  
- Show captured image thumbnail
- Display OCR-extracted data in editable fields:
  * Product name (with confidence indicator)
  * Price (with confidence indicator)
  * Size (optional)
- [Looks Good] → next step
- [Retake] → back to Step 2

Step 4: Capture Non-GF Product
- Same as Step 2 but for regular product
- Guidance: "Now scan the regular equivalent product"

Step 5: Review Non-GF Product
- Same as Step 3

Step 6: Finalize
- Show side-by-side comparison
- Show differential calculation
- Category picker
- Notes field
- [Save Product Pair] → saves to SwiftData with images
- [Cancel] → discard and return to library

Use clean navigation, progress indicator, and handle all edge cases.
Store images using ImageStorageService and save UUIDs to ProductPair model.
```

**Files to Create:**
- `Views/CaptureFlow/ProductCaptureFlowView.swift`

**Files to Modify:**
- `ContentView.swift` (Capture tab shows ProductCaptureFlowView)
- `Models/ProductPair.swift` (add imageUUID properties for storing image references)

**Acceptance Criteria:**
- [ ] Flow guides through all steps
- [ ] OCR extracts data correctly
- [ ] User can edit OCR results
- [ ] Images save properly
- [ ] Product pair creates successfully
- [ ] Can see saved pair in Library tab

**Testing Steps:**
1. Go to Capture tab
2. Follow complete flow with real products
3. Verify OCR extraction quality
4. Edit any incorrect OCR data
5. Complete flow and verify product appears in library
6. Check that images display in detail view

**Commit Message:**
```
Implement guided product capture flow with OCR assistance
```

---

### Session 12: OCR Confidence Indicators

**Objective:** Add visual indicators for OCR confidence and improve UX

**Context for Claude Code:**
```
Enhance the review screens in ProductCaptureFlowView:

1. Add confidence indicator component:
   - High confidence (>0.85): Green checkmark icon
   - Medium confidence (0.6-0.85): Yellow warning icon + "Please verify"
   - Low confidence (<0.6): Red X icon + "Likely incorrect - please edit"

2. Auto-highlight low-confidence fields for user attention

3. Add "Why?" info button that explains confidence scoring

4. Update field styling:
   - High confidence: Normal style
   - Medium: Yellow border
   - Low: Red border with yellow highlight

5. Add haptic feedback when low confidence detected

Make it intuitive and non-intrusive while ensuring user verifies questionable data.
```

**Files to Modify:**
- `Views/CaptureFlow/ProductCaptureFlowView.swift`
- Create `Utilities/ConfidenceIndicatorView.swift` (reusable component)

**Acceptance Criteria:**
- [ ] Confidence indicators display correctly
- [ ] Colors match confidence levels
- [ ] Visual hierarchy guides user attention
- [ ] Haptics work on low confidence
- [ ] Info popover explains scoring

**Testing Steps:**
1. Test with high-quality product label (should show green)
2. Test with blurry image (should show yellow/red)
3. Verify colors and icons appropriate
4. Confirm users understand what to do

**Commit Message:**
```
Add OCR confidence indicators to guide user verification
```

---

## PHASE 4: RECEIPT VERIFICATION (Sessions 13-15)

**Goal:** Scan receipts and match to products

---

### Session 13: Receipt Scanning View

**Objective:** Create UI to capture and review receipt

**Context for Claude Code:**
```
Create Views/CaptureFlow/ReceiptCaptureView.swift that:

1. Shows list of unverified product pairs (checkbox selection)
2. [Scan Receipt] button → launches DocumentScannerView
3. After capture, runs OCR on receipt
4. Shows receipt image with OCR overlay highlighting detected text
5. Extracts:
   - Store name (from top of receipt)
   - Date (from receipt)
   - All line items with prices
   - Total (from bottom)

6. For each selected product pair, attempts to find matching line item:
   - Fuzzy string matching on product name
   - Exact price matching
   - Highlights potential matches

7. User confirms each match or manually selects correct line
8. [Confirm All] saves receipt and updates product pairs as verified

Use smart matching algorithm that accounts for:
- Abbreviations (UDI GF BRD vs "Udi's Gluten Free Bread")
- Price variations (different sizes)
- Multiple quantities
```

**Files to Create:**
- `Views/CaptureFlow/ReceiptCaptureView.swift`
- `Services/ReceiptParserService.swift` (parsing logic)

**Files to Modify:**
- `Services/OCRService.swift` (add receipt-specific parsing)

**Acceptance Criteria:**
- [ ] Can scan receipt
- [ ] OCR extracts line items
- [ ] Matching suggestions appear
- [ ] User can confirm matches
- [ ] Receipt saves with associations

**Testing Steps:**
1. Create 2-3 unverified product pairs
2. Go to receipt verification flow
3. Scan actual grocery receipt
4. Verify line items detected
5. Match products to receipt lines
6. Confirm products marked as verified

**Commit Message:**
```
Add receipt scanning and product matching functionality
```

---

### Session 14: Receipt Detail View

**Objective:** View receipt details and associated products

**Context for Claude Code:**
```
Create Views/Library/ReceiptDetailView.swift that:
- Shows receipt image (zoomable)
- Displays receipt metadata:
  * Store name
  * Purchase date
  * Total amount
- Lists all associated ProductPairs with differentials
- Shows summary: "3 products verified, total differential: $12.47"
- [Unlink Product] option for each product
- [Delete Receipt] with confirmation (doesn't delete products, just unlinks)

Also update ProductPairListView:
- Add filter toggle: "Show Verified Only" / "Show Unverified Only" / "Show All"
- Add verification badge to each item
```

**Files to Create:**
- `Views/Library/ReceiptDetailView.swift`

**Files to Modify:**
- `Views/Library/ProductPairListView.swift` (add filters, navigation to receipt)

**Acceptance Criteria:**
- [ ] Receipt detail displays correctly
- [ ] Can navigate from product to receipt
- [ ] Filters work in product list
- [ ] Unlinking works properly
- [ ] Images zoom correctly

**Testing Steps:**
1. View verified product
2. Tap to see associated receipt
3. Verify all data displays
4. Test zoom on receipt image
5. Test filter toggles in product list

**Commit Message:**
```
Add receipt detail view and product verification filters
```

---

### Session 15: Bulk Receipt Verification

**Objective:** Allow users to efficiently verify multiple products from one shopping trip

**Context for Claude Code:**
```
Enhance ReceiptCaptureView to support batch operations:

1. Smart date filtering:
   - When user scans receipt, auto-suggest products created on same date
   - "Found 5 products from [date] - verify with this receipt?"

2. Bulk selection:
   - Select all matching date
   - Manual multi-select
   - Deselect all

3. Quick match mode:
   - Auto-match products where price exactly matches receipt line
   - Show only non-matches for user review
   - [Accept All Auto-Matches] button

4. Progress indicator:
   - "3 of 5 products matched"
   - Clear visual feedback

Make it efficient for users who shop weekly and batch-verify.
```

**Files to Modify:**
- `Views/CaptureFlow/ReceiptCaptureView.swift`

**Acceptance Criteria:**
- [ ] Date filtering works
- [ ] Bulk selection intuitive
- [ ] Auto-matching accurate
- [ ] Progress clear
- [ ] Handles edge cases (no matches, all match, etc.)

**Testing Steps:**
1. Create 5 products on same date
2. Scan receipt from that date
3. Verify auto-suggestions appear
4. Test auto-matching
5. Verify all 5 products successfully linked

**Commit Message:**
```
Add bulk receipt verification with auto-matching
```

---

## PHASE 5: EXPORT & REPORTING (Sessions 16-18)

**Goal:** Generate CSV and PDF reports for tax filing

---

### Session 16: Summary Dashboard

**Objective:** Create summary view showing annual statistics

**Context for Claude Code:**
```
Create Views/Reports/SummaryDashboardView.swift that displays:

Header:
- Total annual differential (large, prominent)
- Tax year selector (dropdown: 2024, 2023, etc.)
- Date range display

Statistics Cards:
- Total products tracked
- Products verified vs unverified (pie chart or bar)
- Average differential per product
- Top 5 categories by total differential

Charts:
- Monthly spending differential (line chart)
- Category breakdown (pie chart or bar chart)

Use Swift Charts framework for native visualizations.
Professional, clean design suitable for showing accountant.
```

**Files to Create:**
- `Views/Reports/SummaryDashboardView.swift`
- `ViewModels/ReportViewModel.swift` (calculations logic)

**Files to Modify:**
- `ContentView.swift` (Reports tab shows SummaryDashboardView)

**Acceptance Criteria:**
- [ ] Dashboard displays correctly
- [ ] Calculations accurate
- [ ] Charts render properly
- [ ] Year selector works
- [ ] Updates when data changes

**Testing Steps:**
1. Create diverse product data across multiple months
2. View Reports tab
3. Verify calculations match manual math
4. Test year selector
5. Verify charts make sense

**Commit Message:**
```
Add summary dashboard with charts and annual statistics
```

---

### Session 17: CSV Export

**Objective:** Export data in CRA-compliant CSV format

**Context for Claude Code:**
```
Create Services/CSVExportService.swift that generates CSV with columns:

Purchase Date, GF Product, GF Price, GF Size, Non-GF Product, Non-GF Price, 
Non-GF Size, Differential, Category, Store, Receipt Verified, Notes

Requirements:
- Proper CSV escaping (handle commas in product names)
- Date formatting: YYYY-MM-DD
- Price formatting: decimal with 2 places, no $ symbol
- Boolean as Yes/No for verified
- UTF-8 encoding
- Filter by date range
- Sort by purchase date

Also create Views/Reports/ExportView.swift that:
- Shows date range picker
- Preview of data to be exported (first 10 rows)
- [Export CSV] button → share sheet
- [Email to Accountant] quick action
- Export summary: "Exporting 47 products, total differential $1,247.50"
```

**Files to Create:**
- `Services/CSVExportService.swift`
- `Views/Reports/ExportView.swift`

**Acceptance Criteria:**
- [ ] CSV generates correctly
- [ ] Opens in Excel/Numbers properly
- [ ] All data fields present
- [ ] No encoding issues
- [ ] Share sheet works

**Testing Steps:**
1. Create sample data
2. Go to Export view
3. Generate CSV
4. Share to Files app
5. Open in Numbers/Excel
6. Verify formatting correct

**Commit Message:**
```
Add CSV export with CRA-compliant formatting
```

---

### Session 18: PDF Report Generation

**Objective:** Generate professional branded PDF report

**Context for Claude Code:**
```
Create Services/PDFGeneratorService.swift that generates PDF with:

Page 1: Cover Page
- App logo/name: "GFPriceChecker - Compare, Save, Claim"
- Tax Year: [Year]
- Prepared for: [User can set name in settings]
- Preparation date
- Total differential summary

Page 2: Summary Statistics
- Breakdown by category (table)
- Monthly summary (table)
- Verification status summary

Page 3+: Detailed Transaction List
- Table with all product pairs
- Columns: Date, GF Product, GF Price, Regular Product, Regular Price, Differential, Category, Store
- Subtotals by category
- Grand total at end

Footer on each page:
- Page numbers
- "Generated by GFPriceChecker"

Styling:
- Professional fonts (Helvetica)
- Color scheme: blues and grays
- Proper margins and spacing
- Table borders and alternating row colors
- Logo/branding

Use PDFKit for generation. Support both US Letter and A4 sizes.
```

**Files to Create:**
- `Services/PDFGeneratorService.swift`
- `Resources/AppLogo.swift` (SwiftUI view for logo that can render to PDF)

**Files to Modify:**
- `Views/Reports/ExportView.swift` (add PDF export option)

**Acceptance Criteria:**
- [ ] PDF generates successfully
- [ ] Professional appearance
- [ ] All data included
- [ ] Multi-page support works
- [ ] Branding consistent

**Testing Steps:**
1. Generate PDF with sample data
2. Share and open on device
3. Verify formatting on different viewers
4. Print preview to check pagination
5. Share with others to verify compatibility

**Commit Message:**
```
Add professional PDF report generation with branding
```

---

## PHASE 6: POLISH & TESTING (Sessions 19-20+)

**Goal:** Refine UX, fix bugs, prepare for TestFlight

---

### Session 19: Settings & Preferences

**Objective:** Add settings screen for app configuration

**Context for Claude Code:**
```
Create Views/Settings/SettingsView.swift with sections:

Personal Information (for PDF reports):
- Full name (TextField)
- Tax ID (optional, masked)

Export Preferences:
- Default date range (current year, last 12 months, all time)
- Currency symbol preference ($ CAD, $ USD)
- PDF paper size (Letter, A4)

Data Management:
- [Export All Data] → creates backup JSON
- [Import Data] → restore from backup
- [Clear All Data] with confirmation

About:
- App version
- [Privacy Policy] link
- [How to Use] tutorial button
- [Contact Support] email link
- [Rate App] (when on App Store)

Store preferences using @AppStorage.
Professional layout with sections and icons.
```

**Files to Create:**
- `Views/Settings/SettingsView.swift`
- `Utilities/AppSettings.swift` (settings management)

**Files to Modify:**
- `ContentView.swift` (add gear icon to navigation, show settings sheet)

**Acceptance Criteria:**
- [ ] Settings save and persist
- [ ] All fields functional
- [ ] Clear data works with confirmation
- [ ] Professional appearance

**Testing Steps:**
1. Open settings
2. Change name and preferences
3. Restart app - verify persistence
4. Test data export/import
5. Test clear data

**Commit Message:**
```
Add settings screen with preferences and data management
```

---

### Session 20: Error Handling & Edge Cases

**Objective:** Improve robustness and user experience with errors

**Context for Claude Code:**
```
Review entire app and add comprehensive error handling:

1. OCR failures:
   - Show friendly message: "Couldn't read text - please enter manually"
   - Offer manual entry fallback
   - Don't crash

2. Image storage failures:
   - Handle disk full scenario
   - Graceful degradation (continue without images)
   - User notification

3. Data validation:
   - Price can't be negative
   - Price can't be zero
   - Product name can't be empty
   - Clear error messages

4. Network/sharing failures:
   - PDF/CSV export errors
   - Email not configured
   - Proper error alerts

5. Empty states:
   - No products: "Get started by adding your first product"
   - No receipts: "Verify your products with receipts"
   - No data for date range: "No products found in this period"

Add proper SwiftUI error handling with:
- @State error properties
- .alert modifiers
- User-friendly error messages
- Logging for debugging
```

**Files to Modify:**
- All service files (add throws, try/catch)
- All view files (add error alerts)
- Create `Utilities/ErrorHandler.swift` (centralized error handling)

**Acceptance Criteria:**
- [ ] No crashes on error scenarios
- [ ] User always knows what went wrong
- [ ] Clear recovery paths
- [ ] Graceful degradation

**Testing Steps:**
1. Test all failure scenarios intentionally
2. Verify error messages make sense
3. Confirm user can recover from errors
4. Test on low storage device

**Commit Message:**
```
Add comprehensive error handling and empty states
```

---

### Session 21: Accessibility & VoiceOver

**Objective:** Make app accessible to users with disabilities

**Context for Claude Code:**
```
Add accessibility throughout app:

1. VoiceOver labels:
   - All buttons have clear labels
   - Images have descriptions
   - Form fields have hints

2. Dynamic Type support:
   - Text scales with system preferences
   - Layouts adjust for large text

3. Color contrast:
   - Verify all text readable
   - Don't rely only on color for information

4. Touch targets:
   - Minimum 44x44 points for all tappable elements

5. Keyboard navigation:
   - Proper tab order in forms
   - Can navigate without touching screen

Add accessibility modifiers:
- .accessibilityLabel()
- .accessibilityHint()
- .accessibilityValue()
- .accessibilityAddTraits()
```

**Files to Modify:**
- All view files (add accessibility modifiers)

**Acceptance Criteria:**
- [ ] VoiceOver can navigate entire app
- [ ] All actions speakable and understandable
- [ ] Dynamic Type works correctly
- [ ] Color contrast meets WCAG standards

**Testing Steps:**
1. Enable VoiceOver in iOS Settings
2. Navigate through entire app with VoiceOver
3. Test with Dynamic Type at largest setting
4. Verify contrast with accessibility inspector

**Commit Message:**
```
Add comprehensive accessibility support for VoiceOver and Dynamic Type
```

---

### Session 22: Performance Optimization

**Objective:** Ensure app runs smoothly with large datasets

**Context for Claude Code:**
```
Optimize app performance:

1. Image loading:
   - Lazy load images in lists
   - Use thumbnails in lists, full images only in detail
   - Cache decoded images

2. SwiftData queries:
   - Add proper fetch limits
   - Use pagination for large lists
   - Add indices to frequently queried fields

3. OCR processing:
   - Show progress indicator
   - Process on background thread
   - Cancel if user navigates away

4. PDF generation:
   - Background processing for large reports
   - Progress indicator
   - Memory efficient rendering

5. List performance:
   - Use LazyVStack where appropriate
   - Limit preview data
   - Efficient row rendering

Profile app with Instruments to identify bottlenecks.
```

**Files to Modify:**
- All view files with lists
- All service files with heavy operations
- Add loading states throughout

**Acceptance Criteria:**
- [ ] Lists scroll smoothly with 100+ items
- [ ] OCR doesn't block UI
- [ ] PDF generation handles 1000+ products
- [ ] No memory warnings

**Testing Steps:**
1. Create 100+ product pairs
2. Scroll through list - should be smooth
3. Generate large PDF - should show progress
4. Run in Instruments to verify no issues

**Commit Message:**
```
Optimize performance for large datasets and background processing
```

---

### Session 23: Onboarding & Tutorial

**Objective:** Create first-run experience to guide users

**Context for Claude Code:**
```
Create Views/Onboarding/OnboardingView.swift with:

Page 1: Welcome
- App name and logo
- Tagline: "Compare, Save, Claim"
- Brief description: "Track price differences for tax deductions"

Page 2: How It Works
- Visual: 1. Scan products
- Visual: 2. Verify with receipts
- Visual: 3. Export for taxes

Page 3: Permissions
- Camera: "We need camera access to scan products and receipts"
- Photos: "We save images to track your purchases"
- [Grant Permissions] buttons

Page 4: Get Started
- Quick tip: "Start by adding your first product pair"
- [Get Started] → dismiss onboarding

Show on first launch only using @AppStorage.
Professional design with illustrations/SF Symbols.
```

**Files to Create:**
- `Views/Onboarding/OnboardingView.swift`

**Files to Modify:**
- `GFPriceCheckerApp.swift` (show onboarding if first launch)

**Acceptance Criteria:**
- [ ] Shows on first launch only
- [ ] Can be completed or skipped
- [ ] Permissions requested appropriately
- [ ] Professional appearance

**Testing Steps:**
1. Delete app and reinstall
2. Launch - verify onboarding appears
3. Complete onboarding
4. Relaunch - verify doesn't show again
5. Test skip functionality

**Commit Message:**
```
Add onboarding flow for first-time users
```

---

### Session 24: App Icon & Launch Screen

**Objective:** Create professional app icon and launch experience

**Context for Claude Code:**
```
1. Design app icon (or I'll provide):
   - 1024x1024 base image
   - Represents gluten-free tracking (wheat symbol crossed out + price tag)
   - Color scheme: blues and orange
   - Clean, professional

2. Create icon set:
   - Generate all required sizes for iOS
   - Add to Assets.xcassets

3. Launch screen:
   - App logo centered
   - Tagline below
   - Clean white/blue gradient background
   - Matches onboarding aesthetic

4. Update app display name:
   - "GFPriceChecker" → might be long
   - Consider: "GF Tracker" or "Price Checker" for home screen

Note: I can help with icon concept, but actual design might need external tool.
```

**Files to Create/Modify:**
- `Assets.xcassets/AppIcon.appiconset/` (add all icon sizes)
- `LaunchScreen.storyboard` or use new SwiftUI launch screen

**Acceptance Criteria:**
- [ ] Icon displays correctly on home screen
- [ ] All icon sizes present
- [ ] Launch screen looks professional
- [ ] Transitions smoothly to app

**Testing Steps:**
1. Install on device
2. View icon on home screen
3. Launch app and observe launch screen
4. Verify no visual glitches

**Commit Message:**
```
Add app icon and professional launch screen
```

---

### Session 25: TestFlight Preparation

**Objective:** Final polish and prepare for TestFlight distribution

**Context for Claude Code:**
```
Pre-TestFlight checklist:

1. Code cleanup:
   - Remove all print() debug statements
   - Remove commented code
   - Fix all warnings
   - Add proper documentation

2. Build configurations:
   - Verify bundle identifier correct
   - Set version: 1.0
   - Set build number: 1
   - Configure code signing

3. Privacy manifest:
   - Document all data collection (none for MVP)
   - Explain camera/photo usage
   - API usage descriptions

4. App Store metadata prep:
   - Screenshot device: iPhone 15 Pro
   - Key screenshots: capture flow, library, PDF export
   - App description draft
   - Keywords

5. Beta testing instructions:
   - What to test
   - How to provide feedback
   - Known limitations

Create TESTING_GUIDE.md for your wife and other testers.
```

**Files to Create:**
- `TESTING_GUIDE.md`
- `CHANGELOG.md`
- `PrivacyInfo.xcprivacy`

**Files to Modify:**
- Project settings (version, build, signing)

**Acceptance Criteria:**
- [ ] No warnings in Xcode
- [ ] Builds successfully for TestFlight
- [ ] All metadata ready
- [ ] Testing guide complete

**Testing Steps:**
1. Archive build (Product → Archive)
2. Verify no errors
3. Upload to TestFlight
4. Wait for processing
5. Invite beta testers

**Commit Message:**
```
Prepare v1.0 for TestFlight beta distribution
```

---

## POST-MVP ENHANCEMENTS (Future Sessions)

These are not part of MVP but good future additions:

### Future: iCloud Sync
- Add CloudKit integration
- Sync across devices
- Conflict resolution

### Future: Widgets
- Home screen widget showing YTD differential
- Lock screen widget with quick add

### Future: Watch App
- Quick capture from wrist
- View summaries

### Future: Advanced Analytics
- Trend analysis
- Predictive savings
- Store comparison

### Future: Export to Tax Software
- TurboTax integration
- Direct CRA NetFile support

### Future: Sharing & Collaboration
- Family sharing
- Export to partner/spouse

---

## Troubleshooting Guide

### Common Issues:

**Issue: SwiftData migration errors after model changes**
Solution: Delete app from simulator, clean build folder, rebuild

**Issue: OCR not detecting text**
Solution: Ensure good lighting, high-quality photos, text orientation correct

**Issue: PDF won't generate**
Solution: Check console for errors, verify sufficient storage, test with smaller dataset

**Issue: Images not loading**
Solution: Verify ImageStorageService paths, check file permissions

**Issue: Build fails with signing errors**
Solution: Update provisioning profile, verify bundle ID unique

---

## Testing Checklist for Each Session

After completing each session:
- [ ] Code compiles without errors
- [ ] Code compiles without warnings
- [ ] Feature works as specified
- [ ] No crashes during testing
- [ ] UI looks professional
- [ ] Tested on simulator AND device (when camera involved)
- [ ] Git committed with proper message
- [ ] README updated if needed

---

## Success Metrics

MVP is complete when:
- ✅ Can manually enter product pairs
- ✅ Can capture products with camera + OCR assistance
- ✅ Can verify products with receipt scanning
- ✅ Can export CSV for tax filing
- ✅ Can generate professional PDF report
- ✅ No critical bugs
- ✅ Your wife successfully uses it for one shopping trip
- ✅ Ready to pitch to Celiac Canada

---

**You're ready to build! Start with Session 1.**

Questions? Reference this plan. Stuck? Describe the problem clearly to Claude Code with context.

Good luck! 🚀
