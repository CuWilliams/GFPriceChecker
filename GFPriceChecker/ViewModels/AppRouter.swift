//
//  AppRouter.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-10-31.
//

import Foundation
import Observation

/// Where the app is: the selected tab, the Library's navigation stack, and the
/// sheet each tab has up.
///
/// Stage 4 of `docs/SCRIPTED_DEMO_PIPELINE.md`. Before this, every one of those
/// was a view's private `@State`, so nothing but a tap could change screens. A
/// demo director, a test or a future deep link now writes here instead, and the
/// views follow.
///
/// Created once in `GFPriceCheckerApp` and read from the environment:
///
/// ```swift
/// @Environment(AppRouter.self) private var router
/// ```
///
/// Each tab keeps its own sheet slot rather than sharing one. A shared slot
/// would be bound by three `.sheet(item:)` modifiers at once, one per tab, and
/// a tab that is not on screen would still be able to clear the others' sheet.
@Observable
final class AppRouter {

    // MARK: - Types

    /// The three tabs, in the order `ContentView` shows them
    enum Tab: Hashable, CaseIterable {
        case capture
        case library
        case reports
    }

    /// A screen pushed onto the Library's navigation stack
    enum LibraryRoute: Hashable {
        case product(ProductPair)
        case receipt(Receipt)
    }

    /// Sheets the Library tab presents from its Add menu
    enum LibrarySheet: String, Identifiable {
        case manualEntry
        case receiptCapture

        var id: String { rawValue }
    }

    /// Sheets the Reports tab presents from its toolbar
    enum ReportsSheet: String, Identifiable {
        case export
        case settings

        var id: String { rawValue }
    }

    /// Every screen the router can put the app on, for `show(_:)`
    enum Destination: Hashable {
        case tab(Tab)
        case captureFlow
        case product(ProductPair)
        case receipt(Receipt)
        case manualEntry
        case receiptCapture
        case export
        case settings
        case onboarding
    }

    // MARK: - State

    var selectedTab: Tab = .capture

    /// The Library's `NavigationStack` path
    var libraryPath: [LibraryRoute] = []

    /// Whether the Capture tab has the product capture flow up
    var showingCaptureFlow = false

    var librarySheet: LibrarySheet?

    var reportsSheet: ReportsSheet?

    /// Whether the onboarding sheet is up. `GFPriceCheckerApp` presents it on a
    /// first launch, and a demo script through `show(.onboarding)`.
    var showingOnboarding = false

    // MARK: - Navigation

    /// Puts the app on `destination` from wherever it is.
    ///
    /// Dismisses every sheet and empties the Library stack first, so the result
    /// does not depend on where the app was. That makes it one step, not a
    /// sequence a caller has to get right.
    ///
    /// Presenting a sheet in the same update that dismisses another can be
    /// dropped by SwiftUI. A scripted caller moving from one sheet to another
    /// should go to `.tab` first and let the dismissal settle.
    func show(_ destination: Destination) {
        showingCaptureFlow = false
        showingOnboarding = false
        librarySheet = nil
        reportsSheet = nil
        libraryPath = []

        switch destination {
        case .tab(let tab):
            selectedTab = tab
        case .captureFlow:
            selectedTab = .capture
            showingCaptureFlow = true
        case .product(let productPair):
            selectedTab = .library
            libraryPath = [.product(productPair)]
        case .receipt(let receipt):
            selectedTab = .library
            libraryPath = [.receipt(receipt)]
        case .manualEntry:
            selectedTab = .library
            librarySheet = .manualEntry
        case .receiptCapture:
            selectedTab = .library
            librarySheet = .receiptCapture
        case .export:
            selectedTab = .reports
            reportsSheet = .export
        case .settings:
            selectedTab = .reports
            reportsSheet = .settings
        case .onboarding:
            // Over the Capture tab, as on a first launch
            selectedTab = .capture
            showingOnboarding = true
        }
    }
}
