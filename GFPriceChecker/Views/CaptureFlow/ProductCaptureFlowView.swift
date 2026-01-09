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

    // Non-GF Product Data
    @State private var nonGFImage: UIImage?
    @State private var nonGFImageUUID: String?
    @State private var nonGFProductName: String = ""
    @State private var nonGFPriceText: String = ""
    @State private var nonGFSize: String = ""

    // Additional Product Pair Data
    @State private var category: String = ""
    @State private var notes: String = ""

    // OCR observations for tap-to-select
    @State private var gfOCRObservations: [SelectableTextObservation] = []
    @State private var nonGFOCRObservations: [SelectableTextObservation] = []

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
        let observations = isGF ? gfOCRObservations : nonGFOCRObservations
        let image = isGF ? gfImage : nonGFImage

        // Check if user has already selected name and price
        let hasSelection = isGF
            ? (!gfProductName.isEmpty && !gfPriceText.isEmpty)
            : (!nonGFProductName.isEmpty && !nonGFPriceText.isEmpty)

        return VStack(spacing: 0) {
            if hasSelection {
                // Show confirmation view with selections and size field
                selectionConfirmationView(isGF: isGF)
            } else if let image = image, !observations.isEmpty {
                // Show tap-to-select interface
                OCRTextSelectorView(
                    image: image,
                    observations: observations,
                    onSelectionComplete: { name, price in
                        if isGF {
                            gfProductName = name
                            gfPriceText = price
                        } else {
                            nonGFProductName = name
                            nonGFPriceText = price
                        }
                    }
                )
            } else {
                // Fallback: No OCR data, show manual entry prompt
                noOCRDataView(isGF: isGF)
            }
        }
    }

    // MARK: - Selection Confirmation View

    private func selectionConfirmationView(isGF: Bool) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Success indicator
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Selection Complete")
                    .font(.headline)

                // Selected values display
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Product Name:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(isGF ? gfProductName : nonGFProductName)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Price:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("$\(isGF ? gfPriceText : nonGFPriceText)")
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)

                // Size field (optional, manual entry)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Size (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., 500g, 16oz", text: isGF ? $gfSize : $nonGFSize)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

                // Action buttons
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
                            .background(Color.blue)
                            .cornerRadius(12)
                    }

                    Button {
                        // Clear selection and re-select
                        if isGF {
                            gfProductName = ""
                            gfPriceText = ""
                        } else {
                            nonGFProductName = ""
                            nonGFPriceText = ""
                        }
                    } label: {
                        Text("Re-select from OCR")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }

                    Button {
                        // Retake photo
                        if isGF {
                            gfProductName = ""
                            gfPriceText = ""
                            gfOCRObservations = []
                            currentStep = .captureGF
                        } else {
                            nonGFProductName = ""
                            nonGFPriceText = ""
                            nonGFOCRObservations = []
                            currentStep = .captureNonGF
                        }
                        showingScanner = true
                    } label: {
                        Text("Retake Photo")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .padding()
        }
    }

    // MARK: - No OCR Data View

    private func noOCRDataView(isGF: Bool) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("No Text Detected")
                .font(.headline)

            Text("The scan didn't detect readable text. You can retake the photo or enter details manually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    if isGF {
                        currentStep = .captureGF
                    } else {
                        currentStep = .captureNonGF
                    }
                    showingScanner = true
                } label: {
                    Label("Retake Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // Allow manual entry by navigating forward
                    // User can use the Library tab for full manual entry
                    if isGF {
                        currentStep = .captureNonGF
                        showingScanner = true
                    } else {
                        currentStep = .finalize
                    }
                } label: {
                    Text("Skip for Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .padding()
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

            // Extract selectable text observations
            let observations = (try? await OCRService.shared.extractSelectableText(from: image)) ?? []

            switch currentStep {
            case .captureGF:
                gfImage = image
                gfImageUUID = uuid
                gfOCRObservations = observations
                currentStep = .reviewGF

            case .captureNonGF:
                nonGFImage = image
                nonGFImageUUID = uuid
                nonGFOCRObservations = observations
                currentStep = .reviewNonGF

            default:
                break
            }

            isProcessingOCR = false
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
            gfOCRConfidence: 0.0, // No longer tracking confidence
            nonGFProductName: nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines),
            nonGFPrice: nonGFPrice,
            nonGFSize: nonGFSize.isEmpty ? nil : nonGFSize,
            nonGFImageUUID: nonGFImageUUID,
            nonGFOCRConfidence: 0.0, // No longer tracking confidence
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
