//
//  CSVExportService.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation

/// Service for generating CSV exports
///
/// Generates CSV files with proper formatting for data exchange:
/// - UTF-8 encoding with BOM for Excel compatibility
/// - Proper CSV escaping for special characters
/// - Date format: YYYY-MM-DD
/// - Price format: decimal with 2 places, no currency symbol
/// - Boolean values as Yes/No
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
        // Filter by date range if provided
        let filteredProducts = filterProducts(products, dateRange: dateRange)

        // Sort by reporting date (ascending - oldest first for tax purposes)
        let sortedProducts = filteredProducts.sorted { $0.reportingDate < $1.reportingDate }

        // Build CSV content
        var csvContent = buildCSVHeader()
        csvContent += buildCSVRows(for: sortedProducts)

        // Generate unique filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
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

    // MARK: - Private Helpers

    /// Filters products by date range using reportingDate
    private func filterProducts(
        _ products: [ProductPair],
        dateRange: ClosedRange<Date>?
    ) -> [ProductPair] {
        guard let range = dateRange else { return products }

        return products.filter { product in
            range.contains(product.reportingDate)
        }
    }

    /// Builds CSV header row
    private func buildCSVHeader() -> String {
        let headers = [
            "Purchase Date",
            "GF Product",
            "GF Price",
            "GF Size",
            "GF Size (num)",
            "Non-GF Product",
            "Non-GF Price",
            "Non-GF Size",
            "Non-GF Size (num)",
            "Size Unit",
            "GF Unit Price",
            "Regular Unit Price",
            "Package Price Differential",
            "Unit Price Differential",
            "Category",
            "Store",
            "Receipt Verified",
            "Notes"
        ]

        return headers.joined(separator: ",") + "\n"
    }

    /// Builds CSV data rows for all products
    private func buildCSVRows(for products: [ProductPair]) -> String {
        products.map { product in
            buildCSVRow(for: product)
        }.joined(separator: "\n")
    }

    /// Builds a single CSV row for a product
    private func buildCSVRow(for product: ProductPair) -> String {
        let fields = [
            formatDate(product.reportingDate),
            escapeField(product.gfProductName),
            formatPrice(product.gfPrice),
            escapeField(product.gfSize ?? ""),
            formatOptionalDecimal(product.gfSizeValue),
            escapeField(product.nonGFProductName),
            formatPrice(product.nonGFPrice),
            escapeField(product.nonGFSize ?? ""),
            formatOptionalDecimal(product.nonGFSizeValue),
            escapeField(product.sizeUnit ?? ""),
            formatOptionalDecimal(product.gfUnitPrice),
            formatOptionalDecimal(product.regularUnitPrice),
            formatPrice(product.differential),
            formatOptionalDecimal(product.normalizedDifferential),
            escapeField(product.category ?? "Uncategorized"),
            escapeField(product.receipt?.storeName ?? ""),
            formatBoolean(product.verified),
            escapeField(product.notes ?? "")
        ]

        return fields.joined(separator: ",")
    }

    /// Formats an optional Decimal as a price string, or empty string if nil
    private func formatOptionalDecimal(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return formatPrice(value)
    }

    /// Formats a date as YYYY-MM-DD
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Formats a price as decimal with 2 places, no currency symbol
    private func formatPrice(_ price: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = "" // No thousands separator for CSV

        return formatter.string(from: price as NSDecimalNumber) ?? "0.00"
    }

    /// Formats a boolean as Yes/No
    private func formatBoolean(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    /// Escapes a CSV field with proper handling of special characters
    ///
    /// Rules:
    /// - If field contains comma, quote, or newline → wrap in quotes
    /// - If field contains quotes → escape with double quotes
    /// - Otherwise → return as-is
    private func escapeField(_ field: String) -> String {
        // Empty fields don't need escaping
        if field.isEmpty {
            return ""
        }

        // Check if escaping is needed
        let needsEscaping = field.contains(",") ||
                           field.contains("\"") ||
                           field.contains("\n") ||
                           field.contains("\r")

        if needsEscaping {
            // Escape existing quotes by doubling them
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            // Wrap in quotes
            return "\"\(escaped)\""
        }

        return field
    }

    // MARK: - Summary Statistics

    /// Calculates export summary statistics
    ///
    /// - Parameters:
    ///   - products: Products to analyze
    ///   - dateRange: Optional date range filter
    /// - Returns: Tuple with count and total differential
    func calculateExportSummary(
        products: [ProductPair],
        dateRange: ClosedRange<Date>? = nil
    ) -> (count: Int, totalDifferential: Decimal) {
        let filtered = filterProducts(products, dateRange: dateRange)
        let total = filtered.reduce(Decimal.zero) { sum, product in
            sum + product.differential
        }

        return (count: filtered.count, totalDifferential: total)
    }
}
