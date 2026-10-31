//
//  DataBackupRoundTripTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-08-14.
//

import Foundation
import GFCore
import SwiftData
import Testing
@testable import GFPriceChecker

/// Guards against silent drift between the SwiftData models and the backup DTOs.
///
/// `DataBackupService` hand-duplicates the field list of `ProductPair` and `Receipt` into
/// `ProductPairBackup` / `ReceiptBackup`. Nothing keeps them in sync and a mismatch fails
/// *silently* — it compiles, it ships, and the data is only lost when a user restores.
///
/// This already happened once: `ProductPairBackup` was never given `gfSizeValue`,
/// `nonGFSizeValue` or `sizeUnit` when unit pricing was added, so a backup round trip
/// reduced every record to package-price-only and wiped the Unit Price Differential.
/// Fixed in b7216c9, but only after it was noticed by chance.
///
/// Two layers of protection, because they fail at different moments:
///
/// 1. **Schema canaries** (`productPairSchemaIsAccountedFor` / `receiptSchemaIsAccountedFor`)
///    reflect over the model and compare its stored-property names against a list checked
///    in here. These trip the moment a property is *declared*, naming the new field.
/// 2. **Round-trip tests** actually export and re-import, asserting field by field via
///    `expectFieldsPreserved`. These prove the data genuinely survives, but only for
///    fields the fixture populates.
///
/// The canaries exist because layer 2 alone is not enough: it stays green for a new field
/// nobody thought to add to the fixture — which is precisely the mistake being guarded
/// against. Adding a property should fail layer 1 and force you through both.
/// Run serially: every test drives the `DataBackupService.shared` singleton, whose export
/// reads and whose import writes `AppSettings.shared` (backed by real `UserDefaults`).
/// Running them concurrently races on that shared state.
@Suite(.serialized)
@MainActor
struct DataBackupRoundTripTests {

    // MARK: - Harness

