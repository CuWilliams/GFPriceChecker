//
//  ProductCaptureFlowView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import GFCore
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
///
/// All of the flow's state and logic lives in `CaptureFlowViewModel`; this view
/// only draws it and routes taps back.
struct ProductCaptureFlowView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var viewModel = CaptureFlowViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content
                stepView

                // Loading overlay
                if viewModel.isProcessingOCR {
                    ocrLoadingOverlay
                }
            }
            .navigationTitle(viewModel.currentStep.title)
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
                    Task { await viewModel.handleScannedImage(image) }
                }
            }
            .onChange(of: viewModel.didSave) { _, saved in
                if saved { dismiss() }
            }
        }
    }

    // MARK: - Step Views

    @ViewBuilder
    private var stepView: some View {
        switch viewModel.currentStep {
        case .introduction:
            introductionView
        case .captureGF:
            capturePlaceholderView(productType: "Gluten-Free")
        case .selectGFRectangle:
            if let image = viewModel.gfImage {
                RectangleSelectorView(
                    image: image,
                    rectangles: viewModel.gfDetectedRectangles,
                    onRectangleSelected: { rectangle in
                        Task { await viewModel.handleRectangleSelection(rectangle, isGF: true) }
                    },
                    onSkip: {
                        Task { await viewModel.handleSkipRectangleSelection(isGF: true) }
                    }
                )
            }
        case .reviewGF:
            reviewView(isGF: true)
        case .captureNonGF:
            capturePlaceholderView(productType: "Regular")
        case .selectNonGFRectangle:
            if let image = viewModel.nonGFImage {
                RectangleSelectorView(
                    image: image,
                    rectangles: viewModel.nonGFDetectedRectangles,
                    onRectangleSelected: { rectangle in
                        Task { await viewModel.handleRectangleSelection(rectangle, isGF: false) }
                    },
                    onSkip: {
                        Task { await viewModel.handleSkipRectangleSelection(isGF: false) }
                    }
                )
            }
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
                viewModel.startCapture()
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
    }

    // MARK: - Review View

    /// Single-screen guided review: name → price → size in one uninterrupted pass
    ///
    /// The selector stays mounted for all three phases so the scan results never
    /// disappear mid-review. `reviewToken` gives each fresh scan a new identity,
    /// which resets the selector's phase when the user retakes a photo or moves
    /// on to the regular product.
    @ViewBuilder
    private func reviewView(isGF: Bool) -> some View {
        let observations = isGF ? viewModel.gfOCRObservations : viewModel.nonGFOCRObservations
        let image = isGF ? viewModel.gfImage : viewModel.nonGFImage

        if let image = image, !observations.isEmpty {
            OCRTextSelectorView(
                image: image,
                observations: observations,
                productName: isGF ? $viewModel.gfProductName : $viewModel.nonGFProductName,
                priceText: isGF ? $viewModel.gfPriceText : $viewModel.nonGFPriceText,
                sizeMode: isGF ? $viewModel.gfSizeMode : $viewModel.nonGFSizeMode,
                sizeText: isGF ? $viewModel.gfSizeText : $viewModel.nonGFSizeText,
                unitPriceText: isGF ? $viewModel.gfUnitPriceText : $viewModel.nonGFUnitPriceText,
                unitPriceBasis: isGF ? $viewModel.gfUnitPriceBasis : $viewModel.nonGFUnitPriceBasis,
                selectedUnit: $viewModel.selectedUnit,
                selectedSizeObservationID: isGF ? viewModel.gfSelectedSizeObservationID : viewModel.nonGFSelectedSizeObservationID,
                onSizeRowTapped: { observation in
                    viewModel.handleSizeRowTap(observation, isGF: isGF)
                },
                continueTitle: isGF ? "Continue to Regular Product" : "Continue to Finalize",
                onContinue: {
                    viewModel.continueFromReview(isGF: isGF)
                },
                onRetake: {
                    viewModel.retake(isGF: isGF)
                }
            )
            .id(viewModel.reviewToken)
        } else {
            // Fallback: No OCR data, show manual entry prompt
            noOCRDataView(isGF: isGF)
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
                    viewModel.retakeAfterNoText(isGF: isGF)
                } label: {
                    Label("Retake Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // Allow manual entry by navigating forward
                    // User can use the Library tab for full manual entry
                    viewModel.skipProduct(isGF: isGF)
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
                    productSummary(
                        title: "Gluten-Free",
                        image: viewModel.gfImage,
                        name: viewModel.gfProductName,
                        price: viewModel.gfPrice,
                        priceColor: .green,
                        sizeMode: viewModel.gfSizeMode,
                        sizeText: viewModel.gfSizeText,
                        unitPriceText: viewModel.gfUnitPriceText
                    )

                    productSummary(
                        title: "Regular",
                        image: viewModel.nonGFImage,
                        name: viewModel.nonGFProductName,
                        price: viewModel.nonGFPrice,
                        priceColor: .blue,
                        sizeMode: viewModel.nonGFSizeMode,
                        sizeText: viewModel.nonGFSizeText,
                        unitPriceText: viewModel.nonGFUnitPriceText
                    )
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Differential
                if let differential = viewModel.packagePriceDifferential {
                    VStack(spacing: 4) {
                        Text("Package Price Differential")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(differential.formatted(.cad))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(differential >= 0 ? .red : .green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }

                // Size-adjusted differential preview — same back-calculation the save uses
                if let normDiff = viewModel.normalizedDifferential {
                    VStack(spacing: 4) {
                        Text("Size-Adjusted Differential")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(normDiff.formatted(.cad))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(normDiff >= 0 ? .orange : .green)
                        Text("Accounts for package size difference")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Size-adjusted differential: \(normDiff.formatted(.cad)). This accounts for the difference in package sizes.")
                }

                // Category
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Category", selection: $viewModel.category) {
                        ForEach(CaptureFlowViewModel.categoryOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Product category")
                    .accessibilityHint("Choose a category to organise your products")
                }

                // Notes
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $viewModel.notes)
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }

                // Save Button
                Button {
                    viewModel.save(into: modelContext)
                } label: {
                    HStack {
                        if viewModel.isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(viewModel.isSaving ? "Saving..." : "Save Product Pair")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isSaving ? Color.gray : Color.green)
                    .cornerRadius(12)
                }
                .disabled(viewModel.isSaving)
            }
            .padding()
        }
    }

    /// One half of the side-by-side comparison on the finalize screen
    private func productSummary(
        title: String,
        image: UIImage?,
        name: String,
        price: Decimal?,
        priceColor: Color,
        sizeMode: SizeInputMode,
        sizeText: String,
        unitPriceText: String
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .cornerRadius(8)
            }

            Text(name)
                .font(.caption)
                .lineLimit(2)

            if let price = price {
                Text(price.formatted(.cad))
                    .font(.headline)
                    .foregroundStyle(priceColor)
            }

            if let unit = viewModel.selectedUnit {
                Group {
                    if sizeMode == .packageSize, !sizeText.isEmpty {
                        Text("\(sizeText) \(unit.displayName)")
                    } else if sizeMode != .packageSize, !unitPriceText.isEmpty {
                        Text("$\(unitPriceText)/\(unit.displayName)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
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
}

#if DEBUG
// MARK: - Preview

#Preview {
    ProductCaptureFlowView()
        .modelContainer(for: [ProductPair.self], inMemory: true)
}
#endif
