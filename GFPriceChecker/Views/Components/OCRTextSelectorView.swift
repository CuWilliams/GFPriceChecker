//
//  OCRTextSelectorView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-01-09.
//

import GFCore
import SwiftUI
import UIKit

/// A view that displays OCR text observations and allows tap-to-select
///
/// Guides the user through a single uninterrupted product verification pass:
/// name → price → size. The observation list stays on screen for all three
/// phases and simply retargets which field a tap populates, so the review
/// never swaps out from under the user.
///
/// Size entry is optional — the user can skip it and continue.
///
/// Which phase the review is in, and which rows are chosen, belong to
/// `CaptureFlowViewModel`; this view draws them and sends taps back. Only the
/// decimal-placement question is its own, because it is presentation.
struct OCRTextSelectorView: View {

    // MARK: - Properties

    /// The scanned image to display as reference
    let image: UIImage

    /// OCR text observations to display
    let observations: [SelectableTextObservation]

    /// Selected product name (owned by the capture flow)
    let productName: String

    /// Selected price as a plain decimal string, no currency symbol
    let priceText: String

    /// How the user is entering size: package size, unit price, or manual
    @Binding var sizeMode: SizeInputMode

    /// Numeric package size, used in `.packageSize` mode
    @Binding var sizeText: String

    /// Unit price, used in `.unitPrice` and `.manual` modes
    @Binding var unitPriceText: String

    /// Whether the entered unit price is in cents or dollars
    @Binding var unitPriceBasis: UnitPriceBasis

    /// Shared unit of measurement for both products in the pair
    @Binding var selectedUnit: SizeUnit?

    /// Where the review is in its name → price → size pass
    let phase: ReviewPhase

    /// Observations chosen for each field, for highlight tracking
    let selectedNameObservationID: UUID?
    let selectedPriceObservationID: UUID?
    let selectedSizeObservationID: UUID?

    /// Called when a row is tapped. The capture flow routes it by phase, and
    /// returns a suggested price when the row needs the decimal question asked.
    let onRowTapped: (SelectableTextObservation) -> String?

    /// Called with the price row and the text the user chose for it, once the
    /// decimal question is answered
    let onPriceConfirmed: (SelectableTextObservation, String) -> Void

    /// Ends the review without a size
    let onSkipSize: () -> Void

    /// Resets name, price and size
    let onClear: () -> Void

    /// Title for the primary advance button (varies by product step)
    let continueTitle: String

    /// Advances the capture flow to the next step
    let onContinue: () -> Void

    /// Discards this capture and returns to the scanner
    let onRetake: () -> Void

    // MARK: - State

    // Decimal inference state
    @State private var showingDecimalConfirmation = false
    @State private var pendingPriceObservation: SelectableTextObservation?
    @State private var suggestedDecimalPrice: String = ""
    @State private var originalPrice: String = ""

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Instructions header
                instructionsHeader

                // Selected values display
                selectedValuesDisplay

                // Scanned image thumbnail
                imageThumbnail

                // OCR text list
                ocrTextList

                // Size entry controls (third phase only)
                if phase == .selectingSize || phase == .complete {
                    sizeInputCard
                }

