//
//  DemoSeed.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-09-14.
//

#if DEBUG
import Foundation
import SwiftData

/// Replaces the store's contents with a demo dataset named by the environment.
///
/// Stage 2 of `docs/SCRIPTED_DEMO_PIPELINE.md`. A scripted take has to start
/// from a library it can predict — the same products, the same receipts, the
/// same totals on screen every run — and the app already knows how to build
/// one: `DataBackupService.importBackup(strategy: .replace)` wipes and reloads
/// in a single call. This is the seam that lets a shell script ask for it.
///
/// The dataset is produced by `Tools/Demo/scrub_backup.py` from a backup
/// exported off a real device. **Never point this at the raw export.** That
/// file carries a SIN and a photograph of every receipt scanned; the scrub is
/// what makes it publishable, and the script verifies its own output.
///
/// One command, from the repo root:
///
/// ```
/// Tools/Demo/seed.sh ~/GFPCDemoData/demo-dataset.json
/// ```
///
/// DEBUG only. In a release build this file does not exist, so neither does
/// any path that reads a JSON file off disk and overwrites the user's library.
@MainActor
enum DemoSeed {

    /// Set to a host path to seed at launch. Reaches the app as
    /// `SIMCTL_CHILD_GFPC_DEMO_DATASET`, which is how `simctl launch` passes
    /// environment through to the process it starts.
    static let datasetVariable = "GFPC_DEMO_DATASET"

    /// The dataset this launch was asked to seed, if any.
    static var requestedDataset: URL? {
        guard let path = ProcessInfo.processInfo.environment[datasetVariable],
              !path.isEmpty else {
            return nil
        }
        // Simulator processes read host paths directly, so the dataset never
        // needs copying into the container.
        //
        // Taken as given, with no tilde expansion. `~` inside a Simulator
        // process is the app's own container, not the Mac's home, so expanding
        // it here would resolve to a path that cannot exist and report the
        // wrong one when it fails. `seed.sh` expands it on the host, where it
        // means what the caller meant.
        return URL(fileURLWithPath: path)
    }

    /// Seeds the store when the environment asks for it, and does nothing at
    /// all when it does not — which is every ordinary DEBUG launch.
    ///
    /// Failures are fatal rather than logged. A take recorded against a store
    /// that half-seeded looks like a take, and the wrong numbers on screen are
    /// not obvious until somebody watches the finished video.
    static func seedIfRequested(container: ModelContainer) async {
        guard let dataset = requestedDataset else { return }

        // Before the import, not after. Not carried in `SettingsBackup`, and the
        // App decides whether to present onboarding about a second and a half
        // into the launch — sooner than a dataset with images finishes loading.
        AppSettings.shared.hasCompletedOnboarding = true

        do {
            let data = try Data(contentsOf: dataset)

            // `.replace` calls `clearAllData` itself, which deletes the stored
            // images along with the objects. One call is the whole wipe.
            try await DataBackupService.shared.importBackup(
                data: data,
                modelContext: container.mainContext,
                strategy: .replace
            )

            print("🌱 Seeded from \(dataset.path)")
        } catch {
            fatalError("""
                \(datasetVariable) is \(dataset.path) but seeding failed: \(error)
                The path must be absolute and on the host: a leading ~ resolves
                to this app's Simulator container, not to the Mac's home.
                """)
        }
    }
}
#endif
