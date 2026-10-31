//
//  SizeTextParserTests.swift
//  GFCoreTests
//
//  Moved from GFPriceCheckerTests/CaptureFlowViewModelTests.swift on 2026-10-31 (#67).
//

import Testing
import GFCore

@Suite("Size text parser")
struct SizeTextParserTests {

    @Test("Package sizes parse to a value and a unit", arguments: [
        ("400g", "400", SizeUnit.grams),
        ("400 g", "400", SizeUnit.grams),
        ("1.5 L", "1.5", SizeUnit.liters),
        ("750mL", "750", SizeUnit.milliliters),
        ("2.5kg", "2.5", SizeUnit.kilograms),
        ("12oz", "12", SizeUnit.ounces),
        ("16 fl oz", "16", SizeUnit.flOunces),
        ("1.5 lb", "1.5", SizeUnit.pounds),
        ("24 count", "24", SizeUnit.count),
    ])
    func parseSize(input: String, value: String, unit: SizeUnit) {
        let parsed = SizeTextParser.parseSize(input)
        #expect(parsed.value == value)
        #expect(parsed.unit == unit)
    }

    @Test("A unit only counts when it sits immediately after the number")
    func unitsMustBeAdjacentToTheNumber() {
        // "kg" and "fl oz" each contain a shorter unit's suffix, so something
        // has to stop 2.5kg reading as 2.5 g. It is not pattern order — it is
        // that every pattern demands the number right before its suffix, and
        // the "k" and the "fl " are in the way.
        #expect(SizeTextParser.parseSize("2.5kg").unit == .kilograms)
        #expect(SizeTextParser.parseSize("16 fl. oz").unit == .flOunces)

        // The same rule, seen from the other side: a unit further along the
        // line is not this number's unit.
        #expect(SizeTextParser.parseSize("500 net g").unit == nil)
        #expect(SizeTextParser.parseUnitPrice("$1.49/each 100 g").unit == nil)
    }

    @Test("Unparseable size text comes back untouched for manual editing")
    func parseSizeFallsBackToRawText() {
        let parsed = SizeTextParser.parseSize("Family Pack")
        #expect(parsed.value == "Family Pack")
        #expect(parsed.unit == nil)
    }

    @Test("Unit prices parse to a value and a unit", arguments: [
        ("$1.49/100g", "1.49", SizeUnit.grams),
        ("0.99/oz", "0.99", SizeUnit.ounces),
        ("$3.50 / kg", "3.50", SizeUnit.kilograms),
        ("$0.45/100 mL", "0.45", SizeUnit.milliliters),
        ("$2.19/fl oz", "2.19", SizeUnit.flOunces),
    ])
    func parseUnitPrice(input: String, value: String, unit: SizeUnit) {
        let parsed = SizeTextParser.parseUnitPrice(input)
        #expect(parsed.value == value)
        #expect(parsed.unit == unit)
    }

    @Test("Unparseable unit price text comes back untouched")
    func parseUnitPriceFallsBackToRawText() {
        let parsed = SizeTextParser.parseUnitPrice("per package")
        #expect(parsed.value == "per package")
        #expect(parsed.unit == nil)
    }
}