                // Action buttons
                actionButtons
            }
            .padding()
        }
        .alert("Decimal Placement", isPresented: $showingDecimalConfirmation) {
            Button("Use \(suggestedDecimalPrice)") {
                acceptSuggestedDecimal()
            }
            Button("Use \(originalPrice)") {
                useOriginalPrice()
            }
            Button("Cancel", role: .cancel) {
                cancelPriceSelection()
            }
        } message: {
            Text("The selected value '\(originalPrice)' has no decimal point. Did you mean '\(suggestedDecimalPrice)'?")
        }
    }

    // MARK: - View Components

    private var instructionsHeader: some View {
        VStack(spacing: 4) {
            Text("Step \(phase.stepNumber) of 3")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(instructionText)
                .font(.headline)
                .foregroundColor(instructionColor)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(phase.stepNumber) of 3. \(instructionText)")
    }

    private var selectedValuesDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: productName.isEmpty ? "circle" : "checkmark.circle.fill")
                    .foregroundColor(productName.isEmpty ? .gray : .green)
                Text("Name: ")
                    .fontWeight(.semibold)
                Text(productName.isEmpty ? "(not selected)" : productName)
                    .foregroundColor(productName.isEmpty ? .secondary : .primary)
                Spacer()
            }

            HStack {
                Image(systemName: priceText.isEmpty ? "circle" : "checkmark.circle.fill")
                    .foregroundColor(priceText.isEmpty ? .gray : .green)
                Text("Price: ")
                    .fontWeight(.semibold)
                Text(priceText.isEmpty ? "(not selected)" : "$\(priceText)")
                    .foregroundColor(priceText.isEmpty ? .secondary : .primary)
                Spacer()
            }

            HStack {
                Image(systemName: hasSizeEntry ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(hasSizeEntry ? .green : .gray)
                Text("Size: ")
                    .fontWeight(.semibold)
                Text(sizeSummaryText)
                    .foregroundColor(hasSizeEntry ? .primary : .secondary)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private var imageThumbnail: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 150)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .accessibilityHidden(true)
    }

    private var ocrTextList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scan Results")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(listHintText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 4) {
                ForEach(observations) { observation in
                    observationRow(observation)
                }
            }
        }
    }

    private func observationRow(_ observation: SelectableTextObservation) -> some View {
        Button {
            handleObservationTap(observation)
        } label: {
            HStack {
                Text(observation.text)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text("\(Int(observation.confidence * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(minHeight: 44)
            .background(backgroundColor(for: observation))
            .cornerRadius(8)
        }
        .accessibilityLabel(accessibilityLabel(for: observation))
        .accessibilityHint(accessibilityHint(for: observation))
    }

    /// Size entry controls, shown once name and price are confirmed
    private var sizeInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Package Size")
                .font(.headline)

            Picker("Size Entry Mode", selection: $sizeMode) {
                ForEach(SizeInputMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Size entry mode")
            .accessibilityHint("Choose how to enter the package size")

            if sizeMode == .packageSize {
                TextField("Size (e.g. 400)", text: $sizeText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("Package size")
                    .accessibilityHint("Enter the numeric size value, for example 400")
            } else {
                TextField("Unit price (e.g. 1.49)", text: $unitPriceText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("Unit price")
                    .accessibilityHint("Enter the price per unit shown on the shelf tag")
                Text("App calculates size from price ÷ unit price.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Currency basis picker — only shown in unit price / manual modes
                HStack {
                    Text("Value basis")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("Unit price basis", selection: $unitPriceBasis) {
                        ForEach(UnitPriceBasis.allCases, id: \.self) { basis in
                            Text(basis.rawValue).tag(basis)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                    .accessibilityLabel("Unit price currency basis")
                    .accessibilityHint("Choose whether the unit price is in cents or dollars")
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            HStack {
                Text("Unit")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Unit", selection: $selectedUnit) {
                    Text("Not specified").tag(Optional<SizeUnit>.none)
                    ForEach(SizeUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(Optional<SizeUnit>.some(unit))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Package size unit")
                .accessibilityHint("Choose the unit of measurement for both products")
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                onContinue()
            } label: {
                Text(continueTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canContinue ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!canContinue)
            .accessibilityLabel(continueTitle)
            .accessibilityHint(canContinue
                ? "Continues to the next step"
                : "Select a product name and price first")

            if phase == .selectingSize {
                Button("Skip Size") {
                    onSkipSize()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Skip size")
                .accessibilityHint("Continues without recording a package size")
            }

            HStack(spacing: 12) {
                Button("Clear Selections") {
                    onClear()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Clear selections")
                .accessibilityHint("Resets name, price, and size selections")

                Button("Retake Photo") {
                    onRetake()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Retake photo")
                .accessibilityHint("Discards this scan and opens the camera again")
            }
        }
    }

    // MARK: - Computed Properties

    private var instructionText: String {
        switch phase {
        case .selectingName:
            return "Tap the product name"
        case .selectingPrice:
            return "Now tap the price"
        case .selectingSize:
            return "Now tap the size, or skip it"
        case .complete:
            return "Review complete"
        }
    }

    private var instructionColor: Color {
        switch phase {
        case .selectingName:
            return .blue
        case .selectingPrice:
            return .green
        case .selectingSize:
            return .orange
        case .complete:
            return .primary
        }
    }

    private var listHintText: String {
        switch phase {
        case .selectingName:
            return "Tap a row to set the name"
        case .selectingPrice:
            return "Tap a row to set the price"
        case .selectingSize:
            return "Tap a row to set the size"
        case .complete:
            return "Tap a row to change the size"
        }
    }

    /// True when the user has entered a size in whichever mode is active
    private var hasSizeEntry: Bool {
        sizeMode == .packageSize ? !sizeText.isEmpty : !unitPriceText.isEmpty
    }

    /// Human-readable summary of the current size entry
    private var sizeSummaryText: String {
        guard hasSizeEntry else {
            return phase == .complete ? "(skipped)" : "(not selected)"
        }

        let unitLabel = selectedUnit?.displayName ?? ""
        if sizeMode == .packageSize {
            return "\(sizeText) \(unitLabel)".trimmingCharacters(in: .whitespaces)
        }

        let symbol = unitPriceBasis == .cents ? "¢" : "$"
        return unitLabel.isEmpty
            ? "\(symbol)\(unitPriceText) per unit"
            : "\(symbol)\(unitPriceText) per \(unitLabel)"
    }

    /// Size is optional, so only name and price gate the advance
    private var canContinue: Bool {
        !productName.isEmpty && !priceText.isEmpty
    }

    // MARK: - Helper Methods

    private func backgroundColor(for observation: SelectableTextObservation) -> Color {
        // Check if this is the selected name
        if selectedNameObservationID == observation.id {
            return Color.blue.opacity(0.3)
        }

        // Check if this is the selected price
        if selectedPriceObservationID == observation.id {
            return Color.green.opacity(0.3)
        }

        // Check if this is the row feeding the size field
        if selectedSizeObservationID == observation.id {
            return Color.orange.opacity(0.3)
        }

        return Color(.systemBackground)
    }

    private func handleObservationTap(_ observation: SelectableTextObservation) {
        guard let suggestion = onRowTapped(observation) else { return }
        // A price row with no decimal point: ask before setting it
        pendingPriceObservation = observation
        originalPrice = observation.text
        suggestedDecimalPrice = suggestion
        showingDecimalConfirmation = true
    }

    private func accessibilityLabel(for observation: SelectableTextObservation) -> String {
        switch phase {
        case .selectingName:
            return "Select \(observation.text) as product name"
        case .selectingPrice:
            return "Select \(observation.text) as price"
        case .selectingSize, .complete:
            return "Select \(observation.text) for size"
        }
    }

    private func accessibilityHint(for observation: SelectableTextObservation) -> String {
        switch phase {
        case .selectingName:
            return "Double tap to select this as the product name"
        case .selectingPrice:
            return "Double tap to select this as the price"
        case .selectingSize, .complete:
            return "Double tap to populate the size field below based on the current mode"
        }
    }

    // MARK: - Decimal Inference Helpers

    /// User accepted the suggested decimal placement
    private func acceptSuggestedDecimal() {
        guard let pending = pendingPriceObservation else { return }
        onPriceConfirmed(pending, suggestedDecimalPrice)
        resetPendingPriceState()
    }

    /// User chose to use the original price without decimal inference
    private func useOriginalPrice() {
        guard let pending = pendingPriceObservation else { return }
        onPriceConfirmed(pending, pending.text)
        resetPendingPriceState()
    }

    /// User cancelled the price selection — stay in the price phase
    private func cancelPriceSelection() {
        resetPendingPriceState()
    }

    private func resetPendingPriceState() {
        pendingPriceObservation = nil
        suggestedDecimalPrice = ""
        originalPrice = ""
    }
}

#if DEBUG
// MARK: - Preview

private struct OCRTextSelectorPreviewHost: View {
    @State private var viewModel: CaptureFlowViewModel = {
        let viewModel = CaptureFlowViewModel()
        viewModel.gfOCRObservations = createSampleObservations()
        return viewModel
    }()

    var body: some View {
        OCRTextSelectorView(
            image: createSampleImage(),
            observations: viewModel.gfOCRObservations,
            productName: viewModel.gfProductName,
            priceText: viewModel.gfPriceText,
            sizeMode: $viewModel.gfSizeMode,
            sizeText: $viewModel.gfSizeText,
            unitPriceText: $viewModel.gfUnitPriceText,
            unitPriceBasis: $viewModel.gfUnitPriceBasis,
            selectedUnit: $viewModel.selectedUnit,
            phase: viewModel.gfReviewPhase,
            selectedNameObservationID: viewModel.gfSelectedNameObservationID,
            selectedPriceObservationID: viewModel.gfSelectedPriceObservationID,
            selectedSizeObservationID: viewModel.gfSelectedSizeObservationID,
            onRowTapped: { viewModel.handleReviewTap($0, isGF: true) },
            onPriceConfirmed: { viewModel.confirmPrice($0, text: $1, isGF: true) },
            onSkipSize: { viewModel.skipSize(isGF: true) },
            onClear: { viewModel.resetProductFields(isGF: true) },
            continueTitle: "Continue to Regular Product",
            onContinue: { print("Continue tapped") },
            onRetake: { print("Retake tapped") }
        )
    }
}

#Preview("Guided Selection") {
    OCRTextSelectorPreviewHost()
}

// MARK: - Preview Helpers

private func createSampleImage() -> UIImage {
    // Create a simple colored image for preview
    let size = CGSize(width: 200, height: 100)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    UIColor.systemBlue.withAlphaComponent(0.2).setFill()
    UIRectFill(CGRect(origin: .zero, size: size))
    let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    UIGraphicsEndImageContext()
    return image
}

private func createSampleObservations() -> [SelectableTextObservation] {
    [
        SelectableTextObservation(
            text: "WHOLE FOODS MARKET",
            boundingBox: CGRect(x: 0.2, y: 0.9, width: 0.6, height: 0.05),
            confidence: 0.95
        ),
        SelectableTextObservation(
            text: "Organic Bananas",
            boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.06),
            confidence: 0.92
        ),
        SelectableTextObservation(
            text: "$3.99",
            boundingBox: CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.06),
            confidence: 0.98
        ),
        SelectableTextObservation(
            text: "400g",
            boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.4, height: 0.05),
            confidence: 0.88
        ),
        SelectableTextObservation(
            text: "Per lb",
            boundingBox: CGRect(x: 0.7, y: 0.6, width: 0.2, height: 0.04),
            confidence: 0.85
        ),
        SelectableTextObservation(
            text: "Item #12345",
            boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.04),
            confidence: 0.90
        )
    ]
}
#endif
