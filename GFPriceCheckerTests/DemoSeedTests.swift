//
//  DemoSeedTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-09-14.
//

import Foundation
import SwiftData
import Testing
@testable import GFPriceChecker

/// Covers the Stage 2 seeding seam and, through it, the shape of the datasets
/// `Tools/Demo/scrub_backup.py` writes.
///
/// The scrubber mirrors `DataBackupService`'s Codable structs in Python so it
/// can tell whether its output will import. A mirror drifts. `seedsAScrubbedDataset`
/// is the check that does not: the JSON it seeds from is literally that tool's
/// output, so a field the two disagree about fails here.
///
/// Serialized, and the settings it touches are restored: seeding writes through
/// `AppSettings.shared`, which is process-wide `@AppStorage`.
@MainActor
@Suite("Demo seeding", .serialized)
struct DemoSeedTests {

    /// `scrub_backup.py --in … --out … --strip-notes --strip-product-images` on a
    /// two-product export, with the drawn receipt image dropped afterwards —
    /// importing it would write a JPEG into the test host's Documents directory,
    /// and the schema is what this is here to pin.
    static let scrubbedDataset = """
    {
      "appVersion": "1.0",
      "productPairs": [
        {
          "category": "Bakery",
          "createdDate": "2025-04-06T14:32:00Z",
          "gfImageData": null,
          "gfImageUUID": null,
          "gfOCRConfidence": 0.91,
          "gfPrice": "7.49",
          "gfProductName": "Northfield GF White Bread",
          "gfSize": "500 g",
          "gfSizeValue": "500",
          "id": "8B32E020-1D78-405A-936E-7CD5C188ADC1",
          "nonGFImageData": null,
          "nonGFImageUUID": null,
          "nonGFOCRConfidence": 0.88,
          "nonGFPrice": "3.29",
          "nonGFProductName": "Pantry Lane White Bread",
          "nonGFSize": "675 g",
          "nonGFSizeValue": "675",
          "notes": null,
          "quantity": 1,
          "receiptID": "7A032B84-AD7D-4BB4-B57B-C4C88EC329C5",
          "sizeUnit": "gram",
          "verified": true
        },
        {
          "category": "Pasta",
          "createdDate": "2025-04-06T14:32:00Z",
          "gfImageData": null,
          "gfImageUUID": null,
          "gfOCRConfidence": 0.91,
          "gfPrice": "4.99",
          "gfProductName": "Northfield GF Penne",
          "gfSize": "500 g",
          "gfSizeValue": "500",
          "id": "4E184435-27E5-4483-9F4B-F629579B6275",
          "nonGFImageData": null,
          "nonGFImageUUID": null,
          "nonGFOCRConfidence": 0.88,
          "nonGFPrice": "1.89",
          "nonGFProductName": "Pantry Lane Penne Rigate",
          "nonGFSize": "675 g",
          "nonGFSizeValue": "675",
          "notes": null,
          "quantity": 1,
          "receiptID": "7A032B84-AD7D-4BB4-B57B-C4C88EC329C5",
          "sizeUnit": "gram",
          "verified": true
        }
      ],
      "receipts": [
        {
          "extractedOCRText": "LOBLAWS\\n2025-04-06 14:32\\nNORTHFIELD GF WHITE BREAD $7.49\\nNORTHFIELD GF PENNE $4.99\\nTOTAL $12.48\\nTHANK YOU FOR SHOPPING",
          "id": "7A032B84-AD7D-4BB4-B57B-C4C88EC329C5",
          "productPairIDs": [
            "8B32E020-1D78-405A-936E-7CD5C188ADC1",
            "4E184435-27E5-4483-9F4B-F629579B6275"
          ],
          "purchaseDate": "2025-04-06T14:32:00Z",
          "receiptImageData": null,
          "receiptImageUUID": null,
          "storeName": "Loblaws",
          "totalAmount": "12.48"
        }
      ],
      "settings": {
        "accountantEmail": "accountant@example.com",
        "currencySymbol": "$",
        "defaultDateRange": "currentYear",
        "defaultPaperSize": "letter",
        "taxID": "000 000 000",
        "userName": "Alex Demo"
      },
      "timestamp": "2026-09-14T09:00:00Z",
      "version": "1.0"
    }
    """

    // MARK: - Environment

