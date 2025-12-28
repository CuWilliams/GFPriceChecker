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
/// 4. Match products to receipt line items (fuzzy matching)
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
    @State private var lineItems: [ReceiptLineItem] = []

    /// Matching results
    @State private var matchResults: [ProductMatchResult] = []

    /// Manual match selections (ProductPair UUID -> ReceiptLineItem index)
    @State private var manualSelections: [UUID: Int] = [:]

    /// Alert state
    @State private var showingAlert = false
    @State private var alertMessage = ""

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
                    handleScannedReceipt(image)
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
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select products to verify with this receipt")
                        .font(.headline)

                    Text("Choose the product pairs you purchased on this shopping trip.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
            // Receipt info header
            receiptInfoHeader

            // Match list
            List {
                ForEach(matchResults, id: \.productPair.id) { matchResult in
                    matchResultRow(matchResult)
                }
            }
            .listStyle(.insetGrouped)

            // Confirm button
            VStack(spacing: 12) {
                Button {
                    confirmAndSave()
                } label: {
                    Label("Confirm All Matches", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Review matches above before confirming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }

    private var receiptInfoHeader: some View {
        VStack(spacing: 12) {
            // Receipt image thumbnail
            if let image = receiptImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Receipt metadata
            VStack(spacing: 4) {
                if !storeName.isEmpty {
                    Text(storeName)
                        .font(.headline)
                }

                HStack(spacing: 16) {
                    Label(purchaseDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)

                    if !totalAmount.isEmpty {
                        Label("Total: $\(totalAmount)", systemImage: "dollarsign.circle")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private func matchResultRow(_ matchResult: ProductMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Product pair info
            VStack(alignment: .leading, spacing: 4) {
                Text(matchResult.productPair.gfProductName)
                    .font(.headline)

                Text("$\(matchResult.productPair.gfPrice as NSDecimalNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Match confidence indicator
            matchConfidenceIndicator(matchResult)

            // Matched line item or manual picker
            if let lineItem = getSelectedLineItem(for: matchResult) {
                matchedLineItemView(lineItem, matchResult: matchResult)
            } else {
                noMatchView(matchResult)
            }
        }
        .padding(.vertical, 8)
    }

    private func matchConfidenceIndicator(_ matchResult: ProductMatchResult) -> some View {
        HStack(spacing: 8) {
            switch matchResult.matchQuality {
            case .high:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("High confidence match")
                    .font(.caption)
                    .foregroundStyle(.green)

            case .medium:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Medium confidence - please verify")
                    .font(.caption)
                    .foregroundStyle(.orange)

            case .low:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Low confidence - manual selection required")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Text("\(Int(matchResult.matchConfidence * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func matchedLineItemView(_ lineItem: ReceiptLineItem, matchResult: ProductMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matched Receipt Item:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(lineItem.productName)
                        .font(.body)

                    Text("$\(lineItem.price as NSDecimalNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }

                Spacer()

                // Manual selection button
                Button {
                    // Clear manual selection to show picker
                    manualSelections.removeValue(forKey: matchResult.productPair.id)
                } label: {
                    Text("Change")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func noMatchView(_ matchResult: ProductMatchResult) -> some View {
        VStack(spacing: 12) {
            Text("No automatic match found")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Manual selection picker
            if !lineItems.isEmpty {
                Menu {
                    ForEach(lineItems.indices, id: \.self) { index in
                        Button {
                            manualSelections[matchResult.productPair.id] = index
                        } label: {
                            VStack(alignment: .leading) {
                                Text(lineItems[index].productName)
                                Text("$\(lineItems[index].price as NSDecimalNumber)")
                            }
                        }
                    }
                } label: {
                    Label("Select Receipt Item", systemImage: "hand.tap")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    /// Gets the selected line item for a match result (either auto-matched or manually selected)
    private func getSelectedLineItem(for matchResult: ProductMatchResult) -> ReceiptLineItem? {
        // Check manual selection first
        if let manualIndex = manualSelections[matchResult.productPair.id],
           lineItems.indices.contains(manualIndex) {
            return lineItems[manualIndex]
        }

        // Use auto-matched if confidence is medium or high
        if matchResult.matchQuality != .low,
           let matchedItem = matchResult.matchedLineItem {
            return matchedItem
        }

        return nil
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

    /// Processes receipt with OCR and fuzzy matching
    private func processReceipt(_ image: UIImage) async {
        do {
            // Extract full receipt text
            let fullText = try await OCRService.shared.extractReceiptText(from: image)
            receiptText = fullText

            print("📄 Receipt OCR extracted:")
            print(fullText)

            // Parse receipt components
            let parser = ReceiptParserService.shared

            // Store name
            if let store = parser.extractStoreName(from: fullText) {
                storeName = store
                print("🏪 Store: \(store)")
            }

            // Date
            if let date = parser.extractDate(from: fullText) {
                purchaseDate = date
                print("📅 Date: \(date.formatted(date: .abbreviated, time: .omitted))")
            }

            // Total
            if let total = parser.extractTotal(from: fullText) {
                totalAmount = "\(total)"
                print("💰 Total: $\(total)")
            }

            // Line items
            lineItems = parser.extractLineItems(from: fullText)
            print("📝 Line items found: \(lineItems.count)")
            for item in lineItems {
                print("  - \(item.productName): $\(item.price)")
            }

            // Get selected products
            let selectedProductPairs = unverifiedProducts.filter { selectedProducts.contains($0.id) }

            // Match products to line items
            matchResults = parser.matchProducts(selectedProductPairs, to: lineItems)
            print("🔍 Match results:")
            for result in matchResults {
                print("  - \(result.productPair.gfProductName): \(Int(result.matchConfidence * 100))% (\(result.matchQuality))")
            }

            isProcessingOCR = false
            currentStep = .reviewMatches

        } catch {
            isProcessingOCR = false
            alertMessage = "Failed to process receipt: \(error.localizedDescription)"
            showingAlert = true
            print("❌ OCR Error: \(error)")
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

            // Parse total amount as Decimal
            let totalDecimal: Decimal?
            if !totalAmount.isEmpty {
                totalDecimal = Decimal(string: totalAmount)
            } else {
                totalDecimal = nil
            }

            // Create Receipt object
            let receipt = Receipt(
                purchaseDate: purchaseDate,
                storeName: storeName.isEmpty ? nil : storeName,
                receiptImageUUID: imageUUID,
                totalAmount: totalDecimal,
                extractedOCRText: receiptText
            )

            // Associate selected products with receipt
            var verifiedCount = 0
            for matchResult in matchResults {
                // Only verify if there's a matched line item (auto or manual)
                if getSelectedLineItem(for: matchResult) != nil {
                    matchResult.productPair.receipt = receipt
                    matchResult.productPair.verified = true
                    verifiedCount += 1
                }
            }

            // Insert receipt into model context
            modelContext.insert(receipt)

            // Save context
            do {
                try modelContext.save()
                print("✅ Receipt saved successfully")
                print("✅ Verified \(verifiedCount) product pairs")
                dismiss()
            } catch {
                alertMessage = "Failed to save receipt: \(error.localizedDescription)"
                showingAlert = true
                print("❌ Save error: \(error)")
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
