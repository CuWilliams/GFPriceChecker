//
//  OCRTextSelectorView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-01-09.
//

import SwiftUI
import UIKit

/// Selection phase for the two-step selection workflow
private enum SelectionPhase {
    case selectingName
    case selectingPrice
    case complete
}

/// A view that displays OCR text observations and allows tap-to-select
///
/// Supports two selection modes:
/// - Product capture: User selects product name, then price
/// - Receipt verification: User confirms or changes a suggested match
struct OCRTextSelectorView: View {

    // MARK: - Properties

    /// The scanned image to display as reference
    let image: UIImage

    /// OCR text observations to display
    let observations: [SelectableTextObservation]

    /// Callback when selection is complete (name, price as string)
    let onSelectionComplete: (String, String) -> Void

    /// Optional: Pre-selected name (for receipt verification mode)
    var suggestedName: String?

    // MARK: - State

    @State private var selectionPhase: SelectionPhase = .selectingName
    @State private var selectedNameObservation: SelectableTextObservation?
    @State private var selectedPriceObservation: SelectableTextObservation?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // Instructions header
            instructionsHeader

            // Selected values display
            selectedValuesDisplay

            // Scanned image thumbnail
            imageThumbnail

            // OCR text list (scrollable)
            ocrTextList

            // Action buttons
            actionButtons
        }
        .padding()
    }

    // MARK: - View Components

    private var instructionsHeader: some View {
        Text(instructionText)
            .font(.headline)
            .foregroundColor(instructionColor)
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
    }

    private var selectedValuesDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: selectedNameObservation != nil ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedNameObservation != nil ? .green : .gray)
                Text("Name: ")
                    .fontWeight(.semibold)
                Text(selectedNameObservation?.text ?? "(not selected)")
                    .foregroundColor(selectedNameObservation != nil ? .primary : .secondary)
                Spacer()
            }

            HStack {
                Image(systemName: selectedPriceObservation != nil ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedPriceObservation != nil ? .green : .gray)
                Text("Price: ")
                    .fontWeight(.semibold)
                Text(extractedPriceText)
                    .foregroundColor(selectedPriceObservation != nil ? .primary : .secondary)
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
    }

    private var ocrTextList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(observations) { observation in
                    observationRow(observation)
                }
            }
        }
        .frame(maxHeight: 300)
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

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Clear Selection") {
                clearSelection()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Clear selection")
            .accessibilityHint("Resets name and price selections")

            Button("Confirm") {
                confirmSelection()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canConfirm)
            .accessibilityLabel("Confirm selection")
            .accessibilityHint("Confirms the selected product name and price")
        }
    }

    // MARK: - Computed Properties

    private var instructionText: String {
        switch selectionPhase {
        case .selectingName:
            return "Tap the product name"
        case .selectingPrice:
            return "Now tap the price"
        case .complete:
            return "Selection complete"
        }
    }

    private var instructionColor: Color {
        switch selectionPhase {
        case .selectingName:
            return .blue
        case .selectingPrice:
            return .green
        case .complete:
            return .primary
        }
    }

    private var extractedPriceText: String {
        guard let priceObs = selectedPriceObservation else {
            return "(not selected)"
        }
        return extractPrice(from: priceObs.text)
    }

    private var canConfirm: Bool {
        selectedNameObservation != nil && selectedPriceObservation != nil
    }

    // MARK: - Helper Methods

    private func backgroundColor(for observation: SelectableTextObservation) -> Color {
        // Check if this is the selected name
        if let selectedName = selectedNameObservation,
           selectedName.id == observation.id {
            return Color.blue.opacity(0.3)
        }

        // Check if this is the selected price
        if let selectedPrice = selectedPriceObservation,
           selectedPrice.id == observation.id {
            return Color.green.opacity(0.3)
        }

        // Check if this matches the suggested name
        if let suggested = suggestedName,
           observation.text.localizedCaseInsensitiveContains(suggested) {
            return Color.yellow.opacity(0.3)
        }

        return Color(.systemBackground)
    }

    private func handleObservationTap(_ observation: SelectableTextObservation) {
        switch selectionPhase {
        case .selectingName:
            selectedNameObservation = observation
            selectionPhase = .selectingPrice

        case .selectingPrice:
            selectedPriceObservation = observation
            selectionPhase = .complete

        case .complete:
            // Taps do nothing in complete phase
            break
        }
    }

    private func clearSelection() {
        selectedNameObservation = nil
        selectedPriceObservation = nil
        selectionPhase = .selectingName
    }

    private func confirmSelection() {
        guard let name = selectedNameObservation?.text,
              let priceObs = selectedPriceObservation else {
            return
        }

        let price = extractPrice(from: priceObs.text)
        onSelectionComplete(name, price)
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
        case .complete:
            return observation.text
        }
    }

    private func accessibilityHint(for observation: SelectableTextObservation) -> String {
        switch selectionPhase {
        case .selectingName:
            return "Double tap to select this as the product name"
        case .selectingPrice:
            return "Double tap to select this as the price"
        case .complete:
            return ""
        }
    }
}

// MARK: - Preview

#Preview("Initial State") {
    OCRTextSelectorView(
        image: createSampleImage(),
        observations: createSampleObservations(),
        onSelectionComplete: { name, price in
            print("Selected - Name: \(name), Price: \(price)")
        }
    )
}

#Preview("With Suggested Name") {
    OCRTextSelectorView(
        image: createSampleImage(),
        observations: createSampleObservations(),
        onSelectionComplete: { name, price in
            print("Selected - Name: \(name), Price: \(price)")
        },
        suggestedName: "Organic Bananas"
    )
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
            text: "Fresh Produce",
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
