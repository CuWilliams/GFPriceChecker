//
//  ReceiptParser.swift
//  GFCore
//
//  Moved from GFPriceChecker/Services/ReceiptParserService.swift on 2026-10-31 (#69).
//

import Foundation

/// Represents a line item extracted from a receipt
public struct ReceiptLineItem: Sendable, Equatable {
    /// Product name or description
    public let productName: String

    /// Price of the item
    public let price: Decimal

    /// Confidence score for this extraction (0.0 to 1.0)
    public let confidence: Float

    public init(productName: String, price: Decimal, confidence: Float) {
        self.productName = productName
        self.price = price
        self.confidence = confidence
    }
}

/// A tracked product as the fuzzy matcher sees it: the GF side's name and price.
///
/// The app builds one from a `ProductPair` and keys the result back to the pair
/// by `id`, the same way `ReportRow` stands in for the model in reporting.
public struct MatchCandidate: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let price: Decimal

    public init(id: UUID, name: String, price: Decimal) {
        self.id = id
        self.name = name
        self.price = price
    }
}

/// Result of matching a candidate to a receipt line item
public struct ProductMatchResult: Sendable, Equatable {
    /// The candidate being matched
    public let candidate: MatchCandidate

    /// The matched receipt line item (if found)
    public let matchedLineItem: ReceiptLineItem?

    /// Confidence score for the match (0.0 to 1.0)
    public let matchConfidence: Float

    public init(candidate: MatchCandidate, matchedLineItem: ReceiptLineItem?, matchConfidence: Float) {
        self.candidate = candidate
        self.matchedLineItem = matchedLineItem
        self.matchConfidence = matchConfidence
    }

    /// Whether this match should be auto-suggested
    public var isAutoSuggested: Bool {
        matchConfidence >= 0.8
    }

    /// Match quality category
    public var matchQuality: MatchQuality {
        if matchConfidence >= 0.8 {
            return .high
        } else if matchConfidence >= 0.5 {
            return .medium
        } else {
            return .low
        }
    }

    public enum MatchQuality: Sendable {
        case high   // Auto-suggest (≥80%)
        case medium // Suggest with confirmation (50-79%)
        case low    // Show but don't suggest (<50%)
    }
}

/// Parses receipt text and matches products
///
/// Provides capabilities for:
/// - Store name extraction from receipt header
/// - Date parsing with multiple format support
/// - Line item extraction (product + price pairs)
/// - Total amount detection
/// - Fuzzy matching between tracked products and receipt items
public enum ReceiptParser {

    // MARK: - Constants

    /// Price matching tolerance for exact matches (±$0.25)
    private static let exactPriceTolerance: Decimal = 0.25

    /// Price matching tolerance for partial matches (±$0.50)
    private static let partialPriceTolerance: Decimal = 0.50

    /// Common store names in Canada
    static let commonStores = [
        "loblaws", "no frills", "real canadian superstore", "zehrs",
        "fortinos", "valu-mart", "independent", "metro", "food basics",
        "sobeys", "safeway", "iga", "freshco", "walmart", "costco",
        "whole foods", "farm boy", "t&t", "nations"
    ]

    /// Common abbreviations in product names
    private static let abbreviations: [String: String] = [
        "gf": "gluten free",
        "brd": "bread",
        "psta": "pasta",
        "flr": "flour",
        "org": "organic",
        "ckrs": "crackers",
        "cks": "cookies",
        "crl": "cereal",
        "pza": "pizza",
        "sce": "sauce"
    ]

    // MARK: - Store Name Extraction

