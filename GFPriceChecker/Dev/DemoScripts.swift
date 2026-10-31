//
//  DemoScripts.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-10-31.
//

#if DEBUG
import Foundation
import GFCore
import SwiftData
import SwiftUI

/// The scripts `DemoDirector` plays, one per take. The timings are the
/// storyboard: retiming a take is an edit here and a rebuild, never a re-shoot.
///
/// `tour` is Stage 5's, and exists to prove the mechanism end to end. The other
/// three are Stage 6's storyboards for the website's three videos, one each:
/// `price-tracking`, `receipt-management` and `reporting-exporting`.
///
/// The capture takes scan `SampleScanImages`' drawn shelf tags and receipt
/// through `ScannerImageProvider`, so real Vision OCR runs on every take and
/// a regression in it shows up as a failed script, not a quietly wrong video.
@MainActor
enum DemoScripts {

    /// Every script `run` knows, which is what `GFPC_DEMO_SCRIPT` is checked
    /// against. `nonisolated` so a parameterized test can take it as arguments.
    nonisolated static let names = ["tour", "price-tracking", "receipt-management", "reporting-exporting"]

    static func run(_ name: String, on d: DemoDirector) async throws {
        guard let script = script(named: name) else { throw DemoDirector.DemoError.unknownScript(name) }
        try await script(d)
    }

    /// The script `name` plays, or `nil`. Apart from `run` so a test can check
    /// every name dispatches without sitting through the script.
    static func script(named name: String) -> ((DemoDirector) async throws -> Void)? {
        switch name {
        case "tour": tour
        case "price-tracking": priceTracking
        case "receipt-management": receiptManagement
        case "reporting-exporting": reportingExporting
        default: nil
        }
    }

    /// Setup a script needs that no take should show, run behind the curtain
    /// after any seed has landed.
    static func prepare(_ name: String, on d: DemoDirector) async throws {
        switch name {
        case "receipt-management":
            try await insertReceiptPairs(d)
            await warm(.library, d)
        case "reporting-exporting": await warm(.reports, d)
        default: break
        }
    }

    // MARK: - tour

    /// Each tab in turn, a product, and the export sheet driven through its
    /// view model. Touches every primitive a real storyboard will use: `push`
    /// to a tab, a pushed screen and a sheet, `screen(_:)` on a registered
    /// view model, an animated write to it, and a `still()`.
    ///
    /// Wants a seeded store, for the product and for a Reports tab with
    /// something on it.
    private static func tour(_ d: DemoDirector) async throws {
        // The Capture tab, as the app opens
        await d.wait(1.0)

        await d.push(.tab(.library))
        await d.wait(1.5)

        await d.push(try d.destination("product"))
        await d.wait(2.0)

        await d.push(.tab(.reports))
        await d.wait(1.0)
        await d.still()

        await d.push(.export)
        let export = try await d.screen(ExportViewModel.self)
        await d.wait(1.0)
        d.animate { export.exportFormat = .pdf }
        await d.wait(1.5)

        // Back to a tab, not straight on to another sheet: see `push`.
        await d.push(.tab(.reports))
        await d.wait(1.0)
    }

    // MARK: - price-tracking

    /// Site video 1, "Capturing a Product Pair": scan the gluten-free bread's
    /// shelf tag, pick its name, price and size from what the scan read, do the
    /// same for the regular loaf, pick a category, save, and open the new pair.
    ///
    /// Still: the finalize screen, which carries both products and the
    /// differential.
    private static func priceTracking(_ d: DemoDirector) async throws {
        // The Capture tab, as the app opens
        await d.wait(1.0)

        await d.push(.captureFlow)
        let capture = try await d.screen(CaptureFlowViewModel.self)
        await d.wait(1.5)

        ScannerImageProvider.enqueue(
            SampleScanImages.shelfTag(SampleScanImages.glutenFreeBread),
            SampleScanImages.shelfTag(SampleScanImages.regularBread)
        )
        capture.startCapture()
        try await review(capture, isGF: true, name: "Gluten Free", price: "7.49", size: "400", on: d)

        d.animate { capture.continueFromReview(isGF: true) }
        try await review(capture, isGF: false, name: "White Sandwich", price: "3.29", size: "570", on: d)

        d.animate { capture.continueFromReview(isGF: false) }
        await d.wait(1.5)
        d.animate { capture.category = "Bread" }
        await d.wait(2.0)
        await d.still()

        // Saving dismisses the sheet
        guard let context = d.context else { throw DemoDirector.DemoError.notAttached }
        capture.save(into: context)
        await d.wait(1.0)

        await d.push(.tab(.library))
        await d.wait(1.5)
        await d.push(try d.destination("product"))
        await d.wait(2.5)
    }

