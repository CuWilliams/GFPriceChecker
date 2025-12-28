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

    /// Bulk operation state
    @State private var showingDateSuggestion = false
    @State private var suggestedProductCount = 0

    // MARK: - Computed Properties

    /// Products with high-confidence auto-matches
    private var autoMatchedProducts: [ProductMatchResult] {
        matchResults.filter { $0.matchQuality == .high }
    }

    /// Products that need manual review
    private var needsReviewProducts: [ProductMatchResult] {
        matchResults.filter { $0.matchQuality != .high }
    }

    /// Number of products with confirmed matches (auto or manual)
    private var confirmedMatchCount: Int {
        matchResults.filter { result in
            getSelectedLineItem(for: result) != nil
        }.count
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
            // Receipt info header
            receiptInfoHeader

            // Progress indicator
            progressIndicator

            // Match list
            List {
                // Auto-matched products section
                if !autoMatchedProducts.isEmpty {
                    Section {
                        ForEach(autoMatchedProducts, id: \.productPair.id) { matchResult in
                            matchResultRow(matchResult)
                        }
                    } header: {
                        HStack {
                            Text("Auto-Matched (\(autoMatchedProducts.count))")
                            Spacer()
                            if !autoMatchedProducts.isEmpty {
                                Button("Accept All") {
                                    acceptAllAutoMatches()
                                }
                                .font(.caption)
                                .textCase(nil)
                            }
                        }
                    }
                }

                // Needs review section
                if !needsReviewProducts.isEmpty {
                    Section {
                        ForEach(needsReviewProducts, id: \.productPair.id) { matchResult in
                            matchResultRow(matchResult)
                        }
                    } header: {
                        Text("Needs Manual Review (\(needsReviewProducts.count))")
                    }
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
                .disabled(confirmedMatchCount == 0)

                // Status text
                if lineItems.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("No receipt items detected - try rescanning")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        // Go back to scan step
                        currentStep = .scanReceipt
                    } label: {
                        Label("Rescan Receipt", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("\(confirmedMatchCount) of \(matchResults.count) products matched")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
        .alert("Smart Suggestions", isPresented: $showingDateSuggestion) {
            Button("Select Suggested", role: .none) {
                selectProductsFromSameDate()
            }
            Button("Skip", role: .cancel) { }
        } message: {
            Text("Found \(suggestedProductCount) product\(suggestedProductCount == 1 ? "" : "s") from \(purchaseDate.formatted(date: .abbreviated, time: .omitted)). Would you like to select them?")
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 12) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(
                            width: geometry.size.width * CGFloat(confirmedMatchCount) / CGFloat(max(matchResults.count, 1)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            // Count label
            Text("\(confirmedMatchCount)/\(matchResults.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
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
            } else {
                // No line items extracted - OCR failed
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    Text("No receipt items detected")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("The receipt scan didn't extract any line items. Try rescanning with better lighting.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
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

    // MARK: Bulk Selection

    /// Selects all unverified products
    private func selectAllProducts() {
        selectedProducts = Set(unverifiedProducts.map { $0.id })
    }

    /// Deselects all products
    private func deselectAllProducts() {
        selectedProducts.removeAll()
    }

    /// Accepts all high-confidence auto-matches (doesn't require manual confirmation)
    private func acceptAllAutoMatches() {
        // Auto-matched products already have their matched line items
        // This is just a visual confirmation for the user
        print("✅ Accepted \(autoMatchedProducts.count) auto-matches")
    }

    /// Selects products created on the same date as the receipt
    private func selectProductsFromSameDate() {
        let calendar = Calendar.current
        let receiptDateComponents = calendar.dateComponents([.year, .month, .day], from: purchaseDate)

        for product in unverifiedProducts {
            let productDateComponents = calendar.dateComponents([.year, .month, .day], from: product.createdDate)

            if receiptDateComponents == productDateComponents {
                selectedProducts.insert(product.id)
            }
        }

        print("✅ Selected \(selectedProducts.count) products from \(purchaseDate.formatted(date: .abbreviated, time: .omitted))")
    }

    /// Checks if there are unselected products from the same date and suggests selecting them
    private func checkForSameDateProducts() {
        let calendar = Calendar.current
        let receiptDateComponents = calendar.dateComponents([.year, .month, .day], from: purchaseDate)

        var sameDateCount = 0
        for product in unverifiedProducts {
            let productDateComponents = calendar.dateComponents([.year, .month, .day], from: product.createdDate)

            // Count products from same date that aren't already selected
            if receiptDateComponents == productDateComponents && !selectedProducts.contains(product.id) {
                sameDateCount += 1
            }
        }

        if sameDateCount > 0 {
            suggestedProductCount = sameDateCount
            showingDateSuggestion = true
            print("💡 Found \(sameDateCount) additional products from same date")
        }
    }

    // MARK: Matching

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
        print("🎯 DEBUG: handleScannedReceipt called")
        print("🎯 DEBUG: Image size: \(image.size)")

        receiptImage = image
        showingScanner = false
        isProcessingOCR = true

        Task {
            print("🎯 DEBUG: Starting processReceipt task")
            await processReceipt(image)
            print("🎯 DEBUG: processReceipt task completed")
        }
    }

    /// Processes receipt with OCR and fuzzy matching
    private func processReceipt(_ image: UIImage) async {
        print("🎯 DEBUG: processReceipt started")
        print("🎯 DEBUG: About to call OCRService.extractReceiptText")

        do {
            // Extract full receipt text
            print("🎯 DEBUG: Calling extractReceiptText...")
            let fullText = try await OCRService.shared.extractReceiptText(from: image)
            print("🎯 DEBUG: extractReceiptText completed")
            print("🎯 DEBUG: Extracted text length: \(fullText.count) characters")

            receiptText = fullText

            print("📄 Receipt OCR extracted:")
            print(fullText)
            print("📄 End of OCR text")

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

            // Smart date suggestion - check for products from same date
            checkForSameDateProducts()

            isProcessingOCR = false
            currentStep = .reviewMatches

        } catch {
            print("🎯 DEBUG: ERROR CAUGHT in processReceipt")
            print("🎯 DEBUG: Error type: \(type(of: error))")
            print("🎯 DEBUG: Error description: \(error)")
            print("🎯 DEBUG: Localized description: \(error.localizedDescription)")

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
