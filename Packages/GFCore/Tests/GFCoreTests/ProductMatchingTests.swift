//
//  ProductMatchingTests.swift
//  GFCoreTests
//
//  Created by Claude Code on 2026-10-31 (#69).
//

import Foundation
import Testing
@testable import GFCore

/// Fuzzy matching of tracked products to receipt line items.
///
/// `matchProducts` has no production caller yet. Wiring it up is #36 and #22.
/// These tests pin the behaviour it was moved with, so that work starts from
/// a known position. `@testable` because the scoring pieces are internal.
@Suite("Product matching")
struct ProductMatchingTests {

    private func isClose(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 0.0001 }

    private func candidate(_ name: String, _ price: String) -> MatchCandidate {
        MatchCandidate(id: UUID(), name: name, price: Decimal(string: price)!)
    }

    private func item(_ name: String, _ price: String) -> ReceiptLineItem {
        ReceiptLineItem(productName: name, price: Decimal(string: price)!, confidence: 0.9)
    }

    // MARK: - matchProducts

    @Test("An abbreviated receipt line at the same price is a high-quality match")
    func abbreviatedExactMatch() throws {
        let bread = candidate("Gluten Free Bread", "5.99")
        let results = ReceiptParser.matchProducts(
            [bread],
            to: [item("MILK 2%", "4.49"), item("GF BRD", "5.99")]
        )

        let result = try #require(results.first)
        #expect(result.candidate == bread)
        #expect(result.matchedLineItem?.productName == "GF BRD")
        #expect(isClose(result.matchConfidence, 1.0))
        #expect(result.isAutoSuggested)
        #expect(result.matchQuality == .high)
    }

    @Test("Each candidate gets one result, in order, keyed by its id")
    func oneResultPerCandidate() {
        let candidates = [candidate("Gluten Free Penne", "4.29"), candidate("Rice Crackers", "3.49")]
        let results = ReceiptParser.matchProducts(
            candidates,
            to: [item("RICE CRACKERS", "3.49"), item("GF PENNE", "4.29")]
        )

        #expect(results.map(\.candidate.id) == candidates.map(\.id))
        #expect(results.map(\.matchedLineItem?.productName) == ["GF PENNE", "RICE CRACKERS"])
    }

