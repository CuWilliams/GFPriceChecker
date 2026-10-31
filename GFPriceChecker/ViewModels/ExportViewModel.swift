//
//  ExportViewModel.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-10-31.
//

import Foundation
import GFCore

// MARK: - Export Format

/// Export format options
enum ExportFormat: String, CaseIterable {
    case csv = "CSV"
    case pdf = "PDF"
}

// MARK: - Export View Model

/// The state and logic of exporting: choose a format and a date range or year,
/// then generate the file and hand it to the share sheet.
///
/// This used to be 18 `@State` properties and ten private methods inside
/// `ExportView`, the last flow left in that position after `CaptureFlowViewModel`
/// and `ReceiptCaptureViewModel` (`docs/SCRIPTED_DEMO_PIPELINE.md` §2 Blocker 2).
/// Out here an export can be driven by method calls and unit-tested.
///
/// CSV and PDF generation reach it through `Dependencies`, so a test can run an
/// export without writing a file.
@Observable
@MainActor
final class ExportViewModel {

    // MARK: - Dependencies

    /// The services the export calls out to, behind closures so tests can stand in for them.
    @MainActor
    struct Dependencies {
        /// Writes a CSV of the given pairs within the range (`nil` for all of them),
        /// returning the file's URL.
        var generateCSV: ([ProductPair], ClosedRange<Date>?) async throws -> URL

        /// Writes the PDF report for one year from that year's pairs and receipts,
        /// returning the file's URL.
        var generatePDF: ([ProductPair], [Receipt], Int, PaperSize) async throws -> URL

        /// The current date, which the presets and the default custom range count from.
        var now: () -> Date

        /// The real services.
        static var live: Dependencies {
            Dependencies(
                generateCSV: { products, range in
                    try await CSVExportService.shared.generateCSV(products: products, dateRange: range)
                },
                generatePDF: { products, receipts, year, paperSize in
                    try await PDFGeneratorService.shared.generatePDF(
                        products: products,
                        receipts: receipts,
                        year: year,
                        userName: AppSettings.shared.userName,
                        paperSize: paperSize
                    )
                },
                now: { Date() }
            )
        }
    }

    private let dependencies: Dependencies

    /// Buckets years in the device's calendar and time zone, as the dashboard does
    private let calculator = ReportCalculator(calendar: .current)

    // MARK: - Data

    /// Every pair. The view keeps this in step with its `@Query`.
    var products: [ProductPair] = []

    /// Every receipt. The view keeps this in step with its `@Query`.
    var receipts: [Receipt] = []

    // MARK: - Choices

    var exportFormat: ExportFormat = .csv
    var selectedPreset: DateRangePreset
    var useCustomRange = false
    var customStartDate: Date
    var customEndDate: Date

    // PDF-specific choices
    var pdfYear: Int
    var paperSize: PaperSize

    // MARK: - Generation

    private(set) var isGenerating = false
    var errorMessage: String?
    var showingError = false

    // MARK: - Unverified Products Warning

    var showingUnverifiedWarning = false
    private(set) var unverifiedProductCount = 0

    /// Set while the warning is waiting on the user, so confirming runs at most one export
    private(set) var hasPendingExport = false

    // MARK: - Presentation

    var showingShareSheet = false
    private(set) var shareItems: [Any] = []

    // MARK: - Initialization

    /// - Parameter dependencies: stand-ins for the CSV and PDF services and the
    ///   clock. `nil` uses the real ones. It is not defaulted to `.live`
    ///   directly because a default argument is evaluated in the caller's
    ///   isolation, and `.live` is main-actor isolated.
    init(dependencies: Dependencies? = nil) {
        let dependencies = dependencies ?? .live
        self.dependencies = dependencies

        let now = dependencies.now()
        selectedPreset = AppSettings.shared.defaultDateRange
        customStartDate = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        customEndDate = now
        pdfYear = Calendar.current.component(.year, from: now)
        paperSize = AppSettings.shared.defaultPaperSize
    }

    // MARK: - Derived Values

    /// The custom range, in order whichever way round the two dates were picked.
    ///
    /// The view constrains each picker by the other, but a `ClosedRange` whose lower
    /// bound is above its upper bound traps, release builds included, so the order
    /// is not left to the pickers.
    var customDateRange: ClosedRange<Date> {
        min(customStartDate, customEndDate)...max(customStartDate, customEndDate)
    }

    /// Current date range based on preset or custom selection
    var currentDateRange: ClosedRange<Date>? {
        if useCustomRange {
            return customDateRange
        } else {
            return calculator.dateRange(for: selectedPreset, now: dependencies.now())
        }
    }

    private var allRows: [ReportRow] {
        products.map(\.reportRow)
    }

    /// Rows within the current date range: what the CSV will contain
    var filteredRows: [ReportRow] {
        ReportCalculator.rows(allRows, in: currentDateRange)
    }

    /// Rows reported in the PDF's year: what the PDF will contain
    var pdfYearRows: [ReportRow] {
        calculator.rows(allRows, inYear: pdfYear)
    }

    /// Preview of first 10 rows
    var previewRows: [ReportRow] {
        Array(filteredRows.sorted { $0.reportingDate < $1.reportingDate }.prefix(10))
    }

    /// Totals for the selected export
    var exportSummary: ReportTotals {
        switch exportFormat {
        case .csv:
            ReportCalculator.totals(filteredRows)
        case .pdf:
            ReportCalculator.totals(pdfYearRows)
        }
    }

    /// Available years from product data
    var availableYears: [Int] {
        calculator.availableYears(allRows)
    }

    var canExport: Bool {
        !isGenerating && exportSummary.count > 0
    }

    // MARK: - Exporting

    /// Generates the selected export and presents the share sheet.
    ///
    /// Save to Files, Share and Email all land here: SwiftUI has no file-save
    /// panel and `mailto:` cannot attach a file, so each one ends in the share
    /// sheet, which offers both. A PDF with unverified pairs is held back behind
    /// a warning; `confirmUnverifiedExport()` resumes it.
    func export() async {
        guard !isGenerating else { return }

        if exportFormat == .pdf {
            let unverifiedCount = ReportCalculator.totals(pdfYearRows).unverifiedCount
            if unverifiedCount > 0 {
                unverifiedProductCount = unverifiedCount
                hasPendingExport = true
                showingUnverifiedWarning = true
                return
            }
        }

        await generate()
    }

    /// Runs the export the unverified-products warning held back.
    func confirmUnverifiedExport() async {
        guard hasPendingExport else { return }
        hasPendingExport = false
        await generate()
    }

    /// Drops the export the unverified-products warning held back.
    func cancelUnverifiedExport() {
        hasPendingExport = false
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let fileURL = try await generateExportFile()
            shareItems = [fileURL]
            showingShareSheet = true
        } catch {
            errorMessage = "Failed to generate \(exportFormat.rawValue): \(error.localizedDescription)"
            showingError = true
        }
    }

    /// Generates export file based on selected format
    private func generateExportFile() async throws -> URL {
        switch exportFormat {
        case .csv:
            return try await dependencies.generateCSV(products, currentDateRange)

        case .pdf:
            // Filter products and receipts by PDF year
            let yearProducts = products.filter { calculator.isDate($0.reportingDate, inYear: pdfYear) }
            let yearReceipts = receipts.filter { calculator.isDate($0.purchaseDate, inYear: pdfYear) }

            // Unverified products check already done upstream
            return try await dependencies.generatePDF(yearProducts, yearReceipts, pdfYear, paperSize)
        }
    }
}
