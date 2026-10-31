//
//  ExportFormatTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-10-30.
//

import Foundation
import GFCore
import PDFKit
import SwiftData
import Testing
@testable import GFPriceChecker

/// Pins the export formats to shared-docs' `PRODUCT_DEFINITION.md` §4 and §6 (issue #66).
///
/// The CSV is read by spreadsheets, not people, so its numbers and dates are machine
/// formats whatever the device locale. The locale test only bites when the run itself is
/// in a comma-decimal locale, and **fr-CA is not one**: the app ships only an English
/// localization, so a French-Canadian device resolves `Locale.current` to `en_CA`, which
/// writes `.`. The region is what matters. Reproduce the original bug with France:
///
/// ```
/// xcodebuild test -scheme GFPriceChecker \
///   -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///   -parallel-testing-enabled NO -testLanguage fr -testRegion FR \
///   -only-testing:GFPriceCheckerTests/ExportFormatTests
/// ```
///
/// Under `en_FR` the old formatter wrote `1234,50`, splitting one field into two.
///
/// Run serially: the exports write into the shared temporary directory through singletons.
@Suite(.serialized)
@MainActor
struct ExportFormatTests {

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

    private static let purchaseDate = Calendar.current.date(
        from: DateComponents(year: 2025, month: 5, day: 6, hour: 12)
    )!

    private func makePair(
        gfName: String = "GF Bread",
        gfPrice: String,
        gfSize: Decimal?,
        regularPrice: String,
        regularSize: Decimal?,
        unit: SizeUnit?,
        notes: String? = nil
    ) -> ProductPair {
        ProductPair(
            gfProductName: gfName,
            gfPrice: Decimal(string: gfPrice)!,
            gfSizeValue: gfSize,
            nonGFProductName: "Regular Bread",
            nonGFPrice: Decimal(string: regularPrice)!,
            nonGFSizeValue: regularSize,
            sizeUnit: unit?.rawValue,
            createdDate: Self.purchaseDate,
            notes: notes
        )
    }

    /// The CSV as written to disk, without the Excel BOM.
    private func csvContents(for products: [ProductPair]) async throws -> String {
        let url = try await CSVExportService.shared.generateCSV(products: products)
        defer { try? FileManager.default.removeItem(at: url) }
        return try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    /// The header and first data row of a CSV with no quoted fields, as a column lookup.
    private func firstRow(of csv: String) throws -> [String: String] {
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        let headers = try #require(lines.first).components(separatedBy: ",")
        let fields = try #require(lines.dropFirst().first).components(separatedBy: ",")
        try #require(headers.count == fields.count)
        return Dictionary(uniqueKeysWithValues: zip(headers, fields))
    }

    // MARK: - Locale

    /// Under a comma-decimal region the device formatter writes `7,99`, which a CSV reader
    /// takes as two columns. Exact strings here catch that, and any grouping separator or
    /// non-Latin digits a locale would add.
    @Test("CSV numbers and dates are machine formats in any locale")
    func csvUsesMachineFormats() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(
            gfPrice: "1234.50", gfSize: 400, regularPrice: "3.99", regularSize: 675, unit: .grams
        )
        context.insert(pair)

        let row = try firstRow(of: try await csvContents(for: [pair]))
        #expect(row["Purchase Date"] == "2025-05-06")
        #expect(row["GF Price"] == "1234.50")
        #expect(row["Non-GF Price"] == "3.99")
        #expect(row["GF Size (num)"] == "400.00")
        #expect(row["Package Price Differential"] == "1230.51")
    }

    // MARK: - Unit Price Columns

    /// §4: `$/100 g` for grams, `$/unit` for everything else, labelled `100g` or the raw unit.
    @Test("CSV unit prices follow the §4 convention", arguments: [
        // unit, GF price / size, regular price / size, basis, GF unit price, regular unit price
        (SizeUnit.grams, "7.99", Decimal(400), "3.99", Decimal(675), "100g", "1.9975", "0.5911"),
        (SizeUnit.kilograms, "12.99", Decimal(2), "8.49", Decimal(string: "2.5")!, "kg", "6.4950", "3.3960"),
        (SizeUnit.milliliters, "5.49", Decimal(946), "3.99", Decimal(1000), "mL", "0.0058", "0.0040"),
        (SizeUnit.count, "6.99", Decimal(6), "4.49", Decimal(10), "count", "1.1650", "0.4490"),
    ])
    func csvUnitPricesFollowConvention(
        unit: SizeUnit, gfPrice: String, gfSize: Decimal, regularPrice: String, regularSize: Decimal,
        basis: String, gfUnitPrice: String, regularUnitPrice: String
    ) async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(
            gfPrice: gfPrice, gfSize: gfSize, regularPrice: regularPrice, regularSize: regularSize, unit: unit
        )
        context.insert(pair)

