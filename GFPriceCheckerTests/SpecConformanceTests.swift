//
//  SpecConformanceTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-10-30.
//

import Foundation
import PDFKit
import SwiftData
import Testing
@testable import GFPriceChecker

/// Pins the arithmetic in shared-docs' `PRODUCT_DEFINITION.md` §3 (issue #65).
///
/// These are the departures that changed numbers users see: a receipt total that ignored
/// quantity, and a normalized total that reported $0.00 where the spec says there is no
/// value. GFCore will move this code (Track F, Stage 2), and these tests are what make
/// sure it moves a correct version.
///
/// Run serially: the PDF test writes into the shared temporary directory through the
/// `PDFGeneratorService` singleton.
@Suite(.serialized)
@MainActor
struct SpecConformanceTests {

    // MARK: - Fixture

    /// A fresh in-memory store.
    ///
    /// - Important: the returned container must be held alive for as long as its context
    ///   is used — letting it deallocate tears down the store underneath SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ProductPair.self, Receipt.self,
            configurations: configuration
        )
    }

    /// A pair whose package differential is exactly $4.50 (7.99 − 3.49).
    private func makePair(quantity: Int, withSizeData: Bool = true) -> ProductPair {
        ProductPair(
            gfProductName: "GF Bread",
            gfPrice: Decimal(string: "7.99")!,
            gfSizeValue: withSizeData ? 400 : nil,
            nonGFProductName: "Regular Bread",
            nonGFPrice: Decimal(string: "3.49")!,
            nonGFSizeValue: withSizeData ? 200 : nil,
            sizeUnit: withSizeData ? SizeUnit.grams.rawValue : nil,
            quantity: quantity,
            createdDate: Calendar.current.date(from: DateComponents(year: 2025, month: 5, day: 6, hour: 12))!
        )
    }

    /// Rounds to cents the way a currency display does.
    private func cents(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    // MARK: - Worked Example

    /// The spec's own example. The intermediate unit prices repeat (3.99 / 675), so the
    /// figure is compared at cents, which is how every surface shows it.
    @Test("The spec's worked example gives $5.63")
    func workedExample() throws {
        let pair = ProductPair(
            gfProductName: "GF Bread",
            gfPrice: Decimal(string: "7.99")!,
            gfSizeValue: 400,
            nonGFProductName: "Regular Bread",
            nonGFPrice: Decimal(string: "3.99")!,
            nonGFSizeValue: 675,
            sizeUnit: SizeUnit.grams.rawValue
        )

        let normalized = try #require(pair.normalizedDifferential)
        #expect(cents(normalized) == Decimal(string: "5.63")!)
        #expect(pair.differential == Decimal(string: "4.00")!)
    }

    // MARK: - Receipt Total

    @Test("A receipt's total sums its pairs' extended differentials")
    func receiptTotalUsesExtendedDifferential() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let receipt = Receipt(storeName: "Loblaws")
        let threeLoaves = makePair(quantity: 3)
        let oneLoaf = makePair(quantity: 1)
        context.insert(receipt)
        context.insert(threeLoaves)
        context.insert(oneLoaf)
        threeLoaves.receipt = receipt
        oneLoaf.receipt = receipt
        try context.save()

        try #require(receipt.productPairs.count == 2)

        // 3 × 4.50 + 1 × 4.50. Summing per-unit differentials gives $9.00.
        #expect(receipt.totalDifferential == Decimal(string: "18.00")!)
        let extendedSum = receipt.productPairs.reduce(Decimal.zero) { $0 + $1.extendedDifferential }
        #expect(receipt.totalDifferential == extendedSum)
    }

    // MARK: - Missing Size Data

    @Test("No size data anywhere means no normalized total, not zero")
    func normalizedTotalIsNilWithoutSizeData() {
        let result = ReportViewModel.calculateTotalNormalizedDifferential(
            for: [makePair(quantity: 2, withSizeData: false), makePair(quantity: 1, withSizeData: false)]
        )
        #expect(result.total == nil)
        #expect(result.excludedCount == 2)
    }

    @Test("An empty product list has no normalized total")
    func normalizedTotalIsNilWhenEmpty() {
        let result = ReportViewModel.calculateTotalNormalizedDifferential(for: [])
        #expect(result.total == nil)
        #expect(result.excludedCount == 0)
    }

    /// The other half of the rule: one sized pair is enough for a real total, and the
    /// sizeless one is excluded rather than counted as zero.
    @Test("A partly sized list totals only the sized pairs")
    func normalizedTotalCountsSizedPairsOnly() {
        // 400 g at $7.99 vs 200 g at $3.49 → (0.019975 − 0.01745) × 400 = $1.01 per unit
        let result = ReportViewModel.calculateTotalNormalizedDifferential(
            for: [makePair(quantity: 2), makePair(quantity: 1, withSizeData: false)]
        )
        #expect(result.total == Decimal(string: "2.02")!)
        #expect(result.excludedCount == 1)
    }

    /// The PDF used to carry its own copy of the sum, which reported $0.00. Read the text
    /// back out to check the cover and the receipt and unverified subtotals all show
    /// "no value". (`drawGrandTotals` is reachable only from `drawTransactionPages`, which
    /// nothing calls, so there is no grand-total line to check.)
    @Test("The PDF shows no value, not $0.00, when nothing has size data")
    func pdfShowsNoValueWithoutSizeData() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let receipt = Receipt(
            purchaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 5, day: 6, hour: 12))!,
            storeName: "Loblaws"
        )
        let verified = makePair(quantity: 3, withSizeData: false)
        verified.verified = true
        let unverified = makePair(quantity: 1, withSizeData: false)
        context.insert(receipt)
        context.insert(verified)
        context.insert(unverified)
        verified.receipt = receipt

        let url = try await PDFGeneratorService.shared.generatePDF(
            products: [verified, unverified],
            receipts: [receipt],
            year: 2025,
            userName: "Test User",
            paperSize: .usLetter
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try #require(PDFDocument(url: url))
        let cover = try #require(document.page(at: 0)?.string)
        #expect(cover.contains("Size-Adjusted Differential Total (Primary)"))
        #expect(cover.contains("—"))

        let text = try #require(document.string)
        // One subtotal for the receipt, one for the unverified section
        #expect(text.components(separatedBy: "Size-Adjusted Subtotal: —").count - 1 == 2)
        #expect(!text.contains("Size-Adjusted Subtotal: CA$0.00"))
        #expect(!text.contains("Size-Adjusted Subtotal: $0.00"))
    }
}
