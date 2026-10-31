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
/// - Unit prices: 4 places, per 100 g for grams and per unit otherwise (spec §4), with the
///   basis in its own column
/// - Numbers and dates in `en_US_POSIX`, whatever the device locale: a region such as France
///   writes `7,99`, which a CSV reader splits into two fields
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
        let dateString = formatDate(Date())
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
            "Quantity",
            "GF Product",
            "GF Price",
            "GF Size",
            "GF Size (num)",
            "Non-GF Product",
            "Non-GF Price",
            "Non-GF Size",
            "Non-GF Size (num)",
            "Size Unit",
            "Unit Price Basis",
            "GF Unit Price",
            "Regular Unit Price",
            "Package Price Differential",
            "Size-Adjusted Differential",
            "Extended Package Differential",
            "Extended Size-Adjusted Differential",
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
        // Unit prices are only meaningful with a unit to state them against
        let unit = product.resolvedSizeUnit
        let fields = [
            formatDate(product.reportingDate),
            String(product.quantity),
            escapeField(product.gfProductName),
            formatPrice(product.gfPrice),
            escapeField(product.gfSize ?? ""),
            formatOptionalDecimal(product.gfSizeValue),
            escapeField(product.nonGFProductName),
            formatPrice(product.nonGFPrice),
            escapeField(product.nonGFSize ?? ""),
            formatOptionalDecimal(product.nonGFSizeValue),
            escapeField(product.sizeUnit ?? ""),
            unit.map { escapeField($0.unitPriceLabel) } ?? "",
            formatUnitPrice(product.gfUnitPrice, unit: unit),
            formatUnitPrice(product.regularUnitPrice, unit: unit),
            formatPrice(product.differential),
            formatOptionalDecimal(product.normalizedDifferential),
            formatPrice(product.extendedDifferential),
            formatOptionalDecimal(product.extendedNormalizedDifferential),
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

    /// Formats a unit price at the spec §4 scale — $/100 g for grams, $/unit otherwise —
    /// to 4 places, since $/mL rounds to nothing at 2. Empty without a unit to scale by.
    private func formatUnitPrice(_ value: Decimal?, unit: SizeUnit?) -> String {
        guard let value, let unit else { return "" }
        return formatDecimal(value * unit.unitPriceScaleFactor, fractionDigits: 4)
    }

    /// Formats a date as YYYY-MM-DD
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // Gregorian calendar, Latin digits
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Formats a price as decimal with 2 places, no currency symbol
    private func formatPrice(_ price: Decimal) -> String {
        formatDecimal(price, fractionDigits: 2)
    }

    /// Formats a decimal with a fixed number of places, `.` as the separator and no grouping
    private func formatDecimal(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits

        return formatter.string(from: value as NSDecimalNumber) ?? ""
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

        // Check if escaping is needed. Scan scalars, not Characters: Swift treats "\r\n" as
        // one Character, so `contains("\n")` misses a Windows line break entirely.
        let needsEscaping = field.unicodeScalars.contains { scalar in
            scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r"
        }

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
            sum + product.extendedDifferential
        }

        return (count: filtered.count, totalDifferential: total)
    }
}
