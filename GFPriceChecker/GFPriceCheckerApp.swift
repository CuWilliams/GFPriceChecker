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

    /// Controls whether the onboarding view is presented
    @State private var showOnboarding = false

    /// Which tab, Library screen and sheet the app is on
    @State private var router = AppRouter()

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
                    .sheet(isPresented: $showOnboarding) {
                        OnboardingView(isPresented: $showOnboarding)
                    }
                    .onAppear {
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
                                    showOnboarding = true
                                }
                            }
                        }
                    }

                // Launch screen overlay
                if showLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            #if DEBUG
            // Stages 2 and 4 of the scripted demo pipeline: seed the store
            // from a scrubbed dataset, then open a named screen, each only
            // when the environment asks. See Dev/DemoSeed.swift, Dev/DemoRoute.swift.
            .task {
                await DemoSeed.seedIfRequested(container: sharedModelContainer)
                DemoRoute.applyIfRequested(router: router, context: sharedModelContainer.mainContext)
            }
            #endif
        }
        .modelContainer(sharedModelContainer)
    }
}
