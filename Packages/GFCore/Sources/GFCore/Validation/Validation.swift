//
//  Validation.swift
//  GFCore
//
//  Moved from GFPriceChecker/Utilities/ValidationRules.swift on 2026-10-31 (#70).
//

import Foundation

/// Why a value failed validation
///
/// The cases say what is wrong, not how to say it: the app maps each one to its own
/// user-facing message. Field names are passed through so that message can name the field.
public enum ValidationError: Error, Hashable, Sendable {
    // MARK: Price
    case priceNegative
    /// Zero, below `Validation.minPrice`, or not a number
    case invalidPrice(field: String)
    case priceTooHigh(Decimal)
    case emptyRequiredField(field: String)

    // MARK: Product name
    case emptyProductName(field: String)
    case productNameTooLong(field: String, max: Int)

    // MARK: Date
    case dateInFuture
    case dateBeforeEarliest

    // MARK: Size value
    case sizeNotANumber(field: String)
    case sizeNotPositive(field: String)
    case sizeTooSmall(field: String)
    case sizeTooLarge(field: String, max: Decimal)

    // MARK: Quantity
    /// Not a whole number, or outside `Validation.minQuantity...maxQuantity`
    case invalidQuantity(field: String)

    // MARK: Optional text fields
    case sizeTextTooLong(max: Int)
    case notesTooLong(max: Int)
    case categoryTooLong(max: Int)
    case storeNameTooLong(max: Int)

    // MARK: Email
    case invalidEmail
}

/// Validation rules for user input and data integrity
///
/// Text inputs are trimmed, and the trimmed value is what a success returns.
public enum Validation {

    // MARK: - Limits

    /// Maximum allowed price (sanity check)
    public static let maxPrice: Decimal = 10_000.00

    /// Minimum allowed price
    public static let minPrice: Decimal = 0.01

    /// Maximum allowed numeric size value (sanity check)
    public static let maxSizeValue: Decimal = 100_000

    /// Minimum allowed numeric size value
    public static let minSizeValue: Decimal = 0.001

    /// Minimum purchase quantity
    public static let minQuantity = 1

    /// Maximum purchase quantity (sanity check)
    public static let maxQuantity = 999

    /// Maximum product name length
    public static let maxProductNameLength = 200

    /// Minimum product name length
    public static let minProductNameLength = 1

    /// Maximum length of the free-text size field
    public static let maxSizeTextLength = 50

    /// Maximum notes length
    public static let maxNotesLength = 1000

    /// Maximum category length
    public static let maxCategoryLength = 50

    /// Maximum store name length
    public static let maxStoreNameLength = 100

    /// Earliest valid receipt date (sanity check): 1 January 2020 in `calendar`
    public static func earliestValidDate(in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = 2020
        components.month = 1
        components.day = 1
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - Price Validation

    /// Validates a price value
    public static func validatePrice(_ price: Decimal) -> Result<Decimal, ValidationError> {
        // Check for negative
        if price < 0 {
            return .failure(.priceNegative)
        }

        // Check for zero
        if price == 0 {
            return .failure(.invalidPrice(field: "Price"))
        }

        // Check minimum
        if price < minPrice {
            return .failure(.invalidPrice(field: "Price"))
        }

        // Check maximum (sanity check)
        if price > maxPrice {
            return .failure(.priceTooHigh(price))
        }

        return .success(price)
    }

    /// Validates a price string and converts to Decimal
    ///
    /// - Note: `fieldName` names only the empty and unparseable cases. A parsed value that
    ///   fails `validatePrice` reports the field as "Price", as it always has.
    public static func validatePriceString(_ priceString: String, fieldName: String = "Price") -> Result<Decimal, ValidationError> {
        // Remove whitespace
        let trimmed = priceString.trimmingCharacters(in: .whitespaces)

        // Check if empty
        if trimmed.isEmpty {
            return .failure(.emptyRequiredField(field: fieldName))
        }

        // Try to convert to Decimal
        guard let decimal = Decimal(string: trimmed) else {
            return .failure(.invalidPrice(field: fieldName))
        }

        // Validate the decimal value
        return validatePrice(decimal)
    }

    // MARK: - Product Name Validation

    /// Validates a product name
    public static func validateProductName(_ name: String, fieldName: String = "Product name") -> Result<String, ValidationError> {
        // Trim whitespace
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if empty
        if trimmed.isEmpty {
            return .failure(.emptyProductName(field: fieldName))
        }

        // Check minimum length
        if trimmed.count < minProductNameLength {
            return .failure(.emptyProductName(field: fieldName))
        }

        // Check maximum length
        if trimmed.count > maxProductNameLength {
            return .failure(.productNameTooLong(field: fieldName, max: maxProductNameLength))
        }

        return .success(trimmed)
    }

    // MARK: - Date Validation

    /// Validates a date: not after `now`, and not before `earliestValidDate(in: calendar)`
    public static func validateDate(_ date: Date, now: Date, calendar: Calendar) -> Result<Date, ValidationError> {
        // Check if date is in the future
        if date > now {
            return .failure(.dateInFuture)
        }

        // Check if date is too far in the past (sanity check)
        if date < earliestValidDate(in: calendar) {
            return .failure(.dateBeforeEarliest)
        }

        return .success(date)
    }

    /// Validates a purchase date (for receipts)
    public static func validatePurchaseDate(_ date: Date, now: Date, calendar: Calendar) -> Result<Date, ValidationError> {
        validateDate(date, now: now, calendar: calendar)
    }

    // MARK: - Optional Field Validation

    /// Validates a numeric size value entered as a string
    ///
    /// - Returns: The validated value, or `nil` for an empty string, meaning not provided
    public static func validateSizeValue(_ text: String, fieldName: String = "Size") -> Result<Decimal?, ValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .success(nil) }

