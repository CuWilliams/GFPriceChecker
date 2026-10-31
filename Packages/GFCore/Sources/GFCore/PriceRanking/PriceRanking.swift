//
//  PriceRanking.swift
//  GFCore
//
//  Moved from GFPriceChecker/Services/OCRService.swift on 2026-10-31 (#69).
//

import Foundation

/// Quality classification for price detection confidence
public enum PriceQuality: Sendable {
    case high    // ≥ 0.85 confidence
    case medium  // 0.60 - 0.85 confidence
    case low     // < 0.60 confidence

    public init(confidence: Float) {
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
public struct PriceMatch: Sendable, Equatable {
    /// The detected price amount
    public let amount: Decimal

    /// OCR confidence score (0.0 to 1.0)
    public let confidence: Float

    /// Bounding box of the detected price in normalized coordinates
    public let boundingBox: NormalizedRect

    /// Estimated font size based on bounding box height
    public let fontSize: Double

    /// Vertical position in image (0.0 = bottom, 1.0 = top)
    public let verticalPosition: Double

    /// Whether the price had a "$" prefix
    public let hasPrefix: Bool

    public init(
        amount: Decimal,
        confidence: Float,
        boundingBox: NormalizedRect,
        fontSize: Double,
        verticalPosition: Double,
        hasPrefix: Bool
    ) {
        self.amount = amount
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.fontSize = fontSize
        self.verticalPosition = verticalPosition
        self.hasPrefix = hasPrefix
    }

    /// Quality classification based on overall confidence
    public var quality: PriceQuality {
        PriceQuality(confidence: confidence)
    }

    /// Composite score for ranking price candidates
    /// Higher score = more likely to be the actual product price
    public var rankingScore: Float {
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

/// Price and product-name detection over recognised text
public enum PriceRanking {

    // MARK: - Constants

    /// Minimum confidence threshold for text recognition
    public static let minimumConfidence: Float = 0.5

    /// Minimum confidence for product name extraction
    public static let productNameMinimumConfidence: Float = 0.7

    /// Percentage of image height to search for product names (top portion)
    public static let productNameSearchArea: Double = 0.3

    // MARK: - Prices

    /// Finds prices in recognised text using pattern matching and spatial analysis
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
    /// - Parameter observations: Text recognised in the image
    /// - Returns: Array of PriceMatch results sorted by ranking score (highest first)
    public static func prices(in observations: [RecognizedText]) -> [PriceMatch] {
        var priceMatches: [PriceMatch] = []

        // Updated regex pattern: Optional $ prefix, then 1-3 digits, dot, 2 digits
        let pricePattern = #"\$?\d{1,3}\.\d{2}"#
        guard let regex = try? NSRegularExpression(pattern: pricePattern, options: []) else {
            return []
        }

        for observation in observations {
            guard observation.confidence >= minimumConfidence else {
                continue
            }

            let text = observation.text
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
                        let boundingBox = observation.box

                        // Font size estimate: height of bounding box in normalized coordinates
                        let fontSize = boundingBox.height

                        // Vertical position: center Y of bounding box
                        // Vision uses bottom-left origin: 0 = bottom, 1 = top
                        let verticalPosition = boundingBox.y + (boundingBox.height / 2.0)

                        let priceMatch = PriceMatch(
                            amount: amount,
                            confidence: observation.confidence,
                            boundingBox: boundingBox,
                            fontSize: fontSize,
                            verticalPosition: verticalPosition,
                            hasPrefix: hasPrefix
                        )

                        priceMatches.append(priceMatch)
                    }
                }
            }
        }

        // Sort by ranking score (highest first)
        let sortedMatches = priceMatches.sorted { $0.rankingScore > $1.rankingScore }
        return sortedMatches
    }

    // MARK: - Product Name

    /// Picks the product name from the top portion of the image
    ///
    /// Product names are typically located in the top 30% of product labels.
    /// Returns the most prominent (longest) text string found in that region.
    ///
    /// - Parameter observations: Text recognised in the image
    /// - Returns: The detected product name, or nil if confidence is too low
    public static func productName(in observations: [RecognizedText]) -> String? {
        var candidateNames: [(text: String, confidence: Float)] = []

        for observation in observations {
            // Only look at text in the top portion of the image
            // Vision uses bottom-left origin, so check if y + height > (1.0 - searchArea)
            let minY = 1.0 - productNameSearchArea
            if observation.box.y < minY {
                continue
            }

            guard observation.confidence >= productNameMinimumConfidence else {
                continue
            }

            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Filter out very short strings (likely not product names)
            if text.count >= 3 {
                candidateNames.append((text: text, confidence: observation.confidence))
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
}
