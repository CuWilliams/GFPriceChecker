//
//  ValidationTests.swift
//  GFCoreTests
//
//  Quantity cases moved from GFPriceCheckerTests/QuantityReportingTests.swift on
//  2026-10-31 (#70). The rest are new.
//

import Foundation
import Testing
import GFCore

/// Every `Validation` rule, at and either side of its limits
///
/// The limits are sanity checks on user input, so the boundaries are what matter: a price
/// of exactly `maxPrice` is accepted and a cent more is not.
@Suite("Validation")
struct ValidationTests {

    private static func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    // MARK: - Price

    @Test("A price between the limits is accepted, the limits included",
          arguments: ["0.01", "6.99", "10000"])
    func priceWithinLimitsIsAccepted(price: String) {
        #expect(Validation.validatePrice(Self.decimal(price)) == .success(Self.decimal(price)))
    }

    @Test("A negative price is rejected as negative")
    func negativePriceIsRejected() {
        #expect(Validation.validatePrice(Self.decimal("-1")) == .failure(.priceNegative))
    }

    @Test("Zero and sub-cent prices are rejected as invalid, naming the field \"Price\"",
          arguments: ["0", "0.009"])
    func priceBelowMinimumIsRejected(price: String) {
        #expect(Validation.validatePrice(Self.decimal(price)) == .failure(.invalidPrice(field: "Price")))
    }

    @Test("A price over the maximum is rejected with the price")
    func priceOverMaximumIsRejected() {
        let price = Self.decimal("10000.01")
        #expect(Validation.validatePrice(price) == .failure(.priceTooHigh(price)))
    }

    @Test("A price string is trimmed and parsed")
    func priceStringIsParsed() {
        #expect(Validation.validatePriceString("  6.99 ") == .success(Self.decimal("6.99")))
    }

