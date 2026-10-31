//
//  ContentView.swift
//  GFPriceChecker
//
//  Created by Curtis Williams on 2025-12-27.
//

import SwiftUI
import SwiftData

/// Main tab view container for the app
///
/// Provides navigation between three main sections:
/// - Capture: Scan and add new product pairs
/// - Library: View and manage saved product pairs
/// - Reports: Generate summaries and export data
struct ContentView: View {

    // MARK: - Environment

    /// SwiftData model context for database operations
    ///
    /// This context is automatically injected by the modelContainer in GFPriceCheckerApp.
    /// Use it to:
    /// - Query data: @Query(sort: \.createdDate) var products: [ProductPair]
    /// - Insert data: modelContext.insert(newProduct)
    /// - Delete data: modelContext.delete(product)
    /// - Save changes: try? modelContext.save()
    ///
    /// Example usage in a view:
    /// ```swift
    /// @Environment(\.modelContext) private var modelContext
    /// @Query var products: [ProductPair]
    ///
    /// func addProduct() {
    ///     let newProduct = ProductPair(...)
    ///     modelContext.insert(newProduct)
    /// }
    /// ```
    @Environment(\.modelContext) private var modelContext

    /// Which tab is selected, so a script can change it without a tap
    @Environment(AppRouter.self) private var router

    // MARK: - Body

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            // Capture Tab - Capture Flow Launcher
            CaptureTabView()
                .tabItem {
                    Label("Capture", systemImage: "camera")
                }
                .tag(AppRouter.Tab.capture)

            // Library Tab - Product List View
            ProductPairListView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(AppRouter.Tab.library)

            // Reports Tab - Summary Dashboard
            SummaryDashboardView()
                .tabItem {
                    Label("Reports", systemImage: "chart.bar")
                }
                .tag(AppRouter.Tab.reports)
        }
    }
}

#if DEBUG
// MARK: - Preview

#Preview {
    ContentView()
        .environment(AppRouter())
        .modelContainer(for: [ProductPair.self, Receipt.self], inMemory: true)
}
#endif
