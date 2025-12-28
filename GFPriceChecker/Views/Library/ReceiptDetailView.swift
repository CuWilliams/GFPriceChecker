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
                        Text("$\(total as NSDecimalNumber)")
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

                LabeledContent("Total Differential") {
                    Text("$\(receipt.totalDifferential as NSDecimalNumber)")
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
                ReceiptImageViewer(image: image)
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
                    Text("$\(productPair.gfPrice as NSDecimalNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("$\(productPair.nonGFPrice as NSDecimalNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // Differential
                Text("$\(productPair.differential as NSDecimalNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(productPair.differential > 0 ? .green : .secondary)

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
            print("✅ Product unlinked from receipt")
        } catch {
            print("❌ Failed to unlink product: \(error)")
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
            print("✅ Receipt deleted successfully")
            dismiss()
        } catch {
            print("❌ Failed to delete receipt: \(error)")
        }
    }
}

// MARK: - Receipt Image Viewer

/// Full-screen zoomable receipt image viewer
struct ReceiptImageViewer: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    let image: UIImage

    // MARK: - State

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale *= delta
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    // Constrain scale
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                        }
                                    } else if scale > 4.0 {
                                        withAnimation {
                                            scale = 4.0
                                        }
                                    }
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            // Double-tap to reset zoom
                            withAnimation {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                }
            }
            .navigationTitle("Receipt Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Reset zoom
                        withAnimation {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    } label: {
                        Label("Reset Zoom", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
    }
}

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
