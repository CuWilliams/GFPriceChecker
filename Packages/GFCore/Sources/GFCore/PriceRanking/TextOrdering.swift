//
//  TextOrdering.swift
//  GFCore
//
//  Moved from GFPriceChecker/Services/OCRService.swift on 2026-10-31 (#69).
//

import Foundation

/// Puts recognised text into reading order for the tap-to-select lists and
/// the receipt parser.
///
/// The two orders differ, and both are load-bearing. The selectable list sorts
/// by each box's vertical centre. Receipt text sorts by each box's *origin*,
/// which is what puts a two-column receipt's label above its own amount, the
/// assumption `ReceiptParser.extractTotal`'s fall-through rests on. See
/// `SubstituteScannerTests.twoColumnLabelSortsAboveItsAmount`.
public enum TextOrdering {

    /// Receipt regions for targeted text extraction
    public enum ReceiptRegion: Sendable {
        case top    // Store name, date (top 25%)
        case middle // Line items (middle 50%)
        case bottom // Totals (bottom 25%)
    }

    // MARK: - Selectable Text

    /// Text for UI display and selection, sorted top-to-bottom
    ///
    /// Drops low-confidence and empty observations and trims what remains.
    ///
    /// - Parameters:
    ///   - observations: Text recognised in the image
    ///   - region: When given, keeps only text whose box intersects it
    /// - Returns: The kept observations with trimmed text, top of image first
    public static func selectableText(
        _ observations: [RecognizedText],
        in region: NormalizedRect? = nil
    ) -> [RecognizedText] {
        var selectableObservations: [RecognizedText] = []

        for observation in observations {
            guard observation.confidence >= PriceRanking.minimumConfidence else {
                continue
            }

            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty strings
            if text.isEmpty {
                continue
            }

            // Check if observation bounding box intersects with the region
            if let region, !region.intersects(observation.box) {
                continue
            }

            selectableObservations.append(RecognizedText(
                text: text,
                confidence: observation.confidence,
                box: observation.box
            ))
        }

        // Sort by vertical position descending (top of image first)
        // Vision uses bottom-left origin, so higher y values are at top
        let sorted = selectableObservations.sorted { $0.box.midY > $1.box.midY }
        return sorted
    }

    // MARK: - Receipt Text

    /// Full text of a receipt as one string, one observation per line
    ///
    /// - Parameters:
    ///   - observations: Text recognised in the receipt image
    ///   - region: When given, keeps only text whose box starts in that band
    /// - Returns: Full text content with line breaks, top of receipt first
    public static func receiptText(
        _ observations: [RecognizedText],
        region: ReceiptRegion? = nil
    ) -> String {
        var filteredObservations = observations

        if let region {
            filteredObservations = observations.filter { observation in
                let yPosition = observation.box.y

                switch region {
                case .top:
                    // Top 25% of receipt (store name, date)
                    return yPosition >= 0.75
                case .middle:
                    // Middle 50% of receipt (line items)
                    return yPosition >= 0.25 && yPosition < 0.75
                case .bottom:
                    // Bottom 25% of receipt (totals)
                    return yPosition < 0.25
                }
            }
        }

        // Sort observations by vertical position (top to bottom)
        // Vision uses bottom-left origin, so higher y values are at top
        let sortedObservations = filteredObservations.sorted { obs1, obs2 in
            // Compare y-coordinate (higher y = higher on page)
            obs1.box.y > obs2.box.y
        }

        var lines: [String] = []

        for observation in sortedObservations {
            guard observation.confidence >= PriceRanking.minimumConfidence else {
                continue
            }

            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append(text)
            }
        }

        return lines.joined(separator: "\n")
    }
}
