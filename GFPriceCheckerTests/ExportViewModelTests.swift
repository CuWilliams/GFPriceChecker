//
//  ExportViewModelTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-10-31.
//

import Foundation
import GFCore
import SwiftData
import Testing
@testable import GFPriceChecker

/// Covers `ExportViewModel` — the logic lifted out of `ExportView` for issue #91
/// (`docs/SCRIPTED_DEMO_PIPELINE.md` §2 Blocker 2).
///
/// Before the extraction this was 18 `@State` properties and ten private methods
/// inside the view, with no test coverage. CSV and PDF generation and the clock
/// reach the view model through `Dependencies`, so every test here runs an export
/// on a fixed date without writing a file.
@MainActor
@Suite("Export view model")
struct ExportViewModelTests {

    // MARK: - Fixtures

    /// A date in the device's calendar, which is the one the view model buckets years in.
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// The fixed "now" every test runs at.
    static let now = date(2026, 6, 15)

    struct GenerationFailure: LocalizedError {
        var errorDescription: String? { "Disk full" }
    }

    /// Records what the view model asked its dependencies for, and returns canned results.
    @MainActor
    final class DependencySpy {
        var csvCalls: [(products: [ProductPair], range: ClosedRange<Date>?)] = []
        var pdfCalls: [(products: [ProductPair], receipts: [Receipt], year: Int, paperSize: PaperSize)] = []
        var fail = false

        let csvURL = URL(fileURLWithPath: "/tmp/export.csv")
        let pdfURL = URL(fileURLWithPath: "/tmp/export.pdf")

        var dependencies: ExportViewModel.Dependencies {
            ExportViewModel.Dependencies(
                generateCSV: { products, range in
                    self.csvCalls.append((products, range))
                    if self.fail { throw GenerationFailure() }
                    return self.csvURL
                },
                generatePDF: { products, receipts, year, paperSize in
                    self.pdfCalls.append((products, receipts, year, paperSize))
                    if self.fail { throw GenerationFailure() }
                    return self.pdfURL
                },
                now: { ExportViewModelTests.now }
            )
        }
    }

    /// An in-memory store. The container is returned alongside the context and
    /// must be held for as long as the context is used — letting it deallocate
    /// tears down the store and traps inside SwiftData on the next fetch.
    static func makeStore() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: ProductPair.self, Receipt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    static func pair(
        _ name: String,
        on date: Date,
        verified: Bool = true,
        in context: ModelContext
    ) -> ProductPair {
        let pair = ProductPair(
            gfProductName: name,
            gfPrice: Decimal(string: "6.99")!,
            nonGFProductName: "Regular \(name)",
            nonGFPrice: Decimal(string: "3.49")!,
            createdDate: date,
            verified: verified
        )
        context.insert(pair)
        return pair
    }

    /// A view model wired to a spy, holding the given pairs and receipts.
    func makeExport(
        products: [ProductPair] = [],
        receipts: [Receipt] = []
    ) -> (ExportViewModel, DependencySpy) {
        let spy = DependencySpy()
        let viewModel = ExportViewModel(dependencies: spy.dependencies)
        viewModel.products = products
        viewModel.receipts = receipts
        return (viewModel, spy)
    }

    // MARK: - Date Ranges

    @Test("Each preset selects the pairs its range covers")
    func presetRanges() throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let thisYear = Self.pair("This Year", on: Self.date(2026, 3, 1), in: context)
        let lastYear = Self.pair("Last Year", on: Self.date(2025, 9, 1), in: context)
        let longAgo = Self.pair("Long Ago", on: Self.date(2023, 1, 1), in: context)
        let (export, _) = makeExport(products: [thisYear, lastYear, longAgo])

        export.useCustomRange = false

        export.selectedPreset = .currentYear
        #expect(Set(export.filteredRows.map(\.id)) == [thisYear.id])

        export.selectedPreset = .lastTwelveMonths
        #expect(Set(export.filteredRows.map(\.id)) == [thisYear.id, lastYear.id])

