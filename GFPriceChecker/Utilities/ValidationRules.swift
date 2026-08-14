//
//  ValidationRules.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation

/// Validation rules for user input and data integrity
///
/// Provides validation for:
/// - Product names
/// - Prices
/// - Dates
/// - Other data fields
struct ValidationRules {

    // MARK: - Constants

    /// Maximum allowed price (sanity check)
    static let maxPrice: Decimal = 10_000.00

    /// Minimum allowed price
    static let minPrice: Decimal = 0.01

    /// Maximum allowed numeric size value (sanity check)
    static let maxSizeValue: Decimal = 100_000

    /// Minimum allowed numeric size value
    static let minSizeValue: Decimal = 0.001

    /// Minimum purchase quantity
    ///
    /// - Note: `nonisolated` so `ErrorHandler.AppError.errorDescription`, which is not
    ///   main-actor isolated, can quote the range in its message.
    nonisolated static let minQuantity = 1

    /// Maximum purchase quantity (sanity check)
    nonisolated static let maxQuantity = 999

    /// Maximum product name length
    static let maxProductNameLength = 200

    /// Minimum product name length
    static let minProductNameLength = 1

    /// Earliest valid receipt date (sanity check: year 2020)
    static let earliestValidDate: Date = {
        var components = DateComponents()
        components.year = 2020
        components.month = 1
        components.day = 1
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()

    // MARK: - Price Validation

    /// Validates a price value
    ///
    /// - Parameter price: The price to validate
    /// - Returns: Result with validated Decimal or error
    static func validatePrice(_ price: Decimal) -> Result<Decimal, ErrorHandler.AppError> {
        // Check for negative
        if price < 0 {
            return .failure(.priceNegative)
        }

        // Check for zero
        if price == 0 {
            return .failure(.invalidPrice("Price"))
        }

        // Check minimum
        if price < minPrice {
            return .failure(.invalidPrice("Price"))
        }

        // Check maximum (sanity check)
        if price > maxPrice {
            return .failure(.priceTooHigh(price))
        }

        return .success(price)
    }

    /// Validates a price string and converts to Decimal
    ///
    /// - Parameters:
    ///   - priceString: The price as a string
    ///   - fieldName: The field name for error messages
    /// - Returns: Result with validated Decimal or error
    static func validatePriceString(_ priceString: String, fieldName: String = "Price") -> Result<Decimal, ErrorHandler.AppError> {
        // Remove whitespace
        let trimmed = priceString.trimmingCharacters(in: .whitespaces)

        // Check if empty
        if trimmed.isEmpty {
            return .failure(.emptyRequiredField(fieldName))
        }

        // Try to convert to Decimal
        guard let decimal = Decimal(string: trimmed) else {
            return .failure(.invalidPrice(fieldName))
        }

        // Validate the decimal value
        return validatePrice(decimal)
    }

    // MARK: - Product Name Validation

    /// Validates a product name
    ///
    /// - Parameters:
    ///   - name: The product name to validate
    ///   - fieldName: The field name for error messages
    /// - Returns: Result with validated string or error
    static func validateProductName(_ name: String, fieldName: String = "Product name") -> Result<String, ErrorHandler.AppError> {
        // Trim whitespace
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if empty
        if trimmed.isEmpty {
            return .failure(.invalidProductName(fieldName))
        }

        // Check minimum length
        if trimmed.count < minProductNameLength {
            return .failure(.invalidProductName(fieldName))
        }

        // Check maximum length
        if trimmed.count > maxProductNameLength {
            return .failure(.invalidProductName("\(fieldName) is too long (max \(maxProductNameLength) characters)"))
        }

        return .success(trimmed)
    }

    // MARK: - Date Validation

    /// Validates a date
    ///
    /// - Parameter date: The date to validate
    /// - Returns: Result with validated Date or error
    static func validateDate(_ date: Date) -> Result<Date, ErrorHandler.AppError> {
        let now = Date()

        // Check if date is in the future
        if date > now {
            return .failure(.invalidDate("Date cannot be in the future"))
        }

        // Check if date is too far in the past (sanity check)
        if date < earliestValidDate {
            return .failure(.invalidDate("Date must be after January 1, 2020"))
        }

        return .success(date)
    }

    /// Validates a purchase date (for receipts)
    ///
    /// - Parameter date: The purchase date to validate
    /// - Returns: Result with validated Date or error
    static func validatePurchaseDate(_ date: Date) -> Result<Date, ErrorHandler.AppError> {
        return validateDate(date)
    }

    // MARK: - Optional Field Validation

    /// Validates a numeric size value entered as a string
    ///
    /// - Parameters:
    ///   - text: The size value as a string (empty string = not provided)
    ///   - fieldName: The field name for error messages
    /// - Returns: Result with validated Decimal (nil means not provided) or error
    static func validateSizeValue(_ text: String, fieldName: String = "Size") -> Result<Decimal?, ErrorHandler.AppError> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .success(nil) }

