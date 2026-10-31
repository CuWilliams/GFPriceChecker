//
//  PriceRankingTests.swift
//  GFCoreTests
//
//  Created by Claude Code on 2026-10-31 (#69).
//

import Foundation
import Testing
import GFCore

/// Price ranking, the product-name heuristic and reading order, over
/// hand-built `RecognizedText`.
///
/// Until #69 these ran only end to end, through real Vision, in
/// `SubstituteScannerTests`. That suite still proves the drawn samples come
/// out of OCR in these shapes. This one pins each rule without an image.
@Suite("Price ranking")
struct PriceRankingTests {

    private func isClose(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 0.0001 }

    private func text(
        _ string: String,
        confidence: Float = 0.95,
        y: Double = 0.5,
        height: Double = 0.05
    ) -> RecognizedText {
        RecognizedText(
            text: string,
            confidence: confidence,
            box: NormalizedRect(x: 0.1, y: y, width: 0.5, height: height)
        )
    }

    private func match(
        fontSize: Double,
        verticalPosition: Double,
        hasPrefix: Bool = false,
        confidence: Float = 1.0
    ) -> PriceMatch {
        PriceMatch(
            amount: 1,
            confidence: confidence,
            boundingBox: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
            fontSize: fontSize,
            verticalPosition: verticalPosition,
            hasPrefix: hasPrefix
        )
    }

    // MARK: - rankingScore

    @Test("Each signal carries its weight: size 0.5, position 0.3, $ 0.1, confidence 0.1")
    func rankingWeights() {
        #expect(isClose(match(fontSize: 0.15, verticalPosition: 0, confidence: 0).rankingScore, 0.5))
        #expect(isClose(match(fontSize: 0, verticalPosition: 1, confidence: 0).rankingScore, 0.3))
        #expect(isClose(match(fontSize: 0, verticalPosition: 0, hasPrefix: true, confidence: 0).rankingScore, 0.1))
        #expect(isClose(match(fontSize: 0, verticalPosition: 0, confidence: 1).rankingScore, 0.1))
    }

    @Test("Font size scales against 0.15 and is capped there")
    func fontSizeIsNormalisedAndCapped() {
        #expect(isClose(match(fontSize: 0.075, verticalPosition: 0, confidence: 0).rankingScore, 0.25))
        #expect(isClose(match(fontSize: 0.3, verticalPosition: 0, confidence: 0).rankingScore, 0.5))
    }

    @Test("A large price low on the tag outranks a small $ price at the top")
    func sizeDominates() {
        let shelfPrice = match(fontSize: 0.12, verticalPosition: 0.3, confidence: 0.9)
        let unitPrice = match(fontSize: 0.03, verticalPosition: 0.9, hasPrefix: true, confidence: 0.9)
        #expect(shelfPrice.rankingScore > unitPrice.rankingScore)
    }

    @Test("Price quality bands at 0.85 and 0.6", arguments: [
        (Float(0.85), PriceQuality.high),
        (0.849, .medium),
        (0.6, .medium),
        (0.599, .low),
    ])
    func qualityBands(confidence: Float, quality: PriceQuality) {
        #expect(PriceQuality(confidence: confidence) == quality)
        #expect(match(fontSize: 0, verticalPosition: 0, confidence: confidence).quality == quality)
    }

    // MARK: - prices(in:)

    @Test("The shelf price outranks the unit price beneath it")
    func shelfTag() throws {
        let prices = PriceRanking.prices(in: [
            text("Gluten Free White Bread", y: 0.8),
            text("$7.49", y: 0.5, height: 0.12),
            text("$1.87/100g", y: 0.2, height: 0.03),
        ])

        #expect(prices.map(\.amount) == [Decimal(string: "7.49")!, Decimal(string: "1.87")!])
        let top = try #require(prices.first)
        #expect(top.hasPrefix)
        #expect(top.fontSize == 0.12)
        #expect(abs(top.verticalPosition - 0.56) < 1e-9)
    }

    @Test("A price without a $ is still a candidate, scored without the bonus")
    func priceWithoutPrefix() throws {
        let price = try #require(PriceRanking.prices(in: [text("3.99")]).first)
        #expect(price.amount == Decimal(string: "3.99"))
        #expect(price.hasPrefix == false)
    }

    @Test("Every price in one observation is a candidate with that observation's box")
    func severalPricesInOneObservation() {
        let prices = PriceRanking.prices(in: [text("2 for $5.00 or 2.79 each")])
        #expect(Set(prices.map(\.amount)) == [Decimal(string: "5.00")!, Decimal(string: "2.79")!])
        #expect(Set(prices.map(\.verticalPosition)).count == 1)
    }

    @Test("Text below 0.5 confidence is ignored; 0.5 itself is kept")
    func confidenceThreshold() {
        #expect(PriceRanking.prices(in: [text("$9.99", confidence: 0.49)]).isEmpty)
        #expect(PriceRanking.prices(in: [text("$9.99", confidence: 0.5)]).count == 1)
    }

    @Test("A number without cents is not a price", arguments: ["1299", "$12", "12.9"])
    func notAPrice(string: String) {
        #expect(PriceRanking.prices(in: [text(string)]).isEmpty)
    }