    @Test("An empty price string is a missing required field", arguments: ["", "   "])
    func emptyPriceStringIsRequired(input: String) {
        #expect(
            Validation.validatePriceString(input, fieldName: "GF price")
                == .failure(.emptyRequiredField(field: "GF price"))
        )
    }

    @Test("An unparseable price string is invalid, naming the field", arguments: ["abc", "$6.99"])
    func unparseablePriceStringIsInvalid(input: String) {
        #expect(
            Validation.validatePriceString(input, fieldName: "GF price")
                == .failure(.invalidPrice(field: "GF price"))
        )
    }

    @Test("A parsed price string out of range reports the value's error, not the field's")
    func parsedPriceStringUsesValueRules() {
        #expect(Validation.validatePriceString("0", fieldName: "GF price") == .failure(.invalidPrice(field: "Price")))
        #expect(Validation.validatePriceString("-2", fieldName: "GF price") == .failure(.priceNegative))
    }

    // MARK: - Product name

    @Test("A product name is returned trimmed")
    func productNameIsTrimmed() {
        #expect(Validation.validateProductName("  GF Bread\n") == .success("GF Bread"))
    }

    @Test("An empty product name is rejected, naming the field", arguments: ["", " \n\t "])
    func emptyProductNameIsRejected(input: String) {
        #expect(
            Validation.validateProductName(input, fieldName: "Regular product name")
                == .failure(.emptyProductName(field: "Regular product name"))
        )
    }

    @Test("A product name of exactly the maximum length is accepted, one more is not")
    func productNameLengthLimit() {
        let atLimit = String(repeating: "a", count: Validation.maxProductNameLength)
        #expect(Validation.validateProductName(atLimit) == .success(atLimit))
        #expect(
            Validation.validateProductName(atLimit + "a")
                == .failure(.productNameTooLong(field: "Product name", max: 200))
        )
    }

    // MARK: - Date

    private static var toronto: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    private static let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21

    @Test("The earliest valid date is midnight on 1 January 2020 in the given calendar")
    func earliestValidDateFollowsCalendar() {
        let earliest = Validation.earliestValidDate(in: Self.toronto)
        // 05:00 UTC is midnight in Toronto, which is on EST in January
        #expect(earliest == Date(timeIntervalSince1970: 1_577_854_800))
    }

    @Test("A date from the earliest valid date up to now is accepted")
    func dateInRangeIsAccepted() {
        let earliest = Validation.earliestValidDate(in: Self.toronto)
        for date in [earliest, Date(timeIntervalSince1970: 1_700_000_000), Self.now] {
            #expect(Validation.validateDate(date, now: Self.now, calendar: Self.toronto) == .success(date))
        }
    }

    @Test("A date after now is rejected")
    func futureDateIsRejected() {
        let date = Self.now.addingTimeInterval(1)
        #expect(Validation.validateDate(date, now: Self.now, calendar: Self.toronto) == .failure(.dateInFuture))
    }

    @Test("A date before the earliest valid date is rejected")
    func dateBeforeEarliestIsRejected() {
        let date = Validation.earliestValidDate(in: Self.toronto).addingTimeInterval(-1)
        #expect(Validation.validateDate(date, now: Self.now, calendar: Self.toronto) == .failure(.dateBeforeEarliest))
    }

    @Test("A purchase date follows the same rules as any date")
    func purchaseDateMatchesDate() {
        let future = Self.now.addingTimeInterval(1)
        #expect(Validation.validatePurchaseDate(future, now: Self.now, calendar: Self.toronto) == .failure(.dateInFuture))
        #expect(Validation.validatePurchaseDate(Self.now, now: Self.now, calendar: Self.toronto) == .success(Self.now))
    }

    // MARK: - Size value

    @Test("An empty size value means not provided", arguments: ["", "   "])
    func emptySizeValueIsNil(input: String) {
        #expect(Validation.validateSizeValue(input) == .success(nil))
    }

    @Test("A size value between the limits is accepted, the limits included",
          arguments: ["0.001", "450", "12.5", "100000"])
    func sizeValueWithinLimitsIsAccepted(input: String) {
        #expect(Validation.validateSizeValue(input) == .success(Self.decimal(input)))
    }

    @Test("Size values outside the limits are rejected with the matching reason")
    func sizeValueOutsideLimitsIsRejected() {
        #expect(Validation.validateSizeValue("abc", fieldName: "GF size") == .failure(.sizeNotANumber(field: "GF size")))
        #expect(Validation.validateSizeValue("0", fieldName: "GF size") == .failure(.sizeNotPositive(field: "GF size")))
        #expect(Validation.validateSizeValue("-5", fieldName: "GF size") == .failure(.sizeNotPositive(field: "GF size")))
        #expect(Validation.validateSizeValue("0.0009", fieldName: "GF size") == .failure(.sizeTooSmall(field: "GF size")))
        #expect(
            Validation.validateSizeValue("100000.1", fieldName: "GF size")
                == .failure(.sizeTooLarge(field: "GF size", max: 100_000))
        )
    }

    // MARK: - Quantity

    @Test("Empty quantity input means a single unit", arguments: ["", "   "])
    func emptyQuantityDefaultsToOne(input: String) {
        // The form leaves the field blank-able rather than forcing the user to type 1 for
        // the overwhelmingly common single-item case.
        #expect(Validation.validateQuantityString(input) == .success(Validation.minQuantity))
    }

    @Test("A whole number in range is accepted, the limits included", arguments: ["1", "12", "999", " 3 "])
    func validQuantityIsAccepted(input: String) {
        let expected = Int(input.trimmingCharacters(in: .whitespaces))!
        #expect(Validation.validateQuantityString(input) == .success(expected))
    }

    @Test(
        "Out-of-range and non-integer quantities are rejected",
        arguments: ["0", "-1", "1000", "2.5", "two", "3 loaves"]
    )
    func invalidQuantityIsRejected(input: String) {
        #expect(Validation.validateQuantityString(input) == .failure(.invalidQuantity(field: "Quantity")))
    }

    // MARK: - Optional text fields

    /// Each optional text rule, with its limit and the error it gives over it
    private static let optionalTextRules: [(name: String, limit: Int, validate: @Sendable (String?) -> Result<String?, ValidationError>, tooLong: ValidationError)] = [
        ("size", 50, Validation.validateSize, .sizeTextTooLong(max: 50)),
        ("notes", 1000, Validation.validateNotes, .notesTooLong(max: 1000)),
        ("category", 50, Validation.validateCategory, .categoryTooLong(max: 50)),
        ("store name", 100, Validation.validateStoreName, .storeNameTooLong(max: 100)),
    ]

    @Test("Optional text that is missing, empty or blank means not provided")
    func blankOptionalTextIsNil() {
        for rule in Self.optionalTextRules {
            for input in [nil, "", "  \n "] as [String?] {
                #expect(rule.validate(input) == .success(nil), "\(rule.name): \(String(describing: input))")
            }
        }
    }

    @Test("Optional text is trimmed, and accepted up to its limit but not past it")
    func optionalTextLengthLimit() {
        for rule in Self.optionalTextRules {
            let atLimit = String(repeating: "a", count: rule.limit)
            #expect(rule.validate("  Bread \n") == .success("Bread"), "\(rule.name)")
            #expect(rule.validate(atLimit) == .success(atLimit), "\(rule.name)")
            #expect(rule.validate(atLimit + "a") == .failure(rule.tooLong), "\(rule.name)")
        }
    }

    // MARK: - Email

    @Test("A missing, empty or blank email means not provided", arguments: [nil, "", "   "] as [String?])
    func blankEmailIsNil(input: String?) {
        #expect(Validation.validateEmail(input) == .success(nil))
    }

    @Test(
        "A well-formed email is accepted, trimmed, whatever its case",
        arguments: ["a@b.co", "user.name+tag@example.ca", "First_Last%1@Mail-Host.Example.COM", " me@x.org\n"]
    )
    func validEmailIsAccepted(input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(Validation.validateEmail(input) == .success(trimmed))
    }

    @Test(
        "A malformed email is rejected",
        arguments: ["plainaddress", "a@b", "a@b.c", "@example.com", "a b@example.com", "a@example.com x", "a@@example.com", "a@example.c0m"]
    )
    func malformedEmailIsRejected(input: String) {
        #expect(Validation.validateEmail(input) == .failure(.invalidEmail))
    }

    // MARK: - Product pair

    @Test("A valid pair passes")
    func validPairPasses() {
        let result = Validation.validateProductPair(
            gfProductName: "GF Bread", gfPrice: Self.decimal("7.99"),
            nonGFProductName: "Bread", nonGFPrice: Self.decimal("3.49"),
            category: "Bread", notes: nil
        )
        #expect((try? result.get()) != nil)
    }

    @Test("A pair reports its first failure, in field order")
    func pairReportsFirstFailure() {
        func failure(
            gfName: String = "GF Bread", gfPrice: String = "7.99",
            regularName: String = "Bread", regularPrice: String = "3.49",
            category: String? = nil, notes: String? = nil
        ) -> ValidationError? {
            let result = Validation.validateProductPair(
                gfProductName: gfName, gfPrice: Self.decimal(gfPrice),
                nonGFProductName: regularName, nonGFPrice: Self.decimal(regularPrice),
                category: category, notes: notes
            )
            if case .failure(let error) = result { return error }
            return nil
        }

        let longNotes = String(repeating: "a", count: 1001)
        let longCategory = String(repeating: "a", count: 51)

        // Everything wrong at once: the GF name comes first
        #expect(
            failure(gfName: "", gfPrice: "0", regularName: "", regularPrice: "0", category: longCategory, notes: longNotes)
                == .emptyProductName(field: "Gluten-free product name")
        )
        #expect(failure(gfPrice: "-1", regularName: "") == .priceNegative)
        #expect(failure(regularName: "", regularPrice: "0") == .emptyProductName(field: "Regular product name"))
        #expect(failure(regularPrice: "20000", category: longCategory) == .priceTooHigh(20_000))
        #expect(failure(category: longCategory, notes: longNotes) == .categoryTooLong(max: 50))
        #expect(failure(notes: longNotes) == .notesTooLong(max: 1000))
    }
}
