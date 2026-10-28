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
struct ReceiptCaptureView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Query

    /// Fetch all unverified product pairs
    @Query(filter: #Predicate<ProductPair> { !$0.verified })
    private var unverifiedProducts: [ProductPair]

    // MARK: - State

    /// Current step in the receipt capture flow
    @State private var currentStep: ReceiptStep = .selectProducts

    /// Selected product pairs to verify with this receipt
    @State private var selectedProducts: Set<UUID> = []

    /// Whether to show the document scanner
    @State private var showingScanner = false

    /// Loading state during OCR processing
    @State private var isProcessingOCR = false

    /// Receipt data
    @State private var receiptImage: UIImage?
    @State private var receiptImageUUID: String?
    @State private var receiptText: String = ""
    @State private var storeName: String = ""
    @State private var purchaseDate: Date = Date()
    @State private var totalAmount: String = ""

    /// OCR observations for tap-to-select
    @State private var receiptOCRObservations: [SelectableTextObservation] = []

    /// Track which product is currently being verified
    @State private var currentVerificationIndex: Int = 0

    /// Store confirmed matches: ProductPair.id -> selected receipt line text
    @State private var confirmedMatches: [UUID: String] = [:]

    /// Alert state
    @State private var showingAlert = false
    @State private var alertMessage = ""

    /// Receipt viewer state
    @State private var showingReceiptViewer = false

    // MARK: - Computed Properties

    /// Products selected for verification
    private var productsToVerify: [ProductPair] {
        unverifiedProducts.filter { selectedProducts.contains($0.id) }
    }

    /// Current product being verified
    private var currentProductToVerify: ProductPair? {
        guard currentVerificationIndex < productsToVerify.count else { return nil }
        return productsToVerify[currentVerificationIndex]
    }

    /// Count of confirmed matches
    private var confirmedCount: Int {
        confirmedMatches.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                stepView

                // Loading overlay
                if isProcessingOCR {
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
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView { image in
                    if let image = image {
                        handleScannedReceipt(image)
                    } else {
                        // User cancelled or scan failed - close the scanner
                        showingScanner = false
                    }
                }
            }
            .alert("Error", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: - Step Views

    @ViewBuilder
    private var stepView: some View {
        switch currentStep {
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
                            selectAllProducts()
                        } label: {
                            Label("Select All", systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            deselectAllProducts()
                        } label: {
                            Label("Deselect All", systemImage: "circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Text("\(selectedProducts.count) selected")
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
                        currentStep = .scanReceipt
                    } label: {
                        Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedProducts.isEmpty)

                    if selectedProducts.isEmpty {
                        Text("Select at least one product to continue")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(selectedProducts.count) product\(selectedProducts.count == 1 ? "" : "s") selected")
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
            toggleProductSelection(product)
        } label: {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: selectedProducts.contains(product.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selectedProducts.contains(product.id) ? .blue : .secondary)

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

    private func toggleProductSelection(_ product: ProductPair) {
        if selectedProducts.contains(product.id) {
            selectedProducts.remove(product.id)
        } else {
            selectedProducts.insert(product.id)
        }
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
                showingScanner = true
            } label: {
                Label("Open Scanner", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            // Back button
            Button {
                currentStep = .selectProducts
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
            if let product = currentProductToVerify {
                productVerificationView(product: product)
            } else {
                // All products verified - show summary
                verificationCompleteView
            }
        }
        .sheet(isPresented: $showingReceiptViewer) {
            if let image = receiptImage {
                ImageViewer(image: image, title: "Receipt")
            }
        }
    }

    // MARK: - Verification Progress Header

    private var verificationProgressHeader: some View {
        VStack(spacing: 8) {
            // Progress text
            Text("Verifying product \(min(currentVerificationIndex + 1, productsToVerify.count)) of \(productsToVerify.count)")
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
                            width: geometry.size.width * CGFloat(confirmedCount) / CGFloat(max(productsToVerify.count, 1)),
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
            if receiptImage != nil {
                Button {
                    showingReceiptViewer = true
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
            if let image = receiptImage {
                ReceiptLineSelector(
                    image: image,
                    observations: receiptOCRObservations,
                    productName: product.gfProductName,
                    onLineSelected: { selectedText in
                        confirmMatch(for: product, withLine: selectedText)
                    },
                    onSkip: {
                        skipProduct(product)
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

                Text("\(confirmedCount) of \(productsToVerify.count) products matched")
                    .foregroundStyle(.secondary)

                // Summary of matches
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(productsToVerify, id: \.id) { product in
                        HStack {
                            Image(systemName: confirmedMatches[product.id] != nil ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(confirmedMatches[product.id] != nil ? .green : .orange)

                            Text(product.gfProductName)
                                .lineLimit(1)

                            Spacer()

                            if confirmedMatches[product.id] != nil {
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
                    confirmAndSave()
                } label: {
                    Label("Save Receipt", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(confirmedCount == 0)
                .padding(.horizontal)

                if confirmedCount == 0 {
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

    // MARK: - Helper Methods

    /// Selects all unverified products
    private func selectAllProducts() {
        selectedProducts = Set(unverifiedProducts.map { $0.id })
    }

    /// Deselects all products
    private func deselectAllProducts() {
        selectedProducts.removeAll()
    }

    /// Confirms a match and moves to next product
    private func confirmMatch(for product: ProductPair, withLine text: String) {
        confirmedMatches[product.id] = text
        currentVerificationIndex += 1
    }

    /// Skips current product without matching
    private func skipProduct(_ product: ProductPair) {
        // Don't add to confirmedMatches
        currentVerificationIndex += 1
    }

    /// Handles scanned receipt image
    private func handleScannedReceipt(_ image: UIImage) {
        receiptImage = image
        showingScanner = false
        isProcessingOCR = true

        Task {
            await processReceipt(image)
        }
    }

    /// Processes receipt with OCR
    private func processReceipt(_ image: UIImage) async {
        do {
            // Extract full receipt text (for display and store/date parsing)
            let fullText = try await OCRService.shared.extractReceiptText(from: image)
            receiptText = fullText

            // Extract selectable observations for tap-to-select
            let observations = try await OCRService.shared.extractSelectableText(from: image)
            receiptOCRObservations = observations

            // Parse receipt metadata (keep this functionality)
            let parser = ReceiptParserService.shared

            if let store = parser.extractStoreName(from: fullText) {
                storeName = store
            }

            if let date = parser.extractDate(from: fullText) {
                purchaseDate = date
            }

            if let total = parser.extractTotal(from: fullText) {
                totalAmount = "\(total)"
            }

            // Reset verification state
            currentVerificationIndex = 0
            confirmedMatches = [:]

            isProcessingOCR = false
            currentStep = .reviewMatches

        } catch {
            isProcessingOCR = false
            alertMessage = "Failed to process receipt: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    /// Confirms matches and saves receipt to SwiftData
    private func confirmAndSave() {
        Task {
            // Save receipt image
            guard let image = receiptImage,
                  let imageUUID = await ImageStorageService.shared.saveImage(image, type: .receipt) else {
                alertMessage = "Failed to save receipt image"
                showingAlert = true
                return
            }

            receiptImageUUID = imageUUID

            // Parse total amount
            let totalDecimal = totalAmount.isEmpty ? nil : Decimal(string: totalAmount)

            // Create Receipt
            let receipt = Receipt(
                purchaseDate: purchaseDate,
                storeName: storeName.isEmpty ? nil : storeName,
                receiptImageUUID: imageUUID,
                totalAmount: totalDecimal,
                extractedOCRText: receiptText
            )

            // Associate confirmed products with receipt
            for product in productsToVerify {
                if confirmedMatches[product.id] != nil {
                    product.receipt = receipt
                    product.verified = true
                }
            }

            modelContext.insert(receipt)

            do {
                try modelContext.save()
                dismiss()
            } catch {
                alertMessage = "Failed to save: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }

    // MARK: - Step Enum

    enum ReceiptStep {
        case selectProducts
        case scanReceipt
        case reviewMatches
    }
}

// MARK: - Receipt Line Selector

/// Simplified selector for receipt verification - single line selection
private struct ReceiptLineSelector: View {
    let image: UIImage
    let observations: [SelectableTextObservation]
    let productName: String
    let onLineSelected: (String) -> Void
    let onSkip: () -> Void

    @State private var selectedObservation: SelectableTextObservation?

    /// Find suggested match via simple text search
    private var suggestedObservation: SelectableTextObservation? {
        let searchTerms = productName.lowercased().split(separator: " ").map(String.init)

        // Find observation containing any significant word from product name
        for observation in observations {
            let obsLower = observation.text.lowercased()
            for term in searchTerms where term.count >= 3 {
                if obsLower.contains(term) {
                    return observation
                }
            }
        }
        return nil
    }

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
                    if let selected = selectedObservation {
                        onLineSelected(selected.text)
                    }
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
            selectedObservation = observation
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
