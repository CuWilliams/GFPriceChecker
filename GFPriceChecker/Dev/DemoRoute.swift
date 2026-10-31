//
//  DemoRoute.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-10-31.
//

#if DEBUG
import Foundation
import SwiftData

/// Opens the app on a named screen when the environment asks for one.
///
/// Stage 4 of `docs/SCRIPTED_DEMO_PIPELINE.md`: the shell-side proof that
/// `AppRouter` reaches the views, and a way to get a still of any screen
/// before Stage 5's director exists.
///
/// ```
/// xcrun simctl launch booted com.cuwilliams66.GFPriceChecker \
///     --env GFPC_DEMO_ROUTE=export
/// ```
///
/// Names are `AppRouter.Destination`'s cases. `product` and `receipt` open the
/// newest of each, which on a seeded store is the same one every run.
///
/// DEBUG only, like `DemoSeed`.
@MainActor
enum DemoRoute {

    /// Set to a destination name to open that screen at launch. Reaches the
    /// app as `SIMCTL_CHILD_GFPC_DEMO_ROUTE`.
    static let routeVariable = "GFPC_DEMO_ROUTE"

    /// Applies the requested route, and does nothing when there is none.
    ///
    /// Call after `DemoSeed.seedIfRequested`, so `product` and `receipt`
    /// resolve against the seeded store rather than the one it replaced.
    ///
    /// An unknown name, or one naming a model the store does not have, is
    /// fatal for the same reason a failed seed is: a still taken of the wrong
    /// screen looks like a still.
    static func applyIfRequested(router: AppRouter, context: ModelContext) {
        guard let name = ProcessInfo.processInfo.environment[routeVariable],
              !name.isEmpty else {
            return
        }

        guard let destination = destination(named: name, context: context) else {
            fatalError("\(routeVariable) is \"\(name)\", which names no screen, or a product or receipt the store does not have")
        }

        // Onboarding is a sheet too, and would arrive over the routed screen.
        AppSettings.shared.hasCompletedOnboarding = true

        router.show(destination)
    }

    /// The destination `name` refers to, or `nil` when it refers to none.
    static func destination(named name: String, context: ModelContext) -> AppRouter.Destination? {
        switch name {
        case "capture": return .tab(.capture)
        case "library": return .tab(.library)
        case "reports": return .tab(.reports)
        case "captureFlow": return .captureFlow
        case "manualEntry": return .manualEntry
        case "receiptCapture": return .receiptCapture
        case "export": return .export
        case "settings": return .settings
        case "product":
            // The Library's own order, so this is the top row
            var descriptor = FetchDescriptor<ProductPair>(
                sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first.map { .product($0) }
        case "receipt":
            var descriptor = FetchDescriptor<Receipt>(
                sortBy: [SortDescriptor(\.purchaseDate, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first.map { .receipt($0) }
        default:
            return nil
        }
    }
}
#endif
