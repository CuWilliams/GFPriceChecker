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

    /// Controls the visibility of the receipt capture sheet
    @State private var showingReceiptCapture = false

    /// Current filter selection
    @State private var filterSelection: ProductFilter = .all

    // MARK: - Computed Properties

    /// Filtered product pairs based on current selection
    private var filteredProducts: [ProductPair] {
        switch filterSelection {
        case .all:
            return productPairs
        case .verified:
            return productPairs.filter { $0.verified }
        case .unverified:
            return productPairs.filter { !$0.verified }
        case .missingSizeData:
            return productPairs.filter { !$0.hasUnitPricingData }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if productPairs.isEmpty {
                    emptyStateView
                } else if filteredProducts.isEmpty {
                    filteredEmptyStateView
                } else {
                    productListView
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filterSelection) {
                            ForEach(ProductFilter.allCases, id: \.self) { filter in
                                Label(filter.title, systemImage: filter.icon)
                                    .tag(filter)
                            }
                        }
                    } label: {
                        Label(filterSelection.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter products")
                    .accessibilityHint("Current filter: \(filterSelection.title)")
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingManualEntry = true
                        } label: {
                            Label("Manual Entry", systemImage: "square.and.pencil")
                        }
                        .accessibilityLabel("Add product manually")
                        .accessibilityHint("Opens form to enter product information")

                        Button {
                            showingReceiptCapture = true
                        } label: {
                            Label("Verify with Receipt", systemImage: "doc.text.viewfinder")
                        }
                        .accessibilityLabel("Verify with receipt")
                        .accessibilityHint("Scan a receipt to verify products")
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .accessibilityLabel("Add product")
                    .accessibilityHint("Choose how to add a new product")
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualProductEntryView()
            }
            .sheet(isPresented: $showingReceiptCapture) {
                ReceiptCaptureView()
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
                .accessibilityHidden(true) // Decorative image

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No products yet")
        .accessibilityHint("Start by adding your first product pair in the Capture tab")
    }

    /// View shown when filter results in no products
    private var filteredEmptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: filterSelection.icon)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true) // Decorative image

            Text("No \(filterSelection.title)")
                .font(.title2)
                .fontWeight(.semibold)

            Text(filterSelection.emptyMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No \(filterSelection.title.lowercased())")
        .accessibilityHint(filterSelection.emptyMessage)
    }

    // MARK: - Product List

    /// List of all product pairs
    private var productListView: some View {
        List {
            ForEach(filteredProducts) { productPair in
                NavigationLink(destination: ProductPairDetailView(productPair: productPair)) {
                    ProductPairRow(productPair: productPair)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Show receipt link for verified products
                    if productPair.verified, let receipt = productPair.receipt {
                        NavigationLink(destination: ReceiptDetailView(receipt: receipt)) {
                            Label("Receipt", systemImage: "doc.text")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Product Filter Enum

/// Filter options for product list
enum ProductFilter: String, CaseIterable {
    case all = "All Products"
    case verified = "Verified Products"
    case unverified = "Unverified Products"
    case missingSizeData = "Missing Size Data"

    var title: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .all:
            return "list.bullet"
        case .verified:
            return "checkmark.circle.fill"
        case .unverified:
            return "exclamationmark.circle"
        case .missingSizeData:
            return "ruler"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all:
            return "No products found"
        case .verified:
            return "No verified products yet. Scan a receipt to verify your products."
        case .unverified:
            return "All products are verified! Great job."
        case .missingSizeData:
            return "All products have size data entered."
        }
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
                if let unitDiff = productPair.normalizedDifferential {
                    // Unit Price Differential (primary)
                    Text(formatCurrency(unitDiff))
                        .font(.headline)
                        .foregroundStyle(differentialColor(unitDiff))

                    // Package Price Differential (secondary)
                    Text(formatCurrency(productPair.differential))
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    // Package Price Differential (primary, no unit data available)
                    Text(formatCurrency(productPair.differential))
                        .font(.headline)
                        .foregroundStyle(differentialColor(productPair.differential))
                }

                // Verification Status
                if productPair.verified {
                    HStack(spacing: 4) {
                        Label("Verified", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        // Receipt indicator
                        if productPair.receipt != nil {
                            Image(systemName: "doc.text.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap to view details")
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Accessibility

    /// VoiceOver label for the product row
    private var accessibilityLabel: String {
        let categoryText = productPair.category != nil ? ", \(productPair.category!)" : ""
        return "\(productPair.gfProductName) compared to \(productPair.nonGFProductName)\(categoryText)"
    }

    /// VoiceOver value for the product row (dynamic info)
    private var accessibilityValue: String {
        let verifiedStatus = productPair.verified ? "Verified" : "Not verified"
        let receiptStatus = productPair.receipt != nil ? ", has receipt" : ""
        if let unitDiff = productPair.normalizedDifferential {
            return "Unit price differential \(formatCurrency(unitDiff)), package difference \(formatCurrency(productPair.differential)), \(verifiedStatus)\(receiptStatus)"
        } else {
            return "Price difference \(formatCurrency(productPair.differential)), \(verifiedStatus)\(receiptStatus)"
        }
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

#if DEBUG
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
#endif
