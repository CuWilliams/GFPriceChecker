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

    // MARK: - Body

    var body: some View {
        TabView {
            // Capture Tab - Future: ProductCaptureFlowView
            Text("Capture")
                .tabItem {
                    Label("Capture", systemImage: "camera")
                }

            // Library Tab - Future: ProductPairListView
            Text("Library")
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            // Reports Tab - Future: SummaryDashboardView
            Text("Reports")
                .tabItem {
                    Label("Reports", systemImage: "chart.bar")
                }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: [ProductPair.self, Receipt.self], inMemory: true)
}
