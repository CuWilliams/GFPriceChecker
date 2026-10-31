//
//  DemoScripts.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-10-31.
//

#if DEBUG
import Foundation

/// The scripts `DemoDirector` plays, one per take. The timings are the
/// storyboard: retiming a take is an edit here and a rebuild, never a re-shoot.
///
/// Stage 5 carries one, `tour`, which exists to prove the mechanism end to end.
/// Stage 6 writes the storyboards for the website's three videos.
@MainActor
enum DemoScripts {

    /// Every script `run` knows, which is what `GFPC_DEMO_SCRIPT` is checked
    /// against. `nonisolated` so a parameterized test can take it as arguments.
    nonisolated static let names = ["tour"]

    static func run(_ name: String, on d: DemoDirector) async throws {
        switch name {
        case "tour": try await tour(d)
        default: throw DemoDirector.DemoError.unknownScript(name)
        }
    }

    // MARK: - tour

    /// Each tab in turn, a product, and the export sheet driven through its
    /// view model. Touches every primitive a real storyboard will use: `push`
    /// to a tab, a pushed screen and a sheet, `screen(_:)` on a registered
    /// view model, an animated write to it, and a `still()`.
    ///
    /// Wants a seeded store, for the product and for a Reports tab with
    /// something on it.
    private static func tour(_ d: DemoDirector) async throws {
        // The Capture tab, as the app opens
        await d.wait(1.0)

        await d.push(.tab(.library))
        await d.wait(1.5)

        await d.push(try d.destination("product"))
        await d.wait(2.0)

        await d.push(.tab(.reports))
        await d.wait(1.0)
        await d.still()

        await d.push(.export)
        let export = try await d.screen(ExportViewModel.self)
        await d.wait(1.0)
        d.animate { export.exportFormat = .pdf }
        await d.wait(1.5)

        // Back to a tab, not straight on to another sheet: see `push`.
        await d.push(.tab(.reports))
        await d.wait(1.0)
    }
}
#endif
