//
//  ReceiptTotalTests.swift
//  GFCoreTests
//
//  Created by Claude Code on 2026-09-14. Moved from GFPriceCheckerTests on 2026-10-31 (#69).
//

import Foundation
import Testing
import GFCore

/// `extractTotal` against the shapes receipts actually print (issue #51).
///
/// `SubstituteScannerTests.receiptParses` covers the same ground end to end,
/// through real OCR over a drawn receipt — that is the test that proves the
/// reassembled text really arrives in these shapes. These are the cheap
/// counterpart: they pin each shape individually, and name the one the parser
/// is deliberately *not* willing to guess at.
///
/// Every case below marked "issue #51" returns nil before the fix, because the
/// old pattern was `#"\$(\d{1,4}\.\d{2})"# ` — a mandatory `$`, on the label's
/// own line.
@Suite("Receipt total extraction")
struct ReceiptTotalTests {

    private var parser: ReceiptParser.Type { ReceiptParser.self }

    // MARK: - Single Line

    @Test("A $-prefixed total on the label's line still parses")
    func dollarPrefixedTotal() {
        let text = """
        SUBTOTAL $17.66
        HST 13% $2.30
        TOTAL $19.96
        """
        #expect(parser.extractTotal(from: text) == Decimal(string: "19.96"))
    }

    /// issue #51, constraint 1: the symbol is in the header if it appears at all.
    @Test("A bare total on the label's line parses")
    func bareTotal() {
        let text = """
        SUBTOTAL     17.66
        HST 13%       2.30
        TOTAL        19.96
        """
        #expect(parser.extractTotal(from: text) == Decimal(string: "19.96"))
    }

    // MARK: - Two Columns

    /// issue #51, constraint 2: Vision returns the gap between the columns as an
    /// observation boundary, so the amount lands on its own line.
    @Test("A total split into its own column parses")
    func twoColumnTotal() {
        let text = """
        SUBTOTAL
        17.66
        HST 13%
        2.30
        TOTAL
        19.96
        THANK YOU FOR SHOPPING
        """
        #expect(parser.extractTotal(from: text) == Decimal(string: "19.96"))
    }

    @Test("A split total is not confused with the split subtotal above it")
    func twoColumnSubtotalIsSkipped() {
        let text = """
        SUBTOTAL
        17.66
        TOTAL
        19.96
        """
        let total = parser.extractTotal(from: text)
        #expect(total == Decimal(string: "19.96"))
        #expect(total != Decimal(string: "17.66"))
    }

    @Test("A split total parses with the symbol present too")
    func twoColumnWithSymbol() {
        let text = """
        TOTAL
        $19.96
        """
        #expect(parser.extractTotal(from: text) == Decimal(string: "19.96"))
    }

    // MARK: - Labels That Merely Contain "Total"

    /// Receipts print savings totals *below* the real one, and the scan runs
    /// bottom-up — so without this guard, dropping the `$` requirement would
    /// hand back the savings figure.
    @Test("A savings total printed below the real one does not win",
          arguments: ["TOTAL SAVINGS 3.40", "TOTAL SAVINGS\n3.40"])
    func savingsTotalIsSkipped(trailer: String) {
        let text = """
        TOTAL 19.96
        \(trailer)
        """
        #expect(parser.extractTotal(from: text) == Decimal(string: "19.96"))
    }

    @Test("An item count labelled TOTAL ITEMS does not win")
    func itemCountIsSkipped() {
        let text = """
        TOTAL 19.96
        TOTAL ITEMS 4
        """
        #expect(parser.extractTotal(from: text) == Decimal(string: "19.96"))
    }

    @Test("GRAND TOTAL is a total")
    func grandTotal() {
        let text = """
        SUBTOTAL 17.66
        GRAND TOTAL
        19.96
        """
        #expect(parser.extractTotal(from: text) == Decimal(string: "19.96"))
    }

    // MARK: - What It Declines To Guess

    @Test("A receipt with no total line yields nil")
    func noTotal() {
        let text = """
        LOBLAWS
        BREAD 3.29
        THANK YOU
        """
        #expect(parser.extractTotal(from: text) == nil)
    }

    /// The fall-through only accepts a line that is *nothing but* an amount,
    /// which is what a right-aligned column is. A number embedded in following
    /// prose is not the total column, and prefilling the wrong figure is worse
    /// than prefilling nothing — `ReceiptCaptureView` just leaves the field for
    /// the user on nil.
    @Test("An amount buried in the next line is not claimed as the total")
    func doesNotClaimEmbeddedAmount() {
        let text = """
        TOTAL
        VISA APPROVED 19.96
        """
        #expect(parser.extractTotal(from: text) == nil)
    }

    /// One line of reach, not a scan to the end of the receipt.
    @Test("The fall-through does not reach past the line below the label")
    func fallThroughReachesOneLine() {
        let text = """
        TOTAL
        CARD ENDING 1234
        19.96
        """
        #expect(parser.extractTotal(from: text) == nil)
    }
}
