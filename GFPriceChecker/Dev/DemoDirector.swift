//
//  DemoDirector.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-10-31.
//

import SwiftUI
import SwiftData

#if DEBUG

/// Plays a scripted take against the app, with no hand on it.
///
/// Stage 5 of `docs/SCRIPTED_DEMO_PIPELINE.md`, and the shape of TrendFit's
/// director (`../TrendFitApp_App/Features/Dev/Demo/`). A hand-driven recording
/// jitters because a mouse is driving it. Launched with `GFPC_DEMO_SCRIPT` set
/// to one of `DemoScripts`' names, the app instead plays that script straight
/// against `AppRouter` and the view models, so every step is the same every
/// run and a UI change means re-running a command, not re-shooting a video.
///
/// ```
/// Tools/Demo/play.sh tour
/// ```
///
/// A launch goes: seed (if `GFPC_DEMO_DATASET` asks), route (if
/// `GFPC_DEMO_ROUTE` asks), then `start`, which holds the curtain, lifts it and
/// plays the script. The seed lands behind the curtain, so a take never shows
/// the store filling.
///
/// Release views carry one hook, `.demoRegistered(_:)`, whose `#else` body at
/// the bottom of this file is `self`. Nothing else here exists in a release
/// build.
@MainActor
final class DemoDirector {

    // MARK: - Launch

    /// Names the script to play. Reaches the app as `SIMCTL_CHILD_GFPC_DEMO_SCRIPT`.
    static let scriptVariable = "GFPC_DEMO_SCRIPT"

    /// Host path written when the script ends, so the shell can stop recording
    /// without guessing at a duration. Its first line is `done <script>`, or
    /// `failed <script>: <error>` when the script threw.
    static let doneFileVariable = "GFPC_DEMO_DONE_FILE"

    /// Host path whose presence puts a run in stills mode. `still()` writes it
    /// at the frame a still is cut from and then holds the screen there. Absent,
    /// which is every video take, `still()` does nothing and the script plays
    /// on, so a still and its take are one script and cannot drift apart.
    static let stillFileVariable = "GFPC_DEMO_STILL_FILE"

    /// Which `still(_:)` mark a stills run stops at. Unset means `tileMark`.
    static let stillMarkVariable = "GFPC_DEMO_STILL_MARK"
    /// `nonisolated` because `still(_:)` takes it as a default argument, which
    /// is evaluated in the caller's isolation.
    nonisolated static let tileMark = "tile"

    /// The armed director, or `nil` on every ordinary launch.
    ///
    /// A singleton rather than an environment value because the views that
    /// register with it are sheets several levels down, and an optional in the
    /// environment would be one more thing every preview had to supply.
    private(set) static var current: DemoDirector?

    /// How long the curtain holds after any seed has landed: long enough for
    /// the recorder to settle after the launch burst, which it drops frames
    /// through. The same 1.5 s the release launch screen holds.
    static let curtainSeconds: Double = 1.5

    /// The curtain's fade, which the script waits out before its first step.
    /// The release launch screen's fade.
    static let curtainFadeSeconds: Double = 0.6

    let scriptName: String
    private let doneFilePath: String?
    private let stillFilePath: String?
    private let stillMark: String
    private let stillHoldSeconds: Double

    /// - Parameter stillHoldSeconds: how long `still()` holds once it has
    ///   written the still file. Long enough to outlast any screenshot, short
    ///   enough that a shell that died mid-run leaves nothing going for long.
    ///   Tests pass 0.
    init(scriptName: String, doneFilePath: String?, stillFilePath: String?,
         stillMark: String?, stillHoldSeconds: Double = 600) {
        self.scriptName = scriptName
        self.doneFilePath = doneFilePath
        self.stillFilePath = stillFilePath
        self.stillMark = stillMark.flatMap { $0.isEmpty ? nil : $0 } ?? Self.tileMark
        self.stillHoldSeconds = stillHoldSeconds
    }

    /// Arms the director when the environment names a script. Called from
    /// `GFPriceCheckerApp.init()`, before the first body, so the root can show
    /// the flat curtain rather than the launch screen from the first frame.
    ///
    /// An unknown name is fatal, as an unknown `GFPC_DEMO_ROUTE` is: a run that
    /// plays nothing still produces a recording.
    static func bootstrapIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let name = env[scriptVariable], !name.isEmpty else { return }

        guard DemoScripts.names.contains(name) else {
            fatalError("\(scriptVariable) is \"\(name)\", which names no script. Scripts: \(DemoScripts.names.joined(separator: ", "))")
        }

        // Onboarding is a sheet, and would arrive over the first shot. DemoSeed
        // sets this too, but a take need not seed.
        AppSettings.shared.hasCompletedOnboarding = true

