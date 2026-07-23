//
//  OCRTextSelectorView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-01-09.
//

import SwiftUI
import UIKit

/// Selection phase for the three-step selection workflow
private enum SelectionPhase {
    case selectingName
    case selectingPrice
    case selectingSize
    case complete

    /// 1-based step number for the progress indicator
    var stepNumber: Int {
        switch self {
        case .selectingName: return 1
        case .selectingPrice: return 2
        case .selectingSize, .complete: return 3
        }
    }
}

/// A view that displays OCR text observations and allows tap-to-select
///
/// Guides the user through a single uninterrupted product verification pass:
/// name → price → size. The observation list stays on screen for all three
/// phases and simply retargets which field a tap populates, so the review
/// never swaps out from under the user.
///
/// Size entry is optional — the user can skip it and continue.
struct OCRTextSelectorView: View {

    // MARK: - Properties

    /// The scanned image to display as reference
    let image: UIImage

    /// OCR text observations to display
    let observations: [SelectableTextObservation]

    /// Selected product name (owned by the capture flow)
    @Binding var productName: String

    /// Selected price as a plain decimal string, no currency symbol
    @Binding var priceText: String

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

    /// Observation currently feeding the size field, for highlight tracking
    let selectedSizeObservationID: UUID?

    /// Called when a row is tapped during the size phase
    ///
    /// The capture flow parses the row and routes it to the correct field
    /// based on the active size mode.
    let onSizeRowTapped: (SelectableTextObservation) -> Void

    /// Title for the primary advance button (varies by product step)
    let continueTitle: String

    /// Advances the capture flow to the next step
    let onContinue: () -> Void

    /// Discards this capture and returns to the scanner
    let onRetake: () -> Void

    // MARK: - State