    /// Extracts store name from receipt text
    ///
    /// Searches the first few lines of the receipt for known store names.
    ///
    /// - Parameter text: Raw receipt OCR text
    /// - Returns: Store name if found, nil otherwise
    public static func extractStoreName(from text: String) -> String? {
        // Split into lines and check first 5 lines for store names
        let lines = text.components(separatedBy: .newlines)
        let headerLines = lines.prefix(5)

        for line in headerLines {
            let normalizedLine = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for known store names
            for store in commonStores {
                if normalizedLine.contains(store) {
                    // Return properly capitalized version
                    return store.capitalized
                }
            }

            // If line is all caps and 3+ words, might be store name
            if line == line.uppercased() && line.split(separator: " ").count >= 3 {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    // MARK: - Date Extraction

    /// Extracts purchase date from receipt text
    ///
    /// Supports multiple date formats:
    /// - MM/DD/YYYY, MM-DD-YYYY, MM.DD.YYYY
    /// - DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY
    /// - YYYY-MM-DD (ISO format)
    /// - Mon DD, YYYY (e.g., "Dec 27, 2024")
    ///
    /// - Parameter text: Raw receipt OCR text
    /// - Returns: Parsed Date if found, nil otherwise
    public static func extractDate(from text: String) -> Date? {
        // Date regex patterns (ordered by priority)
        let patterns = [
            // ISO format: YYYY-MM-DD
            #"\b(\d{4})-(\d{2})-(\d{2})\b"#,
            // MM/DD/YYYY or DD/MM/YYYY
            #"\b(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})\b"#,
            // Mon DD, YYYY (e.g., Dec 27, 2024)
            #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* (\d{1,2}),? (\d{4})\b"#
        ]

        let dateFormatters = createDateFormatters()

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let matchRange = Range(match.range, in: text) {
                let dateString = String(text[matchRange])

                // Try each formatter until one works
                for formatter in dateFormatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    /// Creates array of date formatters for various formats
    private static func createDateFormatters() -> [DateFormatter] {
        let formats = [
            "yyyy-MM-dd",           // 2024-12-27
            "MM/dd/yyyy",           // 12/27/2024
            "MM-dd-yyyy",           // 12-27-2024
            "dd/MM/yyyy",           // 27/12/2024
            "dd-MM-yyyy",           // 27-12-2024
            "MMM dd, yyyy",         // Dec 27, 2024
            "MMM dd yyyy",          // Dec 27 2024
            "MMMM dd, yyyy"         // December 27, 2024
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }
    }

    // MARK: - Line Item Extraction

    /// Extracts line items (product + price) from receipt text
    ///
    /// Searches for lines containing both text and a price in $X.XX format.
    /// Supports both single-line format (PRODUCT $X.XX) and multi-line format (PRODUCT on line 1, X.XX on line 2).
    ///
    /// - Parameter text: Raw receipt OCR text
    /// - Returns: Array of ReceiptLineItem objects
    public static func extractLineItems(from text: String) -> [ReceiptLineItem] {
        var lineItems: [ReceiptLineItem] = []
        let lines = text.components(separatedBy: .newlines)
        var processedLineIndices = Set<Int>()

        // PASS 1: Extract single-line items (existing logic)
        // Pattern to match price at end of line: $X.XX
        let pricePattern = #"\$(\d{1,3}\.\d{2})\s*$"#
        guard let priceRegex = try? NSRegularExpression(pattern: pricePattern, options: []) else {
            return []
        }

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip very short lines or lines that look like headers/footers
            guard trimmedLine.count >= 5,
                  !isHeaderOrFooterLine(trimmedLine) else {
                continue
            }

            // Check if line contains a price
            let range = NSRange(trimmedLine.startIndex..., in: trimmedLine)
            guard let priceMatch = priceRegex.firstMatch(in: trimmedLine, options: [], range: range),
                  let priceRange = Range(priceMatch.range(at: 1), in: trimmedLine) else {
                continue
            }

            let priceString = String(trimmedLine[priceRange])
            guard let price = Decimal(string: priceString) else {
                continue
            }

            // Extract product name (everything before the price)
            let productNameEndIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: priceMatch.range.location)
            let productName = String(trimmedLine[..<productNameEndIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip if product name is empty or too short
            guard productName.count >= 2 else {
                continue
            }

            // Confidence based on line quality
            let confidence = calculateLineConfidence(line: trimmedLine, productName: productName, price: price)

            lineItems.append(ReceiptLineItem(
                productName: productName,
                price: price,
                confidence: confidence
            ))

            processedLineIndices.insert(index)
        }

        // PASS 2: Extract look-behind items (PRICE on line N, PRODUCT on line N+1)
        // Pattern for standalone price: optional leading dash, optional $, digits, decimal, 2 digits, optional trailing dash/tax indicators (H, G, etc.)
        let standalonePricePattern = #"^\s*\-?\$?(\d{1,3}\.\d{2})[\-\sA-Z]*$"#
        guard let standalonePriceRegex = try? NSRegularExpression(pattern: standalonePricePattern, options: []) else {
            return lineItems
        }

        // This handles cases where price appears before the product name (common in Costco receipts)
        for index in 1..<lines.count {
            // Skip if already processed
            if processedLineIndices.contains(index) || processedLineIndices.contains(index - 1) {
                continue
            }

            let previousLine = lines[index - 1].trimmingCharacters(in: .whitespacesAndNewlines)
            let currentLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if previous line is a standalone price
            let prevRange = NSRange(previousLine.startIndex..., in: previousLine)
            guard let priceMatch = standalonePriceRegex.firstMatch(in: previousLine, options: [], range: prevRange),
                  let priceRange = Range(priceMatch.range(at: 1), in: previousLine) else {
                continue
            }

            // Check if current line could be a product name (including product codes)
            guard currentLine.count >= 3,
                  !isHeaderOrFooterLine(currentLine),
                  !currentLine.contains("$"),
                  !isLikelyDiscount(currentLine) else {
                continue
            }

            let priceString = String(previousLine[priceRange])
            guard let price = Decimal(string: priceString) else {
                continue
            }

            // Additional validation: price should be reasonable for a grocery item
            guard price >= 0.50 && price <= 200.0 else {
                continue
            }

            let productName = currentLine

            // Boost confidence for lines with product codes (e.g., "1751411 B FREE TORTS")
            var confidence = calculateLineConfidence(line: currentLine, productName: productName, price: price) * 0.9
            if hasProductCode(currentLine) {
                confidence = min(confidence * 1.15, 1.0) // 15% boost for product codes
            }

            lineItems.append(ReceiptLineItem(
                productName: productName,
                price: price,
                confidence: confidence
            ))

            processedLineIndices.insert(index - 1)
            processedLineIndices.insert(index)
        }

        // PASS 3: Extract forward items (PRODUCT on line N, PRICE on line N+1)
        // This is a fallback for receipts where product comes before price
        for index in 0..<lines.count - 1 {
            // Skip if already processed
            if processedLineIndices.contains(index) || processedLineIndices.contains(index + 1) {
                continue
            }

            let currentLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let nextLine = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if next line is a standalone price
            let nextRange = NSRange(nextLine.startIndex..., in: nextLine)
            guard let priceMatch = standalonePriceRegex.firstMatch(in: nextLine, options: [], range: nextRange),
                  let priceRange = Range(priceMatch.range(at: 1), in: nextLine) else {
                continue
            }

            // Check if current line could be a product name
            guard currentLine.count >= 3,
                  !isHeaderOrFooterLine(currentLine),
                  !currentLine.contains("$"),
                  !isLikelyDiscount(currentLine) else { // Added discount check
                continue
            }

            let priceString = String(nextLine[priceRange])
            guard let price = Decimal(string: priceString) else {
                continue
            }

            // Additional validation: price should be reasonable for a grocery item
            guard price >= 0.50 && price <= 200.0 else {
                continue
            }

            let productName = currentLine

            // Confidence slightly lower for multi-line items
            let confidence = calculateLineConfidence(line: currentLine, productName: productName, price: price) * 0.9

            lineItems.append(ReceiptLineItem(
                productName: productName,
                price: price,
                confidence: confidence
            ))

            processedLineIndices.insert(index)
            processedLineIndices.insert(index + 1)
        }

        return lineItems
    }

    /// Determines if a line is likely a header or footer
    private static func isHeaderOrFooterLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter out lines that are only symbols/special characters
        if trimmed.allSatisfy({ !$0.isLetter && !$0.isNumber }) {
            return true
        }

        // Common header/footer keywords
        let excludeKeywords = [
            "total", "subtotal", "tax", "gst", "hst", "pst",
            "payment", "cash", "credit", "debit", "change",
            "thank you", "receipt", "invoice", "cashier",
            "store", "phone", "address", "date", "time",
            "amount", "customer copy", "merchant copy", "copy",
            "interac", "approved", "reference", "auth", "acct"
        ]

        for keyword in excludeKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }

        return false
    }

    /// Determines if a line is likely a discount indicator (e.g., "2029974 TPD/1751411")
    private static func isLikelyDiscount(_ line: String) -> Bool {
        let lowercased = line.lowercased()

        // Common discount indicators
        let discountKeywords = ["tpd", "discount", "off", "savings", "coupon", "promo"]

        for keyword in discountKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }

        return false
    }

    /// Checks if a line starts with a product code (6-7 digit number)
    private static func hasProductCode(_ line: String) -> Bool {
        // Pattern: line starts with 6-7 digits followed by space
        let productCodePattern = #"^\d{6,7}\s+"#
        guard let regex = try? NSRegularExpression(pattern: productCodePattern, options: []) else {
            return false
        }

        let range = NSRange(line.startIndex..., in: line)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }

    /// Calculates confidence for a line item extraction
    private static func calculateLineConfidence(line: String, productName: String, price: Decimal) -> Float {
        var confidence: Float = 0.7 // Base confidence

        // Higher confidence if product name has multiple words
        if productName.split(separator: " ").count >= 2 {
            confidence += 0.1
        }

        // Higher confidence if price is reasonable ($0.50 - $50.00)
        if price >= 0.5 && price <= 50 {
            confidence += 0.1
        }

        // Lower confidence if line has unusual characters
        let alphanumericRatio = Float(productName.filter { $0.isLetter || $0.isWhitespace }.count) / Float(productName.count)
        if alphanumericRatio < 0.7 {
            confidence -= 0.2
        }

        return min(max(confidence, 0.0), 1.0)
    }

    // MARK: - Total Extraction

    /// Labels that contain "total" without being the receipt's total.
    ///
    /// The amount no longer has to carry a `$` to be recognised, which widens
    /// what a "total" line can be confused with — a `TOTAL SAVINGS 3.40`
    /// printed below the real total would otherwise win, since the scan runs
    /// bottom-up.
    private static let nonTotalLabels = [
        "subtotal", "sub total", "sub-total",
        "total savings", "total discount", "total items", "total number"
    ]

    /// Extracts total amount from receipt text
    ///
    /// Scans upward for a line labelled "total" and takes the amount from it.
    /// Two things real receipts do that the naive version of this missed
    /// (issue #51):
    ///
    /// - **The `$` is usually absent.** Canadian grocery receipts print
    ///   `TOTAL      19.96`; the symbol appears in the header if at all. So the
    ///   symbol is optional here.
    /// - **The amount is right-aligned into a second column.** Vision returns a
    ///   wide horizontal gap as a *separate* text observation, so the label's
    ///   line arrives carrying no amount and the number lands on the line below
    ///   it. When that happens this falls through to the next line, the same way
    ///   `extractLineItems` pairs a Costco-style product line with the price
    ///   printed beneath it.
    ///
    /// - Parameter text: Raw receipt OCR text
    /// - Returns: Total amount if found, nil otherwise
    public static func extractTotal(from text: String) -> Decimal? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // The `$` is optional: see the note above.
        let amountPattern = #"\$?\s*(\d{1,4}\.\d{2})"#
        // A column of its own holds nothing but the amount.
        let standalonePattern = #"^\$?\s*(\d{1,4}\.\d{2})$"#

        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: []),
              let standaloneRegex = try? NSRegularExpression(pattern: standalonePattern, options: []) else {
            return nil
        }

        func amount(in line: String, using regex: NSRegularExpression) -> Decimal? {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  let captured = Range(match.range(at: 1), in: line) else {
                return nil
            }
            return Decimal(string: String(line[captured]))
        }

        for index in lines.indices.reversed() { // Start from bottom
            let lowercased = lines[index].lowercased()
            guard lowercased.contains("total") else {
                continue
            }

            // Skip subtotals and the other labels that merely contain the word.
            if nonTotalLabels.contains(where: { lowercased.contains($0) }) {
                continue
            }

            // The amount is on the label's own line.
            if let total = amount(in: lines[index], using: amountRegex) {
                return total
            }

            // Otherwise it was right-aligned into its own observation. Take the
            // next line if it is nothing but an amount; stop at the line after
            // that, so a "TOTAL" with no number under it cannot reach down and
            // claim an unrelated figure further along the receipt.
            let next = index + 1
            if next < lines.count, let total = amount(in: lines[next], using: standaloneRegex) {
                return total
            }
        }

        return nil
    }

