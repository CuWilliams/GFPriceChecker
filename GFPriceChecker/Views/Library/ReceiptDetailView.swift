//
//  ReceiptDetailView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-28.
//

import SwiftUI
import SwiftData

/// Detail view for viewing and managing a receipt
///
/// Features:
/// - Zoomable receipt image
/// - Receipt metadata (store, date, total)
/// - List of associated product pairs with differentials
/// - Summary statistics
/// - Unlink products from receipt
/// - Delete receipt with confirmation
struct ReceiptDetailView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    /// The receipt to display
    let receipt: Receipt

    // MARK: - State

    /// Whether to show the delete confirmation alert
    @State private var showingDeleteAlert = false

    /// Whether to show image viewer
    @State private var showingImageViewer = false

    /// Receipt image loaded from storage
    @State private var receiptImage: UIImage?

    /// Loading state
    @State private var isLoadingImage = false

    // MARK: - Body

    var body: some View {
        List {
            // Receipt image section
            if let image = receiptImage {
                Section {
                    receiptImageView(image)
                }
            } else if isLoadingImage {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                }
            }

            // Receipt metadata section
            Section("Receipt Information") {
                // Store name
                if let storeName = receipt.storeName {
                    LabeledContent("Store", value: storeName)
                }

                // Purchase date
                LabeledContent("Date") {
                    Text(receipt.purchaseDate.formatted(date: .long, time: .omitted))
                }

                // Total amount
                if let total = receipt.totalAmount {
                    LabeledContent("Total") {
                        Text(total, format: .currency(code: "CAD"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Summary section
            Section("Summary") {
                LabeledContent("Products Verified") {
                    Text("\(receipt.verifiedProductCount)")
                        .fontWeight(.medium)
                }

                LabeledContent("Package Price Differential Total") {
                    Text(receipt.totalDifferential, format: .currency(code: "CAD"))
                        .fontWeight(.bold)
                        .foregroundStyle(receipt.totalDifferential > 0 ? .green : .secondary)
                }
            }

            // Associated products section
            if !receipt.productPairs.isEmpty {
                Section("Verified Products") {
                    ForEach(receipt.productPairs, id: \.id) { productPair in
                        productPairRow(productPair)
                    }
                }
            }
        }
        .navigationTitle("Receipt Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .alert("Delete Receipt?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteReceipt()
            }
        } message: {
            Text("This will delete the receipt and unlink all verified products. The products themselves will not be deleted, but will be marked as unverified.")
        }
        .sheet(isPresented: $showingImageViewer) {
            if let image = receiptImage {
                ImageViewer(image: image, title: "Receipt Image")
            }
        }
        .task {
            await loadReceiptImage()
        }
    }

    // MARK: - Receipt Image View

    private func receiptImageView(_ image: UIImage) -> some View {
        Button {
            showingImageViewer = true
        } label: {
            VStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                    Text("Tap to view full size")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Product Pair Row

    private func productPairRow(_ productPair: ProductPair) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Product name
                Text(productPair.gfProductName)
                    .font(.body)

                // vs non-GF product
                Text("vs \(productPair.nonGFProductName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Prices
                HStack(spacing: 8) {
                    Text(productPair.gfPrice, format: .currency(code: "CAD"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(productPair.nonGFPrice, format: .currency(code: "CAD"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if productPair.quantity > 1 {
                        Text("×\(productPair.quantity)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("\(productPair.quantity) units purchased")
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // Differential for the whole purchase, so the rows add up to the summary total
                Text(productPair.extendedDifferential, format: .currency(code: "CAD"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(productPair.extendedDifferential > 0 ? .green : .secondary)

                // Unlink button
                Button(role: .destructive) {
                    unlinkProduct(productPair)
                } label: {
                    Text("Unlink")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper Methods

    /// Loads the receipt image from storage
    private func loadReceiptImage() async {
        guard let imageUUID = receipt.receiptImageUUID else {
            return
        }

        isLoadingImage = true

        if let image = await ImageStorageService.shared.retrieveImage(uuid: imageUUID, type: .receipt) {
            receiptImage = image
        }

        isLoadingImage = false
    }

    /// Unlinks a product pair from this receipt
    private func unlinkProduct(_ productPair: ProductPair) {
        productPair.receipt = nil
        productPair.verified = false

        do {
            try modelContext.save()
        } catch {
            ErrorHandler.shared.log(error, context: "Unlinking product from receipt")
        }
    }

    /// Deletes the receipt and unlinks all products
    private func deleteReceipt() {
        // Unlink all product pairs first
        for productPair in receipt.productPairs {
            productPair.receipt = nil
            productPair.verified = false
        }

        // Delete receipt image from storage
        if let imageUUID = receipt.receiptImageUUID {
            Task {
                await ImageStorageService.shared.deleteImage(uuid: imageUUID, type: .receipt)
            }
        }

        // Delete receipt from model context
        modelContext.delete(receipt)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            ErrorHandler.shared.log(error, context: "Deleting receipt")
        }
    }
}

#if DEBUG
// MARK: - Preview

#Preview("Receipt with Products") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ProductPair.self, Receipt.self, configurations: config)

    // Create sample products
    let product1 = ProductPair(
        gfProductName: "Udi's Gluten Free Bread",
        gfPrice: Decimal(string: "6.99")!,
        nonGFProductName: "Wonder Bread",
        nonGFPrice: Decimal(string: "3.49")!,
        category: "Bread",
        verified: true
    )

    let product2 = ProductPair(
        gfProductName: "Barilla GF Pasta",
        gfPrice: Decimal(string: "5.49")!,
        nonGFProductName: "Barilla Pasta",
        nonGFPrice: Decimal(string: "2.29")!,
        category: "Pasta",
        verified: true
    )

    // Create receipt
    let receipt = Receipt(
        purchaseDate: Date(),
        storeName: "Loblaws",
        totalAmount: Decimal(string: "47.83")!,
        productPairs: [product1, product2]
    )

    container.mainContext.insert(receipt)

    return NavigationStack {
        ReceiptDetailView(receipt: receipt)
    }
    .modelContainer(container)
}

#Preview("Receipt without Products") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ProductPair.self, Receipt.self, configurations: config)

    let receipt = Receipt(
        purchaseDate: Date(),
        storeName: "Sobeys",
        totalAmount: Decimal(string: "23.45")!
    )

    container.mainContext.insert(receipt)

    return NavigationStack {
        ReceiptDetailView(receipt: receipt)
    }
    .modelContainer(container)
}
#endif