        guard let value = Decimal(string: trimmed) else {
            return .failure(.sizeNotANumber(field: fieldName))
        }

        guard value > 0 else {
            return .failure(.sizeNotPositive(field: fieldName))
        }

        guard value >= minSizeValue else {
            return .failure(.sizeTooSmall(field: fieldName))
        }

        guard value <= maxSizeValue else {
            return .failure(.sizeTooLarge(field: fieldName, max: maxSizeValue))
        }

        return .success(value)
    }

    /// Validates a purchase quantity entered as text
    ///
    /// An empty field means "one unit", matching the model default, so the form does not
    /// force the user to type a 1 for the overwhelmingly common single-item case.
    public static func validateQuantityString(_ text: String, fieldName: String = "Quantity") -> Result<Int, ValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .success(minQuantity) }

        guard let value = Int(trimmed) else {
            return .failure(.invalidQuantity(field: fieldName))
        }

        guard value >= minQuantity, value <= maxQuantity else {
            return .failure(.invalidQuantity(field: fieldName))
        }

        return .success(value)
    }

    /// Validates an optional size field
    public static func validateSize(_ size: String?) -> Result<String?, ValidationError> {
        validateOptionalText(size, maxLength: maxSizeTextLength, tooLong: .sizeTextTooLong(max: maxSizeTextLength))
    }

    /// Validates an optional notes field
    public static func validateNotes(_ notes: String?) -> Result<String?, ValidationError> {
        validateOptionalText(notes, maxLength: maxNotesLength, tooLong: .notesTooLong(max: maxNotesLength))
    }

    /// Validates an optional category field
    public static func validateCategory(_ category: String?) -> Result<String?, ValidationError> {
        validateOptionalText(category, maxLength: maxCategoryLength, tooLong: .categoryTooLong(max: maxCategoryLength))
    }

    // MARK: - Store Name Validation

    /// Validates a store name
    public static func validateStoreName(_ storeName: String?) -> Result<String?, ValidationError> {
        validateOptionalText(storeName, maxLength: maxStoreNameLength, tooLong: .storeNameTooLong(max: maxStoreNameLength))
    }

    /// Trims an optional text field, treating empty and whitespace-only as not provided
    private static func validateOptionalText(
        _ text: String?,
        maxLength: Int,
        tooLong: ValidationError
    ) -> Result<String?, ValidationError> {
        guard let text, !text.isEmpty else {
            return .success(nil)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .success(nil)
        }

        // Check length
        if trimmed.count > maxLength {
            return .failure(tooLong)
        }

        return .success(trimmed)
    }

    // MARK: - Email Validation

    /// Validates an email address
    ///
    /// A basic shape check, case-insensitive: local part, `@`, domain, and a top-level
    /// domain of two or more letters.
    public static func validateEmail(_ email: String?) -> Result<String?, ValidationError> {
        guard let email, !email.isEmpty else {
            return .success(nil)
        }

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .success(nil)
        }

        // Built per call: `Regex` is not `Sendable`, so it can't be a static
        let emailPattern = /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/.ignoresCase()

        if trimmed.wholeMatch(of: emailPattern) == nil {
            return .failure(.invalidEmail)
        }

        return .success(trimmed)
    }

    // MARK: - Combined Validation

    /// Validates a complete product pair, returning the first error encountered
    public static func validateProductPair(
        gfProductName: String,
        gfPrice: Decimal,
        nonGFProductName: String,
        nonGFPrice: Decimal,
        category: String? = nil,
        notes: String? = nil
    ) -> Result<Void, ValidationError> {
        // Validate GF product name
        if case .failure(let error) = validateProductName(gfProductName, fieldName: "Gluten-free product name") {
            return .failure(error)
        }

        // Validate GF price
        if case .failure(let error) = validatePrice(gfPrice) {
            return .failure(error)
        }

        // Validate non-GF product name
        if case .failure(let error) = validateProductName(nonGFProductName, fieldName: "Regular product name") {
            return .failure(error)
        }

        // Validate non-GF price
        if case .failure(let error) = validatePrice(nonGFPrice) {
            return .failure(error)
        }

        // Validate optional fields
        if case .failure(let error) = validateCategory(category) {
            return .failure(error)
        }

        if case .failure(let error) = validateNotes(notes) {
            return .failure(error)
        }

        return .success(())
    }
}
