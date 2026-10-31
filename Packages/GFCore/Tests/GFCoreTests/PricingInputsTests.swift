//
//  PricingInputsTests.swift
//  GFCoreTests
//
//  Moved from GFPriceCheckerTests/QuantityReportingTests.swift and
//  CaptureFlowViewModelTests.swift on 2026-10-31 (#67).
//

import Foundation
import Testing
import GFCore

/// Pins the arithmetic in shared-docs' `PRODUCT_DEFINITION.md` §3.
///
/// `differential` and `normalizedDifferential` stay **per unit**; every place that totals
/// a purchase must reach for `extendedDifferential` / `extendedNormalizedDifferential`
/// instead. That split is deliberate — rates like `unitPriceDifferential` must never
/// scale — but it means a missed call site compiles, ships, and simply reports a smaller
/// number. So these tests use a quantity of 3 and assert exact totals.
@Suite("Pricing inputs")
struct PricingInputsTests {

    // MARK: - Fixture

    /// The numbers below are chosen so every derived value lands on an exact `Decimal`:
    ///
    /// - `differential`          = 7.99 − 3.49                = 4.50
    /// - `gfUnitPrice`           = 7.99 / 400                 = 0.019975
    /// - `regularUnitPrice`      = 3.49 / 200                 = 0.01745
    /// - `unitPriceDifferential` = 0.019975 − 0.01745         = 0.002525
    /// - `normalizedDifferential`= 0.002525 × 400             = 1.01
    ///
    /// Repeating decimals here would force approximate comparisons and hide small errors.
    private static let perUnitDifferential = Decimal(string: "4.50")!
    private static let perUnitNormalized = Decimal(string: "1.01")!

    private func makeInputs(quantity: Int, withSizeData: Bool = true) -> PricingInputs {
        PricingInputs(
            gfPrice: Decimal(string: "7.99")!,
            nonGFPrice: Decimal(string: "3.49")!,
            gfSizeValue: withSizeData ? 400 : nil,
            nonGFSizeValue: withSizeData ? 200 : nil,
            quantity: quantity
        )
    }

