//
//  QuantityReportingTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-08-14.
//

import Foundation
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
/// "greater than zero". Every aggregation the dashboard and the exports depend on is
/// covered, because the failure mode is a single overlooked `reduce`.
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
    ///   - category: Category used by the grouping tests.
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

    /// A date in a fixed month, so the monthly grouping tests are not sensitive to today.
    private func date(year: Int, month: Int, day: Int) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        return try #require(Calendar.current.date(from: components))
    }

    /// First instant of the month containing `date`, which is how `groupByMonth` keys its
    /// dictionary.
    private func monthStart(of date: Date) throws -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return try #require(calendar.date(from: components))
    }

    // MARK: - Model Arithmetic

    @Test("Extended differentials scale with quantity, per-unit ones do not")
    func extendedDifferentialsScaleWithQuantity() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(quantity: 3)
        context.insert(pair)

        // Per-unit figures are what the detail view shows, and must ignore quantity.
        #expect(pair.differential == Self.perUnitDifferential)
        #expect(pair.normalizedDifferential == Self.perUnitNormalized)

        // Extended figures are what the reports and exports total.
        #expect(pair.extendedDifferential == Decimal(string: "13.50")!)
        #expect(pair.extendedNormalizedDifferential == Decimal(string: "3.03")!)
    }

    @Test("A single-unit purchase leaves the extended figures equal to the per-unit ones")
    func quantityOneIsIdentity() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(quantity: 1)
        context.insert(pair)

        #expect(pair.quantity == 1)
        #expect(pair.extendedDifferential == pair.differential)
        #expect(pair.extendedNormalizedDifferential == pair.normalizedDifferential)
    }

    @Test("Unit prices are rates and never scale with quantity")
    func ratesDoNotScaleWithQuantity() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let single = makePair(quantity: 1)
        let triple = makePair(quantity: 3)
        context.insert(single)
        context.insert(triple)

        // Buying three loaves does not change the price per gram. If any of these ever
        // start tracking quantity, every unit price shown or exported becomes nonsense.
        #expect(triple.gfUnitPrice == single.gfUnitPrice)
        #expect(triple.regularUnitPrice == single.regularUnitPrice)
        #expect(triple.unitPriceDifferential == single.unitPriceDifferential)
        #expect(triple.unitPriceDifferential == Decimal(string: "0.002525")!)
    }

    @Test("Extended normalized differential stays nil when size data is incomplete")
    func extendedNormalizedIsNilWithoutSizeData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(quantity: 4, withSizeData: false)
        context.insert(pair)

        #expect(pair.normalizedDifferential == nil)
        #expect(pair.extendedNormalizedDifferential == nil)

        // The package differential still scales — only the size-adjusted one is unavailable.
        #expect(pair.extendedDifferential == Decimal(string: "18.00")!)
    }

    // MARK: - ReportViewModel Aggregations

    @Test("Dashboard totals sum extended differentials")
    func reportTotalsUseExtendedAmounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ReportViewModel()

        let pair = makePair(quantity: 3)
        context.insert(pair)

        #expect(viewModel.calculateTotalDifferential(for: [pair]) == Decimal(string: "13.50")!)

        let normalized = ReportViewModel.calculateTotalNormalizedDifferential(for: [pair])
        #expect(normalized.total == Decimal(string: "3.03")!)
        #expect(normalized.excludedCount == 0)
    }

    @Test("Averages divide by units purchased, not by pair count")
    func averagesDivideByUnitCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ReportViewModel()

        // Three pairs, nine units, every unit carrying the same $4.50 premium. The average
        // premium per item is therefore $4.50. Dividing by pair count instead would give
        // $13.50 — the discrepancy is what this test exists to catch.
        let pairs = [
            makePair(quantity: 3),
            makePair(quantity: 1),
            makePair(quantity: 5, withSizeData: false)
        ]
        pairs.forEach { context.insert($0) }

        #expect(viewModel.calculateTotalDifferential(for: pairs) == Decimal(string: "40.50")!)
        #expect(viewModel.calculateAverageDifferential(for: pairs) == Decimal(string: "4.50")!)

        // The sizeless pair contributes to neither the normalized total nor its denominator,
        // so the normalized average stays $1.01 across the four eligible units.
        let normalized = ReportViewModel.calculateTotalNormalizedDifferential(for: pairs)
        #expect(normalized.total == Decimal(string: "4.04")!)
        #expect(normalized.excludedCount == 1)
        #expect(viewModel.calculateAverageNormalizedDifferential(for: pairs) == Self.perUnitNormalized)
    }

    @Test("Category grouping reflects quantity")
    func categoryGroupingUsesExtendedAmounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ReportViewModel()

        let bread = makePair(quantity: 3, category: "Bread")
        let pasta = makePair(quantity: 1, category: "Pasta")
        context.insert(bread)
        context.insert(pasta)

        let totals = viewModel.groupByCategory(products: [bread, pasta])
        #expect(totals["Bread"] == Decimal(string: "13.50")!)
        #expect(totals["Pasta"] == Decimal(string: "4.50")!)

        let normalizedTotals = viewModel.groupByCategoryNormalized(products: [bread, pasta])
        #expect(normalizedTotals["Bread"] == Decimal(string: "3.03")!)
        #expect(normalizedTotals["Pasta"] == Self.perUnitNormalized)
    }

    @Test("Monthly grouping reflects quantity")
    func monthlyGroupingUsesExtendedAmounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ReportViewModel()

        let march = try date(year: 2025, month: 3, day: 10)
        let april = try date(year: 2025, month: 4, day: 2)

        let marchKey = try monthStart(of: march)
        let aprilKey = try monthStart(of: april)

        let marchPair = makePair(quantity: 3, createdDate: march)
        let aprilPair = makePair(quantity: 1, createdDate: april)
        context.insert(marchPair)
        context.insert(aprilPair)

        let totals = viewModel.groupByMonth(products: [marchPair, aprilPair])
        #expect(totals[marchKey] == Decimal(string: "13.50")!)
        #expect(totals[aprilKey] == Decimal(string: "4.50")!)

        let normalizedTotals = viewModel.groupByMonthNormalized(products: [marchPair, aprilPair])
        #expect(normalizedTotals[marchKey] == Decimal(string: "3.03")!)
        #expect(normalizedTotals[aprilKey] == Self.perUnitNormalized)
    }

    // MARK: - CSV Export

    @Test("CSV carries a Qty column and extended differentials that reconcile")
    func csvExportIncludesQuantityAndExtendedColumns() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(quantity: 3)
        context.insert(pair)

        let url = try await CSVExportService.shared.generateCSV(products: [pair])
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\u{FEFF}", with: "") // strip the Excel BOM
        let lines = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 2)

        // `buildCSVHeader` and `buildCSVRow` are positional arrays kept in sync by hand.
        // A field added to one and not the other shifts every later column silently, so
        // check the counts match before trusting any lookup by name.
        let headers = try #require(lines.first).components(separatedBy: ",")
        let fields = try #require(lines.last).components(separatedBy: ",")
        #expect(headers.count == fields.count)

        func field(_ column: String) throws -> String {
            let index = try #require(headers.firstIndex(of: column))
            return fields[index]
        }

        let quantity = try field("Quantity")
        let packageDiff = try field("Package Price Differential")
        let extendedPackageDiff = try field("Extended Package Differential")
        let sizeAdjustedDiff = try field("Size-Adjusted Differential")
        let extendedSizeAdjustedDiff = try field("Extended Size-Adjusted Differential")

        #expect(quantity == "3")
        #expect(packageDiff == "4.50")
        #expect(extendedPackageDiff == "13.50")
        #expect(sizeAdjustedDiff == "1.01")
        #expect(extendedSizeAdjustedDiff == "3.03")
    }

    @Test("CSV summary total is the extended amount")
    func csvSummaryUsesExtendedAmounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(quantity: 3)
        context.insert(pair)

        let summary = CSVExportService.shared.calculateExportSummary(products: [pair])
        #expect(summary.count == 1)
        #expect(summary.totalDifferential == Decimal(string: "13.50")!)
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

    // MARK: - Validation

    @Test("Empty quantity input means a single unit")
    func emptyQuantityDefaultsToOne() throws {
        // The form leaves the field blank-able rather than forcing the user to type 1 for
        // the overwhelmingly common single-item case.
        let blank = try ValidationRules.validateQuantityString("").get()
        let whitespace = try ValidationRules.validateQuantityString("   ").get()

        #expect(blank == ValidationRules.minQuantity)
        #expect(whitespace == ValidationRules.minQuantity)
    }

    @Test("A valid whole number is accepted")
    func validQuantityIsAccepted() throws {
        let result = try ValidationRules.validateQuantityString("12").get()
        #expect(result == 12)
    }

    @Test(
        "Out-of-range and non-integer quantities are rejected",
        arguments: ["0", "-1", "1000", "2.5", "two", "3 loaves"]
    )
    func invalidQuantityIsRejected(input: String) {
        switch ValidationRules.validateQuantityString(input) {
        case .success(let value):
            Issue.record("Expected \(input) to be rejected, got \(value)")
        case .failure(let error):
            guard case .invalidQuantity = error else {
                Issue.record("Expected .invalidQuantity for \(input), got \(error)")
                return
            }
        }
    }
}