    // MARK: - Fuzzy Matching

    /// Matches candidates to receipt line items using fuzzy matching
    ///
    /// Algorithm considers:
    /// - Exact and partial product name matches
    /// - Price matching with tolerance
    /// - Common abbreviations
    /// - Levenshtein distance for typos
    ///
    /// - Parameters:
    ///   - candidates: The tracked products to match
    ///   - lineItems: Array of ReceiptLineItems from OCR
    /// - Returns: One ProductMatchResult per candidate, in the same order, with confidence scores
    public static func matchProducts(_ candidates: [MatchCandidate], to lineItems: [ReceiptLineItem]) -> [ProductMatchResult] {
        var results: [ProductMatchResult] = []

        for candidate in candidates {
            var bestMatch: ReceiptLineItem?
            var bestConfidence: Float = 0.0

            // Try to find best matching line item
            for lineItem in lineItems {
                let confidence = calculateMatchConfidence(
                    candidate: candidate,
                    lineItem: lineItem
                )

                if confidence > bestConfidence {
                    bestConfidence = confidence
                    bestMatch = lineItem
                }
            }

            results.append(ProductMatchResult(
                candidate: candidate,
                matchedLineItem: bestMatch,
                matchConfidence: bestConfidence
            ))
        }

        return results
    }

