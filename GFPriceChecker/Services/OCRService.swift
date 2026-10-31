//
//  OCRService.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation
import GFCore
import Vision
import UIKit
import VisionKit
import SwiftUI

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

/// Represents a detected rectangle in an image (e.g., shelf price tag, product label)
struct DetectedRectangle: Identifiable {
    let id = UUID()
    /// Bounding box in normalized coordinates (0-1)
    let boundingBox: CGRect
    /// Detection confidence score (0.0 to 1.0)
    let confidence: Float
    /// Estimated area (width * height) for ranking
    var area: CGFloat {
        boundingBox.width * boundingBox.height
    }
}

/// Service for extracting text and data from product images using Vision framework
///
/// Runs the Vision requests and maps their results to and from GFCore's values.
/// Everything decided about the text once it is recognised — thresholds, price
/// ranking, the product-name heuristic, reading order — is in GFCore's
/// `PriceRanking` and `TextOrdering`.
@MainActor
final class OCRService {
    // MARK: - Singleton

    static let shared = OCRService()

    private init() {}

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

    /// Extracts all text from an image as GFCore values, one per observation
    /// that has a candidate
    private func recognizeText(in image: UIImage) async throws -> [GFCore.RecognizedText] {
        try await extractText(from: image).compactMap(GFCore.RecognizedText.init)
    }

    /// Finds prices in an image, ranked by `PriceRanking.prices(in:)`
    ///
    /// - Parameter image: The UIImage to search for prices
    /// - Returns: Array of PriceMatch results sorted by ranking score (highest first)
    /// - Throws: OCRError if recognition fails
    func findPrices(in image: UIImage) async throws -> [PriceMatch] {
        PriceRanking.prices(in: try await recognizeText(in: image))
    }

    /// Extracts product name from the top portion of the image, chosen by
    /// `PriceRanking.productName(in:)`
    ///
    /// - Parameter image: The UIImage to extract product name from
    /// - Returns: The detected product name, or nil if confidence is too low
    /// - Throws: OCRError if recognition fails
    func findProductName(in image: UIImage) async throws -> String? {
        PriceRanking.productName(in: try await recognizeText(in: image))
    }

    /// Extracts text observations for UI display and selection
    ///
    /// - Parameter image: The UIImage to extract text from
    /// - Returns: Array of SelectableTextObservation sorted by vertical position (top first)
    /// - Throws: OCRError if recognition fails
    func extractSelectableText(from image: UIImage) async throws -> [SelectableTextObservation] {
        TextOrdering.selectableText(try await recognizeText(in: image))
            .map(SelectableTextObservation.init)
    }

    /// Extracts selectable text observations from a specific region of the image
    ///
    /// Useful for extracting text from user-selected rectangular regions (e.g., shelf price tags).
    ///
    /// - Parameters:
    ///   - image: The UIImage to extract text from
    ///   - region: The bounding box (normalized 0-1) to extract text from
    /// - Returns: Array of SelectableTextObservation within the region, sorted top-to-bottom
    /// - Throws: OCRError if recognition fails
    func extractSelectableText(from image: UIImage, region: CGRect) async throws -> [SelectableTextObservation] {
        TextOrdering.selectableText(try await recognizeText(in: image), in: GFCore.NormalizedRect(region))
            .map(SelectableTextObservation.init)
    }

    /// Detects rectangular regions in an image (e.g., shelf price tags, product labels)
    ///
    /// Uses Vision framework's rectangle detection to identify potential regions of interest.
    /// Useful for allowing users to select specific areas like shelf price tags before OCR.
    ///
    /// - Parameter image: The UIImage to detect rectangles in
    /// - Returns: Array of DetectedRectangle sorted by area (largest first)
    /// - Throws: OCRError if detection fails
    func detectRectangles(in image: UIImage) async throws -> [DetectedRectangle] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                var rectangles: [DetectedRectangle] = []

                for observation in observations {
                    // Filter by confidence threshold
                    guard observation.confidence >= 0.5 else { continue }
                    let rectangle = DetectedRectangle(
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence
                    )

                    rectangles.append(rectangle)
                }

                // Sort by area (largest first) - larger rectangles likely more important
                let sorted = rectangles.sorted { $0.area > $1.area }
                continuation.resume(returning: sorted)
            }

            // Configure rectangle detection
            request.minimumAspectRatio = 0.3  // Allow wide rectangles (price tags)
            request.maximumAspectRatio = 1.0  // Prevent very tall/narrow rectangles
            request.minimumSize = 0.1         // Minimum 10% of image size
            request.maximumObservations = 10  // Limit to top 10 rectangles

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error))
            }
        }
    }

    // MARK: - Receipt-Specific OCR

    /// Extracts full text from a receipt image
    ///
    /// Returns all recognized text as a single string, preserving line breaks.
    /// Useful for receipt parsing where layout and structure matter.
    ///
    /// - Parameters:
    ///   - image: The receipt image
    ///   - region: When given, only text from that band (.top, .middle, .bottom)
    /// - Returns: Full text content with line breaks
    /// - Throws: OCRError if recognition fails
    func extractReceiptText(
        from image: UIImage,
        region: TextOrdering.ReceiptRegion? = nil
    ) async throws -> String {
        TextOrdering.receiptText(try await recognizeText(in: image), region: region)
    }
}

// MARK: - Mapping to GFCore

// Vision has its own `RecognizedText` and `NormalizedRect` (the iOS 18 Swift API),
// so this file names the core's with `GFCore.`.

extension GFCore.RecognizedText {
    /// Vision's top candidate for the observation, or nil if it has none
    init?(_ observation: VNRecognizedTextObservation) {
        guard let candidate = observation.topCandidates(1).first else { return nil }
        self.init(
            text: candidate.string,
            confidence: candidate.confidence,
            box: GFCore.NormalizedRect(observation.boundingBox)
        )
    }
}

extension GFCore.NormalizedRect {
    init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }
}

extension CGRect {
    init(_ rect: GFCore.NormalizedRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

extension SelectableTextObservation {
    init(_ text: GFCore.RecognizedText) {
        self.init(text: text.text, boundingBox: CGRect(text.box), confidence: text.confidence)
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

#if DEBUG
#Preview {
    Text("OCRService - See console for test results")
        .task {
            // Example usage in a real view:
            // let prices = try? await OCRService.shared.findPrices(in: someImage)
            // let productName = try? await OCRService.shared.findProductName(in: someImage)
            print("✅ OCRService ready for use")
        }
}
#endif
