//
//  QuantityReportingTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-08-14.
//

import Foundation
import GFCore
import SwiftData
import Testing
@testable import GFPriceChecker

/// Guards the purchase-quantity arithmetic against silent under-reporting.
///
/// `ProductPair.differential` and `normalizedDifferential` stay **per unit**; every place
/// that totals a purchase must reach for `extendedDifferential` /
/// `extendedNormalizedDifferential` instead. That split is deliberate — rates like
/// `unitPriceDifferential` must never scale — but it means a missed call site compiles,
/// ships, and simply reports a smaller number. There is no crash and no warning; a user
/// who bought three loaves sees one loaf's premium in their records.
///
/// So these tests deliberately use a quantity of 3 and assert exact totals rather than
/// "greater than zero". The arithmetic itself lives in GFCore and is tested there:
/// `PricingInputsTests` for one pair, `ReportCalculatorTests` for the totals and groupings,
/// `CSVExporterTests` for the CSV columns, and `ValidationTests` for the quantity field.
/// What stays here is the app's edge — the services handing `ProductPair`s to the core,
/// and the PDF's parallel column arrays.
///
/// Run serially: the CSV and PDF services are `@MainActor` singletons that write files
/// into the shared temporary directory under a date-derived filename.
@Suite(.serialized)
@MainActor
struct QuantityReportingTests {

    // MARK: - Fixture

    /// The numbers below are chosen so every derived value lands on an exact `Decimal`:
    ///
    /// - `differential`          = 7.99 − 3.49                = 4.50
    /// - `gfUnitPrice`           = 7.99 / 400                 = 0.019975
    /// - `regularUnitPrice`      = 3.49 / 200                 = 0.01745
    /// - `unitPriceDifferential` = 0.019975 − 0.01745         = 0.002525
    /// - `normalizedDifferential`= 0.002525 × 400             = 1.01
    ///
    /// Repeating decimals here would force approximate comparisons and hide small errors.
    private static let gfPrice = Decimal(string: "7.99")!
    private static let regularPrice = Decimal(string: "3.49")!
    private static let perUnitDifferential = Decimal(string: "4.50")!
    private static let perUnitNormalized = Decimal(string: "1.01")!

    /// A fresh in-memory store, matching the harness in `DataBackupRoundTripTests`.
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

    /// Builds a pair with the fixed prices above.
    ///
    /// - Parameters:
    ///   - quantity: Units purchased.
    ///   - withSizeData: When false the size values are omitted, so `normalizedDifferential`
    ///     is nil and the pair is excluded from every normalized aggregation.
    ///   - category: Category recorded on the pair.
    ///   - createdDate: Drives `reportingDate` when there is no receipt.
    private func makePair(
        quantity: Int,
        withSizeData: Bool = true,
        category: String? = "Bread",
        createdDate: Date = Date()
    ) -> ProductPair {
        ProductPair(
            gfProductName: "GF Bread",
            gfPrice: Self.gfPrice,
            gfSize: withSizeData ? "400g" : nil,
            gfSizeValue: withSizeData ? 400 : nil,
            nonGFProductName: "Regular Bread",
            nonGFPrice: Self.regularPrice,
            nonGFSize: withSizeData ? "200g" : nil,
            nonGFSizeValue: withSizeData ? 200 : nil,
            sizeUnit: withSizeData ? SizeUnit.grams.rawValue : nil,
            quantity: quantity,
            createdDate: createdDate,
            category: category
        )
    }

    /// A fixed date, so the PDF's tax year is not sensitive to today.
    private func date(year: Int, month: Int, day: Int) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        return try #require(Calendar.current.date(from: components))
    }

    // MARK: - CSV Export

    @Test("CSV summary total is the extended amount")
    func csvSummaryUsesExtendedAmounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(quantity: 3)
        context.insert(pair)

        let summary = CSVExportService.shared.calculateExportSummary(products: [pair])
        #expect(summary.count == 1)
        #expect(summary.unitCount == 3)
        #expect(summary.totalDifferential == Decimal(string: "13.50")!)
        #expect(summary.totalNormalizedDifferential == Decimal(string: "3.03")!)
    }

    // MARK: - PDF Export

    @Test("PDF generation survives a multi-unit dataset")
    func pdfGenerationHandlesQuantities() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let purchaseDate = try date(year: 2025, month: 5, day: 6)
        let receipt = Receipt(purchaseDate: purchaseDate, storeName: "Loblaws")
        let verified = makePair(quantity: 3, createdDate: purchaseDate)
        verified.verified = true
        verified.receipt = receipt
        let unverified = makePair(quantity: 2, withSizeData: false, createdDate: purchaseDate)

        context.insert(receipt)
        context.insert(verified)
        context.insert(unverified)

        // The transaction table's headers, column widths and row data are three parallel
        // arrays. Adding the Qty column to one and not the others would desync them, so
        // exercise both the verified (per-receipt) and unverified table paths.
        let url = try await PDFGeneratorService.shared.generatePDF(
            products: [verified, unverified],
            receipts: [receipt],
            year: 2025,
            userName: "Test User",
            paperSize: .usLetter
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
        #expect(data.starts(with: Array("%PDF".utf8)))
    }
}
