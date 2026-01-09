//
//  OCRService.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation
import Vision
import UIKit
import VisionKit
import SwiftUI

/// Quality classification for price detection confidence
enum PriceQuality {
    case high    // ≥ 0.85 confidence
    case medium  // 0.60 - 0.85 confidence
    case low     // < 0.60 confidence

    init(confidence: Float) {
        if confidence >= 0.85 {
            self = .high
        } else if confidence >= 0.6 {
            self = .medium
        } else {
            self = .low
        }
    }
}

/// Result of price detection from OCR
struct PriceMatch {
    /// The detected price amount
    let amount: Decimal

    /// OCR confidence score (0.0 to 1.0)
    let confidence: Float

    /// Bounding box of the detected price in normalized coordinates
    let boundingBox: CGRect

    /// Estimated font size based on bounding box height
    let fontSize: CGFloat

    /// Vertical position in image (0.0 = bottom, 1.0 = top)
    let verticalPosition: CGFloat

    /// Whether the price had a "$" prefix
    let hasPrefix: Bool

    /// Quality classification based on overall confidence
    var quality: PriceQuality {
        PriceQuality(confidence: confidence)
    }

    /// Composite score for ranking price candidates
    /// Higher score = more likely to be the actual product price
    var rankingScore: Float {
        // Normalize fontSize (assume typical range 0.01-0.15 in normalized coords)
        let fontSizeNormalized = min(Float(fontSize) / 0.15, 1.0)

        // Vertical position score (higher on image = higher score)
        let positionScore = Float(verticalPosition)

        // Weighted scoring algorithm:
        // - Font size (50%): Larger text is typically the price
        // - Vertical position (30%): Prices are usually in top-center
        // - Has prefix (10%): "$" is a tiebreaker
        // - OCR confidence (10%): Trust the OCR accuracy
        let score = (fontSizeNormalized * 0.5) +
                    (positionScore * 0.3) +
                    (hasPrefix ? 0.1 : 0.0) +
                    (confidence * 0.1)

        return score
    }
}

/// Represents a single text observation for UI display and selection
struct SelectableTextObservation: Identifiable {
    let id = UUID()
    /// The recognized text content
    let text: String
    /// Bounding box in normalized coordinates (0-1)
    let boundingBox: CGRect
    /// OCR confidence score (0.0 to 1.0)
    let confidence: Float
    /// Vertical position for sorting (higher = top of image)
    var verticalPosition: CGFloat {
        boundingBox.origin.y + boundingBox.height / 2
    }
}

/// Service for extracting text and data from product images using Vision framework
///
/// Provides OCR capabilities for:
/// - General text extraction
/// - Price detection with pattern matching
/// - Product name extraction from top region
@MainActor
final class OCRService {

    // MARK: - Singleton

    static let shared = OCRService()

    private init() {}

    // MARK: - Constants

    /// Minimum confidence threshold for text recognition
    private let minimumConfidence: Float = 0.5

    /// Minimum confidence for product name extraction
    private let productNameMinimumConfidence: Float = 0.7

    /// Percentage of image height to search for product names (top portion)
    private let productNameSearchArea: CGFloat = 0.3

    // MARK: - Public Methods