    /// Waits for one product's scan to be read, then taps its name, price and
    /// size rows in turn. Each row is found by what it reads, so a scan that
    /// reads differently fails the take rather than picking the wrong row.
    private static func review(_ capture: CaptureFlowViewModel, isGF: Bool,
                               name: String, price: String, size: String,
                               on d: DemoDirector) async throws {
        let step: CaptureStep = isGF ? .reviewGF : .reviewNonGF
        try await d.waitUntil("the \(isGF ? "GF" : "regular") scan to be read") {
            capture.currentStep == step && !capture.isProcessingOCR
        }
        // The scanner's sheet is still going down
        await d.wait(1.5)

        let rows = isGF ? capture.gfOCRObservations : capture.nonGFOCRObservations
        for text in [name, price, size] {
            guard let row = rows.first(where: { $0.text.localizedCaseInsensitiveContains(text) }) else {
                throw DemoDirector.DemoError.notOnScreen(text)
            }
            d.animate(.easeInOut(duration: 0.3)) { _ = capture.handleReviewTap(row, isGF: isGF) }
            await d.wait(1.2)
        }
        await d.wait(0.8)
    }

    // MARK: - receipt-management

    /// The two pairs the drawn receipt verifies, unverified, inserted behind
    /// the curtain. The seeded library is all verified, so these are the
    /// only pairs the take offers.
    ///
    /// Dated the morning of the receipt, as a shopper who captured on the way
    /// round the store would have them.
    private static func insertReceiptPairs(_ d: DemoDirector) async throws {
        guard let context = d.context else { throw DemoDirector.DemoError.notAttached }
        let shopped = ISO8601DateFormatter().date(from: "2026-03-14T14:05:00-04:00") ?? .now

        func pair(_ gf: SampleScanImages.ShelfTag, _ regular: SampleScanImages.ShelfTag,
                  category: String, minutesIn: Double) async -> ProductPair {
            ProductPair(
                gfProductName: gf.name,
                gfPrice: Decimal(string: gf.price.replacingOccurrences(of: "$", with: "")) ?? 0,
                gfSize: gf.size.replacingOccurrences(of: " ", with: ""),
                gfSizeValue: Decimal(string: SizeTextParser.parseSize(gf.size).value),
                gfImageUUID: await ImageStorageService.shared.saveImage(
                    SampleScanImages.shelfTag(gf), type: .product),
                nonGFProductName: regular.name,
                nonGFPrice: Decimal(string: regular.price.replacingOccurrences(of: "$", with: "")) ?? 0,
                nonGFSize: regular.size.replacingOccurrences(of: " ", with: ""),
                nonGFSizeValue: Decimal(string: SizeTextParser.parseSize(regular.size).value),
                nonGFImageUUID: await ImageStorageService.shared.saveImage(
                    SampleScanImages.shelfTag(regular), type: .product),
                sizeUnit: SizeTextParser.parseSize(gf.size).unit?.rawValue,
                createdDate: shopped.addingTimeInterval(minutesIn * 60),
                category: category,
                verified: false
            )
        }

        context.insert(await pair(SampleScanImages.glutenFreeBread, SampleScanImages.regularBread,
                                  category: "Bread", minutesIn: 0))
        context.insert(await pair(SampleScanImages.glutenFreePenne, SampleScanImages.regularPenne,
                                  category: "Pasta", minutesIn: 6))
        try context.save()
    }

