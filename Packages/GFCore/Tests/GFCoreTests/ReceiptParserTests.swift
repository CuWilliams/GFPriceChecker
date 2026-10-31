//
//  ReceiptParserTests.swift
//  GFCoreTests
//
//  Created by Claude Code on 2026-10-31 (#69).
//

import Foundation
import Testing
import GFCore

/// Store name, date and line-item extraction. Until #69 none of these had a
/// test. `extractTotal` has its own suite, `ReceiptTotalTests`.
///
/// These pin what the parser does today, moved unchanged from the app. Where
/// that is arguably wrong, the test sits under "Known gaps" and says so. A fix
/// lands in its own PR and flips that test on purpose.
@Suite("Receipt parser")
struct ReceiptParserTests {

    // MARK: - Store Name

    @Test("A known store in the header is returned capitalised", arguments: [
        ("LOBLAWS #1234\n123 MAIN ST", "Loblaws"),
        ("Welcome to\nNO FRILLS", "No Frills"),
        ("REAL CANADIAN SUPERSTORE\nST. JOHN'S", "Real Canadian Superstore"),
        ("t&t supermarket", "T&T"),
        ("VALU-MART", "Valu-Mart"),
    ])
    func knownStore(text: String, expected: String) {
        #expect(ReceiptParser.extractStoreName(from: text) == expected)
    }

    @Test("An unknown all-caps header of three or more words is taken as the store")
    func allCapsHeader() {
        let text = "  FRESH MARKET GROCERS  \nBread 3.29"
        #expect(ReceiptParser.extractStoreName(from: text) == "FRESH MARKET GROCERS")
    }

    @Test("A two-word all-caps line is not enough to be a store")
    func twoWordHeaderIsNotAStore() {
        #expect(ReceiptParser.extractStoreName(from: "CORNER SHOP\nBread 3.29") == nil)
    }

    @Test("Only the first five lines are searched")
    func onlyTheHeaderIsSearched() {
        let text = (1...5).map { "line \($0)" }.joined(separator: "\n") + "\nLOBLAWS"
        #expect(ReceiptParser.extractStoreName(from: text) == nil)
    }

    /// Lines are taken in order and the all-caps fallback runs per line, so an
    /// all-caps greeting above the store's name wins.
    @Test("An earlier all-caps line beats a known store below it")
    func headerOrder() {
        let text = """
        WELCOME TO OUR STORE
        LOBLAWS
        """
        #expect(ReceiptParser.extractStoreName(from: text) == "WELCOME TO OUR STORE")
    }

    // MARK: - Date

    private func ymd(_ date: Date?) -> [Int?] {
        guard let date else { return [] }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return [parts.year, parts.month, parts.day]
    }

    /// There is no dotted formatter: ICU's parser accepts a `.` where the
    /// format has a `/`, so the slash formats read dotted dates too.
    @Test("Each supported format parses to the same day", arguments: [
        "DATE 2024-12-27 14:02",
        "12/27/2024",
        "12-27-2024",
        "27/12/2024",
        "27-12-2024",
        "12.27.2024",
        "27.12.2024",
        "Dec 27, 2024",
        "Dec 27 2024",
        "December 27, 2024",
    ])
    func supportedFormats(text: String) {
        #expect(ymd(ReceiptParser.extractDate(from: text)) == [2024, 12, 27])
    }

    @Test("A single-digit day parses in the month-name format")
    func singleDigitDay() {
        #expect(ymd(ReceiptParser.extractDate(from: "Mar 7, 2026")) == [2026, 3, 7])
    }

    /// Canadian receipts print both orders. The parser cannot know which it
    /// has, so when both readings are valid dates, month-first wins.
    @Test("An ambiguous numeric date reads month first")
    func ambiguousDateIsMonthFirst() {
        #expect(ymd(ReceiptParser.extractDate(from: "03/04/2026")) == [2026, 3, 4])
    }

    @Test("An ISO date wins over a numeric date earlier in the text")
    func isoHasPriority() {
        let text = """
        REF 01/02/2025
        2026-03-14
        """
        #expect(ymd(ReceiptParser.extractDate(from: text)) == [2026, 3, 14])
    }

    @Test("Text with no date yields nil")
    func noDate() {
        #expect(ReceiptParser.extractDate(from: "LOBLAWS\nTOTAL 19.96") == nil)
    }

    // MARK: - Line Items: Pass 1, Single Line

