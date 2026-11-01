//
//  GFPriceCheckerApp.swift
//  GFPriceChecker
//
//  Created by Curtis Williams on 2025-12-27.
//

import SwiftUI
import SwiftData

/// Main app entry point for GFPriceChecker
///
/// Configures the SwiftData model container for persistence of ProductPair and Receipt data.
/// The model container is automatically injected into the environment and accessible
/// throughout the app via @Environment(\.modelContext).
@main
struct GFPriceCheckerApp: App {

    // MARK: - State

    /// Controls whether the launch screen is displayed
    @State private var showLaunchScreen = true

    /// Which tab, Library screen and sheet the app is on, onboarding included
    @State private var router = AppRouter()

    // MARK: - Init

    init() {
        #if DEBUG
        // GFPC_DEMO_SCRIPT=<name>: the scripted demo takes (Dev/DemoDirector.swift).
        // Armed before the first body, so the curtain is up from the first frame.
        DemoDirector.bootstrapIfRequested()
        #endif
    }

    // MARK: - SwiftData Container Configuration

    /// Shared model container for the entire app
    ///
    /// This container manages persistence for:
    /// - ProductPair: Gluten-free vs regular product comparisons
    /// - Receipt: Purchase receipts that verify product pairs
    ///
    /// The container uses the default configuration with:
    /// - Local storage in app's application support directory
    /// - Automatic schema migration
    /// - iCloud sync disabled (local-only for privacy)
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ProductPair.self,
            Receipt.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            // Fatal error is acceptable here as the app cannot function without data persistence
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - App Scene

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app content
                ContentView()
                    .environment(router)
                    .sheet(isPresented: $router.showingOnboarding) {
                        OnboardingView(isPresented: $router.showingOnboarding)
                    }
                    .onAppear {
                        #if DEBUG
                        // A scripted take lifts its own curtain, once any seed has landed
                        if DemoDirector.current != nil { return }
                        #endif

                        // Dismiss launch screen after delay with smooth transition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.6)) {
                                showLaunchScreen = false
                            }
                        }
                    }
                    .onChange(of: showLaunchScreen) { oldValue, newValue in
                        // Only check for onboarding after launch screen is dismissed
                        if !newValue {
                            // Small delay to ensure smooth transition
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if !AppSettings.shared.hasCompletedOnboarding {
                                    router.showingOnboarding = true
                                }
                            }
                        }
                    }

                // Launch screen overlay
                if showLaunchScreen {
                    launchOverlay
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            #if DEBUG
            // Stages 2, 4 and 5 of the scripted demo pipeline: seed the store
            // from a scrubbed dataset, open a named screen, then play a script,
            // each only when the environment asks. See Dev/DemoSeed.swift,
            // Dev/DemoRoute.swift and Dev/DemoDirector.swift.
            .task {
                await DemoSeed.seedIfRequested(container: sharedModelContainer)
                DemoRoute.applyIfRequested(router: router, context: sharedModelContainer.mainContext)
                await DemoDirector.current?.start(router: router, context: sharedModelContainer.mainContext) {
                    withAnimation(.easeOut(duration: DemoDirector.curtainFadeSeconds)) {
                        showLaunchScreen = false
                    }
                }
            }
            #endif
        }
        .modelContainer(sharedModelContainer)
    }

    /// The launch screen, or in a scripted take the flat curtain that stands in
    /// for it (see `DemoCurtainView` for why it has to be flat)
    @ViewBuilder
    private var launchOverlay: some View {
        #if DEBUG
        if DemoDirector.current != nil {
            DemoCurtainView()
        } else {
            LaunchScreenView()
        }
        #else
        LaunchScreenView()
        #endif
    }
}
