//
//  CSVExporter.swift
//  GFCore
//
//  Moved from GFPriceChecker/Services/CSVExportService.swift on 2026-10-31 (#68).
//

import Foundation

/// Generates the itemized CSV described in PRODUCT_DEFINITION.md §6
///
/// - Rows oldest first, by reporting date
/// - Proper CSV escaping for special characters
/// - Date format: YYYY-MM-DD
/// - Price format: decimal with 2 places, no currency symbol
/// - Unit prices: 4 places, per 100 g for grams and per unit otherwise (spec §4), with the
///   basis in its own column
/// - Numbers and dates in `en_US_POSIX`, whatever the device locale: a region such as France
///   writes `7,99`, which a CSV reader splits into two fields
/// - Boolean values as Yes/No
///
/// The text has no byte-order mark; `CSVExportService` adds one when it writes the file.
public enum CSVExporter {

    /// The column titles, in order
    public static let headers = [
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

    /// The CSV for `rows`: a header line, then one line per row, oldest first
    ///
    /// - Parameter timeZone: The time zone purchase dates are written in. The app passes
    ///   the device's, so a date matches the one the app shows.
    public static func generate(rows: [ReportRow], timeZone: TimeZone) -> String {
        let sorted = rows.sorted { $0.reportingDate < $1.reportingDate }
        let dateFormatter = makeDateFormatter(timeZone: timeZone)

        var csv = headers.joined(separator: ",") + "\n"
        csv += sorted.map { line(for: $0, dateFormatter: dateFormatter) }.joined(separator: "\n")
        return csv
    }

    /// Formats a date as YYYY-MM-DD, for file names and the like
    public static func formatDate(_ date: Date, timeZone: TimeZone) -> String {
        makeDateFormatter(timeZone: timeZone).string(from: date)
    }

    // MARK: - Rows

    /// Builds a single CSV line for a row
    private static func line(for row: ReportRow, dateFormatter: DateFormatter) -> String {
        let pricing = row.pricing
        // Unit prices are only meaningful with a unit to state them against
        let unit = row.resolvedSizeUnit
        let fields = [
            dateFormatter.string(from: row.reportingDate),
            String(pricing.quantity),
            escapeField(row.gfProductName),
            formatPrice(pricing.gfPrice),
            escapeField(row.gfSize ?? ""),
            formatOptionalDecimal(pricing.gfSizeValue),
            escapeField(row.nonGFProductName),
            formatPrice(pricing.nonGFPrice),
            escapeField(row.nonGFSize ?? ""),
            formatOptionalDecimal(pricing.nonGFSizeValue),
            escapeField(row.sizeUnit ?? ""),
            unit.map { escapeField($0.unitPriceLabel) } ?? "",
            formatUnitPrice(pricing.gfUnitPrice, unit: unit),
            formatUnitPrice(pricing.regularUnitPrice, unit: unit),
            formatPrice(pricing.differential),
            formatOptionalDecimal(pricing.normalizedDifferential),
            formatPrice(pricing.extendedDifferential),
            formatOptionalDecimal(pricing.extendedNormalizedDifferential),
            escapeField(row.categoryName),
            escapeField(row.storeName ?? ""),
            formatBoolean(row.verified),
            escapeField(row.notes ?? "")
        ]

        return fields.joined(separator: ",")
    }

    // MARK: - Formatting

    private static func makeDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // Gregorian calendar, Latin digits
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// Formats an optional Decimal as a price string, or empty string if nil
    private static func formatOptionalDecimal(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return formatPrice(value)
    }

    /// Formats a unit price at the spec §4 scale — $/100 g for grams, $/unit otherwise —
    /// to 4 places, since $/mL rounds to nothing at 2. Empty without a unit to scale by.
    private static func formatUnitPrice(_ value: Decimal?, unit: SizeUnit?) -> String {
        guard let value, let unit else { return "" }
        return formatDecimal(value * unit.unitPriceScaleFactor, fractionDigits: 4)
    }

    /// Formats a price as decimal with 2 places, no currency symbol
    private static func formatPrice(_ price: Decimal) -> String {
        formatDecimal(price, fractionDigits: 2)
    }

    /// Formats a decimal with a fixed number of places, rounded half-up, `.` as the separator and no grouping
    private static func formatDecimal(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp // PRODUCT_DEFINITION.md §3: half a cent rounds away from zero

        return formatter.string(from: value as NSDecimalNumber) ?? ""
    }

    /// Formats a boolean as Yes/No
    private static func formatBoolean(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    /// Escapes a CSV field with proper handling of special characters
    ///
    /// Rules:
    /// - If field contains comma, quote, or newline → wrap in quotes
    /// - If field contains quotes → escape with double quotes
    /// - Otherwise → return as-is
    static func escapeField(_ field: String) -> String {
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
}
