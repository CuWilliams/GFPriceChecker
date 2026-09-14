//
//  QuantityMigrationTests.swift
//  GFPriceCheckerTests
//

import Foundation
import SwiftData
import Testing
@testable import GFPriceChecker

/// Covers SwiftData's implicit lightweight migration of `ProductPair.quantity`.
///
/// `quantity` was added in `31de668` with an inline default and deliberately no
/// `SchemaMigrationPlan` (see `ProductPair.swift:104-107`). That default is the only thing
/// backfilling the column for stores written before the property existed. Nothing else in
/// the suite can catch it breaking: every other test builds an in-memory container from the
/// current schema, which is born at the new version and never walks a migration path.
///
/// So these tests write a store under a *pre-quantity* schema, let it close, and reopen the
/// same file under the shipping schema — which is what happens on a user's phone when they
/// install an update over an existing install.
///
/// Removing the default was tried, to confirm these fail for the reason claimed. It does not
/// backfill zero, as one might assume. CoreData refuses the migration outright —
/// `NSCocoaErrorDomain 134110`, *"Validation error missing attribute values on mandatory
/// destination attribute"*, entity `ProductPair`, attribute `quantity` — and the container
/// never loads. The app turns that into `fatalError` (`GFPriceCheckerApp.swift:57`), so the
/// real consequence is a launch crash for every user who already had data, with no route to
/// it short of deleting the app. All five tests below go red on that.
///
/// - Note: On-disk by necessity. `isStoredInMemoryOnly: true` has no file to migrate and
///   would pass no matter what the model said.
@Suite("Quantity lightweight migration")
struct QuantityMigrationTests {

    // MARK: - The pre-quantity schema

    /// `ProductPair` and `Receipt` exactly as they stood at `31de668^`, before `quantity`.
    ///
    /// Nested inside a `VersionedSchema` so the entity names stay `ProductPair` and
    /// `Receipt` — SwiftData keys migration off the entity name, not the Swift type, so a
    /// legacy model called `LegacyProductPair` would read as an unrelated entity and the
    /// store would come back empty instead of migrated.
    enum PreQuantitySchema: VersionedSchema {
        static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
        static var models: [any PersistentModel.Type] { [ProductPair.self, Receipt.self] }

        @Model
        final class ProductPair {
            var gfProductName: String = ""
            var gfPrice: Decimal = 0
            var gfSize: String?
            var gfSizeValue: Decimal?
            var gfImageUUID: String?
            var gfOCRConfidence: Float = 0
            var nonGFProductName: String = ""
            var nonGFPrice: Decimal = 0
            var nonGFSize: String?
            var nonGFSizeValue: Decimal?
            var nonGFImageUUID: String?
            var nonGFOCRConfidence: Float = 0
            var sizeUnit: String?
            var id: UUID = UUID()
            var createdDate: Date = Date()
            var category: String?
            var notes: String?
            var verified: Bool = false
            var receipt: Receipt?

            init(
                gfProductName: String,
                gfPrice: Decimal,
                nonGFProductName: String,
                nonGFPrice: Decimal,
                id: UUID = UUID(),
                category: String? = nil
            ) {
                self.gfProductName = gfProductName
                self.gfPrice = gfPrice
                self.nonGFProductName = nonGFProductName
                self.nonGFPrice = nonGFPrice
                self.id = id
                self.category = category
            }
        }

        @Model
        final class Receipt {
            var id: UUID = UUID()
            var purchaseDate: Date = Date()
            var storeName: String?
            var receiptImageUUID: String?
            var totalAmount: Decimal?
            var extractedOCRText: String?

            @Relationship(deleteRule: .nullify, inverse: \ProductPair.receipt)
            var productPairs: [ProductPair] = []

            init(id: UUID = UUID(), purchaseDate: Date = Date(), storeName: String? = nil) {
                self.id = id
                self.purchaseDate = purchaseDate
                self.storeName = storeName
            }
        }
    }

    // MARK: - Helpers