    @Test("With nothing scoring above zero there is no match")
    func noMatch() throws {
        let result = try #require(ReceiptParser.matchProducts(
            [candidate("Bread", "5.99")],
            to: [item("MILK", "12.49")]
        ).first)

        #expect(result.matchedLineItem == nil)
        #expect(result.matchConfidence == 0)
        #expect(result.matchQuality == .low)
    }

    @Test("A receipt with no line items matches nothing")
    func noLineItems() {
        let results = ReceiptParser.matchProducts([candidate("Bread", "5.99")], to: [])
        #expect(results.count == 1)
        #expect(results.first?.matchedLineItem == nil)
    }

    @Test("Price and name are weighted equally")
    func priceAndNameAreHalfEach() throws {
        // Name identical, price $0.40 out (0.6): 0.5 + 0.3.
        let result = try #require(ReceiptParser.matchProducts(
            [candidate("Rice Crackers", "3.49")],
            to: [item("RICE CRACKERS", "3.89")]
        ).first)
        #expect(isClose(result.matchConfidence, 0.8))
    }

    @Test("Match quality bands at 0.8 and 0.5", arguments: [
        (Float(0.8), ProductMatchResult.MatchQuality.high, true),
        (0.79, .medium, false),
        (0.5, .medium, false),
        (0.49, .low, false),
    ])
    func qualityBands(confidence: Float, quality: ProductMatchResult.MatchQuality, suggested: Bool) {
        let result = ProductMatchResult(
            candidate: candidate("Bread", "1.00"),
            matchedLineItem: nil,
            matchConfidence: confidence
        )
        #expect(result.matchQuality == quality)
        #expect(result.isAutoSuggested == suggested)
    }

    // MARK: - Price Confidence

    @Test("Price confidence steps down at $0.25, $0.50 and $1.00", arguments: [
        ("5.99", Float(1.0)),
        ("6.24", 0.9),
        ("5.74", 0.9),
        ("6.25", 0.6),
        ("6.49", 0.6),
        ("6.50", 0.3),
        ("6.99", 0.3),
        ("7.00", 0.0),
    ])
    func priceConfidence(lineItemPrice: String, expected: Float) {
        let confidence = ReceiptParser.calculatePriceConfidence(
            productPairPrice: Decimal(string: "5.99")!,
            lineItemPrice: Decimal(string: lineItemPrice)!
        )
        #expect(confidence == expected)
    }

    // MARK: - Name Confidence

    @Test("Names that normalise to the same text are an exact match")
    func exactName() {
        #expect(ReceiptParser.calculateNameConfidence(
            productPairName: "Gluten-Free Bread!", lineItemName: "gluten free  bread"
        ) == 1.0)
    }

    @Test("A name contained in the other scores 0.8")
    func containedName() {
        #expect(ReceiptParser.calculateNameConfidence(
            productPairName: "Gluten Free Penne", lineItemName: "PENNE"
        ) == 0.8)
    }

    @Test("Shared words score their Jaccard similarity")
    func jaccardName() {
        // {rice, crackers} vs {rice, cakes}: 1 shared of 3.
        #expect(isClose(ReceiptParser.calculateNameConfidence(
            productPairName: "Rice Crackers", lineItemName: "Rice Cakes"
        ), 1.0 / 3.0))
    }

    @Test("Sharing \"gluten\" or \"free\" adds 0.2")
    func glutenFreeBoost() {
        // {gluten, free, penne, pasta} vs {gluten, free, spaghetti}: 2 of 5, +0.2.
        #expect(isClose(ReceiptParser.calculateNameConfidence(
            productPairName: "GF Penne Psta", lineItemName: "GF Spaghetti"
        ), 0.6))
    }

    /// The Levenshtein fallback only runs when both word sets are empty, and
    /// two empty names are already an exact match. So a typo scores on word
    /// overlap alone, and a one-word typo scores nothing. The fallback is
    /// unreachable as written.
    @Test("Known gap: a misspelt one-word name scores zero, not its Levenshtein similarity")
    func typoIsNotRescued() {
        #expect(ReceiptParser.calculateNameConfidence(productPairName: "Bread", lineItemName: "Braed") == 0)
        #expect(ReceiptParser.calculateLevenshteinSimilarity("bread", "braed") > 0.5)
    }

    // MARK: - Normalisation

    @Test("Normalisation lowercases, expands abbreviations and collapses punctuation")
    func normalisation() {
        #expect(ReceiptParser.normalizeProductName("  GF Brd, ORG.  ") == "gluten free bread organic")
    }

    /// Abbreviations are replaced as substrings, not whole words.
    @Test("Known gap: an abbreviation inside a longer word is expanded too")
    func abbreviationsAreSubstrings() {
        #expect(ReceiptParser.normalizeProductName("Snacks") == "snacookies")
    }

    // MARK: - Levenshtein

    @Test("Levenshtein distance counts single-character edits", arguments: [
        ("kitten", "sitting", 3),
        ("bread", "bread", 0),
        ("bread", "breads", 1),
        ("bread", "brad", 1),
        ("bread", "braed", 2),
        ("abc", "xyz", 3),
    ])
    func levenshteinDistance(a: String, b: String, distance: Int) {
        #expect(ReceiptParser.levenshteinDistance(a, b) == distance)
        #expect(ReceiptParser.levenshteinDistance(b, a) == distance)
    }

    @Test("Levenshtein similarity is one minus distance over the longer length")
    func levenshteinSimilarity() {
        #expect(isClose(ReceiptParser.calculateLevenshteinSimilarity("kitten", "sitting"), 1 - 3.0 / 7.0))
        #expect(ReceiptParser.calculateLevenshteinSimilarity("bread", "bread") == 1)
        #expect(ReceiptParser.calculateLevenshteinSimilarity("abc", "xyz") == 0)
    }

    // MARK: - Jaccard

    @Test("Jaccard similarity is shared words over all words")
    func jaccardSimilarity() {
        #expect(isClose(ReceiptParser.calculateJaccardSimilarity(["a", "b"], ["b", "c"])!, 1.0 / 3.0))
        #expect(ReceiptParser.calculateJaccardSimilarity(["a", "b"], ["b", "a"]) == 1)
        #expect(ReceiptParser.calculateJaccardSimilarity(["a"], ["b"]) == 0)
        #expect(ReceiptParser.calculateJaccardSimilarity(["a"], []) == 0)
    }

    @Test("Jaccard similarity of two empty sets is undefined")
    func jaccardOfNothing() {
        #expect(ReceiptParser.calculateJaccardSimilarity([], []) == nil)
    }
}
