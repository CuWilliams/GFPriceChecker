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

/// Result of price detection from OCR
struct PriceMatch {
    /// The detected price amount
    let amount: Decimal

    /// Confidence score from OCR (0.0 to 1.0)
    let confidence: Float

    /// Bounding box of the detected price in normalized coordinates
    let boundingBox: CGRect
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
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noTextDetected)
                    return
                }

                continuation.resume(returning: observations)
            }

            // Configure for accurate recognition
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error))
            }
        }
    }

    /// Finds prices in an image using pattern matching
    ///
    /// Searches for common price formats like $X.XX, $XX.XX, $XXX.XX
    ///
    /// - Parameter image: The UIImage to search for prices
    /// - Returns: Array of PriceMatch results sorted by confidence (highest first)
    /// - Throws: OCRError if recognition fails
    func findPrices(in image: UIImage) async throws -> [PriceMatch] {
        let observations = try await extractText(from: image)

        var priceMatches: [PriceMatch] = []

        // Regex pattern for prices: $X.XX, $XX.XX, $XXX.XX
        let pricePattern = #"\$\d{1,3}\.\d{2}"#
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

                    // Remove $ and convert to Decimal
                    let numberString = priceString.replacingOccurrences(of: "$", with: "")
                    if let amount = Decimal(string: numberString) {
                        let priceMatch = PriceMatch(
                            amount: amount,
                            confidence: candidate.confidence,
                            boundingBox: observation.boundingBox
                        )
                        priceMatches.append(priceMatch)
                    }
                }
            }
        }

        // Sort by confidence (highest first)
        return priceMatches.sorted { $0.confidence > $1.confidence }
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
        let observations = try await extractText(from: image)

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