    /// Calculates match confidence between a candidate and ReceiptLineItem
    private static func calculateMatchConfidence(candidate: MatchCandidate, lineItem: ReceiptLineItem) -> Float {
        var confidence: Float = 0.0

        // Check price matching (50% weight)
        let priceConfidence = calculatePriceConfidence(
            productPairPrice: candidate.price,
            lineItemPrice: lineItem.price
        )
        confidence += priceConfidence * 0.5

        // Check name matching (50% weight)
        let nameConfidence = calculateNameConfidence(
            productPairName: candidate.name,
            lineItemName: lineItem.productName
        )
        confidence += nameConfidence * 0.5

        return min(max(confidence, 0.0), 1.0)
    }

    /// Calculates confidence for price matching
    static func calculatePriceConfidence(productPairPrice: Decimal, lineItemPrice: Decimal) -> Float {
        let difference = abs(productPairPrice - lineItemPrice)

        if difference == 0 {
            return 1.0
        } else if difference <= exactPriceTolerance {
            return 0.9 // Within ±$0.25
        } else if difference <= partialPriceTolerance {
            return 0.6 // Within ±$0.50
        } else if difference <= 1.0 {
            return 0.3 // Within ±$1.00
        } else {
            return 0.0
        }
    }

    /// Calculates confidence for name matching using fuzzy string comparison
    static func calculateNameConfidence(productPairName: String, lineItemName: String) -> Float {
        // Normalize both strings
        let normalizedProductName = normalizeProductName(productPairName)
        let normalizedLineItemName = normalizeProductName(lineItemName)

        // Exact match
        if normalizedProductName == normalizedLineItemName {
            return 1.0
        }

        // Check if one contains the other
        if normalizedProductName.contains(normalizedLineItemName) ||
           normalizedLineItemName.contains(normalizedProductName) {
            return 0.8
        }

        // Check for key word matches
        let productWords = Set(normalizedProductName.split(separator: " ").map(String.init))
        let lineItemWords = Set(normalizedLineItemName.split(separator: " ").map(String.init))

        if let jaccardSimilarity = calculateJaccardSimilarity(productWords, lineItemWords) {
            // Boost confidence if key words like "gluten free" match
            let intersection = productWords.intersection(lineItemWords)
            if intersection.contains("gluten") || intersection.contains("free") {
                return min(jaccardSimilarity + 0.2, 1.0)
            }

            return jaccardSimilarity
        }

        // Use Levenshtein distance for typo tolerance
        let levenshteinSimilarity = calculateLevenshteinSimilarity(
            normalizedProductName,
            normalizedLineItemName
        )

        return levenshteinSimilarity
    }

