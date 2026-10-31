//
//  PlainDecimal.swift
//  GFCore
//
//  Created on 2026-10-31 (#84).
//

import Foundation

/// A decimal number written the plain way, the only way the product reads decimal text
///
/// An optional leading `-`, then ASCII digits with at most one `.`, and at least one digit
/// somewhere: `6.99`, `.5` and `5.` all qualify. Nothing else does: no `+`, exponent, grouping
/// separator, currency symbol, space, non-ASCII digit or trailing text (PRODUCT_DEFINITION.md
/// §2).
///
/// `Decimal(string:)` reads the longest number at the start of a string and ignores the rest,
/// so on its own it turned "1,5" into 1. Checking the whole string first means text that
/// can only be half-read is rejected, never silently changed.
struct PlainDecimal: Sendable {
    let value: Decimal

    /// How many digits follow the `.`, trailing zeros included
    let fractionDigits: Int

    /// `text` as a plain decimal, or `nil` if any of it is anything else. Not trimmed.
    init?(_ text: some StringProtocol) {
        var integerDigits = 0
        var fractionDigits = 0
        var seenPoint = false
        var hasMinus = false

        for (offset, byte) in text.utf8.enumerated() {
            switch byte {
            case UInt8(ascii: "-") where offset == 0:
                hasMinus = true
            case UInt8(ascii: "."):
                guard !seenPoint else { return nil }
                seenPoint = true
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                if seenPoint { fractionDigits += 1 } else { integerDigits += 1 }
            default:
                return nil
            }
        }

        guard integerDigits + fractionDigits > 0 else { return nil }

        // Spell it the way `Decimal(string:)` reads most surely, a digit either side of the
        // point, and in POSIX so the device locale has no say
        var digits = text.drop { $0 == "-" }
        if digits.hasSuffix(".") { digits = digits.dropLast() }
        let spelled = (hasMinus ? "-" : "") + (digits.hasPrefix(".") ? "0" : "") + digits

        guard let value = Decimal(string: spelled, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        self.value = value
        self.fractionDigits = fractionDigits
    }
}
