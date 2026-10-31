//
//  CurrencyFormatTests.swift
//  GFCoreTests
//
//  Created by Claude Code on 2026-10-31.
//

import Foundation
import Testing
import GFCore

/// Money is shown rounded half-up (PRODUCT_DEFINITION.md §3)
@Suite("Currency format")
struct CurrencyFormatTests {

    /// Formats in a fixed locale, so the expected strings don't depend on the machine's
    private func text(_ value: String) -> String {
        Decimal(string: value)!.formatted(.cad.locale(Locale(identifier: "en_CA")))
    }

    @Test("A half cent rounds away from zero", arguments: [
        ("0.465", "$0.47"),
        ("0.475", "$0.48"),
        ("3.845", "$3.85"),
        ("6.745", "$6.75"),
        ("-0.125", "-$0.13"),
    ])
    func halfCentRoundsUp(value: String, expected: String) {
        #expect(text(value) == expected)
    }

    @Test("Anything off the half cent rounds to the nearest", arguments: [
        ("5.6256", "$5.63"),
        ("0.4649", "$0.46"),
        ("16.8767", "$16.88"),
        ("4", "$4.00"),
    ])
    func otherValuesRoundToNearest(value: String, expected: String) {
        #expect(text(value) == expected)
    }
}
