//
//  PricingInputs.swift
//  GFCore
//
//  Moved from GFPriceChecker/Models/ProductPair.swift and
//  CaptureFlowViewModel.swift on 2026-10-31 (#67).
//

import Foundation

/// The figures a product pair's arithmetic needs, and every formula in
/// `PRODUCT_DEFINITION.md` §3 over them.
///
/// `ProductPair.pricing` builds one of these, and the model's computed properties
/// forward here, so this is the only copy of the arithmetic.
public struct PricingInputs: Hashable, Sendable {

    /// Price of the gluten-free product in Canadian dollars
    public var gfPrice: Decimal

    /// Price of the regular product in Canadian dollars
    public var nonGFPrice: Decimal

    /// Numeric size of the gluten-free product, in the pair's shared unit
    public var gfSizeValue: Decimal?

    /// Numeric size of the regular product, in the pair's shared unit
    public var nonGFSizeValue: Decimal?

    /// Number of units purchased in the transaction
    public var quantity: Int

    public init(
        gfPrice: Decimal,
        nonGFPrice: Decimal,
        gfSizeValue: Decimal? = nil,
        nonGFSizeValue: Decimal? = nil,
        quantity: Int = 1
    ) {
        self.gfPrice = gfPrice
        self.nonGFPrice = nonGFPrice
        self.gfSizeValue = gfSizeValue
        self.nonGFSizeValue = nonGFSizeValue
        self.quantity = quantity
    }

    // MARK: - Per-Unit Figures

    /// The price differential between gluten-free and non-gluten-free products, for one unit
    ///
    /// - Important: This is a **per-unit** value and ignores `quantity`. Anything that totals
    ///   a purchase — report aggregates, export line items, grand totals — must use
    ///   `extendedDifferential` instead, or it will under-report multi-unit purchases.
    /// - Returns: The difference (gfPrice - nonGFPrice)
    public var differential: Decimal {
        gfPrice - nonGFPrice
    }

    /// Price per size unit for the GF product (nil if size is unavailable or zero)
    public var gfUnitPrice: Decimal? {
        guard let s = gfSizeValue, s > 0 else { return nil }
        return gfPrice / s
    }

    /// Price per size unit for the regular product (nil if size is unavailable or zero)
    public var regularUnitPrice: Decimal? {
        guard let s = nonGFSizeValue, s > 0 else { return nil }
        return nonGFPrice / s
    }

    /// Size-adjusted differential for one unit, normalized for package size
    ///
    /// Formula: (gfUnitPrice - regularUnitPrice) × gfSize
    /// Example: GF $7.99/400g vs Regular $3.99/675g → ($0.01997 - $0.00591) × 400 = $5.63
    /// Returns nil when size data is incomplete for either product.
    /// - Important: **Per-unit**, like `differential`. Totals must use
    ///   `extendedNormalizedDifferential`.
    public var normalizedDifferential: Decimal? {
        guard let gfU = gfUnitPrice,
              let regU = regularUnitPrice,
              let s = gfSizeValue else { return nil }
        return (gfU - regU) * s
    }

    /// Price difference per unit between GF and regular products (nil if size data incomplete)
    ///
    /// - Note: This is a rate ($/g, $/oz, …), so it deliberately does **not** scale with
    ///   `quantity`. Buying three loaves does not change the price per gram.
    public var unitPriceDifferential: Decimal? {
        guard let gfU = gfUnitPrice, let regU = regularUnitPrice else { return nil }
        return gfU - regU
    }

    // MARK: - Extended Figures

    /// The package price differential for the whole purchase: `differential` × `quantity`
    ///
    /// This is the figure that belongs in report totals and export line items.
    public var extendedDifferential: Decimal {
        differential * Decimal(quantity)
    }

    /// The size-adjusted differential for the whole purchase: `normalizedDifferential` × `quantity`
    ///
    /// Returns nil for the same reason `normalizedDifferential` does — incomplete size data.
    public var extendedNormalizedDifferential: Decimal? {
        normalizedDifferential.map { $0 * Decimal(quantity) }
    }

    // MARK: - Back-Calculation

    /// The package size implied by a price and a unit price: `price / unitPrice`.
    ///
    /// Capture uses this when the shelf tag gives a unit price instead of a package
    /// size. A unit price in cents is converted to dollars first.
    ///
    /// - Returns: `nil` when the unit price is zero or negative, which is not a size.
    public static func packageSize(
        price: Decimal,
        unitPrice: Decimal,
        basis: UnitPriceBasis
    ) -> Decimal? {
        guard unitPrice > 0 else { return nil }
        let unitPriceInDollars = basis == .cents ? unitPrice / 100 : unitPrice
        return price / unitPriceInDollars
    }
}
