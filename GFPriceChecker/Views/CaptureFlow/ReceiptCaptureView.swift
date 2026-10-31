//
//  ReceiptCaptureView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import SwiftData

/// View for scanning receipts and matching them to product pairs
///
/// Workflow:
/// 1. Select unverified product pairs
/// 2. Scan receipt with camera
/// 3. Process OCR and extract receipt data
/// 4. Sequential tap-to-select verification for each product
/// 5. Confirm matches and save receipt
///
/// The steps, their state and the save live in `ReceiptCaptureViewModel`. The
/// view keeps the `@Query` of unverified pairs and hands it to the view model.
struct ReceiptCaptureView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Query

    /// Fetch all unverified product pairs
    @Query(filter: #Predicate<ProductPair> { !$0.verified })
    private var unverifiedProducts: [ProductPair]

    // MARK: - State

    /// All of the flow's state and logic lives in `ReceiptCaptureViewModel`;
    /// this view only draws it.
    @State private var viewModel = ReceiptCaptureViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                stepView

                // Loading overlay
                if viewModel.isProcessingOCR {
                    ocrLoadingOverlay
                }
            }
            .navigationTitle("Verify with Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingScanner) {
                DocumentScannerView { image in
                    Task { await viewModel.handleScannedReceipt(image) }
                }
            }
            .alert("Error", isPresented: $viewModel.showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.alertMessage)
            }
            .onChange(of: unverifiedProducts, initial: true) { _, products in
                viewModel.refreshUnverifiedProducts(products)
            }
            .onChange(of: viewModel.didSave) { _, saved in
                if saved { dismiss() }
            }
        }
        // So a scripted take can drive this sheet; nothing in a release build
        .demoRegistered(viewModel)
    }

    // MARK: - Step Views

    @ViewBuilder
    private var stepView: some View {
        switch viewModel.currentStep {
        case .selectProducts:
            productSelectionView
        case .scanReceipt:
            scanReceiptPromptView
        case .reviewMatches:
            matchReviewView
        }
    }

    // MARK: - Product Selection View

    private var productSelectionView: some View {
        VStack(spacing: 0) {
            if unverifiedProducts.isEmpty {
                emptyStateView
            } else {
                // Instructions and bulk actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select products to verify with this receipt")
                        .font(.headline)

                    Text("Choose the product pairs you purchased on this shopping trip.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Bulk selection buttons
                    HStack(spacing: 12) {
                        Button {
                            viewModel.selectAllProducts()
                        } label: {
                            Label("Select All", systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            viewModel.deselectAllProducts()
                        } label: {
                            Label("Deselect All", systemImage: "circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Text("\(viewModel.selectedProducts.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGroupedBackground))

                // Product list
                List {
                    ForEach(unverifiedProducts, id: \.id) { product in
                        productSelectionRow(product)
                    }
                }
                .listStyle(.insetGrouped)
            }

            // Action button
            if !unverifiedProducts.isEmpty {
                VStack(spacing: 12) {
                    Button {
                        viewModel.continueToScan()
                    } label: {
                        Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedProducts.isEmpty)

                    if viewModel.selectedProducts.isEmpty {
                        Text("Select at least one product to continue")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(viewModel.selectedProducts.count) product\(viewModel.selectedProducts.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private func productSelectionRow(_ product: ProductPair) -> some View {
        Button {
            viewModel.toggleProductSelection(product)
        } label: {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: viewModel.selectedProducts.contains(product.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(viewModel.selectedProducts.contains(product.id) ? .blue : .secondary)

                // Product info
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.gfProductName)
                        .font(.body)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text("$\(product.gfPrice as NSDecimalNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let category = product.category {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(product.createdDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Differential
                Text("$\(product.differential as NSDecimalNumber)")
                    .font(.subheadline)
                    .foregroundStyle(product.differential > 0 ? .green : .secondary)
                    .fontWeight(.medium)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scan Receipt Prompt View

    private var scanReceiptPromptView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            // Instructions
            VStack(spacing: 12) {
                Text("Ready to Scan Receipt")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Position the receipt flat with good lighting. The scanner will automatically detect edges.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Scan button
            Button {
                viewModel.openScanner()
            } label: {
                Label("Open Scanner", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            // Back button
            Button {
                viewModel.backToProductSelection()
            } label: {
                Text("Back to Product Selection")
            }
            .padding(.bottom)
        }
    }

    // MARK: - Match Review View

    private var matchReviewView: some View {
        VStack(spacing: 0) {
            // Progress indicator
            verificationProgressHeader

            // Main content
            if let product = viewModel.currentProductToVerify {
                productVerificationView(product: product)
            } else {
                // All products verified - show summary
                verificationCompleteView
            }
        }
        .sheet(isPresented: $viewModel.showingReceiptViewer) {
            if let image = viewModel.receiptImage {
                ImageViewer(image: image, title: "Receipt")
            }
        }
    }

    // MARK: - Verification Progress Header

    private var verificationProgressHeader: some View {
        VStack(spacing: 8) {
            // Progress text
            Text("Verifying product \(min(viewModel.currentVerificationIndex + 1, viewModel.productsToVerify.count)) of \(viewModel.productsToVerify.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(
                            width: geometry.size.width * CGFloat(viewModel.confirmedCount) / CGFloat(max(viewModel.productsToVerify.count, 1)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Product Verification View

    private func productVerificationView(product: ProductPair) -> some View {
        VStack(spacing: 0) {
            // Product being verified
            VStack(alignment: .leading, spacing: 8) {
                Text("Find this product on the receipt:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.gfProductName)
                            .font(.headline)
                        Text("$\(product.gfPrice as NSDecimalNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    if let category = product.category {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))

            // View receipt button
            if viewModel.receiptImage != nil {
                Button {
                    viewModel.showReceiptViewer()
                } label: {
                    Label("Tap to View Receipt", systemImage: "doc.text.viewfinder")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityLabel("View Receipt")
                .accessibilityHint("Opens the full receipt image in a viewer")
            }

            // Receipt line selector
            if let image = viewModel.receiptImage {
                ReceiptLineSelector(
                    image: image,
                    observations: viewModel.receiptOCRObservations,
                    selectedObservation: viewModel.selectedReceiptLine,
                    suggestedObservation: viewModel.suggestedReceiptLine(for: product),
                    onLineTapped: { viewModel.selectReceiptLine($0) },
                    onConfirm: { viewModel.confirmSelectedLine() },
                    onSkip: {
                        viewModel.skipProduct(product)
                    }
                )
            }
        }
    }

    // MARK: - Verification Complete View

    private var verificationCompleteView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Verification Complete")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(viewModel.confirmedCount) of \(viewModel.productsToVerify.count) products matched")
                    .foregroundStyle(.secondary)

                // Summary of matches
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.productsToVerify, id: \.id) { product in
                        HStack {
                            Image(systemName: viewModel.confirmedMatches[product.id] != nil ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(viewModel.confirmedMatches[product.id] != nil ? .green : .orange)

                            Text(product.gfProductName)
                                .lineLimit(1)

                            Spacer()

                            if viewModel.confirmedMatches[product.id] != nil {
                                Text("Matched")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("Skipped")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Save button
                Button {
                    Task { await viewModel.save(into: modelContext) }
                } label: {
                    Label("Save Receipt", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.confirmedCount == 0)
                .padding(.horizontal)

                if viewModel.confirmedCount == 0 {
                    Text("Match at least one product to save the receipt")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("All Products Verified")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("You don't have any unverified product pairs. Add products from the Capture tab, then come back here to verify them with receipts.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Loading Overlay

    private var ocrLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Processing receipt...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Receipt Line Selector

/// Simplified selector for receipt verification - single line selection
///
/// The selection and the suggestion belong to `ReceiptCaptureViewModel`; this
/// view draws them and sends taps back.
private struct ReceiptLineSelector: View {
    let image: UIImage
    let observations: [SelectableTextObservation]
    let selectedObservation: SelectableTextObservation?
    let suggestedObservation: SelectableTextObservation?
    let onLineTapped: (SelectableTextObservation) -> Void
    let onConfirm: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Instructions
            Text(selectedObservation == nil ? "Tap the matching line on the receipt" : "Line selected - confirm or change")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)

            // Scrollable receipt text
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(observations) { observation in
                        receiptLineRow(observation)
                    }
                }
                .padding(.horizontal)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onSkip()
                } label: {
                    Text("Skip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onConfirm()
                } label: {
                    Label("Confirm Match", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedObservation == nil)
            }
            .padding()
        }
    }

    private func receiptLineRow(_ observation: SelectableTextObservation) -> some View {
        let isSelected = selectedObservation?.id == observation.id
        let isSuggested = suggestedObservation?.id == observation.id && selectedObservation == nil

        return Button {
            onLineTapped(observation)
        } label: {
            HStack {
                Text(observation.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(2)

                Spacer()

                if isSuggested {
                    Text("Suggested")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : (isSuggested ? Color.yellow.opacity(0.2) : Color(.secondarySystemGroupedBackground)))
            )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
// MARK: - Preview

#Preview("With Unverified Products") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ProductPair.self, Receipt.self, configurations: config)

    // Add sample unverified products
    let product1 = ProductPair(
        gfProductName: "Udi's Gluten Free Bread",
        gfPrice: Decimal(string: "6.99")!,
        nonGFProductName: "Wonder Bread",
        nonGFPrice: Decimal(string: "3.49")!,
        category: "Bread",
        verified: false
    )

    let product2 = ProductPair(
        gfProductName: "Barilla GF Pasta",
        gfPrice: Decimal(string: "5.49")!,
        nonGFProductName: "Barilla Pasta",
        nonGFPrice: Decimal(string: "2.29")!,
        category: "Pasta",
        verified: false
    )

    container.mainContext.insert(product1)
    container.mainContext.insert(product2)

    return ReceiptCaptureView()
        .modelContainer(container)
}

#Preview("Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ProductPair.self, Receipt.self, configurations: config)

    return ReceiptCaptureView()
        .modelContainer(container)
}
#endif
