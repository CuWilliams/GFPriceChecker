//
//  AppRouterTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-10-31.
//

import Foundation
import SwiftData
import Testing
@testable import GFPriceChecker

/// Covers Stage 4's router and the DEBUG launch hook that names its screens.
///
/// What these cannot show is that a view follows the router. That was checked
/// by launching with `GFPC_DEMO_ROUTE` set to each destination and looking at
/// the screen; see `DemoRoute`.
@MainActor
@Suite("App router")
struct AppRouterTests {

    /// Holds the container alive alongside its context
    @MainActor
    struct Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
    }

    static func makeStore() throws -> Store {
        let container = try ModelContainer(
            for: ProductPair.self, Receipt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return Store(container: container)
    }

    static func pair(named name: String, created: Date) -> ProductPair {
        ProductPair(
            gfProductName: "GF \(name)",
            gfPrice: 6.99,
            nonGFProductName: name,
            nonGFPrice: 3.49,
            createdDate: created,
            category: "Bakery"
        )
    }

    /// A router somewhere else entirely: another tab, a pushed screen and a
    /// sheet on every tab
    static func clutteredRouter(store: Store) -> AppRouter {
        let pair = pair(named: "Bread", created: .now)
        store.context.insert(pair)

        let router = AppRouter()
        router.selectedTab = .capture
        router.libraryPath = [.product(pair)]
        router.showingCaptureFlow = true
        router.librarySheet = .manualEntry
        router.reportsSheet = .settings
        return router
    }

    // MARK: - Defaults

    @Test("Starts on the Capture tab with nothing pushed or presented")
    func startsClean() {
        let router = AppRouter()

        #expect(router.selectedTab == .capture)
        #expect(router.libraryPath.isEmpty)
        #expect(router.showingCaptureFlow == false)
        #expect(router.librarySheet == nil)
        #expect(router.reportsSheet == nil)
    }

    // MARK: - show(_:)

    @Test("Each tab destination selects the tab and clears everything else",
          arguments: AppRouter.Tab.allCases)
    func showTab(_ tab: AppRouter.Tab) throws {
        let store = try Self.makeStore()
        let router = Self.clutteredRouter(store: store)

        router.show(.tab(tab))

        #expect(router.selectedTab == tab)
        #expect(router.libraryPath.isEmpty)
        #expect(router.showingCaptureFlow == false)
        #expect(router.librarySheet == nil)
        #expect(router.reportsSheet == nil)
    }

    @Test("The capture flow opens over the Capture tab")
    func showCaptureFlow() throws {
        let store = try Self.makeStore()
        let router = Self.clutteredRouter(store: store)

        router.show(.captureFlow)

        #expect(router.selectedTab == .capture)
        #expect(router.showingCaptureFlow)
        #expect(router.librarySheet == nil)
        #expect(router.reportsSheet == nil)
        #expect(router.libraryPath.isEmpty)
    }

    @Test("A product or receipt replaces the Library stack rather than pushing onto it")
    func showLibraryScreens() throws {
        let store = try Self.makeStore()
        let router = Self.clutteredRouter(store: store)
        let pair = Self.pair(named: "Pasta", created: .now)
        let receipt = Receipt(purchaseDate: .now, storeName: "Store", totalAmount: 10)
        store.context.insert(pair)
        store.context.insert(receipt)

        router.show(.product(pair))
        #expect(router.selectedTab == .library)
        #expect(router.libraryPath == [.product(pair)])
        #expect(router.showingCaptureFlow == false)
        #expect(router.reportsSheet == nil)

        router.show(.receipt(receipt))
        #expect(router.selectedTab == .library)
        #expect(router.libraryPath == [.receipt(receipt)])
    }

    @Test("Each sheet opens on its own tab, with the other tabs' sheets dismissed")
    func showSheets() throws {
        let store = try Self.makeStore()
        let router = Self.clutteredRouter(store: store)

        router.show(.manualEntry)
        #expect(router.selectedTab == .library)
        #expect(router.librarySheet == .manualEntry)
        #expect(router.reportsSheet == nil)
        #expect(router.showingCaptureFlow == false)

        router.show(.receiptCapture)
        #expect(router.selectedTab == .library)
        #expect(router.librarySheet == .receiptCapture)

        router.show(.export)
        #expect(router.selectedTab == .reports)
        #expect(router.reportsSheet == .export)
        #expect(router.librarySheet == nil)

        router.show(.settings)
        #expect(router.selectedTab == .reports)
        #expect(router.reportsSheet == .settings)
        #expect(router.libraryPath.isEmpty)
    }

    // MARK: - DemoRoute

    @Test("Every screen name resolves to its destination")
    func namesResolve() throws {
        let store = try Self.makeStore()
        let expected: [String: AppRouter.Destination] = [
            "capture": .tab(.capture),
            "library": .tab(.library),
            "reports": .tab(.reports),
            "captureFlow": .captureFlow,
            "manualEntry": .manualEntry,
            "receiptCapture": .receiptCapture,
            "export": .export,
            "settings": .settings,
        ]

        for (name, destination) in expected {
            #expect(DemoRoute.destination(named: name, context: store.context) == destination)
        }
    }

    @Test("An unknown name resolves to nothing, so the hook can refuse it")
    func unknownNameIsNil() throws {
        let store = try Self.makeStore()

        #expect(DemoRoute.destination(named: "Export", context: store.context) == nil)
        #expect(DemoRoute.destination(named: "detail", context: store.context) == nil)
    }

    @Test("`product` and `receipt` open the newest, and nothing on an empty store")
    func modelNamesResolveToNewest() throws {
        let store = try Self.makeStore()
        #expect(DemoRoute.destination(named: "product", context: store.context) == nil)
        #expect(DemoRoute.destination(named: "receipt", context: store.context) == nil)

        let older = Self.pair(named: "Crackers", created: Date(timeIntervalSince1970: 1_750_000_000))
        let newer = Self.pair(named: "Bread", created: Date(timeIntervalSince1970: 1_760_000_000))
        let oldReceipt = Receipt(purchaseDate: Date(timeIntervalSince1970: 1_750_000_000), storeName: "A", totalAmount: 5)
        let newReceipt = Receipt(purchaseDate: Date(timeIntervalSince1970: 1_760_000_000), storeName: "B", totalAmount: 6)
        // Inserted newest first, so the sort is what picks, not insertion order
        for model in [newer, older] { store.context.insert(model) }
        for model in [newReceipt, oldReceipt] { store.context.insert(model) }
        try store.context.save()

        #expect(DemoRoute.destination(named: "product", context: store.context) == .product(newer))
        #expect(DemoRoute.destination(named: "receipt", context: store.context) == .receipt(newReceipt))
    }
}