        current = DemoDirector(
            scriptName: name,
            doneFilePath: env[doneFileVariable],
            stillFilePath: env[stillFileVariable],
            stillMark: env[stillMarkVariable]
        )
        print("🎬 Demo director armed for '\(name)'")
    }

    // MARK: - Running

    private(set) var router: AppRouter?
    private(set) var context: ModelContext?
    private var hasStarted = false

    /// Hands over what a script drives. Separate from `start` so a test can
    /// drive the primitives without playing a script.
    func attach(router: AppRouter, context: ModelContext) {
        self.router = router
        self.context = context
    }

    /// Holds the curtain, lifts it, plays the script, and writes the done file.
    ///
    /// Called from the App's launch task after the seed, so the hold is
    /// measured from a populated store rather than from launch.
    ///
    /// - Parameter liftCurtain: hides the curtain. The App owns that state, and
    ///   supplies the animation.
    func start(router: AppRouter, context: ModelContext, liftCurtain: () -> Void) async {
        guard !hasStarted else { return }
        hasStarted = true
        attach(router: router, context: context)

        await wait(Self.curtainSeconds)
        liftCurtain()
        await wait(Self.curtainFadeSeconds)

        do {
            try await DemoScripts.run(scriptName, on: self)
            finish(failure: nil)
        } catch {
            finish(failure: error)
        }
    }

    // MARK: - Registration (from the release hook)

    private var registered: [ObjectIdentifier: AnyObject] = [:]

    func register<VM: AnyObject>(_ viewModel: VM) {
        registered[ObjectIdentifier(VM.self)] = viewModel
    }

    // MARK: - Primitives

    enum DemoError: Error, CustomStringConvertible {
        case timedOut(String)
        case notRegistered(String)
        case noDestination(String)
        case unknownScript(String)
        case notAttached

        var description: String {
            switch self {
            case .timedOut(let what): "timed out waiting for \(what)"
            case .notRegistered(let type): "no \(type) registered"
            case .noDestination(let name): "\"\(name)\" names no screen, or a model the store does not have"
            case .unknownScript(let name): "\"\(name)\" names no script"
            case .notAttached: "the director has no router or context yet"
            }
        }
    }

    func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// How long `push` holds after changing screens, so the next step runs on a
    /// screen that has arrived. A shade over the system push, which TrendFit
    /// measured at ~0.5 s; a sheet's presentation is the same order.
    static let settleSeconds: Double = 0.6

    /// Puts the app on `destination`, and returns once the transition is over.
    ///
    /// The hold is the point. A transition is where the recorder competes with
    /// the app for the host's CPU, and work started the instant it begins
    /// starves the capture into a frozen half-slid frame. Holding here means a
    /// script cannot forget to. It also gives `show(_:)` the gap it needs
    /// between dismissing one sheet and presenting another: go to a `.tab`
    /// first, and the hold is that gap.
    ///
    /// Forgets every registered view model first. `show(_:)` dismisses every
    /// sheet, and every view that registers is presented in one, so whatever
    /// was registered belongs to a screen that is going away. Without this,
    /// `screen(_:)` would hand back the last export sheet's view model rather
    /// than wait for the new one.
    func push(_ destination: AppRouter.Destination) async {
        registered.removeAll()
        router?.show(destination)
        await wait(Self.settleSeconds)
    }

    /// The destination `DemoRoute` gives `name`, so a script can say "the
    /// newest product" the way the route hook does.
    func destination(_ name: String) throws -> AppRouter.Destination {
        guard let context else { throw DemoError.notAttached }
        guard let destination = DemoRoute.destination(named: name, context: context) else {
            throw DemoError.noDestination(name)
        }
        return destination
    }

    /// Resolves once a view model of `type` has registered. Polling rather
    /// than a continuation keeps the hook a single stateless line.
    func screen<VM: AnyObject>(_ type: VM.Type, timeout: Double = 10) async throws -> VM {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let viewModel = registered[ObjectIdentifier(type)] as? VM { return viewModel }
            await wait(0.05)
        }
        throw DemoError.notRegistered(String(describing: type))
    }

    func waitUntil(_ what: String, timeout: Double = 30, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            guard Date() < deadline else { throw DemoError.timedOut(what) }
            await wait(0.05)
        }
    }

    func animate(_ animation: Animation = .easeInOut(duration: 0.6), _ body: () -> Void) {
        withAnimation(animation, body)
    }

    // MARK: - Stills and the end

    /// The frame this script's still is cut from, at `mark`.
    ///
    /// Returns at once in a video take, and at any mark the run is not stopping
    /// at. In stills mode it writes the file the shell is waiting on and then
    /// holds, because the screenshot has to land on a screen that is holding
    /// still; the shell terminates the app once it has the frame.
    func still(_ mark: String = DemoDirector.tileMark) async {
        guard let stillFilePath, mark == stillMark else { return }
        print("🎬 DEMO STILL READY: \(scriptName) at \(mark)")
        FileManager.default.createFile(atPath: stillFilePath, contents: Data(scriptName.utf8))
        await wait(stillHoldSeconds)
    }

    /// True only in a stills run stopping at `mark`, for steps that exist for
    /// that frame alone.
    func isCapturing(_ mark: String) -> Bool {
        stillFilePath != nil && mark == stillMark
    }

    /// Writes the done file. A failed script writes it too, with the error, so
    /// the shell reports the failure rather than timing out on it — a take
    /// that stopped halfway is still a recording, and would otherwise be cut
    /// and published as one.
    func finish(failure: (any Error)?) {
        let line = failure.map { "failed \(scriptName): \($0)" } ?? "done \(scriptName)"
        print("🎬 DEMO SCRIPT \(line)")
        guard let doneFilePath else { return }
        FileManager.default.createFile(atPath: doneFilePath, contents: Data((line + "\n").utf8))
    }
}

// MARK: - Release hook

extension View {
    /// Registers the screen's view model with the director, so a script can
    /// drive it once `screen(_:)` hands it over.
    func demoRegistered<VM: AnyObject>(_ viewModel: VM) -> some View {
        onAppear { DemoDirector.current?.register(viewModel) }
    }
}

#else

extension View {
    func demoRegistered<VM: AnyObject>(_ viewModel: VM) -> some View { self }
}

#endif