    /// Normalizes product name for matching
    static func normalizeProductName(_ name: String) -> String {
        var normalized = name.lowercased()

        // Expand abbreviations
        for (abbr, full) in abbreviations {
            normalized = normalized.replacingOccurrences(of: abbr, with: full)
        }

        // Remove punctuation
        normalized = normalized.components(separatedBy: .punctuationCharacters).joined(separator: " ")

        // Remove extra whitespace
        normalized = normalized.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return normalized.trimmingCharacters(in: .whitespaces)
    }

    /// Jaccard similarity of two word sets: shared words over all words.
    ///
    /// - Returns: nil when both sets are empty, since the ratio is undefined
    static func calculateJaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Float? {
        let intersection = a.intersection(b)
        let union = a.union(b)

        guard !union.isEmpty else { return nil }

        return Float(intersection.count) / Float(union.count)
    }

    /// Calculates Levenshtein similarity (0.0 = completely different, 1.0 = identical)
    static func calculateLevenshteinSimilarity(_ s1: String, _ s2: String) -> Float {
        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)

        guard maxLength > 0 else { return 1.0 }

        let similarity = 1.0 - (Float(distance) / Float(maxLength))
        return max(similarity, 0.0)
    }

    /// Calculates Levenshtein distance between two strings
    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m {
            matrix[i][0] = i
        }

        for j in 0...n {
            matrix[0][j] = j
        }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[m][n]
    }
}
