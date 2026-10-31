//
//  SizeUnit.swift
//  GFCore
//
//  Moved from GFPriceChecker/Models/ProductPair.swift on 2026-10-31 (#67).
//

import Foundation

/// Unit of measurement for product sizes
public enum SizeUnit: String, CaseIterable, Sendable {
    case grams = "g"
    case kilograms = "kg"
    case milliliters = "mL"
    case liters = "L"
    case ounces = "oz"
    case pounds = "lb"
    case flOunces = "fl oz"
    case count = "count"

    public var displayName: String { rawValue }

    /// Scaling factor for display: grams use $/100g convention; all other units display as-is
    public var unitPriceScaleFactor: Decimal {
        self == .grams ? 100 : 1
    }

    /// Label used when displaying a unit price (e.g. "100g" for grams, "oz" for ounces)
    public var unitPriceLabel: String {
        self == .grams ? "100g" : rawValue
    }
}

/// Whether a unit price read off a shelf tag is in cents or dollars
public enum UnitPriceBasis: String, CaseIterable, Sendable {
    case cents = "Cents (¢)"
    case dollars = "Dollars ($)"
}