    /// Site video 2, "Verifying Against a Receipt": pick the two unverified
    /// pairs, scan the receipt, confirm the line each one was bought on, save,
    /// and open the receipt with its products.
    ///
    /// Still: the matching screen with the first pair's line selected.
    private static func receiptManagement(_ d: DemoDirector) async throws {
        await d.wait(1.0)

        await d.push(.receiptCapture)
        let receipt = try await d.screen(ReceiptCaptureViewModel.self)
        try await d.waitUntil("the unverified pairs") { receipt.unverifiedProducts.count == 2 }
        await d.wait(1.5)

        for product in receipt.unverifiedProducts.sorted(by: { $0.createdDate < $1.createdDate }) {
            d.animate(.easeInOut(duration: 0.3)) { receipt.toggleProductSelection(product) }
            await d.wait(0.8)
        }
        await d.wait(0.8)
        let verified = receipt.productsToVerify

        d.animate { receipt.continueToScan() }
        await d.wait(1.5)

        ScannerImageProvider.enqueue(SampleScanImages.receipt(SampleScanImages.groceryReceipt))
        receipt.openScanner()
        try await d.waitUntil("the receipt to be read") {
            receipt.currentStep == .reviewMatches && !receipt.isProcessingOCR
        }
        await d.wait(1.5)

        var first = true
        while let product = receipt.currentProductToVerify {
            // The line the screen marks "Suggested", so the take taps what a
            // viewer's eye is already on
            guard let line = receipt.suggestedReceiptLine(for: product) else {
                throw DemoDirector.DemoError.notOnScreen(product.gfProductName)
            }
            d.animate(.easeInOut(duration: 0.3)) { receipt.selectReceiptLine(line) }
            await d.wait(1.5)
            if first { await d.still() }
            first = false
            d.animate { receipt.confirmSelectedLine() }
            await d.wait(1.5)
        }
        await d.wait(1.0)

        // Saving dismisses the sheet
        guard let context = d.context else { throw DemoDirector.DemoError.notAttached }
        guard await receipt.save(into: context), let saved = verified.first?.receipt else {
            throw DemoDirector.DemoError.timedOut("the receipt to save")
        }
        // Pushing onto the Library's stack while the sheet is still sliding
        // away stalls the push halfway for seconds, so both get room.
        await d.wait(1.5)

        await d.push(.tab(.library))
        await d.wait(1.5)
        await d.push(.receipt(saved))
        await d.wait(3.0)
    }

    // MARK: - Warm-up

    /// A tab's first appearance over the seeded library holds the screen for
    /// seconds, which a take reads as a long stare at the Capture tab. A tab
    /// stays built once shown, so the one a take is headed for is shown once
    /// behind the curtain, and the take opens on Capture as the others do.
    /// The receipt sheet counts: it is presented from the Library tab.
    private static func warm(_ tab: AppRouter.Tab, _ d: DemoDirector) async {
        await d.push(.tab(tab))
        await d.wait(1.0)
        await d.push(.tab(.capture))
    }

    // MARK: - reporting-exporting

    /// Site video 3, "Exporting Your Records": the Reports dashboard, then the
    /// export sheet switched to a PDF of the year, generated and handed to the
    /// share sheet.
    ///
    /// Still: the dashboard.
    private static func reportingExporting(_ d: DemoDirector) async throws {
        await d.wait(1.0)

        await d.push(.tab(.reports))
        await d.wait(3.0)
        await d.still()

        await d.push(.export)
        let export = try await d.screen(ExportViewModel.self)
        await d.wait(2.0)
        d.animate { export.exportFormat = .pdf }
        await d.wait(2.0)

        await export.export()
        // The seeded library is all verified, so this is not expected; but a
        // dataset with unverified pairs would otherwise stop the take here.
        if export.showingUnverifiedWarning {
            await d.wait(1.5)
            await export.confirmUnverifiedExport()
        }
        try await d.waitUntil("the share sheet") { export.showingShareSheet }
        await d.wait(3.0)
    }
}
#endif
