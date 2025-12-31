//
//  ProductCaptureFlowView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import SwiftData

/// Guided flow for capturing and comparing GF vs non-GF products
///
/// Multi-step workflow:
/// 1. Introduction
/// 2. Capture GF product
/// 3. Review GF product (OCR data editable)
/// 4. Capture non-GF product
/// 5. Review non-GF product (OCR data editable)
/// 6. Finalize and save
struct ProductCaptureFlowView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Current step in the capture flow
    @State private var currentStep: CaptureStep = .introduction

    /// Whether to show the document scanner
    @State private var showingScanner = false

    /// Loading state during OCR processing
    @State private var isProcessingOCR = false

    /// Loading state during save operation
    @State private var isSaving = false

    // GF Product Data
    @State private var gfImage: UIImage?
    @State private var gfImageUUID: String?
    @State private var gfProductName: String = ""
    @State private var gfPriceText: String = ""
    @State private var gfSize: String = ""
    @State private var gfOCRConfidence: Float = 0.0

    // Non-GF Product Data
    @State private var nonGFImage: UIImage?
    @State private var nonGFImageUUID: String?
    @State private var nonGFProductName: String = ""
    @State private var nonGFPriceText: String = ""
    @State private var nonGFSize: String = ""
    @State private var nonGFOCRConfidence: Float = 0.0

    // Additional Product Pair Data
    @State private var category: String = ""
    @State private var notes: String = ""

    // Price Selection State
    @State private var showingPriceSelection = false
    @State private var priceCandidates: [PriceMatch] = []
    @State private var isSelectingGFPrice = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content
                stepView

                // Loading overlay
                if isProcessingOCR {
                    ocrLoadingOverlay
                }
            }
            .navigationTitle(currentStep.title)
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
                    handleScannedImage(image)
                }
            }
            .alert("Select Price", isPresented: $showingPriceSelection) {
                ForEach(Array(priceCandidates.prefix(3).enumerated()), id: \.offset) { index, candidate in
                    Button("$\(candidate.amount) (score: \(String(format: "%.2f", candidate.rankingScore)))") {
                        selectPriceCandidate(candidate)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Multiple prices detected. Please select the correct product price.")
            }
        }
    }

    // MARK: - Step Views

    @ViewBuilder
    private var stepView: some View {
        switch currentStep {
        case .introduction:
            introductionView
        case .captureGF:
            capturePlaceholderView(productType: "Gluten-Free")
        case .reviewGF:
            reviewView(isGF: true)
        case .captureNonGF:
            capturePlaceholderView(productType: "Regular")
        case .reviewNonGF:
            reviewView(isGF: false)
        case .finalize:
            finalizeView
        }
    }

    // MARK: - Introduction

    private var introductionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "camera.metering.center.weighted")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            Text("Capture Product Pair")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(number: 1, text: "Photograph shelf price tag (GF product)", icon: "tag.fill")
                instructionRow(number: 2, text: "Review and edit extracted data")
                instructionRow(number: 3, text: "Photograph shelf price tag (regular product)", icon: "tag.fill")
                instructionRow(number: 4, text: "Review and finalize")
            }
            .padding()

            // Guidance note
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Results")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Photograph shelf price tags for best OCR accuracy. They contain both product name and price clearly.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)

            Button {
                currentStep = .captureGF
                showingScanner = true
            } label: {
                Text("Start Capture")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    private func instructionRow(number: Int, text: String, icon: String? = nil) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())

            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
            }

            Text(text)
                .font(.body)

            Spacer()
        }
    }

    // MARK: - Capture Placeholder

    private func capturePlaceholderView(productType: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Scanning \(productType) Product")
                .font(.title2)
                .fontWeight(.semibold)

            // Guidance tip
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.blue)
                Text("💡 TIP: Photograph the shelf price tag for best OCR accuracy")
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)

            Text("Shelf tags contain both product name and price. You can also photograph product packaging if preferred.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
        .onAppear {
            // Scanner is shown via sheet, this is just a placeholder
        }
    }

    // MARK: - Review View

    private func reviewView(isGF: Bool) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image preview
                if let image = isGF ? gfImage : nonGFImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                }

                // OCR Results Section
                VStack(spacing: 16) {
                    Text("Review Extracted Data")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Product Name
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Product Name")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            // Show confidence indicator only if OCR was attempted (confidence > 0)
                            let nameConfidence: Float = 0.0 // Product names don't have separate confidence yet
                            if nameConfidence > 0 {
                                ConfidenceIndicatorView(
                                    confidence: nameConfidence,
                                    label: "\(Int(nameConfidence * 100))%",
                                    showInfo: false
                                )
                            }
                        }
                        TextField("Enter product name", text: isGF ? $gfProductName : $nonGFProductName)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.background)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // Price
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Price")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            let confidence = isGF ? gfOCRConfidence : nonGFOCRConfidence
                            if confidence > 0 {
                                ConfidenceIndicatorView(
                                    confidence: confidence,
                                    label: "\(Int(confidence * 100))%",
                                    showInfo: true
                                )
                            }
                        }

                        let priceConfidence = isGF ? gfOCRConfidence : nonGFOCRConfidence
                        TextField("0.00", text: isGF ? $gfPriceText : $nonGFPriceText)
                            .keyboardType(.decimalPad)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(ConfidenceIndicatorView.backgroundColor(for: priceConfidence) ?? .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        priceConfidence > 0 ? ConfidenceIndicatorView.borderColor(for: priceConfidence) : Color.gray.opacity(0.3),
                                        lineWidth: priceConfidence > 0 && priceConfidence < 0.85 ? 2 : 1
                                    )
                            )
                    }

                    // Size (optional)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Size (Optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., 500g, 16oz", text: isGF ? $gfSize : $nonGFSize)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()

                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        if isGF {
                            currentStep = .captureNonGF
                            showingScanner = true
                        } else {
                            currentStep = .finalize
                        }
                    } label: {
                        Text(isGF ? "Continue to Regular Product" : "Continue to Finalize")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canProceed(from: isGF) ? Color.blue : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!canProceed(from: isGF))

                    Button {
                        // Retake
                        if isGF {
                            currentStep = .captureGF
                        } else {
                            currentStep = .captureNonGF
                        }
                        showingScanner = true
                    } label: {
                        Text("Retake Photo")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
                .padding()
            }
            .padding()
        }
    }

    private func canProceed(from isGF: Bool) -> Bool {
        let name = isGF ? gfProductName : nonGFProductName
        let price = isGF ? gfPriceText : nonGFPriceText

        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               Decimal(string: price) != nil
    }

    // MARK: - Finalize View

    private var finalizeView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Review Product Pair")
                    .font(.headline)

                // Side-by-side comparison
                HStack(spacing: 16) {
                    // GF Product
                    VStack(spacing: 8) {
                        Text("Gluten-Free")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let image = gfImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .cornerRadius(8)
                        }

                        Text(gfProductName)
                            .font(.caption)
                            .lineLimit(2)

                        if let price = Decimal(string: gfPriceText) {
                            Text(price.formatted(.currency(code: "CAD")))
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Non-GF Product
                    VStack(spacing: 8) {
                        Text("Regular")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let image = nonGFImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .cornerRadius(8)
                        }

                        Text(nonGFProductName)
                            .font(.caption)
                            .lineLimit(2)

                        if let price = Decimal(string: nonGFPriceText) {
                            Text(price.formatted(.currency(code: "CAD")))
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Differential
                if let gfPrice = Decimal(string: gfPriceText),
                   let nonGFPrice = Decimal(string: nonGFPriceText) {
                    let differential = gfPrice - nonGFPrice
                    VStack(spacing: 4) {
                        Text("Price Differential")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(differential.formatted(.currency(code: "CAD")))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(differential >= 0 ? .red : .green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }

                // Category
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., Bread, Pasta", text: $category)
                        .textFieldStyle(.roundedBorder)
                }

                // Notes
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $notes)
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }

                // Save Button
                Button {
                    saveProductPair()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isSaving ? "Saving..." : "Save Product Pair")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSaving ? Color.gray : Color.green)
                    .cornerRadius(12)
                }
                .disabled(isSaving)
            }
            .padding()
        }
    }

    // MARK: - OCR Loading Overlay

    private var ocrLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Processing Image...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(Color.gray.opacity(0.9))
            .cornerRadius(16)
        }
    }

    // MARK: - Actions

    /// Handles image from document scanner
    private func handleScannedImage(_ image: UIImage?) {
        guard let image = image else { return }

        Task {
            isProcessingOCR = true

            // Save image to storage
            let uuid = await ImageStorageService.shared.saveImage(image, type: .product)

            // Run OCR
            let productName = try? await OCRService.shared.findProductName(in: image)
            let prices = try? await OCRService.shared.findPrices(in: image)

            // Determine which product we're capturing
            switch currentStep {
            case .captureGF:
                gfImage = image
                gfImageUUID = uuid
                gfProductName = productName ?? ""

                // Handle price candidates
                if let allPrices = prices, !allPrices.isEmpty {
                    let topPrice = allPrices.first!

                    // Check if we should show price selection alert
                    // Show alert if: top candidate quality < high AND multiple candidates exist
                    if topPrice.quality != .high && allPrices.count > 1 {
                        // Store candidates and show selection alert
                        priceCandidates = allPrices
                        isSelectingGFPrice = true
                        isProcessingOCR = false
                        showingPriceSelection = true
                        return // Wait for user selection
                    } else {
                        // Auto-select top candidate (high confidence or only one option)
                        gfPriceText = String(describing: topPrice.amount)
                        gfOCRConfidence = topPrice.confidence

                        // Trigger haptic feedback if confidence is low
                        if ConfidenceIndicatorView.requiresAttention(for: topPrice.confidence) {
                            await MainActor.run {
                                triggerHapticFeedback(for: topPrice.confidence)
                            }
                        }
                    }
                }
                currentStep = .reviewGF

            case .captureNonGF:
                nonGFImage = image
                nonGFImageUUID = uuid
                nonGFProductName = productName ?? ""

                // Handle price candidates
                if let allPrices = prices, !allPrices.isEmpty {
                    let topPrice = allPrices.first!

                    // Check if we should show price selection alert
                    if topPrice.quality != .high && allPrices.count > 1 {
                        // Store candidates and show selection alert
                        priceCandidates = allPrices
                        isSelectingGFPrice = false
                        isProcessingOCR = false
                        showingPriceSelection = true
                        return // Wait for user selection
                    } else {
                        // Auto-select top candidate
                        nonGFPriceText = String(describing: topPrice.amount)
                        nonGFOCRConfidence = topPrice.confidence

                        // Trigger haptic feedback if confidence is low
                        if ConfidenceIndicatorView.requiresAttention(for: topPrice.confidence) {
                            await MainActor.run {
                                triggerHapticFeedback(for: topPrice.confidence)
                            }
                        }
                    }
                }
                currentStep = .reviewNonGF

            default:
                break
            }

            isProcessingOCR = false
        }
    }

    /// Handles user selection of a price candidate
    private func selectPriceCandidate(_ candidate: PriceMatch) {
        if isSelectingGFPrice {
            gfPriceText = String(describing: candidate.amount)
            gfOCRConfidence = candidate.confidence
            currentStep = .reviewGF
        } else {
            nonGFPriceText = String(describing: candidate.amount)
            nonGFOCRConfidence = candidate.confidence
            currentStep = .reviewNonGF
        }
    }

    /// Saves the product pair to SwiftData
    private func saveProductPair() {
        guard let gfPrice = Decimal(string: gfPriceText),
              let nonGFPrice = Decimal(string: nonGFPriceText) else {
            print("❌ Invalid price format")
            return
        }

        isSaving = true

        let productPair = ProductPair(
            gfProductName: gfProductName.trimmingCharacters(in: .whitespacesAndNewlines),
            gfPrice: gfPrice,
            gfSize: gfSize.isEmpty ? nil : gfSize,
            gfImageUUID: gfImageUUID,
            gfOCRConfidence: gfOCRConfidence,
            nonGFProductName: nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines),
            nonGFPrice: nonGFPrice,
            nonGFSize: nonGFSize.isEmpty ? nil : nonGFSize,
            nonGFImageUUID: nonGFImageUUID,
            nonGFOCRConfidence: nonGFOCRConfidence,
            category: category.isEmpty ? nil : category,
            notes: notes.isEmpty ? nil : notes,
            verified: false
        )

        modelContext.insert(productPair)

        do {
            try modelContext.save()
            print("✅ Saved ProductPair: \(productPair.gfProductName) vs \(productPair.nonGFProductName)")
            print("   Differential: $\(productPair.differential)")

            isSaving = false
            dismiss()
        } catch {
            print("❌ Save failed: \(error.localizedDescription)")
            isSaving = false
        }
    }

    /// Triggers haptic feedback based on confidence level
    private func triggerHapticFeedback(for confidence: Float) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        switch confidence {
        case 0.6..<0.85:
            // Medium confidence - warning feedback
            generator.notificationOccurred(.warning)
        case 0.0..<0.6:
            // Low confidence - error feedback
            generator.notificationOccurred(.error)
        default:
            // High confidence - no haptic needed
            break
        }
        #endif
    }
}

// MARK: - Capture Step Enum

private enum CaptureStep {
    case introduction
    case captureGF
    case reviewGF
    case captureNonGF
    case reviewNonGF
    case finalize

    var title: String {
        switch self {
        case .introduction:
            return "Capture Product Pair"
        case .captureGF:
            return "Scan GF Product"
        case .reviewGF:
            return "Review GF Product"
        case .captureNonGF:
            return "Scan Regular Product"
        case .reviewNonGF:
            return "Review Regular Product"
        case .finalize:
            return "Finalize"
        }
    }
}

// MARK: - Preview

#Preview {
    ProductCaptureFlowView()
        .modelContainer(for: [ProductPair.self], inMemory: true)
}
