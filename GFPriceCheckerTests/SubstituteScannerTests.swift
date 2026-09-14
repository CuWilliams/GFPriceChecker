//
//  SubstituteScannerTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-09-13.
//

import Foundation
import Testing
import UIKit
@testable import GFPriceChecker

/// Covers the no-camera seam that lets the capture flows run in the Simulator.
///
/// The seam's whole value rests on one thing the compiler cannot check: that the
/// substitute images are actually *readable*. A sample the capture flow cannot
/// get a price out of leaves the flow just as stuck as a blank scanner sheet did,
/// and it would fail silently — the flow still advances to the review step, only
/// with every field empty.
///
/// So these tests run the real `OCRService` and the real `ReceiptParserService`
/// over the drawn images and assert the values the flows depend on come back.
@MainActor
@Suite("Substitute scanner", .serialized)
struct SubstituteScannerTests {

    // MARK: - Shelf Tags

    @Test("Every sample in the catalog renders")
    func catalogRenders() {
        let samples = SampleScanImages.catalog
        #expect(samples.count == 5)

        for sample in samples {
            let image = sample.image()
            #expect(image.size.width > 0, "\(sample.id) rendered an empty image")
            #expect(image.size.height > 0, "\(sample.id) rendered an empty image")
        }

        let ids = Set(samples.map(\.id))
        #expect(ids.count == samples.count, "sample ids must be unique — they key the ForEach")
    }

    @Test("A shelf tag yields its name, price and size to OCR")
    func shelfTagIsReadable() async throws {
        let image = SampleScanImages.shelfTag(SampleScanImages.glutenFreeBread)
        let observations = try await OCRService.shared.extractSelectableText(from: image)
        let text = observations.map(\.text).joined(separator: "\n")

        #expect(text.contains("7.49"), "shelf price missing from OCR:\n\(text)")
        #expect(text.contains("Gluten Free"), "product name missing from OCR:\n\(text)")
        #expect(
            text.range(of: #"400\s*g"#, options: .regularExpression) != nil,
            "package size missing or unparseable:\n\(text)"
        )
        #expect(
            text.range(of: #"1\.87\s*/\s*100\s*g"#, options: .regularExpression) != nil,
            "unit price missing or unparseable:\n\(text)"
        )
    }

    @Test("OCR reads shelf tags at high confidence")
    func shelfTagConfidenceIsHigh() async throws {
        let image = SampleScanImages.shelfTag(SampleScanImages.regularBread)
        let observations = try await OCRService.shared.extractSelectableText(from: image)

        let worst = try #require(observations.map(\.confidence).min())
        #expect(worst >= 0.6, "a sample should not be read less confidently than a real photo")
    }

    /// The point of drawing the shelf price largest: `findPrices` weights font
    /// size at 50%, so the tag has to make the shelf price beat the unit price
    /// printed below it. If this inverts, the capture flow auto-fills $1.87.
    @Test("The shelf price outranks the unit price on the same tag")
    func shelfPriceOutranksUnitPrice() async throws {
        let image = SampleScanImages.shelfTag(SampleScanImages.glutenFreeBread)
        let prices = try await OCRService.shared.findPrices(in: image)

        let top = try #require(prices.first, "no price candidates found on the tag")
        #expect(top.amount == Decimal(string: "7.49"))
        #expect(prices.count > 1, "the unit price should also be a candidate, just a worse one")
    }

    /// Parameterized over plain ids rather than over the `ShelfTag` values
    /// themselves: the arguments are evaluated outside the suite's actor, so a
    /// type reference in that position picks up an isolation warning that is an
    /// error under the Swift 6 language mode.
    @Test("Each tag in the catalog gives up its own price",
          arguments: ["gf-bread", "regular-bread", "gf-penne", "regular-penne"])
    func everyTagYieldsItsPrice(id: String) async throws {
        let entry = try #require(SampleScanImages.shelfTags.first { $0.id == id })
        let expected = entry.tag.price.replacingOccurrences(of: "$", with: "")

        let image = SampleScanImages.shelfTag(entry.tag)
        let prices = try await OCRService.shared.findPrices(in: image)

        let top = try #require(prices.first, "no price found on \(entry.tag.name)")
        #expect(top.amount == Decimal(string: expected), "\(entry.tag.name) read as \(top.amount)")
    }

    // MARK: - Receipt

    /// `ReceiptCaptureView` prefills store, date and total from the parser. All
    /// three come from OCR text, so this asserts the drawn receipt survives the
    /// round trip rather than that the parser works on a hand-written string.
    @Test("The sample receipt parses to store, date and total")
    func receiptParses() async throws {
        let image = SampleScanImages.receipt(SampleScanImages.groceryReceipt)
        let text = try await OCRService.shared.extractReceiptText(from: image)
        let parser = ReceiptParserService.shared

        #expect(parser.extractStoreName(from: text) == "Loblaws", "store not found in:\n\(text)")

        let date = try #require(parser.extractDate(from: text), "date not found in:\n\(text)")
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 14)

        // $19.96, not the $17.66 subtotal sitting two lines above it.
        #expect(parser.extractTotal(from: text) == Decimal(string: "19.96"), "total wrong in:\n\(text)")
    }

    @Test("The receipt lists every product it is meant to verify")
    func receiptListsProducts() async throws {
        let image = SampleScanImages.receipt(SampleScanImages.groceryReceipt)
        let text = try await OCRService.shared.extractReceiptText(from: image).uppercased()

        for line in SampleScanImages.groceryReceipt.lines {
            #expect(text.contains(line.name), "\(line.name) missing from receipt OCR:\n\(text)")
        }
    }

    // MARK: - Programmatic Supply

    @Test("The provider hands back queued images in order, once each")
    func providerIsAFifoQueue() {
        ScannerImageProvider.reset()
        defer { ScannerImageProvider.reset() }

        #expect(ScannerImageProvider.hasPendingImages == false)
        #expect(ScannerImageProvider.takeNext() == nil)

        let first = SampleScanImages.shelfTag(SampleScanImages.glutenFreeBread)
        let second = SampleScanImages.shelfTag(SampleScanImages.regularBread)
        ScannerImageProvider.enqueue(first, second)

        #expect(ScannerImageProvider.hasPendingImages)
        #expect(ScannerImageProvider.takeNext() === first)
        #expect(ScannerImageProvider.takeNext() === second)
        #expect(ScannerImageProvider.hasPendingImages == false)
        #expect(ScannerImageProvider.takeNext() == nil)
    }

    @Test("Reset drops anything still queued")
    func resetClearsTheQueue() {
        ScannerImageProvider.reset()
        defer { ScannerImageProvider.reset() }

        ScannerImageProvider.enqueue(SampleScanImages.shelfTag(SampleScanImages.glutenFreePenne))
        #expect(ScannerImageProvider.hasPendingImages)

        ScannerImageProvider.reset()
        #expect(ScannerImageProvider.hasPendingImages == false)
    }
}