    @Test("No dataset is requested when the variable is absent or empty")
    func requestedDatasetIsNilWithoutTheVariable() {
        unsetenv(DemoSeed.datasetVariable)
        #expect(DemoSeed.requestedDataset == nil)

        setenv(DemoSeed.datasetVariable, "", 1)
        #expect(DemoSeed.requestedDataset == nil, "an empty variable is not a request to seed")
        unsetenv(DemoSeed.datasetVariable)
    }

    /// `seed.sh` hands over an absolute host path, already expanded. The app
    /// must not touch it: `~` inside a Simulator process is the app's own
    /// container, so anything that looks like expansion here resolves to the
    /// wrong place — and `URL(fileURLWithPath:)` does expand one, which is why
    /// this pins the passthrough rather than trusting it.
    @Test("An absolute host path reaches the importer unchanged")
    func requestedDatasetIsTakenAsGiven() throws {
        let given = "/Users/somebody/GFPCDemoData/demo-dataset.json"
        setenv(DemoSeed.datasetVariable, given, 1)
        defer { unsetenv(DemoSeed.datasetVariable) }

        #expect(try #require(DemoSeed.requestedDataset).path == given)
    }

    // MARK: - Seeding

    @Test("Seeding does nothing when no dataset is named")
    func seedingIsInertByDefault() async throws {
        unsetenv(DemoSeed.datasetVariable)
        let container = try emptyContainer()

        await DemoSeed.seedIfRequested(container: container)

        let products = try container.mainContext.fetch(FetchDescriptor<ProductPair>())
        #expect(products.isEmpty, "an ordinary DEBUG launch must not touch the store")
    }

    @Test("Seeding loads a scrubbed dataset into an empty store")
    func seedsAScrubbedDataset() async throws {
        let settings = AppSettings.shared
        let restore = (settings.userName, settings.accountantEmail, settings.taxID,
                       settings.hasCompletedOnboarding)
        defer {
            (settings.userName, settings.accountantEmail, settings.taxID,
             settings.hasCompletedOnboarding) = restore
            unsetenv(DemoSeed.datasetVariable)
        }

        let path = try writeDataset(Self.scrubbedDataset)
        setenv(DemoSeed.datasetVariable, path, 1)
        let container = try emptyContainer()

        await DemoSeed.seedIfRequested(container: container)

        let products = try container.mainContext.fetch(FetchDescriptor<ProductPair>())
        let receipts = try container.mainContext.fetch(FetchDescriptor<Receipt>())
        #expect(products.count == 2)
        #expect(receipts.count == 1)

        let bread = try #require(products.first { $0.gfProductName.contains("Bread") })
        #expect(bread.gfPrice == Decimal(string: "7.49"))
        #expect(bread.nonGFPrice == Decimal(string: "3.29"))
        #expect(bread.differential == Decimal(string: "4.20"))
        #expect(bread.category == "Bakery")
        #expect(bread.quantity == 1)

        // The relationship is the part the JSON expresses by id alone, so it is
        // the part a schema mismatch loses silently.
        let receipt = try #require(receipts.first)
        #expect(receipt.storeName == "Loblaws")
        #expect(receipt.totalAmount == Decimal(string: "12.48"))
        #expect(receipt.productPairs.count == 2)
        #expect(bread.receipt?.id == receipt.id)
        #expect(bread.reportingDate == receipt.purchaseDate)

        #expect(settings.taxID == "000 000 000")
        #expect(settings.accountantEmail == "accountant@example.com")
        #expect(settings.hasCompletedOnboarding, "a seeded Simulator must not open onboarding")
    }

    @Test("Seeding replaces whatever the store already held")
    func seedingReplacesExistingData() async throws {
        let settings = AppSettings.shared
        let restore = settings.hasCompletedOnboarding
        defer {
            settings.hasCompletedOnboarding = restore
            unsetenv(DemoSeed.datasetVariable)
        }

        let container = try emptyContainer()
        container.mainContext.insert(
            ProductPair(gfProductName: "Stale", gfPrice: 1, nonGFProductName: "Stale", nonGFPrice: 1)
        )
        try container.mainContext.save()

        let path = try writeDataset(Self.scrubbedDataset)
        setenv(DemoSeed.datasetVariable, path, 1)
        await DemoSeed.seedIfRequested(container: container)

        let products = try container.mainContext.fetch(FetchDescriptor<ProductPair>())
        #expect(products.count == 2, "a take starts from the dataset, not from it plus history")
        #expect(!products.contains { $0.gfProductName == "Stale" })
    }

    // MARK: - Helpers

    private func emptyContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ProductPair.self, Receipt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func writeDataset(_ json: String) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("demo-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