    // MARK: - productName(in:)

    @Test("The longest confident line in the top 30% is the product name")
    func productName() {
        let name = PriceRanking.productName(in: [
            text("PC", y: 0.9),
            text("Gluten Free Bread", y: 0.8),
            text("Gluten Free Bread Sliced White Loaf", y: 0.5),
            text("Gluten Free Bread Sliced", confidence: 0.69, y: 0.85),
        ])
        #expect(name == "Gluten Free Bread")
    }

    @Test("The top region is judged by the box's origin, from 0.7 up")
    func productNameRegionUsesOrigin() {
        #expect(PriceRanking.productName(in: [text("Rice Penne", y: 0.72)]) == "Rice Penne")
        // Its centre is at 0.74, but it starts below 0.7.
        #expect(PriceRanking.productName(in: [text("Rice Penne", y: 0.69, height: 0.1)]) == nil)
    }

    @Test("Between names of equal length, the more confident one wins")
    func productNameTieBreak() {
        let name = PriceRanking.productName(in: [
            text("Rice Penne", confidence: 0.8, y: 0.9),
            text("Corn Penne", confidence: 0.9, y: 0.8),
        ])
        #expect(name == "Corn Penne")
    }

    @Test("Names are trimmed, and under three characters is not a name")
    func productNameTrimsAndRejectsShortText() {
        #expect(PriceRanking.productName(in: [text("  Oats \n", y: 0.9)]) == "Oats")
        #expect(PriceRanking.productName(in: [text(" GF ", y: 0.9)]) == nil)
    }

    // MARK: - Reading Order

    /// The two orders differ on purpose. `b` starts higher but `a` reaches
    /// higher. A two-column receipt's label and amount are this shape, and
    /// receipt text must keep sorting by origin for `extractTotal` to find the
    /// amount on the line after its label.
    @Test("Selectable text sorts by centre; receipt text sorts by origin")
    func twoOrders() {
        let a = text("tall", y: 0.50, height: 0.10)  // centre 0.55
        let b = text("short", y: 0.52, height: 0.02)  // centre 0.53

        #expect(TextOrdering.selectableText([b, a]).map(\.text) == ["tall", "short"])
        #expect(TextOrdering.receiptText([a, b]) == "short\ntall")
    }

    @Test("Selectable text is trimmed, and empty or unconfident lines are dropped")
    func selectableFiltering() {
        let lines = TextOrdering.selectableText([
            text("  Gluten Free  ", y: 0.9),
            text("   ", y: 0.8),
            text("$7.49", confidence: 0.3, y: 0.7),
            text("400 g", y: 0.6),
        ])
        #expect(lines.map(\.text) == ["Gluten Free", "400 g"])
    }

    @Test("A region keeps only text that overlaps it, not text that only touches it")
    func selectableRegion() {
        let region = NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5)
        let lines = TextOrdering.selectableText([
            text("inside", y: 0.7),
            text("straddling", y: 0.48),
            text("touching", y: 0.25, height: 0.25),
            text("outside", y: 0.1),
        ], in: region)
        #expect(lines.map(\.text) == ["inside", "straddling"])
    }

    @Test("Receipt text is one trimmed line per confident observation, top first")
    func receiptLines() {
        let receipt = TextOrdering.receiptText([
            text("TOTAL 19.96", y: 0.1),
            text(" LOBLAWS ", y: 0.9),
            text("smudge", confidence: 0.2, y: 0.6),
            text("", y: 0.55),
            text("GF BREAD 5.99", y: 0.5),
        ])
        #expect(receipt == "LOBLAWS\nGF BREAD 5.99\nTOTAL 19.96")
    }

    @Test("Receipt regions split at 0.25 and 0.75 by origin", arguments: [
        (TextOrdering.ReceiptRegion.top, "header"),
        (.middle, "item\nlow item"),
        (.bottom, "footer"),
    ])
    func receiptRegions(region: TextOrdering.ReceiptRegion, expected: String) {
        let observations = [
            text("header", y: 0.75),
            text("item", y: 0.74),
            text("low item", y: 0.25),
            text("footer", y: 0.24),
        ]
        #expect(TextOrdering.receiptText(observations, region: region) == expected)
    }

    // MARK: - NormalizedRect

    /// The same cases as probing `CGRect.intersects` directly, so the core's
    /// rect selects the same region text the app's did.
    @Test("Intersection follows CGRect: shared edges and corners do not count")
    func intersects() {
        let unit = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        #expect(unit.intersects(NormalizedRect(x: 0.5, y: 0.5, width: 1, height: 1)))
        #expect(unit.intersects(NormalizedRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1)))
        #expect(unit.intersects(NormalizedRect(x: 0.5, y: 0.5, width: 0, height: 0)))
        #expect(unit.intersects(NormalizedRect(x: 1.5, y: 0, width: -1, height: 1)))
        #expect(!unit.intersects(NormalizedRect(x: 1, y: 0, width: 1, height: 1)))
        #expect(!unit.intersects(NormalizedRect(x: 1, y: 1, width: 1, height: 1)))
    }
}