    /// Extracts all text from an image
    ///
    /// - Parameter image: The UIImage to extract text from
    /// - Returns: Array of text observations with bounding boxes
    /// - Throws: OCRError if recognition fails
    func extractText(from image: UIImage) async throws -> [VNRecognizedTextObservation] {
        print("🔍 OCRService: extractText called")

        guard let cgImage = image.cgImage else {
            print("🔍 OCRService: ERROR - cgImage is nil")
            throw OCRError.invalidImage
        }

        print("🔍 OCRService: cgImage obtained, size: \(cgImage.width)x\(cgImage.height)")

        return try await withCheckedThrowingContinuation { continuation in
            print("🔍 OCRService: Creating VNRecognizeTextRequest")

            let request = VNRecognizeTextRequest { request, error in
                print("🔍 OCRService: VNRecognizeTextRequest callback fired")

                if let error = error {
                    print("🔍 OCRService: ERROR in request - \(error)")
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    print("🔍 OCRService: ERROR - No observations or wrong type")
                    continuation.resume(throwing: OCRError.noTextDetected)
                    return
                }

                print("🔍 OCRService: Successfully got \(observations.count) observations")
                continuation.resume(returning: observations)
            }

            // Configure for accurate recognition
            print("🔍 OCRService: Configuring request")
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            print("🔍 OCRService: Creating VNImageRequestHandler")
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                print("🔍 OCRService: Performing Vision request...")
                try handler.perform([request])
                print("🔍 OCRService: Vision request performed (callback should fire)")
            } catch {
                print("🔍 OCRService: ERROR performing request - \(error)")
                continuation.resume(throwing: OCRError.recognitionFailed(error))
            }
        }
    }

    /// Finds prices in an image using pattern matching and spatial analysis
    ///
    /// Searches for common price formats with or without "$" prefix:
    /// - $X.XX, $XX.XX, $XXX.XX (with prefix)
    /// - X.XX, XX.XX, XXX.XX (without prefix)
    ///
    /// Uses spatial analysis to rank candidates:
    /// - Font size (larger = more likely actual price)
    /// - Vertical position (higher = more likely actual price)
    /// - Presence of "$" (tiebreaker)
    /// - OCR confidence
    ///
    /// - Parameter image: The UIImage to search for prices
    /// - Returns: Array of PriceMatch results sorted by ranking score (highest first)
    /// - Throws: OCRError if recognition fails
    func findPrices(in image: UIImage) async throws -> [PriceMatch] {
        print("🔍 DEBUG: findPrices() called")
        let observations = try await extractText(from: image)
        print("🔍 DEBUG: Got \(observations.count) text observations")

        var priceMatches: [PriceMatch] = []

        // Updated regex pattern: Optional $ prefix, then 1-3 digits, dot, 2 digits
        let pricePattern = #"\$?\d{1,3}\.\d{2}"#
        let regex = try NSRegularExpression(pattern: pricePattern, options: [])

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else {
                continue
            }

            let text = candidate.string
            let range = NSRange(text.startIndex..., in: text)

            // Find all price matches in this text observation
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                if let matchRange = Range(match.range, in: text) {
                    let priceString = String(text[matchRange])

                    // Check if price has "$" prefix
                    let hasPrefix = priceString.hasPrefix("$")

                    // Remove $ and convert to Decimal
                    let numberString = priceString.replacingOccurrences(of: "$", with: "")
                    if let amount = Decimal(string: numberString) {
                        // Calculate spatial features
                        let boundingBox = observation.boundingBox

                        // Font size estimate: height of bounding box in normalized coordinates
                        let fontSize = boundingBox.height

                        // Vertical position: center Y of bounding box
                        // Vision uses bottom-left origin: 0 = bottom, 1 = top
                        let verticalPosition = boundingBox.origin.y + (boundingBox.height / 2.0)

                        let priceMatch = PriceMatch(
                            amount: amount,
                            confidence: candidate.confidence,
                            boundingBox: boundingBox,
                            fontSize: fontSize,
                            verticalPosition: verticalPosition,
                            hasPrefix: hasPrefix
                        )

                        print("🔍 DEBUG: Found price: \(priceString) | Amount: \(amount) | Confidence: \(candidate.confidence) | FontSize: \(fontSize) | Y-Pos: \(verticalPosition) | HasPrefix: \(hasPrefix) | Score: \(priceMatch.rankingScore)")

                        priceMatches.append(priceMatch)
                    }
                }
            }
        }

        // Sort by ranking score (highest first)
        let sortedMatches = priceMatches.sorted { $0.rankingScore > $1.rankingScore }

        print("🔍 DEBUG: Total price candidates found: \(sortedMatches.count)")
        if let topCandidate = sortedMatches.first {
            print("🔍 DEBUG: Top candidate: $\(topCandidate.amount) (score: \(topCandidate.rankingScore), quality: \(topCandidate.quality))")
        }

        return sortedMatches
    }

    /// Extracts product name from the top portion of the image
    ///
    /// Product names are typically located in the top 30% of product labels.
    /// Returns the most prominent (longest) text string found in that region.
    ///
    /// - Parameter image: The UIImage to extract product name from
    /// - Returns: The detected product name, or nil if confidence is too low
    /// - Throws: OCRError if recognition fails
    func findProductName(in image: UIImage) async throws -> String? {
        let observations = try await extractText(from: image)

        var candidateNames: [(text: String, confidence: Float)] = []

        for observation in observations {
            // Only look at text in the top portion of the image
            // VisionKit uses bottom-left origin, so check if y + height > (1.0 - searchArea)
            let minY = 1.0 - productNameSearchArea
            if observation.boundingBox.origin.y < minY {
                continue
            }

            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= productNameMinimumConfidence else {
                continue
            }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)

            // Filter out very short strings (likely not product names)
            if text.count >= 3 {
                candidateNames.append((text: text, confidence: candidate.confidence))
            }
        }

        // Return the longest text with highest confidence
        // Prioritize length (product names are typically longer than other text)
        let sorted = candidateNames.sorted { first, second in
            if first.text.count != second.text.count {
                return first.text.count > second.text.count
            }
            return first.confidence > second.confidence
        }

        return sorted.first?.text
    }

    /// Extracts text observations for UI display and selection
    ///
    /// Returns individual text observations sorted top-to-bottom,
    /// suitable for rendering in a scrollable tap-to-select interface.
    ///
    /// - Parameter image: The UIImage to extract text from
    /// - Returns: Array of SelectableTextObservation sorted by vertical position (top first)
    /// - Throws: OCRError if recognition fails
    func extractSelectableText(from image: UIImage) async throws -> [SelectableTextObservation] {
        print("🔍 OCRService: extractSelectableText called")

        let observations = try await extractText(from: image)
        print("🔍 OCRService: Got \(observations.count) text observations for selection")

        var selectableObservations: [SelectableTextObservation] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else {
                continue
            }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty strings
            if text.isEmpty {
                continue
            }

            let selectable = SelectableTextObservation(
                text: text,
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence
            )

            selectableObservations.append(selectable)
        }

        // Sort by vertical position descending (top of image first)
        // Vision uses bottom-left origin, so higher y values are at top
        let sorted = selectableObservations.sorted { $0.verticalPosition > $1.verticalPosition }

        print("🔍 OCRService: Extracted \(sorted.count) selectable text observations")

        return sorted
    }

    // MARK: - Receipt-Specific OCR

    /// Extracts full text from a receipt image
    ///
    /// Returns all recognized text as a single string, preserving line breaks.
    /// Useful for receipt parsing where layout and structure matter.
    ///
    /// - Parameter image: The receipt image
    /// - Returns: Full text content with line breaks
    /// - Throws: OCRError if recognition fails
    func extractReceiptText(from image: UIImage) async throws -> String {
        print("🔍 OCRService: extractReceiptText called")
        print("🔍 OCRService: Image size: \(image.size)")

        let observations = try await extractText(from: image)
        print("🔍 OCRService: Got \(observations.count) text observations")

        // Sort observations by vertical position (top to bottom)
        // VisionKit uses bottom-left origin, so higher y values are at top
        let sortedObservations = observations.sorted { obs1, obs2 in
            // Compare y-coordinate (higher y = higher on page)
            obs1.boundingBox.origin.y > obs2.boundingBox.origin.y
        }

        var lines: [String] = []

        for observation in sortedObservations {
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else {
                continue
            }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append(text)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Extracts text from a specific region of the receipt
    ///
    /// Useful for targeted extraction (e.g., header, body, footer).
    ///
    /// - Parameters:
    ///   - image: The receipt image
    ///   - region: The region to extract from (.top, .middle, .bottom)
    /// - Returns: Text from the specified region
    /// - Throws: OCRError if recognition fails
    func extractReceiptText(from image: UIImage, region: ReceiptRegion) async throws -> String {
        let observations = try await extractText(from: image)

        var filteredObservations: [VNRecognizedTextObservation] = []

        for observation in observations {
            let yPosition = observation.boundingBox.origin.y

            switch region {
            case .top:
                // Top 25% of receipt (store name, date)
                if yPosition >= 0.75 {
                    filteredObservations.append(observation)
                }
            case .middle:
                // Middle 50% of receipt (line items)
                if yPosition >= 0.25 && yPosition < 0.75 {
                    filteredObservations.append(observation)
                }
            case .bottom:
                // Bottom 25% of receipt (totals)
                if yPosition < 0.25 {
                    filteredObservations.append(observation)
                }
            }
        }

        // Sort by vertical position
        let sortedObservations = filteredObservations.sorted { obs1, obs2 in
            obs1.boundingBox.origin.y > obs2.boundingBox.origin.y
        }

        var lines: [String] = []

        for observation in sortedObservations {
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else {
                continue
            }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append(text)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Receipt regions for targeted text extraction
    enum ReceiptRegion {
        case top    // Store name, date (top 25%)
        case middle // Line items (middle 50%)
        case bottom // Totals (bottom 25%)
    }
}

// MARK: - Error Types

enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(Error)
    case noTextDetected

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The provided image is invalid or cannot be processed"
        case .recognitionFailed(let error):
            return "Text recognition failed: \(error.localizedDescription)"
        case .noTextDetected:
            return "No text was detected in the image"
        }
    }
}

// MARK: - Preview Helper

#Preview {
    Text("OCRService - See console for test results")
        .task {
            // Example usage in a real view:
            // let prices = try? await OCRService.shared.findPrices(in: someImage)
            // let productName = try? await OCRService.shared.findProductName(in: someImage)
            print("✅ OCRService ready for use")
        }
}
