//
//  ConfidenceIndicatorView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI

/// Visual indicator for OCR confidence levels
///
/// Displays color-coded confidence feedback to help users verify OCR-extracted data:
/// - High confidence (≥0.85): Green checkmark
/// - Medium confidence (0.6-0.85): Yellow warning with "Please verify"
/// - Low confidence (<0.6): Red X with "Likely incorrect"
struct ConfidenceIndicatorView: View {

    // MARK: - Properties

    /// OCR confidence score (0.0 to 1.0)
    let confidence: Float

    /// Optional label to show alongside the indicator
    let label: String?

    /// Whether to show the info button
    let showInfo: Bool

    /// State for showing info popover
    @State private var showingInfo = false

    // MARK: - Initialization

    init(confidence: Float, label: String? = nil, showInfo: Bool = false) {
        self.confidence = confidence
        self.label = label
        self.showInfo = showInfo
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // Confidence icon and text
            HStack(spacing: 4) {
                Image(systemName: confidenceLevel.icon)
                    .foregroundStyle(confidenceLevel.color)
                    .font(.caption)

                if let message = confidenceLevel.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(confidenceLevel.color)
                }

                if let label = label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Info button
            if showInfo {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .popover(isPresented: $showingInfo) {
                    confidenceInfoView
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    // MARK: - Confidence Level

    private var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.85...1.0:
            return .high
        case 0.6..<0.85:
            return .medium
        case 0.0..<0.6:
            return .low
        default:
            return .low
        }
    }

    // MARK: - Info View

    private var confidenceInfoView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OCR Confidence")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                confidenceRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "High Confidence (85%+)",
                    description: "OCR is very confident. Data is likely correct."
                )

                confidenceRow(
                    icon: "exclamationmark.triangle.fill",
                    color: .yellow,
                    title: "Medium Confidence (60-85%)",
                    description: "OCR is uncertain. Please verify the data."
                )

                confidenceRow(
                    icon: "xmark.circle.fill",
                    color: .red,
                    title: "Low Confidence (<60%)",
                    description: "OCR struggled with this text. Likely incorrect - please edit."
                )
            }

            Text("Tip: You can always edit any field manually, regardless of confidence level.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: 300)
    }

    private func confidenceRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Confidence Level Enum

private enum ConfidenceLevel {
    case high
    case medium
    case low

    var icon: String {
        switch self {
        case .high:
            return "checkmark.circle.fill"
        case .medium:
            return "exclamationmark.triangle.fill"
        case .low:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .high:
            return .green
        case .medium:
            return .yellow
        case .low:
            return .red
        }
    }

    var message: String? {
        switch self {
        case .high:
            return nil // No message for high confidence
        case .medium:
            return "Please verify"
        case .low:
            return "Likely incorrect"
        }
    }

    var borderColor: Color {
        switch self {
        case .high:
            return .gray.opacity(0.3) // Normal border
        case .medium:
            return .yellow
        case .low:
            return .red
        }
    }

    var backgroundColor: Color? {
        switch self {
        case .high, .medium:
            return nil
        case .low:
            return .red.opacity(0.1)
        }
    }
}

// MARK: - Helper Extension

extension ConfidenceIndicatorView {
    /// Returns the border color for the given confidence level
    static func borderColor(for confidence: Float) -> Color {
        let level: ConfidenceLevel
        switch confidence {
        case 0.85...1.0:
            level = .high
        case 0.6..<0.85:
            level = .medium
        default:
            level = .low
        }
        return level.borderColor
    }

    /// Returns the background color for the given confidence level
    static func backgroundColor(for confidence: Float) -> Color? {
        let level: ConfidenceLevel
        switch confidence {
        case 0.85...1.0:
            level = .high
        case 0.6..<0.85:
            level = .medium
        default:
            level = .low
        }
        return level.backgroundColor
    }

    /// Returns true if the confidence requires user attention (medium or low)
    static func requiresAttention(for confidence: Float) -> Bool {
        return confidence < 0.85
    }
}

// MARK: - Preview

#Preview("High Confidence") {
    VStack(spacing: 20) {
        ConfidenceIndicatorView(confidence: 0.95)
        ConfidenceIndicatorView(confidence: 0.92, label: "Confidence: 92%")
        ConfidenceIndicatorView(confidence: 0.88, showInfo: true)
    }
    .padding()
}

#Preview("Medium Confidence") {
    VStack(spacing: 20) {
        ConfidenceIndicatorView(confidence: 0.75)
        ConfidenceIndicatorView(confidence: 0.65, label: "Confidence: 65%")
        ConfidenceIndicatorView(confidence: 0.70, showInfo: true)
    }
    .padding()
}

#Preview("Low Confidence") {
    VStack(spacing: 20) {
        ConfidenceIndicatorView(confidence: 0.45)
        ConfidenceIndicatorView(confidence: 0.30, label: "Confidence: 30%")
        ConfidenceIndicatorView(confidence: 0.55, showInfo: true)
    }
    .padding()
}
