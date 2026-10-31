//
//  ValidationRules.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation
import GFCore

/// Validation for the app's forms, in the app's error type
///
/// The rules and limits are GFCore's `Validation`. This wraps the ones the app calls, and
/// maps each `ValidationError` to an `AppError` carrying the app's message.
struct ValidationRules {

    // MARK: - Constants

    /// Minimum purchase quantity
    static let minQuantity = Validation.minQuantity

    /// Maximum purchase quantity (sanity check)
    static let maxQuantity = Validation.maxQuantity

    // MARK: - Rules

    /// Validates a price string and converts to Decimal
    static func validatePriceString(_ priceString: String, fieldName: String = "Price") -> Result<Decimal, ErrorHandler.AppError> {
        Validation.validatePriceString(priceString, fieldName: fieldName).mapError(ErrorHandler.AppError.init)
    }

    /// Validates a product name, returning it trimmed
    static func validateProductName(_ name: String, fieldName: String = "Product name") -> Result<String, ErrorHandler.AppError> {
        Validation.validateProductName(name, fieldName: fieldName).mapError(ErrorHandler.AppError.init)
    }

    /// Validates a numeric size value entered as a string (nil means not provided)
    static func validateSizeValue(_ text: String, fieldName: String = "Size") -> Result<Decimal?, ErrorHandler.AppError> {
        Validation.validateSizeValue(text, fieldName: fieldName).mapError(ErrorHandler.AppError.init)
    }

    /// Validates a purchase quantity entered as text; an empty field means one unit
    static func validateQuantityString(_ text: String, fieldName: String = "Quantity") -> Result<Int, ErrorHandler.AppError> {
        Validation.validateQuantityString(text, fieldName: fieldName).mapError(ErrorHandler.AppError.init)
    }

    /// Validates an optional notes field
    static func validateNotes(_ notes: String?) -> Result<String?, ErrorHandler.AppError> {
        Validation.validateNotes(notes).mapError(ErrorHandler.AppError.init)
    }

    /// Validates an optional category field
    static func validateCategory(_ category: String?) -> Result<String?, ErrorHandler.AppError> {
        Validation.validateCategory(category).mapError(ErrorHandler.AppError.init)
    }
}

// MARK: - Messages

extension ErrorHandler.AppError {
    /// The app's error, and so its message, for a core validation failure
    ///
    /// - Note: Every message here is the one `ValidationRules` produced before the rules
    ///   moved to GFCore. Most ride on `.invalidProductName`, whose description appends
    ///   " cannot be empty", so they read oddly; see `ValidationMessageTests`.
    nonisolated init(_ error: ValidationError) {
        switch error {
        case .priceNegative:
            self = .priceNegative
        case .invalidPrice(let field):
            self = .invalidPrice(field)
        case .priceTooHigh(let price):
            self = .priceTooHigh(price)
        case .emptyRequiredField(let field):
            self = .emptyRequiredField(field)
        case .emptyProductName(let field):
            self = .invalidProductName(field)
        case .productNameTooLong(let field, let max):
            self = .invalidProductName("\(field) is too long (max \(max) characters)")
        case .dateInFuture:
            self = .invalidDate("Date cannot be in the future")
        case .dateBeforeEarliest:
            self = .invalidDate("Date must be after January 1, 2020")
        case .sizeNotANumber(let field):
            self = .invalidProductName("\(field) must be a number (e.g., 450 or 12.5)")
        case .sizeNotPositive(let field):
            self = .invalidProductName("\(field) must be greater than zero")
        case .sizeTooSmall(let field):
            self = .invalidProductName("\(field) is too small")
        case .sizeTooLarge(let field, let max):
            self = .invalidProductName("\(field) is unrealistically large (max \(max))")
        case .invalidQuantity(let field):
            self = .invalidQuantity(field)
        case .sizeTextTooLong(let max):
            self = .invalidProductName("Size is too long (max \(max) characters)")
        case .notesTooLong(let max):
            self = .invalidProductName("Notes are too long (max \(max) characters)")
        case .categoryTooLong(let max):
            self = .invalidProductName("Category is too long (max \(max) characters)")
        case .storeNameTooLong(let max):
            self = .invalidProductName("Store name is too long (max \(max) characters)")
        case .invalidEmail:
            self = .invalidProductName("Invalid email address")
        }
    }
}
