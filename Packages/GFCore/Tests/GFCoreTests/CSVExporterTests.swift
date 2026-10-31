//
//  CSVExporterTests.swift
//  GFCoreTests
//
//  Moved from GFPriceCheckerTests/QuantityReportingTests.swift on 2026-10-31 (#68).
//

import Foundation
import Testing
@testable import GFCore

/// Pins the CSV text. The file-writing path, BOM and locale run are tested in the app by
/// `ExportFormatTests`.
@Suite("CSV exporter")
struct CSVExporterTests {

    private static let toronto = TimeZone(identifier: "America/Toronto")!

    private func date(year: Int, month: Int, day: Int, hour: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.toronto
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func makeRow(
        quantity: Int = 1,
        reportingDate: Date,
        gfName: String = "GF Bread",
        notes: String? = nil
    ) -> ReportRow {
        ReportRow(
            reportingDate: reportingDate,
            pricing: PricingInputs(
                gfPrice: Decimal(string: "7.99")!,
                nonGFPrice: Decimal(string: "3.49")!,
                gfSizeValue: 400,
                nonGFSizeValue: 200,
                quantity: quantity
            ),
            gfProductName: gfName,
            gfSize: "400g",
            nonGFProductName: "Regular Bread",
            nonGFSize: "200g",
            sizeUnit: SizeUnit.grams.rawValue,
            category: nil,
            verified: true,
            storeName: "Loblaws",
            notes: notes
        )
    }

    /// The lines of a CSV with no quoted fields, each as a column lookup
    private func records(_ csv: String) throws -> [[String: String]] {
        let lines = csv.components(separatedBy: "\n")
        let headers = try #require(lines.first).components(separatedBy: ",")
        return try lines.dropFirst().map { line in
            let fields = line.components(separatedBy: ",")
            // Header and row are positional arrays. A field added to one and not the other
            // shifts every later column silently, so check the counts first.
            try #require(fields.count == headers.count)
            return Dictionary(uniqueKeysWithValues: zip(headers, fields))
        }
    }

    @Test("CSV carries a Quantity column and extended differentials that reconcile")
    func quantityAndExtendedColumns() throws {
        let csv = CSVExporter.generate(
            rows: [makeRow(quantity: 3, reportingDate: try date(year: 2025, month: 5, day: 6, hour: 12))],
            timeZone: Self.toronto
        )
        let row = try #require(try records(csv).first)

        #expect(row["Quantity"] == "3")
        #expect(row["Package Price Differential"] == "4.50")
        #expect(row["Extended Package Differential"] == "13.50")
        #expect(row["Size-Adjusted Differential"] == "1.01")
        #expect(row["Extended Size-Adjusted Differential"] == "3.03")
        #expect(row["Unit Price Basis"] == "100g")
        #expect(row["GF Unit Price"] == "1.9975")
        #expect(row["Category"] == "Uncategorized")
        #expect(row["Store"] == "Loblaws")
        #expect(row["Receipt Verified"] == "Yes")
    }

    @Test("Rows are written oldest first, with no trailing newline")
    func rowsOldestFirst() throws {
        let csv = CSVExporter.generate(
            rows: [
                makeRow(reportingDate: try date(year: 2025, month: 6, day: 1, hour: 12), gfName: "June"),
                makeRow(reportingDate: try date(year: 2025, month: 2, day: 1, hour: 12), gfName: "February")
            ],
            timeZone: Self.toronto
        )
        #expect(try records(csv).map { $0["GF Product"] } == ["February", "June"])
        #expect(!csv.hasSuffix("\n"))
    }

    /// 21:00 on 6 May in Toronto is already 7 May in UTC.
    @Test("Purchase dates are written in the given time zone")
    func datesFollowTimeZone() throws {
        let evening = try date(year: 2025, month: 5, day: 6, hour: 21)
        let rows = [makeRow(reportingDate: evening)]

        #expect(try records(CSVExporter.generate(rows: rows, timeZone: Self.toronto)).first?["Purchase Date"] == "2025-05-06")
        #expect(try records(CSVExporter.generate(rows: rows, timeZone: TimeZone(identifier: "UTC")!)).first?["Purchase Date"] == "2025-05-07")
    }

    @Test("An empty export is the header line alone")
    func emptyExport() {
        #expect(CSVExporter.generate(rows: [], timeZone: Self.toronto)
            == CSVExporter.headers.joined(separator: ",") + "\n")
    }

    @Test("Fields holding commas, quotes and line breaks are quoted", arguments: [
        ("plain", "plain"),
        ("", ""),
        ("Bread, white", "\"Bread, white\""),
        ("The \"good\" one", "\"The \"\"good\"\" one\""),
        ("line\nbreak", "\"line\nbreak\""),
        ("windows\r\nbreak", "\"windows\r\nbreak\"")
    ])
    func escaping(input: String, expected: String) {
        #expect(CSVExporter.escapeField(input) == expected)
    }
}