    /// Rounds to cents the way a currency display does.
    private func cents(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    // MARK: - Worked Example

    /// The spec's own example. The intermediate unit prices repeat (3.99 / 675), so the
    /// figure is compared at cents, which is how every surface shows it.
    @Test("The spec's worked example gives $5.63")
    func workedExample() throws {
        let inputs = PricingInputs(
            gfPrice: Decimal(string: "7.99")!,
            nonGFPrice: Decimal(string: "3.99")!,
            gfSizeValue: 400,
            nonGFSizeValue: 675
        )

        let normalized = try #require(inputs.normalizedDifferential)
        #expect(cents(normalized) == Decimal(string: "5.63")!)
        #expect(inputs.differential == Decimal(string: "4.00")!)
    }

    @Test("The size-adjusted differential normalizes for package size")
    func normalizedDifferential() {
        // GF: $6.00 for 500 g → $0.012/g.  Regular: $4.00 for 1000 g → $0.004/g.
        // Difference $0.008/g over the 500 g GF package → $4.00.
        let inputs = PricingInputs(
            gfPrice: Decimal(string: "6.00")!,
            nonGFPrice: Decimal(string: "4.00")!,
            gfSizeValue: 500,
            nonGFSizeValue: 1000
        )

        #expect(inputs.normalizedDifferential == Decimal(4))
    }

    // MARK: - Quantity

    @Test("Extended differentials scale with quantity, per-unit ones do not")
    func extendedDifferentialsScaleWithQuantity() {
        let inputs = makeInputs(quantity: 3)

        // Per-unit figures are what the detail view shows, and must ignore quantity.
        #expect(inputs.differential == Self.perUnitDifferential)
        #expect(inputs.normalizedDifferential == Self.perUnitNormalized)

        // Extended figures are what the reports and exports total.
        #expect(inputs.extendedDifferential == Decimal(string: "13.50")!)
        #expect(inputs.extendedNormalizedDifferential == Decimal(string: "3.03")!)
    }

    @Test("A single-unit purchase leaves the extended figures equal to the per-unit ones")
    func quantityOneIsIdentity() {
        let inputs = makeInputs(quantity: 1)

        #expect(inputs.extendedDifferential == inputs.differential)
        #expect(inputs.extendedNormalizedDifferential == inputs.normalizedDifferential)
    }

    @Test("Quantity defaults to a single unit")
    func quantityDefaultsToOne() {
        let inputs = PricingInputs(gfPrice: 5, nonGFPrice: 3)
        #expect(inputs.quantity == 1)
        #expect(inputs.extendedDifferential == 2)
    }

    @Test("Unit prices are rates and never scale with quantity")
    func ratesDoNotScaleWithQuantity() {
        let single = makeInputs(quantity: 1)
        let triple = makeInputs(quantity: 3)

        // Buying three loaves does not change the price per gram. If any of these ever
        // start tracking quantity, every unit price shown or exported becomes nonsense.
        #expect(triple.gfUnitPrice == single.gfUnitPrice)
        #expect(triple.regularUnitPrice == single.regularUnitPrice)
        #expect(triple.unitPriceDifferential == single.unitPriceDifferential)
        #expect(triple.unitPriceDifferential == Decimal(string: "0.002525")!)
    }

    // MARK: - Missing Size Data

    @Test("Extended normalized differential stays nil when size data is incomplete")
    func extendedNormalizedIsNilWithoutSizeData() {
        let inputs = makeInputs(quantity: 4, withSizeData: false)

        #expect(inputs.normalizedDifferential == nil)
        #expect(inputs.extendedNormalizedDifferential == nil)

        // The package differential still scales — only the size-adjusted one is unavailable.
        #expect(inputs.extendedDifferential == Decimal(string: "18.00")!)
    }

    @Test("One missing size is enough to leave the size-adjusted figures unavailable")
    func oneMissingSizeIsIncomplete() {
        let inputs = PricingInputs(
            gfPrice: Decimal(string: "6.00")!,
            nonGFPrice: Decimal(string: "4.00")!,
            gfSizeValue: 500
        )

        #expect(inputs.gfUnitPrice != nil)
        #expect(inputs.regularUnitPrice == nil)
        #expect(inputs.unitPriceDifferential == nil)
        #expect(inputs.normalizedDifferential == nil)
    }

    @Test("A zero size is not a size", arguments: [Decimal(0), Decimal(-5)])
    func nonPositiveSizeHasNoUnitPrice(size: Decimal) {
        let inputs = PricingInputs(gfPrice: 6, nonGFPrice: 4, gfSizeValue: size, nonGFSizeValue: size)

        #expect(inputs.gfUnitPrice == nil)
        #expect(inputs.regularUnitPrice == nil)
        #expect(inputs.normalizedDifferential == nil)
    }

    // MARK: - Back-Calculation

    @Test("Package size is back-calculated from price and unit price")
    func packageSizeBackCalculated() {
        // Cents basis: 50¢ per unit → $0.50 → 10 units for $5.00
        #expect(PricingInputs.packageSize(price: 5, unitPrice: 50, basis: .cents) == Decimal(10))

        // Dollars basis: $0.50 per unit → the same 10 units
        let half = Decimal(string: "0.50")!
        #expect(PricingInputs.packageSize(price: 5, unitPrice: half, basis: .dollars) == Decimal(10))
    }

    @Test("A zero or negative unit price leaves the size unknown", arguments: [Decimal(0), Decimal(-1)])
    func packageSizeNilWhenUnitPriceUnusable(unitPrice: Decimal) {
        #expect(
            PricingInputs.packageSize(price: 5, unitPrice: unitPrice, basis: .dollars) == nil,
            "Dividing by a zero unit price is not a size"
        )
    }

    // MARK: - Unit Price Convention

    @Test("Grams display per 100 g, every other unit per one unit")
    func unitPriceConvention() {
        #expect(SizeUnit.grams.unitPriceScaleFactor == 100)
        #expect(SizeUnit.grams.unitPriceLabel == "100g")

        for unit in SizeUnit.allCases where unit != .grams {
            #expect(unit.unitPriceScaleFactor == 1)
            #expect(unit.unitPriceLabel == unit.rawValue)
        }
    }
}