        let row = try firstRow(of: try await csvContents(for: [pair]))
        #expect(row["Unit Price Basis"] == basis)
        #expect(row["GF Unit Price"] == gfUnitPrice)
        #expect(row["Regular Unit Price"] == regularUnitPrice)
    }

    @Test("CSV leaves unit prices empty without size data")
    func csvUnitPricesEmptyWithoutSizes() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(gfPrice: "7.99", gfSize: nil, regularPrice: "3.99", regularSize: nil, unit: nil)
        context.insert(pair)

        let row = try firstRow(of: try await csvContents(for: [pair]))
        #expect(row["Unit Price Basis"] == "")
        #expect(row["GF Unit Price"] == "")
        #expect(row["Regular Unit Price"] == "")
        #expect(row["Size-Adjusted Differential"] == "")
    }

    /// The spec's worked example, as the CSV writes it. The per-package figure is not a
    /// unit price differential, and the CSV no longer says it is.
    @Test("CSV names the per-package figure Size-Adjusted Differential")
    func csvNamesSizeAdjustedDifferential() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(gfPrice: "7.99", gfSize: 400, regularPrice: "3.99", regularSize: 675, unit: .grams)
        context.insert(pair)

        let csv = try await csvContents(for: [pair])
        let row = try firstRow(of: csv)
        #expect(row["Size-Adjusted Differential"] == "5.63")
        #expect(row["Extended Size-Adjusted Differential"] == "5.63")
        #expect(!csv.contains("Unit Price Differential"))
    }

    // MARK: - Escaping

    /// The CRLF case is the one that broke: Swift treats `"\r\n"` as a single `Character`,
    /// so `contains("\n")` and `contains("\r")` are both false for a field whose only line
    /// breaks are Windows-style, and the field went out unquoted.
    @Test("CSV quotes fields holding commas, quotes and line breaks")
    func csvEscapesSpecialCharacters() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pair = makePair(
            gfName: "Bread, \"Sliced\"",
            gfPrice: "7.99", gfSize: nil, regularPrice: "3.99", regularSize: nil, unit: nil,
            notes: "Line one\r\nLine two"
        )
        pair.category = "Snacks\nTreats"
        context.insert(pair)

        let csv = try await csvContents(for: [pair])
        #expect(csv.contains(",\"Bread, \"\"Sliced\"\"\","))
        #expect(csv.contains(",\"Snacks\nTreats\","))
        #expect(csv.hasSuffix(",\"Line one\r\nLine two\""))
    }

    // MARK: - PDF

    /// 6.255 is a tie that `Double` cannot hold — it is stored as 6.25499… — so formatting
    /// through `Double` drops a cent that the Decimal value and the cover total both keep.
    @Test("The PDF formats money from Decimal, not Double")
    func pdfFormatsMoneyAsDecimal() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // (7.99 / 400 − 3.47 / 800) × 400 = 7.99 − 1.735 = 6.255 exactly
        let pair = makePair(gfPrice: "7.99", gfSize: 400, regularPrice: "3.47", regularSize: 800, unit: .grams)
        context.insert(pair)
        try #require(pair.extendedNormalizedDifferential == Decimal(string: "6.255")!)

        let url = try await PDFGeneratorService.shared.generatePDF(
            products: [pair],
            receipts: [],
            year: 2025,
            userName: "Test User",
            paperSize: .usLetter
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try #require(PDFDocument(url: url))
        let text = try #require(document.string)
        let expected = Decimal(string: "6.26")!.formatted(.number.precision(.fractionLength(2)))
        let doubleRounded = Decimal(string: "6.25")!.formatted(.number.precision(.fractionLength(2)))
        #expect(text.contains(expected))
        #expect(!text.contains(doubleRounded))
        #expect(!text.contains("Unit Price Diff"))
    }
}