        export.selectedPreset = .allTime
        #expect(export.currentDateRange == nil)
        #expect(export.filteredRows.count == 3)
    }

    @Test("The default custom range is the year up to now")
    func defaultCustomRange() {
        let (export, _) = makeExport()

        #expect(export.customEndDate == Self.now)
        #expect(export.customStartDate == Self.date(2025, 6, 15))
        #expect(export.pdfYear == 2026)
    }

    @Test("A custom range selects the pairs between its dates")
    func customRange() throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let before = Self.pair("Before", on: Self.date(2025, 12, 31), in: context)
        let inside = Self.pair("Inside", on: Self.date(2026, 2, 14), in: context)
        let after = Self.pair("After", on: Self.date(2026, 4, 1), in: context)
        let (export, _) = makeExport(products: [before, inside, after])

        export.useCustomRange = true
        export.customStartDate = Self.date(2026, 1, 1, hour: 0)
        export.customEndDate = Self.date(2026, 3, 31, hour: 23)

        #expect(export.filteredRows.map(\.id) == [inside.id])
    }

    @Test("A custom range picked end first is read in order instead of trapping")
    func reversedCustomRange() throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let inside = Self.pair("Inside", on: Self.date(2026, 2, 14), in: context)
        let after = Self.pair("After", on: Self.date(2026, 4, 1), in: context)
        let (export, _) = makeExport(products: [inside, after])

        // Building `start...end` from these traps, release builds included
        export.useCustomRange = true
        export.customStartDate = Self.date(2026, 3, 31, hour: 23)
        export.customEndDate = Self.date(2026, 1, 1, hour: 0)

        let range = try #require(export.currentDateRange)
        #expect(range.lowerBound == Self.date(2026, 1, 1, hour: 0))
        #expect(range.upperBound == Self.date(2026, 4, 1, hour: 0).addingTimeInterval(-1))
        #expect(export.filteredRows.map(\.id) == [inside.id])
    }

    @Test("A custom range covers the whole of its first and last day, whatever time its dates carry")
    func customRangeIsWholeDays() throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let dayBefore = Self.pair("Day Before", on: Self.date(2026, 2, 28, hour: 23), in: context)
        let earlyFirstDay = Self.pair("Early First Day", on: Self.date(2026, 3, 1, hour: 8), in: context)
        let lateLastDay = Self.pair("Late Last Day", on: Self.date(2026, 3, 31, hour: 23), in: context)
        let dayAfter = Self.pair("Day After", on: Self.date(2026, 4, 1, hour: 0), in: context)
        let (export, _) = makeExport(products: [dayBefore, earlyFirstDay, lateLastDay, dayAfter])

        // Picked days keep the time of day the screen was opened at: noon
        export.useCustomRange = true
        export.customStartDate = Self.date(2026, 3, 1)
        export.customEndDate = Self.date(2026, 3, 31)
        #expect(Set(export.filteredRows.map(\.id)) == [earlyFirstDay.id, lateLastDay.id])

        export.customStartDate = Self.date(2026, 3, 31)
        export.customEndDate = Self.date(2026, 3, 1)
        #expect(Set(export.filteredRows.map(\.id)) == [earlyFirstDay.id, lateLastDay.id])
    }

    @Test("A custom range of one day covers that whole day")
    func customRangeOfOneDay() throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let morning = Self.pair("Morning", on: Self.date(2026, 3, 1, hour: 8), in: context)
        let evening = Self.pair("Evening", on: Self.date(2026, 3, 1, hour: 23), in: context)
        let nextDay = Self.pair("Next Day", on: Self.date(2026, 3, 2, hour: 0), in: context)
        let (export, _) = makeExport(products: [morning, evening, nextDay])

        export.useCustomRange = true
        export.customStartDate = Self.date(2026, 3, 1)
        export.customEndDate = Self.date(2026, 3, 1)

        #expect(Set(export.filteredRows.map(\.id)) == [morning.id, evening.id])
    }

    // MARK: - Exporting

    @Test("A CSV export generates over the current range and opens the share sheet")
    func csvExport() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let bread = Self.pair("GF Bread", on: Self.date(2026, 3, 1), in: context)
        let (export, spy) = makeExport(products: [bread])
        export.exportFormat = .csv
        export.selectedPreset = .currentYear

        #expect(export.canExport)
        await export.export()

        let call = try #require(spy.csvCalls.only)
        #expect(call.products.map(\.id) == [bread.id])
        #expect(call.range == export.currentDateRange)
        #expect(spy.pdfCalls.isEmpty)
        #expect(export.showingShareSheet)
        #expect(export.shareItems.compactMap { $0 as? URL } == [spy.csvURL])
        #expect(!export.isGenerating)
    }

    @Test("A PDF export hands over only the chosen year's pairs and receipts")
    func pdfExport() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let thisYear = Self.pair("This Year", on: Self.date(2026, 3, 1), in: context)
        let lastYear = Self.pair("Last Year", on: Self.date(2025, 9, 1), in: context)
        let receiptThisYear = Receipt(purchaseDate: Self.date(2026, 3, 1))
        let receiptLastYear = Receipt(purchaseDate: Self.date(2025, 9, 1))
        context.insert(receiptThisYear)
        context.insert(receiptLastYear)
        let (export, spy) = makeExport(
            products: [thisYear, lastYear],
            receipts: [receiptThisYear, receiptLastYear]
        )
        export.exportFormat = .pdf
        export.pdfYear = 2026
        export.paperSize = .a4

        #expect(export.availableYears == [2026, 2025])
        await export.export()

        let call = try #require(spy.pdfCalls.only)
        #expect(call.products.map(\.id) == [thisYear.id])
        #expect(call.receipts.map(\.id) == [receiptThisYear.id])
        #expect(call.year == 2026)
        #expect(call.paperSize == .a4)
        #expect(!export.showingUnverifiedWarning)
        #expect(export.showingShareSheet)
    }

    @Test("Unverified pairs hold a PDF export behind the warning until it is confirmed")
    func unverifiedWarningDefersThenResumes() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let verified = Self.pair("Verified", on: Self.date(2026, 3, 1), in: context)
        let unverified = Self.pair("Unverified", on: Self.date(2026, 4, 1), verified: false, in: context)
        // Unverified, but outside the PDF's year, so not counted
        let lastYear = Self.pair("Last Year", on: Self.date(2025, 4, 1), verified: false, in: context)
        let (export, spy) = makeExport(products: [verified, unverified, lastYear])
        export.exportFormat = .pdf
        export.pdfYear = 2026

        await export.export()

        #expect(export.showingUnverifiedWarning)
        #expect(export.unverifiedProductCount == 1)
        #expect(export.hasPendingExport)
        #expect(spy.pdfCalls.isEmpty)
        #expect(!export.showingShareSheet)

        await export.confirmUnverifiedExport()

        #expect(spy.pdfCalls.count == 1)
        #expect(!export.hasPendingExport)
        #expect(export.showingShareSheet)

        // A second confirmation has nothing left to resume
        await export.confirmUnverifiedExport()
        #expect(spy.pdfCalls.count == 1)
    }

    @Test("Cancelling the unverified warning drops the export")
    func unverifiedWarningCancelled() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let unverified = Self.pair("Unverified", on: Self.date(2026, 4, 1), verified: false, in: context)
        let (export, spy) = makeExport(products: [unverified])
        export.exportFormat = .pdf
        export.pdfYear = 2026

        await export.export()
        export.cancelUnverifiedExport()
        await export.confirmUnverifiedExport()

        #expect(spy.pdfCalls.isEmpty)
        #expect(!export.hasPendingExport)
        #expect(!export.showingShareSheet)
    }

    @Test("Unverified pairs don't hold back a CSV export")
    func unverifiedCSVNotWarned() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let unverified = Self.pair("Unverified", on: Self.date(2026, 4, 1), verified: false, in: context)
        let (export, spy) = makeExport(products: [unverified])
        export.exportFormat = .csv
        export.selectedPreset = .allTime

        await export.export()

        #expect(!export.showingUnverifiedWarning)
        #expect(spy.csvCalls.count == 1)
    }

    @Test("A generation failure surfaces as a message and no share sheet")
    func generationFailure() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let bread = Self.pair("GF Bread", on: Self.date(2026, 3, 1), in: context)
        let (export, spy) = makeExport(products: [bread])
        spy.fail = true
        export.exportFormat = .csv
        export.selectedPreset = .allTime

        await export.export()

        #expect(export.showingError)
        #expect(export.errorMessage == "Failed to generate CSV: Disk full")
        #expect(!export.showingShareSheet)
        #expect(!export.isGenerating)
    }

    @Test("Nothing to export disables exporting")
    func emptyExportDisabled() throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let longAgo = Self.pair("Long Ago", on: Self.date(2023, 1, 1), in: context)
        let (export, _) = makeExport(products: [longAgo])
        export.exportFormat = .csv
        export.selectedPreset = .currentYear

        #expect(export.exportSummary.count == 0)
        #expect(!export.canExport)
    }
}

private extension Array {
    /// The sole element, or `nil` when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