    @State private var selectionPhase: SelectionPhase = .selectingName
    @State private var selectedNameObservationID: UUID?
    @State private var selectedPriceObservationID: UUID?

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
                if selectionPhase == .selectingSize || selectionPhase == .complete {
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
            Text("Step \(selectionPhase.stepNumber) of 3")
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
        .accessibilityLabel("Step \(selectionPhase.stepNumber) of 3. \(instructionText)")
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

            if selectionPhase == .selectingSize {
                Button("Skip Size") {
                    selectionPhase = .complete
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Skip size")
                .accessibilityHint("Continues without recording a package size")
            }

            HStack(spacing: 12) {
                Button("Clear Selections") {
                    clearSelection()
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
        switch selectionPhase {
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
        switch selectionPhase {
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
        switch selectionPhase {
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
            return selectionPhase == .complete ? "(skipped)" : "(not selected)"
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
        switch selectionPhase {
        case .selectingName:
            productName = observation.text
            selectedNameObservationID = observation.id
            selectionPhase = .selectingPrice

        case .selectingPrice:
            // Check if we should infer decimal placement
            if shouldInferDecimal(for: observation.text) {
                // Store pending observation and show confirmation alert
                pendingPriceObservation = observation
                originalPrice = observation.text
                suggestedDecimalPrice = suggestDecimalPlacement(for: observation.text)
                showingDecimalConfirmation = true
            } else {
                // Normal price selection
                priceText = extractPrice(from: observation.text)
                selectedPriceObservationID = observation.id
                selectionPhase = .selectingSize
            }

        case .selectingSize, .complete:
            // Stay in phase so the user can retap a different row
            onSizeRowTapped(observation)
        }
    }

    private func clearSelection() {
        productName = ""
        priceText = ""
        sizeText = ""
        unitPriceText = ""
        sizeMode = .packageSize
        unitPriceBasis = .cents
        selectedNameObservationID = nil
        selectedPriceObservationID = nil
        selectionPhase = .selectingName
    }

    /// Extracts price from text using regex pattern
    /// - Parameter text: The text to extract price from
    /// - Returns: Extracted price string, or full text if no pattern found
    private func extractPrice(from text: String) -> String {
        // Pattern: Optional $, 1-3 digits, dot, 2 digits
        let pattern = #"\$?\d{1,3}\.\d{2}"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let matchRange = Range(match.range, in: text) {
                let priceString = String(text[matchRange])
                // Remove $ if present
                return priceString.replacingOccurrences(of: "$", with: "")
            }
        }

        // If no pattern found, return full text
        return text
    }

    private func accessibilityLabel(for observation: SelectableTextObservation) -> String {
        switch selectionPhase {
        case .selectingName:
            return "Select \(observation.text) as product name"
        case .selectingPrice:
            return "Select \(observation.text) as price"
        case .selectingSize, .complete:
            return "Select \(observation.text) for size"
        }
    }

    private func accessibilityHint(for observation: SelectableTextObservation) -> String {
        switch selectionPhase {
        case .selectingName:
            return "Double tap to select this as the product name"
        case .selectingPrice:
            return "Double tap to select this as the price"
        case .selectingSize, .complete:
            return "Double tap to populate the size field below based on the current mode"
        }
    }

    // MARK: - Decimal Inference Helpers

    /// Checks if a text value should trigger decimal inference
    /// - Parameter text: The text to check
    /// - Returns: true if text is 3+ consecutive digits without decimal point
    private func shouldInferDecimal(for text: String) -> Bool {
        // Remove whitespace and extract numeric part
        let cleaned = text.trimmingCharacters(in: .whitespaces)

        // Pattern: 3 or more consecutive digits, no decimal point
        let pattern = #"^\d{3,}$"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            return regex.firstMatch(in: cleaned, options: [], range: range) != nil
        }

        return false
    }

    /// Suggests decimal placement for a numeric string
    /// - Parameter text: The numeric text (e.g., "999", "1299")
    /// - Returns: Suggested price with decimal (e.g., "$9.99", "$12.99")
    private func suggestDecimalPlacement(for text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespaces)

        // Insert decimal point before last 2 digits
        if cleaned.count >= 3 {
            let endIndex = cleaned.index(cleaned.endIndex, offsetBy: -2)
            let dollars = String(cleaned[..<endIndex])
            let cents = String(cleaned[endIndex...])
            return "$\(dollars).\(cents)"
        }

        // Fallback: just add $
        return "$\(cleaned)"
    }

    /// User accepted the suggested decimal placement
    private func acceptSuggestedDecimal() {
        guard let pending = pendingPriceObservation else { return }

        priceText = extractPrice(from: suggestedDecimalPrice)
        selectedPriceObservationID = pending.id
        selectionPhase = .selectingSize

        resetPendingPriceState()
    }

    /// User chose to use the original price without decimal inference
    private func useOriginalPrice() {
        guard let pending = pendingPriceObservation else { return }

        priceText = extractPrice(from: pending.text)
        selectedPriceObservationID = pending.id
        selectionPhase = .selectingSize

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
    @State private var productName = ""
    @State private var priceText = ""
    @State private var sizeMode: SizeInputMode = .packageSize
    @State private var sizeText = ""
    @State private var unitPriceText = ""
    @State private var unitPriceBasis: UnitPriceBasis = .cents
    @State private var selectedUnit: SizeUnit?
    @State private var selectedSizeObservationID: UUID?

    let observations = createSampleObservations()

    var body: some View {
        OCRTextSelectorView(
            image: createSampleImage(),
            observations: observations,
            productName: $productName,
            priceText: $priceText,
            sizeMode: $sizeMode,
            sizeText: $sizeText,
            unitPriceText: $unitPriceText,
            unitPriceBasis: $unitPriceBasis,
            selectedUnit: $selectedUnit,
            selectedSizeObservationID: selectedSizeObservationID,
            onSizeRowTapped: { observation in
                sizeText = observation.text
                selectedSizeObservationID = observation.id
            },
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
