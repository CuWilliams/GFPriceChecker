//
//  ProductPairListView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import SwiftData

/// Displays a list of all saved product pairs from SwiftData
///
/// This view is the main "Library" tab showing all product comparisons.
/// Users can see their saved product pairs, verification status, and price differentials.
struct ProductPairListView: View {

    // MARK: - Environment

    /// SwiftData model context for database operations
    @Environment(\.modelContext) private var modelContext

    // MARK: - Query

    /// All product pairs sorted by creation date (newest first)
    ///
    /// SwiftData's @Query automatically updates the view when data changes.
    /// The sort descriptor ensures users see their most recent entries first.
    @Query(sort: \ProductPair.createdDate, order: .reverse)
    private var productPairs: [ProductPair]

    // MARK: - State

    /// Controls the visibility of the manual entry sheet
    @State private var showingManualEntry = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if productPairs.isEmpty {
                    emptyStateView
                } else {
                    productListView
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingManualEntry = true
                    } label: {
                        Label("Add Product", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualProductEntryView()
            }
        }
    }

    // MARK: - Empty State

    /// View shown when no product pairs exist
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Products Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Start by adding your first product pair in the Capture tab")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Product List

    /// List of all product pairs
    private var productListView: some View {
        List {
            ForEach(productPairs) { productPair in
                ProductPairRow(productPair: productPair)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Product Pair Row

/// Individual row displaying a product pair
///
/// Shows the GF product name, price differential, category, and verification status.
struct ProductPairRow: View {

    // MARK: - Properties

    let productPair: ProductPair

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                // GF Product Name
                Text(productPair.gfProductName)
                    .font(.headline)

                // Non-GF Product Name (secondary)
                Text("vs \(productPair.nonGFProductName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Category Badge
                if let category = productPair.category {
                    categoryBadge(category)
                        .padding(.top, 4)
                }
            }

            Spacer()

            // Right side: Differential and Status
            VStack(alignment: .trailing, spacing: 4) {
                // Price Differential
                Text(formatCurrency(productPair.differential))
                    .font(.headline)
                    .foregroundStyle(differentialColor(productPair.differential))

                // Verification Status
                if productPair.verified {
                    Label("Verified", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper Views

    /// Category badge with rounded background
    private func categoryBadge(_ category: String) -> some View {
        Text(category)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.15))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }

    // MARK: - Formatting Helpers

    /// Formats a Decimal as currency
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    /// Returns appropriate color for the differential amount
    ///
    /// - Positive differential: green (GF costs more, as expected)
    /// - Zero or negative: red (unusual case)
    private func differentialColor(_ amount: Decimal) -> Color {
        if amount > 0 {
            return .green
        } else {
            return .red
        }
    }
}

// MARK: - Preview

#Preview("With Products") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: ProductPair.self,
        configurations: config
    )

    // Add sample data
    let product1 = ProductPair(
        gfProductName: "Udi's Gluten Free Bread",
        gfPrice: Decimal(string: "6.99")!,
        gfSize: "450g",
        nonGFProductName: "Wonder Bread",
        nonGFPrice: Decimal(string: "3.49")!,
        nonGFSize: "450g",
        category: "Bread",
        verified: true
    )

    let product2 = ProductPair(
        gfProductName: "Barilla GF Pasta",
        gfPrice: Decimal(string: "5.49")!,
        gfSize: "340g",
        nonGFProductName: "Barilla Pasta",
        nonGFPrice: Decimal(string: "2.29")!,
        nonGFSize: "454g",
        category: "Pasta",
        verified: false
    )

    let product3 = ProductPair(
        gfProductName: "Glutino Crackers",
        gfPrice: Decimal(string: "4.99")!,
        nonGFProductName: "Ritz Crackers",
        nonGFPrice: Decimal(string: "3.29")!,
        category: "Crackers",
        verified: true
    )

    container.mainContext.insert(product1)
    container.mainContext.insert(product2)
    container.mainContext.insert(product3)

    return ProductPairListView()
        .modelContainer(container)
}

#Preview("Empty State") {
    ProductPairListView()
        .modelContainer(for: ProductPair.self, inMemory: true)
}