    /// A fresh in-memory store. Mirrors the pattern used by the app's `#Preview` blocks
    /// (e.g. `ProductPairListView.swift`).
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ProductPair.self, Receipt.self,
            configurations: configuration
        )
    }

    /// Exports from one store and imports into a second, independent one.
    ///
    /// Two containers matter: importing back into the source context could be satisfied by
    /// objects already resident there, which would pass without proving anything.
    ///
    /// - Returns: the destination *container*, not its context. Returning the context alone
    ///   lets the container deallocate at function exit, which tears down the in-memory
    ///   store out from under it and traps inside SwiftData on the next fetch. Callers must
    ///   hold this container for as long as they use its context.
    private func roundTrip(from source: ModelContainer) async throws -> ModelContainer {
        let data = try await DataBackupService.shared.exportBackup(modelContext: source.mainContext)

        let destination = try makeContainer()
        try await DataBackupService.shared.importBackup(
            data: data,
            modelContext: destination.mainContext,
            strategy: .replace
        )
        return destination
    }

    // Fixed whole-second timestamps: the backup encodes dates as ISO-8601, which has
    // one-second resolution, so a `Date()` here would fail to compare equal after a trip
    // through JSON for reasons that have nothing to do with schema drift.
    private static let createdDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let purchaseDate = Date(timeIntervalSince1970: 1_699_000_000)

    // MARK: - Fixtures

    /// A `ProductPair` with **every** stored property set to a distinct, non-default value.
    ///
    /// Non-default matters: a field the DTO silently drops must differ from what a freshly
    /// initialised object would hold anyway, or the assertion passes on a coincidence.
    /// That is why `verified` is `true`, the OCR confidences are non-zero, and `quantity`
    /// is 3 rather than the default 1.
    ///
    /// The image UUIDs are deliberately populated with sentinel strings that no file on
    /// disk will ever match. `loadImageAsBase64` returns nil rather than throwing for a
    /// missing file, and import falls back to `gfImageUUID ?? productBackup.gfImageUUID`,
    /// so these round-trip exactly while touching the filesystem zero times.
    private func makeFullyPopulatedProductPair(
        id: UUID = UUID(),
        receipt: Receipt? = nil
    ) -> ProductPair {
        ProductPair(
            gfProductName: "Fixture GF Bread",
            gfPrice: Decimal(string: "7.99")!,
            gfSize: "400g",
            gfSizeValue: Decimal(string: "400")!,
            gfImageUUID: "fixture-gf-image-uuid",
            gfOCRConfidence: 0.91,
            nonGFProductName: "Fixture Regular Bread",
            nonGFPrice: Decimal(string: "3.49")!,
            nonGFSize: "675g",
            nonGFSizeValue: Decimal(string: "675")!,
            nonGFImageUUID: "fixture-nongf-image-uuid",
            nonGFOCRConfidence: 0.87,
            sizeUnit: SizeUnit.grams.rawValue,
            quantity: 3,
            id: id,
            createdDate: Self.createdDate,
            category: "Bread",
            notes: "Fixture notes for round-trip coverage",
            verified: true,
            receipt: receipt
        )
    }

    /// A `Receipt` with every stored scalar set to a distinct, non-default value.
    private func makeFullyPopulatedReceipt(
        id: UUID = UUID(),
        productPairs: [ProductPair] = []
    ) -> Receipt {
        Receipt(
            id: id,
            purchaseDate: Self.purchaseDate,
            storeName: "Fixture Grocers",
            receiptImageUUID: "fixture-receipt-image-uuid",
            totalAmount: Decimal(string: "47.83")!,
            extractedOCRText: "FIXTURE GROCERS\nGF BREAD 7.99\nBREAD 3.49",
            productPairs: productPairs
        )
    }

    // MARK: - Assertions

    /// Asserts all 19 scalar stored properties of `ProductPair` survived the round trip.
    ///
    /// The 20th stored property, the `receipt` relationship, is covered separately by
    /// `receiptProductLinkIsRebuilt` because it is reconstructed by hand on import.
    private func expectFieldsPreserved(_ restored: ProductPair, matches original: ProductPair) {
        #expect(restored.gfProductName == original.gfProductName)
        #expect(restored.gfPrice == original.gfPrice)
        #expect(restored.gfSize == original.gfSize)
        #expect(restored.gfSizeValue == original.gfSizeValue)
        #expect(restored.gfImageUUID == original.gfImageUUID)
        #expect(restored.gfOCRConfidence == original.gfOCRConfidence)

        #expect(restored.nonGFProductName == original.nonGFProductName)
        #expect(restored.nonGFPrice == original.nonGFPrice)
        #expect(restored.nonGFSize == original.nonGFSize)
        #expect(restored.nonGFSizeValue == original.nonGFSizeValue)
        #expect(restored.nonGFImageUUID == original.nonGFImageUUID)
        #expect(restored.nonGFOCRConfidence == original.nonGFOCRConfidence)

        #expect(restored.sizeUnit == original.sizeUnit)
        #expect(restored.quantity == original.quantity)

        #expect(restored.id == original.id)
        #expect(restored.createdDate == original.createdDate)
        #expect(restored.category == original.category)
        #expect(restored.notes == original.notes)
        #expect(restored.verified == original.verified)
    }

    /// Asserts all 6 stored scalars of `Receipt` survived the round trip.
    ///
    /// The 7th stored property, the `productPairs` relationship, is covered by
    /// `receiptProductLinkIsRebuilt`.
    private func expectFieldsPreserved(_ restored: Receipt, matches original: Receipt) {
        #expect(restored.id == original.id)
        #expect(restored.purchaseDate == original.purchaseDate)
        #expect(restored.storeName == original.storeName)
        #expect(restored.receiptImageUUID == original.receiptImageUUID)
        #expect(restored.totalAmount == original.totalAmount)
        #expect(restored.extractedOCRText == original.extractedOCRText)
    }

    /// The stored-property names of a `@Model` type, via reflection.
    ///
    /// The `@Model` macro rewrites stored properties into underscore-prefixed members and
    /// adds two synthetic ones, `_$backingData` and `_$observationRegistrar`. Dropping the
    /// `_$` members and the leading underscore leaves the declared property names.
    ///
    /// If a future Swift or SwiftData release changes that expansion, the schema tests
    /// below fail loudly with the names they actually saw — noisy, but never silent.
    private func storedPropertyNames(of subject: Any) -> Set<String> {
        Set(
            Mirror(reflecting: subject).children
                .compactMap(\.label)
                .filter { !$0.hasPrefix("_$") }
                .map { String($0.dropFirst()) }
        )
    }

    // MARK: - Schema canaries
    //
    // The round-trip tests below only catch a dropped field once someone populates it in
    // the fixture. These two catch it the moment the property is declared, which is the
    // point at which the mistake is actually made.

    @Test("ProductPair has no stored property the backup DTO is unaware of")
    func productPairSchemaIsAccountedFor() {
        // Every one of these is carried by `DataBackupService.ProductPairBackup` and
        // asserted in `expectFieldsPreserved`, except `receipt`, which is a relationship
        // denormalised to `receiptID` and covered by `receiptProductLinkIsRebuilt`.
        //
        // If this fails you added, removed or renamed a property on ProductPair. Carry it
        // through all three sites in DataBackupService.swift — the DTO, `exportBackup` and
        // `importBackup` — then populate it in `makeFullyPopulatedProductPair`, assert it
        // in `expectFieldsPreserved`, and add it here. Skipping the DataBackupService half
        // is exactly the b7216c9 bug.
        let accountedFor: Set<String> = [
            "gfProductName", "gfPrice", "gfSize", "gfSizeValue", "gfImageUUID", "gfOCRConfidence",
            "nonGFProductName", "nonGFPrice", "nonGFSize", "nonGFSizeValue", "nonGFImageUUID",
            "nonGFOCRConfidence",
            "sizeUnit", "quantity",
            "id", "createdDate", "category", "notes", "verified", "receipt"
        ]

        expectSchemaMatches(makeFullyPopulatedProductPair(), accountedFor)
    }

    @Test("Receipt has no stored property the backup DTO is unaware of")
    func receiptSchemaIsAccountedFor() {
        // As above, but for `ReceiptBackup`. `productPairs` is the relationship,
        // denormalised to `productPairIDs` on export.
        let accountedFor: Set<String> = [
            "id", "purchaseDate", "storeName", "receiptImageUUID",
            "totalAmount", "extractedOCRText", "productPairs"
        ]

        expectSchemaMatches(makeFullyPopulatedReceipt(), accountedFor)
    }

    /// Compares a model's stored properties against the list checked in above, reporting
    /// only the difference.
    ///
    /// A plain `#expect(a == b)` on two sets dumps both in full on failure — twenty-odd
    /// unordered names to eyeball. The symmetric difference is the one thing you need:
    /// the property you just added, removed, or renamed.
    private func expectSchemaMatches(
        _ subject: Any,
        _ accountedFor: Set<String>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let unaccounted = storedPropertyNames(of: subject).symmetricDifference(accountedFor)
        #expect(
            unaccounted.isEmpty,
            "Stored properties not accounted for in the backup DTO: \(unaccounted.sorted())",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Round-trip tests

    @Test("Every ProductPair field survives export then import")
    func productPairSurvivesRoundTrip() async throws {
        let source = try makeContainer()
        let original = makeFullyPopulatedProductPair()
        source.mainContext.insert(original)
        try source.mainContext.save()

        let destination = try await roundTrip(from: source)
        let restoredPairs = try destination.mainContext.fetch(FetchDescriptor<ProductPair>())

        #expect(restoredPairs.count == 1)
        let restored = try #require(restoredPairs.first)
        expectFieldsPreserved(restored, matches: original)

        // These two are derived, not stored, so they can only survive if the size fields
        // did — this is the reporting value b7216c9 was losing. They are asserted in
        // addition to the raw fields above because they cover different subsets:
        // `normalizedDifferential` depends on the two size *values* only, while
        // `hasUnitPricingData` also requires `sizeUnit`.
        #expect(restored.normalizedDifferential == original.normalizedDifferential)
        #expect(restored.normalizedDifferential != nil)
        #expect(restored.hasUnitPricingData)

        // The reported figure is the extended one, so prove it survives too — a dropped
        // `quantity` would leave `normalizedDifferential` intact and only show up here.
        #expect(restored.extendedNormalizedDifferential == original.extendedNormalizedDifferential)
        #expect(restored.extendedDifferential == original.extendedDifferential)
    }

    @Test("Every Receipt field survives export then import")
    func receiptSurvivesRoundTrip() async throws {
        let source = try makeContainer()
        let original = makeFullyPopulatedReceipt()
        source.mainContext.insert(original)
        try source.mainContext.save()

        let destination = try await roundTrip(from: source)
        let restoredReceipts = try destination.mainContext.fetch(FetchDescriptor<Receipt>())

        #expect(restoredReceipts.count == 1)
        let restored = try #require(restoredReceipts.first)
        expectFieldsPreserved(restored, matches: original)
    }

    @Test("The receipt to product-pair link is rebuilt on import")
    func receiptProductLinkIsRebuilt() async throws {
        let source = try makeContainer()

        let receiptID = UUID()
        let firstPairID = UUID()
        let secondPairID = UUID()

        let receipt = makeFullyPopulatedReceipt(id: receiptID)
        let firstPair = makeFullyPopulatedProductPair(id: firstPairID, receipt: receipt)
        let secondPair = makeFullyPopulatedProductPair(id: secondPairID, receipt: receipt)

        source.mainContext.insert(receipt)
        source.mainContext.insert(firstPair)
        source.mainContext.insert(secondPair)
        try source.mainContext.save()

        let destination = try await roundTrip(from: source)

        let restoredReceipt = try #require(
            try destination.mainContext.fetch(FetchDescriptor<Receipt>()).first
        )
        let restoredPairs = try destination.mainContext.fetch(FetchDescriptor<ProductPair>())

        #expect(restoredPairs.count == 2)

        // Import reconstructs this by hand — it looks the receipt up in a local
        // `[UUID: Receipt]` map and sets both sides of the relationship. Nothing in the
        // type system checks that, so assert both directions.
        for pair in restoredPairs {
            #expect(pair.receipt?.id == receiptID)
        }

        // Both sides get written on import: the `ProductPair(receipt:)` initialiser and an
        // explicit `receipt.productPairs.append(product)`. SwiftData maintains the inverse
        // automatically, so this count catches a double-append regression.
        #expect(restoredReceipt.productPairs.count == 2)
        #expect(Set(restoredReceipt.productPairs.map(\.id)) == [firstPairID, secondPairID])
    }

    @Test("A backup written before unit pricing and quantity existed still imports")
    func legacyBackupWithoutUnitPricingStillImports() async throws {
        // Shaped like a build-7 backup: no gfSizeValue / nonGFSizeValue / sizeUnit keys,
        // and no quantity key either. Those DTO fields are optional precisely so older
        // files stay decodable, and that compatibility path had no test until now.
        //
        // Settings are left empty on purpose. `importBackup` skips empty strings and
        // unparseable enum raw values, so this fixture cannot disturb the real
        // UserDefaults-backed AppStorage that AppSettings.shared writes through.
        let legacyBackupJSON = """
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

        let destination = try makeContainer()
        let data = try #require(legacyBackupJSON.data(using: .utf8))

        try await DataBackupService.shared.importBackup(
            data: data,
            modelContext: destination.mainContext,
            strategy: .replace
        )

        let restoredPairs = try destination.mainContext.fetch(FetchDescriptor<ProductPair>())
        #expect(restoredPairs.count == 1)

        let restored = try #require(restoredPairs.first)
        #expect(restored.gfProductName == "Legacy GF Bread")
        #expect(restored.gfPrice == Decimal(string: "6.99")!)
        #expect(restored.nonGFPrice == Decimal(string: "2.99")!)
        #expect(restored.category == "Bread")

        // The absent keys must land as nil rather than failing the decode outright.
        #expect(restored.gfSizeValue == nil)
        #expect(restored.nonGFSizeValue == nil)
        #expect(restored.sizeUnit == nil)

        // A legacy record predates quantity, so it must import as a single-unit purchase —
        // anything else would silently inflate the amounts in a restored tax report.
        #expect(restored.quantity == 1)
        #expect(restored.extendedDifferential == restored.differential)

        // With no size data there is no unit price to report, which is the correct
        // degraded state for a legacy record — not the silent data loss of b7216c9.
        #expect(restored.normalizedDifferential == nil)
        #expect(restored.hasUnitPricingData == false)
    }
}
