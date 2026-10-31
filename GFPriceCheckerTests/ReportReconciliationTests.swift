//
//  ReportReconciliationTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-10-31.
//

import Foundation
import GFCore
import PDFKit
import SwiftData
import Testing
@testable import GFPriceChecker

/// The dashboard, the CSV and the PDF report the same totals for the same year (#68).
///
/// Each of those used to sum the products itself, and the copies drifted: the PDF's
/// normalized total reported $0.00 where the dashboard reported nothing, and the PDF never
/// drew the grand-total line it had code for. They now all read `ReportTotals` from GFCore.
/// This test runs the demo dataset — the one the website's videos are recorded from —
/// through every surface and checks the numbers agree.
///
/// Run serially: the CSV and PDF services are `@MainActor` singletons that write files
/// into the shared temporary directory.
@Suite(.serialized)
@MainActor
struct ReportReconciliationTests {

    /// Nearly all of the demo dataset falls in this year, and some of its pairs have no
    /// size data, so the size-adjusted total excludes rows
    private static let year = 2026

    private static let datasetURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/Demo/demo-dataset.json")

    // MARK: - Fixture

    /// The products and receipts from the demo dataset, in an in-memory store
    ///
    /// Mirrors `DataBackupService.importBackup`'s mapping without its image files and
    /// settings, which a report doesn't read. The container is returned so the caller can
    /// hold it alive while the models are in use.
    private func loadDemoDataset() throws -> (ModelContainer, [ProductPair], [Receipt]) {
        let container = try ModelContainer(
            for: ProductPair.self, Receipt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(
            DataBackupService.BackupData.self,
            from: Data(contentsOf: Self.datasetURL)
        )

        var receiptsByID: [UUID: Receipt] = [:]
        for backup in backup.receipts {
            let receipt = Receipt(
                id: backup.id,
                purchaseDate: backup.purchaseDate,
                storeName: backup.storeName,
                totalAmount: backup.totalAmount.flatMap { Decimal(string: $0) }
            )
            context.insert(receipt)
            receiptsByID[receipt.id] = receipt
        }

        var products: [ProductPair] = []
        for backup in backup.productPairs {
            let receipt = backup.receiptID.flatMap { receiptsByID[$0] }
            let product = ProductPair(
                gfProductName: backup.gfProductName,
                gfPrice: try #require(Decimal(string: backup.gfPrice)),
                gfSize: backup.gfSize,
                gfSizeValue: backup.gfSizeValue.flatMap { Decimal(string: $0) },
                nonGFProductName: backup.nonGFProductName,
                nonGFPrice: try #require(Decimal(string: backup.nonGFPrice)),
                nonGFSize: backup.nonGFSize,
                nonGFSizeValue: backup.nonGFSizeValue.flatMap { Decimal(string: $0) },
                sizeUnit: backup.sizeUnit,
                quantity: backup.quantity ?? 1,
                id: backup.id,
                createdDate: backup.createdDate,
                category: backup.category,
                notes: backup.notes,
                verified: backup.verified,
                receipt: receipt
            )
            context.insert(product)
            receipt?.productPairs.append(product)
            products.append(product)
        }
        try context.save()

        return (container, products, Array(receiptsByID.values))
    }

    /// Splits CSV text into records of fields, honouring RFC 4180 quoting
    ///
    /// Product names in the demo dataset contain commas, so splitting on "," would shift
    /// the columns.
    private func parseCSV(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()

        while let character = pending {
            pending = iterator.next()
            if inQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                record.append(field)
                field = ""
            } else if character == "\n" {
                record.append(field)
                records.append(record)
                record = []
                field = ""
            } else {
                field.append(character)
            }
        }
        record.append(field)
        records.append(record)
        return records
    }

    // MARK: - Reconciliation

    @Test("Dashboard, CSV and PDF report the same totals for the demo dataset")
    func totalsReconcileAcrossSurfaces() async throws {
        let (container, products, receipts) = try loadDemoDataset()
        defer { withExtendedLifetime(container) {} }
        let calculator = ReportCalculator(calendar: .current)

        // The dashboard's figures
        let dashboard = ReportCalculator.totals(
            ReportViewModel(selectedYear: Self.year).rowsForSelectedYear(from: products)
        )
        try #require(dashboard.count > 0)
        try #require(dashboard.normalizedExcludedCount > 0, "The dataset should exercise excluded rows")
        let normalizedTotal = try #require(dashboard.totalNormalizedDifferential)

        // The CSV export over the same year, as ExportView would request it
        let midYear = try #require(Calendar.current.date(from: DateComponents(year: Self.year, month: 6, day: 15)))
        let range = calculator.dateRange(for: .currentYear, now: midYear)
        let summary = CSVExportService.shared.calculateExportSummary(products: products, dateRange: range)
        #expect(summary == dashboard)

        let csvURL = try await CSVExportService.shared.generateCSV(products: products, dateRange: range)
        defer { try? FileManager.default.removeItem(at: csvURL) }
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        let records = parseCSV(csv)
        let headers = try #require(records.first)
        let rows = records.dropFirst()
        #expect(rows.count == dashboard.count)
        #expect(rows.allSatisfy { $0.count == headers.count })

        func columnSum(_ name: String) throws -> Decimal {
            let index = try #require(headers.firstIndex(of: name))
            return try rows.reduce(Decimal.zero) { sum, row in
                row[index].isEmpty ? sum : sum + (try #require(Decimal(string: row[index])))
            }
        }

        // Prices are whole cents, so the package column sums to the total exactly
        #expect(try columnSum("Extended Package Differential") == dashboard.totalDifferential)

        // A total rounds the final sum, not the rows (PRODUCT_DEFINITION.md §3). The CSV
        // rounds each size-adjusted row to the cent, so its column drifts from the total by
        // up to half a cent per row. On this dataset the drift is real — the column sums to
        // $355.57 against a $355.58 total — so a total built from rounded rows fails here.
        let sizedRows = Decimal(dashboard.count - dashboard.normalizedExcludedCount)
        let drift = try columnSum("Extended Size-Adjusted Differential") - normalizedTotal
        #expect(abs(drift) <= sizedRows * Decimal(string: "0.005")!)
        #expect(drift != 0, "The demo dataset should tell a rounded sum from a sum of rounded rows")

        // The PDF: the cover and the grand-total line under the transactions
        let url = try await PDFGeneratorService.shared.generatePDF(
            products: products.filter { calculator.isDate($0.reportingDate, inYear: Self.year) },
            receipts: receipts.filter { calculator.isDate($0.purchaseDate, inYear: Self.year) },
            year: Self.year,
            userName: "Test User",
            paperSize: .usLetter
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try #require(PDFDocument(url: url))
        let cover = try #require(document.page(at: 0)?.string)
        let text = try #require(document.string)
        let normalizedText = normalizedTotal.formatted(.currency(code: "CAD"))
        let packageText = dashboard.totalDifferential.formatted(.currency(code: "CAD"))

        #expect(cover.contains(normalizedText))
        #expect(cover.contains(packageText))
        #expect(text.contains("Size-Adjusted Differential Total: \(normalizedText)"))
        #expect(text.contains("Package Price Differential Total (For Reference): \(packageText)"))
    }
}
