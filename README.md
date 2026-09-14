# GFPriceChecker

**Compare, Save, Claim**

Track price differentials between gluten-free and regular products.

---

## Overview

GFPriceChecker is an iOS app that helps people with celiac disease document what gluten-free food actually costs them compared to the regular equivalent. Canada's Medical Expense Tax Credit lets that incremental cost be claimed as a medical expense, and the tedious part is the record-keeping, not the arithmetic.

**Status:** Public TestFlight beta since January 2026. The 1.0 App Store submission is the current milestone.

**Website:** [gfpricechecker.com](https://gfpricechecker.com) — features, FAQ, beta signup, privacy policy and terms.

### The Problem

Documenting a year of gluten-free purchases by hand means:
- Keeping every receipt
- Finding the regular equivalent and its price
- Adjusting for package size, so a 450 g loaf and a 675 g loaf compare honestly
- Calculating each differential
- Organizing it all into something an accountant can read

### The Solution

GFPriceChecker streamlines this by:
1. **Capturing product pairs** — scan the gluten-free product and its regular equivalent in-store
2. **OCR assistance** — read prices and sizes off shelf tags automatically
3. **Unit pricing** — compare by unit ($/100 g for weights, $/unit otherwise) rather than per package, so different sizes compare fairly
4. **Receipt verification** — link products to the receipt that proves the purchase
5. **Export** — produce a PDF report or CSV spreadsheet of a year's records

---

## Features

- ✅ **Product Pair Tracking** — store GF and non-GF product information, with package size
- ✅ **Camera Integration** — document scanning with VisionKit
- ✅ **OCR Text Extraction** — read prices and sizes from shelf tags and receipts
- ✅ **Receipt Verification** — link products to receipts, with fuzzy matching against receipt lines
- ✅ **Categories** — organize products by type
- ✅ **CSV Export** — itemized spreadsheet of a year's products
- ✅ **PDF Reports** — branded multi-page report, receipt images included
- ✅ **Summary Dashboard** — annual statistics and insights
- ✅ **Backup & Restore** — JSON backup containing images

### Privacy & Security

- 🔒 **Local-first** — all data stored on device only
- 🔒 **No tracking** — zero analytics or data collection
- 🔒 **No account required** — no registration, no cloud
- 🔒 **Full control** — export and delete your data anytime

---

## Technical Architecture

### Stack

- **Platform:** iOS 18.0+
- **Language:** Swift, 5.0 language mode (`SWIFT_VERSION = 5.0`) on the Xcode 26 toolchain
- **UI Framework:** SwiftUI
- **Data Persistence:** SwiftData
- **OCR:** Vision Framework
- **Document Scanning:** VisionKit
- **PDF Generation:** PDFKit
- **Architecture:** MVVM (Model-View-ViewModel)

Note the project is *not* in Swift 6 language mode. It does run with the Xcode 26 defaults
`SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which is
why so few types carry an explicit `@MainActor`. See the Concurrency section of `claude.md`.

### Project Structure
```
GFPriceChecker/
├── Models/              # SwiftData models
│   ├── ProductPair.swift
│   └── Receipt.swift
├── ViewModels/          # Flow state and business logic
│   ├── CaptureFlowViewModel.swift
│   └── ReportViewModel.swift
├── Views/               # SwiftUI views
│   ├── CaptureFlow/     # Product and receipt capture
│   ├── Library/         # Product list and details
│   ├── Reports/         # Analytics and export
│   ├── Settings/        # App configuration
│   ├── Onboarding/
│   └── Components/      # Reusable UI components
├── Services/            # Business services
│   ├── OCRService.swift
│   ├── ReceiptParserService.swift
│   ├── ImageStorageService.swift
│   ├── CSVExportService.swift
│   ├── PDFGeneratorService.swift
│   └── DataBackupService.swift
├── Utilities/           # Helpers and extensions
└── Resources/           # App branding
```

A fuller map, with the patterns worth knowing before changing any of it, is in `claude.md`.

---

## What This App Does and Doesn't Claim

The app helps you keep records. It does not file anything, and it makes no claim about what you
are eligible to deduct.

### What it gives you

- ✅ **Incremental cost tracking** — the GF versus regular difference, adjusted for package size
- ✅ **Receipt documentation** — products linked to the purchase that backs them
- ✅ **Detailed records** — product names, dates, stores, amounts
- ✅ **Exportable records** — CSV and PDF

### What remains yours to do

- Obtain a medical diagnosis letter from a doctor
- Only claim products for the person with celiac disease
- Keep your receipts
- Ensure the price comparisons are reasonable equivalents

**Note:** This app is a record-keeping tool, not tax advice. The exports are not endorsed by, approved by, or affiliated with the Canada Revenue Agency. Consult a tax professional about your own situation — and note the Medical Expense Tax Credit only applies to medical expenses above a threshold of roughly three percent of net income, so a modest year may not reach it.

---

## Development Setup

### Prerequisites

- Xcode 26.1.1
- iOS 18.0+ device or simulator
- Apple Developer account (for device testing)

### Installation

1. Clone repository:
```bash
git clone https://github.com/CuWilliams/GFPriceChecker.git
cd GFPriceChecker
```

2. Open in Xcode:
```bash
open GFPriceChecker.xcodeproj
```

3. Build and run:
- Select target device/simulator
- Press Cmd+R

Note that no shared scheme is committed; the `GFPriceChecker` scheme resolves from your local
`xcuserdata` the first time you open the project.

### Testing

Tests are Swift Testing (`import Testing`), not XCTest. From Xcode, Cmd+U. From the command line:

```bash
xcodebuild test -scheme GFPriceChecker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:GFPriceCheckerTests
```

`-parallel-testing-enabled NO` is not optional — without it xcodebuild clones a second simulator
and the run dies on insufficient system resources. Drop `-only-testing:` to include the UI tests.

---

## Usage Guide

### Adding a Product Pair

1. Tap **Capture** tab
2. Follow guided flow:
   - Scan gluten-free product shelf tag
   - Review and edit OCR-extracted price and size
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

### Exporting Your Records

1. Go to **Reports** tab
2. Review summary dashboard
3. Select date range (tax year)
4. Choose export format:
   - CSV for spreadsheet software
   - PDF for a printed report
5. Share via email, AirDrop, or Files

---

## Roadmap

Tracked in [GitHub Issues](https://github.com/CuWilliams/GFPriceChecker/issues) and the
GFPriceChecker Roadmap project. The 1.0 App Store submission is milestone `1.0 - App Store`.

Longer-term ideas, none of them committed: iCloud sync, a home screen widget, bulk operations,
and continued OCR accuracy work.

---

## Documentation

- **`claude.md`** — development guide: patterns, conventions, testing strategy, known limitations
- **`docs/DEVELOPMENT_HISTORY.md`** — session-by-session implementation log, Sessions 1-27
- **`docs/SCRIPTED_DEMO_PIPELINE.md`** — plan for generating the website's instructional videos
- **`docs/archive/`** — superseded planning documents, kept as a historical record
- **[CuWilliams/shared-docs](https://github.com/CuWilliams/shared-docs)** — documentation shared
  with the website and any future Android app: content conventions, and the platform-independent
  product definition. Also the CLAUDE.md tooling used across all repos.

---

## Contributing

This is a personal project and the repository is private. Contributions are not open at this time.

Feedback from beta testers is very welcome — through TestFlight, or by email.

---

## Support & Feedback

- **Beta testers:** submit feedback via TestFlight, and include a screenshot with bug reports
- **Email:** gfpricechecker@gmail.com
- **Issues:** GitHub Issues

---

## License

Not yet chosen. The repository is private and no license is granted for reuse.

Copyright © 2026 Curtis Williams

---

## Acknowledgments

Built for the celiac community, starting with one person who needed a better way to track the cost.

Special thanks to Canadian celiac advocacy organizations, and to the beta testers.

---

## Disclaimer

This app is a record-keeping tool, not tax advice. It is not affiliated with, endorsed by, or approved by the Canada Revenue Agency. Always consult a qualified tax professional regarding your specific situation. Tax rules and regulations are subject to change.

---

**GFPriceChecker - Compare, Save, Claim**

*Making the cost of celiac disease easier to document, one product at a time.*
