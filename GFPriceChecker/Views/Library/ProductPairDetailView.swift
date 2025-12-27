//
//  ProductPairDetailView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import SwiftData

/// Displays detailed information about a product pair
///
/// Shows all product information, differential, and provides edit/delete actions.
struct ProductPairDetailView: View {

    // MARK: - Environment

    /// SwiftData model context for deleting products
    @Environment(\.modelContext) private var modelContext

    /// Dismiss action to pop view after delete
    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    /// The product pair to display
    let productPair: ProductPair

    // MARK: - State

    /// Controls the visibility of the edit sheet
    @State private var showingEditSheet = false

    /// Controls the visibility of the delete confirmation alert
    @State private var showingDeleteAlert = false

    // MARK: - Body

    var body: some View {
        List {
            // Differential Section
            differentialSection

            // Gluten-Free Product Section
            gfProductSection

            // Non-Gluten-Free Product Section
            nonGFProductSection

            // Category Section
            if let category = productPair.category {
                categorySection(category)
            }

            // Notes Section
            if let notes = productPair.notes, !notes.isEmpty {
                notesSection(notes)
            }

            // Metadata Section
            metadataSection
        }
        .navigationTitle("Product Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ManualProductEntryView(productPair: productPair)
        }
        .alert("Delete Product Pair?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteProductPair()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Sections

    /// Differential section showing price difference
    private var differentialSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Price Differential")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(formatCurrency(productPair.differential))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(differentialColor(productPair.differential))
                }

                Spacer()

                if productPair.verified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// Gluten-Free product information section
    private var gfProductSection: some View {
        Section {
            LabeledContent("Product Name", value: productPair.gfProductName)

            LabeledContent("Price", value: formatCurrency(productPair.gfPrice))

            if let size = productPair.gfSize {
                LabeledContent("Size", value: size)
            }

            if productPair.gfOCRConfidence > 0 {
                LabeledContent("OCR Confidence") {
                    HStack {
                        Text(formatPercentage(productPair.gfOCRConfidence))
                        confidenceIndicator(productPair.gfOCRConfidence)
                    }
                }
            }
        } header: {
            Label("Gluten-Free Product", systemImage: "leaf.fill")
        }
    }

    /// Non-Gluten-Free product information section
    private var nonGFProductSection: some View {
        Section {
            LabeledContent("Product Name", value: productPair.nonGFProductName)

            LabeledContent("Price", value: formatCurrency(productPair.nonGFPrice))

            if let size = productPair.nonGFSize {
                LabeledContent("Size", value: size)
            }

            if productPair.nonGFOCRConfidence > 0 {
                LabeledContent("OCR Confidence") {
                    HStack {
                        Text(formatPercentage(productPair.nonGFOCRConfidence))
                        confidenceIndicator(productPair.nonGFOCRConfidence)
                    }
                }
            }
        } header: {
            Label("Regular Product", systemImage: "shippingbox.fill")
        }
    }

    /// Category section
    private func categorySection(_ category: String) -> some View {
        Section {
            HStack {
                Text(category)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        } header: {
            Text("Category")
        }
    }

    /// Notes section
    private func notesSection(_ notes: String) -> some View {
        Section {
            Text(notes)
        } header: {
            Text("Notes")
        }
    }

    /// Metadata section showing creation date
    private var metadataSection: some View {
        Section {
            LabeledContent("Created", value: productPair.createdDate.formatted(date: .abbreviated, time: .shortened))
        } header: {
            Text("Metadata")
        }
    }

    // MARK: - Helper Views

    /// OCR confidence indicator
    private func confidenceIndicator(_ confidence: Float) -> some View {
        Group {
            if confidence > 0.85 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if confidence > 0.6 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }

    // MARK: - Formatting Helpers

    /// Formats a Decimal as currency
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    /// Formats a Float as percentage
    private func formatPercentage(_ value: Float) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }

    /// Returns appropriate color for the differential amount
    private func differentialColor(_ amount: Decimal) -> Color {
        if amount > 0 {
            return .green
        } else {
            return .red
        }
    }

    // MARK: - Actions

    /// Deletes the product pair from SwiftData
    private func deleteProductPair() {
        modelContext.delete(productPair)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProductPairDetailView(
            productPair: ProductPair(
                gfProductName: "Udi's Gluten Free Bread",
                gfPrice: Decimal(string: "6.99")!,
                gfSize: "450g",
                gfOCRConfidence: 0.92,
                nonGFProductName: "Wonder Bread",
                nonGFPrice: Decimal(string: "3.49")!,
                nonGFSize: "450g",
                nonGFOCRConfidence: 0.95,
                category: "Bread",
                notes: "Regular weekly purchase at Loblaws",
                verified: true
            )
        )
    }
    .modelContainer(for: ProductPair.self, inMemory: true)
}
