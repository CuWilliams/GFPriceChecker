//
//  BackupFormatTests.swift
//  GFCoreTests
//
//  Created by Claude Code on 2026-10-31 (#70).
//

import Foundation
import Testing
import GFCore

/// The backup schema, read the way every past backup was written
///
/// The format is the migration path between platforms (PRODUCT_DEFINITION.md §7), so what
/// matters is that existing files keep decoding: the two datasets in `Tools/Demo`, and a
/// backup from before unit pricing and quantity existed. The round trip through SwiftData
/// is `DataBackupRoundTripTests`, in the app.
@Suite("Backup format")
struct BackupFormatTests {

    // MARK: - Fixtures

    /// `Tools/Demo` at the repository root
    private static let demoDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GFCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // GFCore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/Demo")

    private func decodeDemoFile(_ name: String) throws -> BackupData {
        try BackupFormat.decode(Data(contentsOf: Self.demoDirectory.appendingPathComponent(name)))
    }

    /// Shaped like a build-7 backup: no `gfSizeValue`, `nonGFSizeValue`, `sizeUnit` or
    /// `quantity` keys, and no optional strings at all
    private static let legacyBackupJSON = """
    {
      "version": "1.0",
      "timestamp": "2026-01-15T12:00:00Z",
      "appVersion": "1.0",
      "productPairs": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "gfProductName": "Legacy GF Bread",
          "gfPrice": "6.99",
          "gfOCRConfidence": 0,
          "nonGFProductName": "Legacy Regular Bread",
          "nonGFPrice": "2.99",
          "nonGFOCRConfidence": 0,
          "createdDate": "2026-01-15T12:00:00Z",
          "category": "Bread",
          "verified": false
        }
      ],
      "receipts": [],
      "settings": {
        "userName": "",
        "accountantEmail": "",
        "taxID": "",
        "currencySymbol": "",
        "defaultPaperSize": "",
        "defaultDateRange": ""
      }
    }
    """

