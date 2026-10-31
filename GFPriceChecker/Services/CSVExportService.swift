//
//  CSVExportService.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation
import GFCore

/// Service for writing CSV exports to disk
///
/// The CSV text — columns, number and date formats, escaping — is `CSVExporter`'s, in
/// GFCore. This service filters by date range, writes the file and adds the UTF-8 BOM
/// Excel needs to read it as UTF-8.
@MainActor
final class CSVExportService {

    // MARK: - Singleton

    static let shared = CSVExportService()

    private init() {}

    // MARK: - CSV Generation

    /// Generates a CSV file from product pairs
    ///
    /// - Parameters:
    ///   - products: Product pairs to export
    ///   - dateRange: Optional date range filter (uses reportingDate)
    /// - Returns: URL of the generated temporary CSV file
    /// - Throws: Error if file writing fails
    func generateCSV(
        products: [ProductPair],
        dateRange: ClosedRange<Date>? = nil
    ) async throws -> URL {
        let rows = ReportCalculator.rows(products.map(\.reportRow), in: dateRange)
        let csvContent = CSVExporter.generate(rows: rows, timeZone: .current)

        // Generate unique filename
        let dateString = CSVExporter.formatDate(Date(), timeZone: .current)
        let filename = "GFPriceChecker_Export_\(dateString).csv"

        // Save to temporary directory
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)

        // Write with UTF-8 encoding (BOM for Excel compatibility)
        let bomPrefix = "\u{FEFF}" // UTF-8 BOM
        let csvWithBOM = bomPrefix + csvContent

        try csvWithBOM.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }

    // MARK: - Summary Statistics

    /// The totals for the rows an export would contain
    ///
    /// - Parameters:
    ///   - products: Products to analyze
    ///   - dateRange: Optional date range filter
    func calculateExportSummary(
        products: [ProductPair],
        dateRange: ClosedRange<Date>? = nil
    ) -> ReportTotals {
        ReportCalculator.totals(ReportCalculator.rows(products.map(\.reportRow), in: dateRange))
    }
}
