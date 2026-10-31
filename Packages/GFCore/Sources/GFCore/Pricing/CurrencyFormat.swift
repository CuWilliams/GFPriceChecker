//
//  CurrencyFormat.swift
//  GFCore
//
//  Created by Claude Code on 2026-10-31.
//

import Foundation

public extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    /// Canadian dollars, rounded half-up: a figure exactly on a half cent rounds away from
    /// zero, so $0.465 shows as $0.47 (PRODUCT_DEFINITION.md §3)
    ///
    /// Every money figure the product shows goes through this. `.currency(code:)` alone
    /// rounds half-even, which would show $0.46.
    static var cad: Self {
        .currency(code: "CAD").rounded(rule: .toNearestOrAwayFromZero)
    }
}