    private static func roundedToCents(_ value: Decimal) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }

    // MARK: - Demo datasets

    @Test("The demo dataset decodes with its records, links and settings")
    func demoDatasetDecodes() throws {
        let backup = try decodeDemoFile("demo-dataset.json")

        #expect(backup.version == BackupFormat.version)
        #expect(backup.timestamp == Date(timeIntervalSince1970: 1_789_394_863)) // 2026-09-14T14:07:43Z
        #expect(backup.productPairs.count == 78)
        #expect(backup.receipts.count == 47)

        // Every pair is verified by a receipt in the file, and every receipt lists it back
        let receiptsByID = Dictionary(uniqueKeysWithValues: backup.receipts.map { ($0.id, $0) })
        for pair in backup.productPairs {
            let receiptID = try #require(pair.receiptID)
            let receipt = try #require(receiptsByID[receiptID])
            #expect(receipt.productPairIDs.contains(pair.id))
        }

        #expect(backup.settings == SettingsBackup(
            userName: "Alex Demo",
            accountantEmail: "accountant@example.com",
            taxID: "000 000 000",
            currencySymbol: "$ CAD",
            defaultPaperSize: "US Letter",
            defaultDateRange: DateRangePreset.currentYear.rawValue
        ))
    }

    @Test("The demo dataset's first record decodes field by field")
    func demoDatasetFirstRecord() throws {
        let backup = try decodeDemoFile("demo-dataset.json")
        let pair = try #require(backup.productPairs.first)

        #expect(pair.id == UUID(uuidString: "FCE9AB3E-D7A8-42E1-A2DE-E50ED6BCA8D9"))
        #expect(pair.gfProductName == "ORGANIC TORTILLA CHIPS")
        #expect(pair.gfPrice == "6.39")
        #expect(pair.gfSize == "908g")
        #expect(pair.gfSizeValue == "908")
        #expect(pair.nonGFProductName == "CORN CHIP DIPPERS")
        #expect(pair.nonGFPrice == "5.99")
        #expect(pair.nonGFSizeValue == "907")
        #expect(pair.sizeUnit == SizeUnit.grams.rawValue)
        #expect(pair.gfImageData != nil)
        #expect(pair.verified)
        #expect(pair.createdDate == Date(timeIntervalSince1970: 1_768_922_527)) // 2026-01-20T15:22:07Z

        // The demo dataset has no quantity keys, so every record is one unit
        #expect(pair.quantity == nil)
        #expect(pair.effectiveQuantity == 1)

        let receipt = try #require(backup.receipts.first)
        #expect(receipt.storeName == "Costco")
        #expect(receipt.totalAmount == "6.39")
        #expect(receipt.productPairIDs == [pair.id])
    }

    @Test("The demo dataset totals what the dashboard has always shown")
    func demoDatasetTotals() throws {
        let backup = try decodeDemoFile("demo-dataset.json")

        let pricing = try backup.productPairs.map { pair in
            PricingInputs(
                gfPrice: try #require(BackupFormat.decimal(from: pair.gfPrice)),
                nonGFPrice: try #require(BackupFormat.decimal(from: pair.nonGFPrice)),
                gfSizeValue: pair.gfSizeValue.flatMap(BackupFormat.decimal(from:)),
                nonGFSizeValue: pair.nonGFSizeValue.flatMap(BackupFormat.decimal(from:)),
                quantity: pair.effectiveQuantity
            )
        }
        let rows = backup.productPairs.indices.map { index in
            ReportRow(
                reportingDate: backup.productPairs[index].createdDate,
                pricing: pricing[index],
                gfProductName: backup.productPairs[index].gfProductName,
                nonGFProductName: backup.productPairs[index].nonGFProductName
            )
        }
        let totals = ReportCalculator.totals(rows)

        // The figures `ReportReconciliationTests` sees through every surface of the app
        #expect(totals.totalDifferential == Decimal(string: "278.03")!)
        let normalized = try #require(totals.totalNormalizedDifferential)
        #expect(Self.roundedToCents(normalized) == Decimal(string: "355.58")!)
        #expect(totals.normalizedExcludedCount == 4)
    }

    @Test("The empty dataset decodes to no records and unset settings")
    func emptyDatasetDecodes() throws {
        let backup = try decodeDemoFile("empty-dataset.json")

        #expect(backup.productPairs.isEmpty)
        #expect(backup.receipts.isEmpty)
        #expect(backup.settings.userName.isEmpty)
        #expect(backup.settings.defaultDateRange.isEmpty)
    }

    // MARK: - Legacy backups

    @Test("A backup written before unit pricing and quantity existed still decodes")
    func legacyBackupDecodes() throws {
        let backup = try BackupFormat.decode(Data(Self.legacyBackupJSON.utf8))
        let pair = try #require(backup.productPairs.first)

        #expect(pair.gfProductName == "Legacy GF Bread")
        #expect(BackupFormat.decimal(from: pair.gfPrice) == Decimal(string: "6.99")!)

        // The absent keys land as nil rather than failing the decode outright
        #expect(pair.gfSize == nil)
        #expect(pair.gfSizeValue == nil)
        #expect(pair.nonGFSizeValue == nil)
        #expect(pair.sizeUnit == nil)
        #expect(pair.gfImageUUID == nil)
        #expect(pair.receiptID == nil)
        #expect(pair.quantity == nil)

        // A legacy record predates quantity, so it reads as a single-unit purchase
        #expect(pair.effectiveQuantity == 1)
    }

    @Test("A recorded quantity is used as it is")
    func recordedQuantityIsUsed() throws {
        let json = Self.legacyBackupJSON.replacingOccurrences(
            of: "\"verified\": false",
            with: "\"verified\": false, \"quantity\": 3"
        )
        let pair = try #require(try BackupFormat.decode(Data(json.utf8)).productPairs.first)
        #expect(pair.quantity == 3)
        #expect(pair.effectiveQuantity == 3)
    }

    // MARK: - Version gate

    @Test("A backup of another version is rejected with its version", arguments: ["2.0", "1.1", "1", ""])
    func otherVersionIsRejected(version: String) {
        let json = Self.legacyBackupJSON.replacingOccurrences(
            of: "\"version\": \"1.0\"",
            with: "\"version\": \"\(version)\""
        )
        #expect(throws: BackupFormatError.incompatibleVersion(version)) {
            try BackupFormat.decode(Data(json.utf8))
        }
    }

    @Test("Data that isn't a backup fails to decode")
    func nonBackupFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try BackupFormat.decode(Data("{\"version\": \"1.0\"}".utf8))
        }
    }

    // MARK: - Writing

    @Test("A written backup has sorted keys, ISO 8601 dates and decimals as strings")
    func encodedFormat() throws {
        let backup = BackupData(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.0",
            productPairs: [],
            receipts: [
                ReceiptBackup(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    purchaseDate: Date(timeIntervalSince1970: 1_699_000_000),
                    storeName: nil,
                    receiptImageUUID: nil,
                    receiptImageData: nil,
                    totalAmount: BackupFormat.string(from: Decimal(string: "1234.50")!),
                    extractedOCRText: nil,
                    productPairIDs: []
                )
            ],
            settings: SettingsBackup(
                userName: "", accountantEmail: "", taxID: "",
                currencySymbol: "", defaultPaperSize: "", defaultDateRange: ""
            )
        )

        let text = try #require(String(data: BackupFormat.encode(backup), encoding: .utf8))

        #expect(text.contains("\"timestamp\" : \"2023-11-14T22:13:20Z\""))
        #expect(text.contains("\"purchaseDate\" : \"2023-11-03T08:26:40Z\""))
        #expect(text.contains("\"totalAmount\" : \"1234.5\""))
        #expect(text.contains("\"version\" : \"1.0\""))

        let topLevelKeys = ["appVersion", "productPairs", "receipts", "settings", "timestamp", "version"]
        let offsets = topLevelKeys.map { text.range(of: "\n  \"\($0)\"")?.lowerBound }
        #expect(offsets.allSatisfy { $0 != nil })
        #expect(offsets.compactMap { $0 } == offsets.compactMap { $0 }.sorted())
    }

    @Test("A backup survives encoding then decoding unchanged")
    func encodeDecodeRoundTrip() throws {
        let original = try BackupFormat.decode(Data(Self.legacyBackupJSON.utf8))
        #expect(try BackupFormat.decode(BackupFormat.encode(original)) == original)
    }

    @Test("Decimals are written without grouping or a locale's separator, and read back exactly",
          arguments: ["0.01", "6.99", "1234.5", "100000", "0.019975"])
    func decimalStrings(text: String) throws {
        let value = try #require(Decimal(string: text))
        #expect(BackupFormat.string(from: value) == text)
        #expect(BackupFormat.decimal(from: text) == value)
    }

    @Test("A decimal string that isn't a number reads as nil")
    func nonNumericDecimalString() {
        #expect(BackupFormat.decimal(from: "abc") == nil)
    }
}