        guard let value = Decimal(string: trimmed) else {
            return .failure(.invalidProductName("\(fieldName) must be a number (e.g., 450 or 12.5)"))
        }

        guard value > 0 else {
            return .failure(.invalidProductName("\(fieldName) must be greater than zero"))
        }

        guard value >= minSizeValue else {
            return .failure(.invalidProductName("\(fieldName) is too small"))
        }

        guard value <= maxSizeValue else {
            return .failure(.invalidProductName("\(fieldName) is unrealistically large (max \(maxSizeValue))"))
        }

        return .success(value)
    }

    /// Validates a purchase quantity entered as text
    ///
    /// An empty field means "one unit", matching the model default, so the form does not
    /// force the user to type a 1 for the overwhelmingly common single-item case.
    ///
    /// - Parameters:
    ///   - text: The raw quantity string
    ///   - fieldName: Field name for the error message
    /// - Returns: Result with the validated quantity or error
    static func validateQuantityString(_ text: String, fieldName: String = "Quantity") -> Result<Int, ErrorHandler.AppError> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .success(minQuantity) }

        guard let value = Int(trimmed) else {
            return .failure(.invalidQuantity(fieldName))
        }

        guard value >= minQuantity, value <= maxQuantity else {
            return .failure(.invalidQuantity(fieldName))
        }

        return .success(value)
    }

    /// Validates an optional size field
    ///
    /// - Parameter size: The size string (optional)
    /// - Returns: Result with validated optional string or error
    static func validateSize(_ size: String?) -> Result<String?, ErrorHandler.AppError> {
        guard let size = size, !size.isEmpty else {
            return .success(nil)
        }

        let trimmed = size.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .success(nil)
        }

        // Check length
        if trimmed.count > 50 {
            return .failure(.invalidProductName("Size is too long (max 50 characters)"))
        }

        return .success(trimmed)
    }

    /// Validates an optional notes field
    ///
    /// - Parameter notes: The notes string (optional)
    /// - Returns: Result with validated optional string or error
    static func validateNotes(_ notes: String?) -> Result<String?, ErrorHandler.AppError> {
        guard let notes = notes, !notes.isEmpty else {
            return .success(nil)
        }

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .success(nil)
        }

        // Check length
        if trimmed.count > 1000 {
            return .failure(.invalidProductName("Notes are too long (max 1000 characters)"))
        }

        return .success(trimmed)
    }

    /// Validates an optional category field
    ///
    /// - Parameter category: The category string (optional)
    /// - Returns: Result with validated optional string or error
    static func validateCategory(_ category: String?) -> Result<String?, ErrorHandler.AppError> {
        guard let category = category, !category.isEmpty else {
            return .success(nil)
        }

        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .success(nil)
        }

        // Check length
        if trimmed.count > 50 {
            return .failure(.invalidProductName("Category is too long (max 50 characters)"))
        }

        return .success(trimmed)
    }

    // MARK: - Store Name Validation

    /// Validates a store name
    ///
    /// - Parameter storeName: The store name (optional)
    /// - Returns: Result with validated optional string or error
    static func validateStoreName(_ storeName: String?) -> Result<String?, ErrorHandler.AppError> {
        guard let storeName = storeName, !storeName.isEmpty else {
            return .success(nil)
        }

        let trimmed = storeName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .success(nil)
        }

        // Check length
        if trimmed.count > 100 {
            return .failure(.invalidProductName("Store name is too long (max 100 characters)"))
        }

        return .success(trimmed)
    }

    // MARK: - Email Validation

    /// Validates an email address
    ///
    /// - Parameter email: The email to validate (optional)
    /// - Returns: Result with validated optional string or error
    static func validateEmail(_ email: String?) -> Result<String?, ErrorHandler.AppError> {
        guard let email = email, !email.isEmpty else {
            return .success(nil)
        }

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .success(nil)
        }

        // Basic email validation
        let emailRegex = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES[c] %@", emailRegex)

        if !emailPredicate.evaluate(with: trimmed) {
            return .failure(.invalidProductName("Invalid email address"))
        }

        return .success(trimmed)
    }

    // MARK: - Combined Validation

    /// Validates a complete ProductPair
    ///
    /// - Parameters:
    ///   - gfProductName: Gluten-free product name
    ///   - gfPrice: Gluten-free product price
    ///   - nonGFProductName: Non-gluten-free product name
    ///   - nonGFPrice: Non-gluten-free product price
    ///   - category: Optional category
    ///   - notes: Optional notes
    /// - Returns: Result with success or first encountered error
    static func validateProductPair(
        gfProductName: String,
        gfPrice: Decimal,
        nonGFProductName: String,
        nonGFPrice: Decimal,
        category: String? = nil,
        notes: String? = nil
    ) -> Result<Void, ErrorHandler.AppError> {
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
