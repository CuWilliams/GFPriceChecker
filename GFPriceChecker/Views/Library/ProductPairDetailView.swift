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

    /// Controls the visibility of the image viewer
    @State private var showingImageViewer = false

    /// The image currently selected for full-screen viewing
    @State private var selectedImage: UIImage?

    /// Selected image title for viewer
    @State private var selectedImageTitle: String = ""

    /// Trigger for image selection (increments to trigger onChange)
    @State private var imageSelectionTrigger = 0

    /// Gluten-free product image loaded from storage
    @State private var gfProductImage: UIImage?

    /// Non-gluten-free product image loaded from storage
    @State private var nonGFProductImage: UIImage?

    /// Loading state for images
    @State private var isLoadingImages = false

    // MARK: - Body

    var body: some View {
        List {
            // Differential Section
            differentialSection

            // Unit Pricing Section (only shown when size data is available)
            if productPair.hasUnitPricingData {
                unitPricingSection
            }

            // Product Images Section
            productImagesSection

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
        .sheet(isPresented: $showingImageViewer) {
            if let image = selectedImage {
                ImageViewer(image: image, title: selectedImageTitle)
            }
        }
        .onChange(of: imageSelectionTrigger) { oldValue, newValue in
            // When trigger changes, present the sheet after state updates complete
            if newValue > 0 {
                showingImageViewer = true
            }
        }
        .task {
            await loadProductImages()
        }
    }

    // MARK: - Sections

    /// Differential section showing price difference
    private var differentialSection: some View {
        Section {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let normDiff = productPair.normalizedDifferential {
                        // Unit Price Differential — value of record (primary)
                        Text("Unit Price Differential")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(formatCurrency(normDiff))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(normDiff >= 0 ? .green : .red)

                        // Package Price Differential — reference only (secondary)
                        Text("Package Price Differential")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)

                        Text(formatCurrency(productPair.differential))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    } else {
                        // No unit data — show package diff as primary
                        Text("Package Price Differential")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(formatCurrency(productPair.differential))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(differentialColor(productPair.differential))
                    }
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

    /// Unit pricing section showing size-adjusted cost analysis
    private var unitPricingSection: some View {
        Section {
            if let unit = productPair.resolvedSizeUnit {
                if let gfSize = productPair.gfSizeValue {
                    LabeledContent("GF Size", value: "\(gfSize) \(unit.displayName)")
                }

                if let regSize = productPair.nonGFSizeValue {
                    LabeledContent("Regular Size", value: "\(regSize) \(unit.displayName)")
                }

                if let gfUnit = productPair.gfUnitPrice {
                    LabeledContent("GF Price / \(unit.displayName)", value: formatCurrency(gfUnit))
                }

                if let regUnit = productPair.regularUnitPrice {
                    LabeledContent("Regular Price / \(unit.displayName)", value: formatCurrency(regUnit))
                }
            }

        } header: {
            Label("Unit Pricing", systemImage: "scalemass")
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

    /// Product images section showing side-by-side images
    private var productImagesSection: some View {
        Section {
            if isLoadingImages {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if gfProductImage != nil || nonGFProductImage != nil {
                HStack(spacing: 16) {
                    // GF Product Image
                    productImageView(
                        image: gfProductImage,
                        title: "Gluten-Free",
                        productName: productPair.gfProductName
                    )
                    .frame(maxWidth: .infinity)

                    // Non-GF Product Image
                    productImageView(
                        image: nonGFProductImage,
                        title: "Regular",
                        productName: productPair.nonGFProductName
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
            } else {
                // No images placeholder
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Product Images")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    Spacer()
                }
            }
        } header: {
            Label("Product Images", systemImage: "photo.on.rectangle")
        }
    }

    /// Individual product image view with tap gesture
    private func productImageView(image: UIImage?, title: String, productName: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let image = image {
                Button {
                    // Set image and title first
                    selectedImage = image
                    selectedImageTitle = "\(title) - \(productName)"
                    // Increment trigger to show sheet via onChange after state updates
                    imageSelectionTrigger += 1
                } label: {
                    VStack(spacing: 4) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )

                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                            Text("Tap to expand")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Image")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
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

    /// Loads product images from storage
    private func loadProductImages() async {
        isLoadingImages = true

        // Load GF product image
        if let gfUUID = productPair.gfImageUUID {
            gfProductImage = await ImageStorageService.shared.retrieveImage(
                uuid: gfUUID,
                type: .product
            )
        }

        // Load non-GF product image
        if let nonGFUUID = productPair.nonGFImageUUID {
            nonGFProductImage = await ImageStorageService.shared.retrieveImage(
                uuid: nonGFUUID,
                type: .product
            )
        }

        isLoadingImages = false
    }
}

#if DEBUG
// MARK: - Preview

#Preview {
    NavigationStack {
        ProductPairDetailView(productPair: .sample)
    }
    .modelContainer(for: ProductPair.self, inMemory: true)
}
#endif