    /// A unique store URL per test, so these can run in parallel and never share a file.
    private static func makeStoreURL() -> URL {
        let dir = URL.temporaryDirectory.appending(path: "quantity-migration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "store.sqlite")
    }

    /// Writes `pairs` into a store at `url` under the pre-quantity schema, then closes it.
    ///
    /// The container is scoped to this call deliberately: it has to deallocate and release
    /// the SQLite file before the shipping schema can open the same path.
    private static func seedPreQuantityStore(
        at url: URL,
        pairs: [(gf: String, gfPrice: Decimal, reg: String, regPrice: Decimal, id: UUID)]
    ) throws {
        let schema = Schema(versionedSchema: PreQuantitySchema.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        let context = ModelContext(container)
        for p in pairs {
            context.insert(
                PreQuantitySchema.ProductPair(
                    gfProductName: p.gf,
                    gfPrice: p.gfPrice,
                    nonGFProductName: p.reg,
                    nonGFPrice: p.regPrice,
                    id: p.id
                )
            )
        }
        try context.save()
    }

    /// Opens `url` under the schema the app actually ships.
    private static func openShippingStore(at url: URL) throws -> ModelContainer {
        let schema = Schema([GFPriceChecker.ProductPair.self, GFPriceChecker.Receipt.self])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }

    // MARK: - Tests

    @Test("A store written before quantity existed still opens")
    func preQuantityStoreOpens() throws {
        let url = Self.makeStoreURL()
        try Self.seedPreQuantityStore(at: url, pairs: [
            (gf: "GF Bread", gfPrice: 7.99, reg: "Wheat Bread", regPrice: 3.49, id: UUID())
        ])

        // This is the one that actually fires when the default goes missing: the container
        // throws loadIssueModelContainer and the app dies at launch. The three below assume
        // a store that opened, so they can only speak once this one holds.
        let container = try Self.openShippingStore(at: url)
        let pairs = try ModelContext(container).fetch(FetchDescriptor<ProductPair>())

        #expect(pairs.count == 1, "The pre-quantity row should survive migration, not be dropped")
    }

    @Test("quantity backfills to 1 rather than 0")
    func quantityBackfillsToOne() throws {
        let url = Self.makeStoreURL()
        let id = UUID()
        try Self.seedPreQuantityStore(at: url, pairs: [
            (gf: "GF Pasta", gfPrice: 5.99, reg: "Regular Pasta", regPrice: 1.99, id: id)
        ])

        let container = try Self.openShippingStore(at: url)
        let context = ModelContext(container)
        let pairs = try context.fetch(FetchDescriptor<ProductPair>())
        let migrated = try #require(pairs.first { $0.id == id }, "Migrated pair not found")

        // Distinct from the test above: there the store will not open, here it opens and
        // lies. A silently wrong value is the worse of the two for a tax deduction, because
        // nothing announces it — every extended differential on a returning user's report
        // comes out scaled by the wrong number and the total still looks plausible.
        #expect(
            migrated.quantity == 1,
            """
            quantity backfilled to \(migrated.quantity), not 1. Implicit migration is no \
            longer honouring the inline default on ProductPair.quantity, so every \
            extendedDifferential on a pre-upgrade pair is wrong — silently, and in a number \
            the user relies on at tax time.
            """
        )
    }

    @Test("Backfilled quantity makes the extended differential match the per-unit one")
    func backfilledQuantityKeepsExtendedDifferentialHonest() throws {
        let url = Self.makeStoreURL()
        let id = UUID()
        try Self.seedPreQuantityStore(at: url, pairs: [
            (gf: "GF Flour", gfPrice: 8.49, reg: "AP Flour", regPrice: 3.99, id: id)
        ])

        let container = try Self.openShippingStore(at: url)
        let context = ModelContext(container)
        let migrated = try #require(
            try context.fetch(FetchDescriptor<ProductPair>()).first { $0.id == id }
        )

        // The user-visible consequence, stated in the app's own terms: for a single-unit
        // purchase the extended figure is the per-unit figure. A quantity of 0 would make
        // this 0 while `differential` stayed 4.50.
        #expect(migrated.differential == Decimal(string: "4.50"))
        #expect(migrated.extendedDifferential == migrated.differential)
    }

    @Test("Existing field values are carried across unchanged")
    func migrationPreservesExistingFields() throws {
        let url = Self.makeStoreURL()
        let id = UUID()
        try Self.seedPreQuantityStore(at: url, pairs: [
            (gf: "GF Oats", gfPrice: 6.25, reg: "Rolled Oats", regPrice: 2.75, id: id)
        ])

        let container = try Self.openShippingStore(at: url)
        let context = ModelContext(container)
        let migrated = try #require(
            try context.fetch(FetchDescriptor<ProductPair>()).first { $0.id == id }
        )

        // Guards the opposite mistake from a missing backfill: a migration that resets the
        // row while happening to get quantity right.
        #expect(migrated.gfProductName == "GF Oats")
        #expect(migrated.gfPrice == Decimal(string: "6.25"))
        #expect(migrated.nonGFProductName == "Rolled Oats")
        #expect(migrated.nonGFPrice == Decimal(string: "2.75"))
    }

    @Test("Multiple pre-quantity rows all backfill")
    func everyRowBackfills() throws {
        let url = Self.makeStoreURL()
        try Self.seedPreQuantityStore(at: url, pairs: (1...5).map { i in
            (gf: "GF \(i)", gfPrice: Decimal(i) + 5, reg: "Reg \(i)", regPrice: Decimal(i), id: UUID())
        })

        let container = try Self.openShippingStore(at: url)
        let pairs = try ModelContext(container).fetch(FetchDescriptor<ProductPair>())

        #expect(pairs.count == 5)
        #expect(pairs.allSatisfy { $0.quantity == 1 }, "Backfill must reach every row, not just the first")
    }
}
