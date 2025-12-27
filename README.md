# GFPriceChecker

**Compare, Save, Claim**

Track price differentials between gluten-free and regular products for Canadian tax deductions.

---

## Overview

GFPriceChecker is an iOS app designed to help individuals with celiac disease track the incremental costs of gluten-free products compared to regular equivalents. This data is used to claim medical expense tax deductions with the Canada Revenue Agency (CRA).

### The Problem

People with celiac disease can claim the price difference between gluten-free and regular products as a medical expense deduction. However, tracking this data throughout the year is tedious:
- Saving all receipts
- Manually calculating differentials
- Organizing data for tax filing
- Providing documentation for CRA audits

### The Solution

GFPriceChecker streamlines this process by:
1. **Capturing product pairs** - Scan gluten-free and regular products in-store
2. **OCR assistance** - Automatically extract prices from photos
3. **Receipt verification** - Link purchases to receipts for documentation
4. **Export for taxes** - Generate CRA-compliant CSV and professional PDF reports

---

## Features

### Core Functionality (MVP)

- ✅ **Product Pair Tracking** - Store GF and non-GF product information
- ✅ **Camera Integration** - Professional document scanning with VisionKit
- ✅ **OCR Text Extraction** - Automatically read prices from labels and receipts
- ✅ **Receipt Verification** - Link products to receipts for audit trail
- ✅ **Category Management** - Organize products by type with custom categories
- ✅ **CSV Export** - CRA-compliant spreadsheet export
- ✅ **PDF Reports** - Professional branded reports for accountants
- ✅ **Summary Dashboard** - Annual statistics and insights

### Privacy & Security

- 🔒 **Local-first** - All data stored on device only
- 🔒 **No tracking** - Zero analytics or data collection
- 🔒 **No account required** - No registration, no cloud
- 🔒 **Full control** - Export and delete your data anytime

---

## Technical Architecture

### Stack

- **Platform:** iOS 17.0+
- **Language:** Swift 6
- **UI Framework:** SwiftUI
- **Data Persistence:** SwiftData
- **OCR:** Vision Framework
- **Document Scanning:** VisionKit
- **PDF Generation:** PDFKit
- **Architecture:** MVVM (Model-View-ViewModel)

### Project Structure
```
GFPriceChecker/
├── Models/              # SwiftData models
│   ├── ProductPair.swift
│   ├── Receipt.swift
│   └── Category.swift
├── ViewModels/          # Business logic
│   └── ReportViewModel.swift
├── Views/               # SwiftUI views
│   ├── CaptureFlow/     # Product and receipt capture
│   ├── Library/         # Product list and details
│   ├── Reports/         # Analytics and export
│   └── Settings/        # App configuration
├── Services/            # Business services
│   ├── OCRService.swift
│   ├── ImageStorageService.swift
│   ├── CSVExportService.swift
│   └── PDFGeneratorService.swift
└── Utilities/           # Helpers and extensions
```

---

## CRA Compliance

This app helps users comply with CRA medical expense deduction requirements for celiac disease:

### Requirements Met

- ✅ **Incremental cost tracking** - Calculates GF vs regular price difference
- ✅ **Receipt documentation** - Links products to purchase receipts
- ✅ **Detailed records** - Product names, dates, stores, amounts
- ✅ **Exportable documentation** - CSV and PDF formats for submission

### User Responsibilities

Users must still:
- Obtain medical diagnosis letter from doctor
- Only claim products for person with celiac disease
- Keep receipts for CRA audit requests
- Ensure price comparisons are reasonable equivalents

**Note:** This app assists with tracking - it does not provide tax advice. Consult a tax professional for filing guidance.

---

## Development Setup

### Prerequisites

- macOS Sonoma 14.0+
- Xcode 15.0+
- iOS 17.0+ device or simulator
- Apple Developer account (for device testing)

### Installation

1. Clone repository:
```bash
git clone https://github.com/[YOUR-USERNAME]/GFPriceChecker.git
cd GFPriceChecker
```

2. Open in Xcode:
```bash
open GFPriceChecker.xcodeproj
```

3. Build and run:
- Select target device/simulator
- Press Cmd+R

### Testing

Run tests:
```bash
# Unit tests
Cmd+U in Xcode

# UI tests
Xcode → Product → Test
```

---

## Usage Guide

### Adding a Product Pair

1. Tap **Capture** tab
2. Follow guided flow:
   - Scan gluten-free product label
   - Review and edit OCR-extracted data
   - Scan regular equivalent product
   - Review and confirm
   - Add optional category/notes
3. Product saved to Library

### Verifying with Receipt

1. Go to **Library** tab
2. Select unverified products
3. Tap **Verify with Receipt**
4. Scan receipt
5. Confirm product matches
6. Products marked as verified ✓

### Exporting for Taxes

1. Go to **Reports** tab
2. Review summary dashboard
3. Select date range (tax year)
4. Choose export format:
   - CSV for spreadsheet software
   - PDF for professional report
5. Share via email, AirDrop, or Files

---

## Roadmap

### v1.0 (MVP) - Current
- Manual and OCR-assisted product entry
- Receipt verification
- CSV and PDF export
- Local storage only

### v1.1 (Planned)
- iCloud sync across devices
- Home screen widget
- Improved OCR accuracy
- Bulk operations

### v2.0 (Future)
- Android version
- Advanced analytics
- Multi-user support (families)
- Integration with tax software

---

## Contributing

This is currently a personal project. Contributions welcome after initial release.

### Development Guidelines

- Follow existing code style (SwiftLint rules)
- Write tests for new features
- Update documentation
- Use conventional commits

---

## Support & Feedback

### For Beta Testers

- Submit feedback via TestFlight
- Report bugs with screenshots
- Suggest features in testing channel

### General Inquiries

- Email: [your-email]
- Issues: GitHub Issues (when public)

---

## Partnership Opportunities

Interested in partnering? This app is being developed with potential support from:

- **Celiac Canada** - National advocacy organization
- **Canadian Celiac Association** - Provincial chapters
- Other gluten-free advocacy groups

Contact for partnership discussions.

---

## License

[To be determined - likely MIT or Apache 2.0 for open source]

Copyright © 2024 [Your Name]

---

## Acknowledgments

Built for the celiac community, starting with one person who needed a better way to track medical expenses.

Special thanks to:
- Canadian celiac advocacy organizations
- CRA for providing medical expense provisions
- Beta testers providing valuable feedback

---

## Disclaimer

This app is a tracking tool, not tax advice. Always consult with a qualified tax professional regarding your specific situation. CRA rules and regulations are subject to change.

---

**GFPriceChecker - Compare, Save, Claim**

*Making tax deductions for celiac disease easier, one product at a time.*