    @Test("A product with a $ price on the same line is one item")
    func singleLineItem() throws {
        let items = ReceiptParser.extractLineItems(from: "GF WHITE BREAD $5.99")

        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.productName == "GF WHITE BREAD")
        #expect(item.price == Decimal(string: "5.99"))
        // 0.7 base, +0.1 for several words, +0.1 for a price in $0.50-$50.
        #expect(abs(item.confidence - 0.9) < 0.0001)
    }

    @Test("Header and footer lines with a $ price are not items", arguments: [
        "SUBTOTAL $17.66", "TOTAL $19.96", "HST 13% $2.30", "DEBIT $19.96", "CHANGE $0.04",
    ])
    func headerAndFooterLinesAreSkipped(line: String) {
        #expect(ReceiptParser.extractLineItems(from: line).isEmpty)
    }

    @Test("A name with too few letters loses confidence")
    func unusualCharactersLowerConfidence() throws {
        let item = try #require(ReceiptParser.extractLineItems(from: "4011 #22 $1.29").first)
        #expect(item.productName == "4011 #22")
        // 0.7 base, +0.1 for two words, +0.1 for the price, then -0.2 because
        // only 1 of the 8 characters, the space, is a letter or whitespace.
        #expect(abs(item.confidence - 0.7) < 0.0001)
    }

    // MARK: - Line Items: Pass 2, Price Above Product (Costco)

    @Test("A Costco-style price line followed by its product is one item")
    func costcoLookBehind() throws {
        let text = """
        12.99 A
        1751411 B FREE TORTS
        """
        let item = try #require(ReceiptParser.extractLineItems(from: text).first)
        #expect(item.productName == "1751411 B FREE TORTS")
        #expect(item.price == Decimal(string: "12.99"))
        // 0.7 base, +0.1 words, +0.1 price, -0.2 for 13 of 20 characters being
        // letters or spaces = 0.7. Then x0.9 for spanning two lines, then x1.15
        // for the product code.
        #expect(abs(item.confidence - 0.7 * 0.9 * 1.15) < 0.0001)
    }

    @Test("A Costco discount line is not taken as the product")
    func costcoDiscountIsSkipped() {
        let text = """
        3.00-
        2029974 TPD/1751411
        """
        #expect(ReceiptParser.extractLineItems(from: text).isEmpty)
    }

    @Test("A standalone price outside $0.50-$200 is not paired", arguments: ["0.49", "200.01"])
    func implausiblePriceIsSkipped(price: String) {
        let text = "\(price)\nGLUTEN FREE BREAD"
        #expect(ReceiptParser.extractLineItems(from: text).isEmpty)
    }

    // MARK: - Line Items: Pass 3, Product Above Price

    @Test("A product followed by its price on the next line is one item")
    func forwardMultiLine() throws {
        let text = """
        GLUTEN FREE BREAD
        5.99
        """
        let item = try #require(ReceiptParser.extractLineItems(from: text).first)
        #expect(item.productName == "GLUTEN FREE BREAD")
        #expect(item.price == Decimal(string: "5.99"))
        #expect(abs(item.confidence - 0.9 * 0.9) < 0.0001)
    }

    @Test("A tax flag after a standalone price is allowed")
    func taxFlagIsAllowed() throws {
        let item = try #require(ReceiptParser.extractLineItems(from: "RICE PASTA\n3.49 H").first)
        #expect(item.price == Decimal(string: "3.49"))
    }

    // MARK: - Line Items: All Passes Together

    @Test("Each line is claimed by at most one item")
    func passesDoNotReuseLines() {
        let text = """
        LOBLAWS
        GF BREAD $5.99
        3.49
        RICE CRACKERS
        GLUTEN FREE PENNE
        4.29
        SUBTOTAL $13.77
        """
        let items = ReceiptParser.extractLineItems(from: text)
        #expect(items.map(\.productName) == ["GF BREAD", "RICE CRACKERS", "GLUTEN FREE PENNE"])
        #expect(items.map(\.price) == ["5.99", "3.49", "4.29"].map { Decimal(string: $0)! })
    }

    /// The look-behind pass runs first, so on a receipt that prints product
    /// first, the price between two names is given to the name *below* it.
    /// The first product and the last price are then left unpaired. Wiring
    /// matching up (#36, #22) needs a way to tell the two layouts apart.
    @Test("Known gap: product-first receipts with several items pair off by one")
    func productFirstReceiptsMisPair() {
        let text = """
        GLUTEN FREE BREAD
        5.99
        RICE CRACKERS
        3.49
        """
        let items = ReceiptParser.extractLineItems(from: text)
        #expect(items.count == 1)
        #expect(items.first?.productName == "RICE CRACKERS")
        #expect(items.first?.price == Decimal(string: "5.99"))
    }

    /// Discount keywords are matched as substrings, and "off" is inside
    /// "coffee".
    @Test("Known gap: a multi-line product containing \"off\" is taken as a discount")
    func coffeeIsADiscount() {
        #expect(ReceiptParser.extractLineItems(from: "GF COFFEE CAKE\n6.49").isEmpty)
    }
}
