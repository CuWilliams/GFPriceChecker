//
//  SizeTextParser.swift
//  GFCore
//
//  Moved from GFPriceChecker/ViewModels/CaptureFlowViewModel.swift on 2026-10-31 (#67).
//

import Foundation

/// Reads package sizes and unit prices out of OCR'd shelf-tag text.
public enum SizeTextParser {

    /// Extracts a numeric size and suggests a SizeUnit from text like "400g", "1.5 L", "12oz"
    public static func parseSize(_ text: String) -> (value: String, unit: SizeUnit?) {
        let unitPatterns: [(pattern: String, unit: SizeUnit)] = [
            (#"(\d+\.?\d*)\s*fl\.?\s*oz"#, .flOunces),
            (#"(\d+\.?\d*)\s*kg"#, .kilograms),
            (#"(\d+\.?\d*)\s*mL"#, .milliliters),
            (#"(\d+\.?\d*)\s*L\b"#, .liters),
            (#"(\d+\.?\d*)\s*oz"#, .ounces),
            (#"(\d+\.?\d*)\s*lb"#, .pounds),
            (#"(\d+\.?\d*)\s*g\b"#, .grams),
            (#"(\d+\.?\d*)\s*count"#, .count),
        ]

        return firstMatch(in: text, patterns: unitPatterns)
    }

    /// Extracts a unit price and suggests a SizeUnit from text like "$1.49/100g", "0.99/oz"
    public static func parseUnitPrice(_ text: String) -> (value: String, unit: SizeUnit?) {
        let unitPatterns: [(pattern: String, unit: SizeUnit)] = [
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*fl\.?\s*oz"#, .flOunces),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*kg"#, .kilograms),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*mL"#, .milliliters),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*L\b"#, .liters),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*oz"#, .ounces),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*lb"#, .pounds),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*g\b"#, .grams),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*count"#, .count),
        ]

        return firstMatch(in: text, patterns: unitPatterns)
    }

    /// Returns the first capture group any pattern matches, with its unit.
    ///
    /// Every pattern requires its suffix to sit immediately after the number,
    /// which is what keeps "2.5kg" from reading as grams and "16 fl oz" from
    /// reading as ounces — the "k" and the "fl " are in the way, so the shorter
    /// patterns do not match at all. Order is the tie-break if that ever stops
    /// holding, so the ambiguous units are still listed first.
    private static func firstMatch(
        in text: String,
        patterns: [(pattern: String, unit: SizeUnit)]
    ) -> (value: String, unit: SizeUnit?) {
        for (pattern, unit) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   match.numberOfRanges > 1,
                   let valRange = Range(match.range(at: 1), in: text) {
                    return (String(text[valRange]), unit)
                }
            }
        }
        // No pattern matched — return raw text for manual editing
        return (text, nil)
    }
}
