//
//  ValidationMessageTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-10-31 (#70).
//

import Foundation
import GFCore
import Testing
@testable import GFPriceChecker

/// The messages the app shows for each validation failure
///
/// The rules are GFCore's, tested in `ValidationTests`. What the app owns is the wording:
/// `AppError.init(_: ValidationError)` maps each case to the message `ValidationRules`
/// produced before the move, corrected in #82, and these pin every one of them.
@Suite("Validation messages")
@MainActor
struct ValidationMessageTests {

    private func message(_ error: ValidationError) -> String? {
        ErrorHandler.AppError(error).errorDescription
    }

    private func failureMessage<T>(_ result: Result<T, ErrorHandler.AppError>) -> String? {
        if case .failure(let error) = result { return error.errorDescription }
        return nil
    }

    @Test("Every validation error maps to its message")
    func everyCaseHasItsMessage() {
        let expected: [(ValidationError, String)] = [
            (.priceNegative, "Price cannot be negative"),
            (.invalidPrice(field: "GF price"), "GF price must be a valid dollar amount"),
            (.priceTooHigh(20_000), "Price $20000 seems unusually high. Please verify."),
            (.emptyRequiredField(field: "GF price"), "GF price is required"),
            (.emptyProductName(field: "Regular product name"), "Regular product name cannot be empty"),
            (.dateInFuture, "Invalid date: Date cannot be in the future"),
            (.dateBeforeEarliest, "Invalid date: Date must be after January 1, 2020"),
            (.invalidQuantity(field: "Quantity"), "Quantity must be a whole number between 1 and 999"),
        ]

        for (error, text) in expected {
            #expect(message(error) == text, "\(error)")
        }
    }

    @Test("Messages that don't mean an empty field don't say so (#82)")
    func noOtherMessageSaysCannotBeEmpty() {
        let sizeSuggestion = "Enter the size printed on the package as a number, such as 450 or 12.5."
        let expected: [(ValidationError, String, String)] = [
            (.productNameTooLong(field: "Product name", max: 200),
             "Product name is too long (max 200 characters)", "Shorten it to 200 characters or fewer."),
            (.sizeNotANumber(field: "GF size"), "GF size must be a number (e.g., 450 or 12.5)", sizeSuggestion),
            (.sizeNotPositive(field: "GF size"), "GF size must be greater than zero", sizeSuggestion),
            (.sizeTooSmall(field: "GF size"), "GF size is too small", sizeSuggestion),
            (.sizeTooLarge(field: "GF size", max: 100_000), "GF size is unrealistically large (max 100000)", sizeSuggestion),
            (.sizeTextTooLong(max: 50), "Size is too long (max 50 characters)", "Shorten it to 50 characters or fewer."),
            (.notesTooLong(max: 1000), "Notes are too long (max 1000 characters)", "Shorten it to 1000 characters or fewer."),
            (.categoryTooLong(max: 50), "Category is too long (max 50 characters)", "Shorten it to 50 characters or fewer."),
            (.storeNameTooLong(max: 100), "Store name is too long (max 100 characters)", "Shorten it to 100 characters or fewer."),
            (.invalidEmail, "Invalid email address", "Check the address, for example name@example.com."),
        ]

        for (error, text, suggestion) in expected {
            #expect(message(error) == text, "\(error)")
            #expect(ErrorHandler.AppError(error).recoverySuggestion == suggestion, "\(error)")
        }
    }

    @Test("An empty product name still says so, and asks for one")
    func emptyProductNameMessage() {
        let error = ErrorHandler.AppError(.emptyProductName(field: "GF product name"))
        #expect(error.errorDescription == "GF product name cannot be empty")
        #expect(error.recoverySuggestion == "Please enter a product name.")
    }

    @Test("The form's rules return the app's errors")
    func wrappersMapToAppErrors() throws {
        #expect(failureMessage(ValidationRules.validatePriceString("", fieldName: "Regular price")) == "Regular price is required")
        #expect(failureMessage(ValidationRules.validatePriceString("-1")) == "Price cannot be negative")
        #expect(failureMessage(ValidationRules.validateProductName(" ", fieldName: "Gluten-free product name"))
                == "Gluten-free product name cannot be empty")
        #expect(failureMessage(ValidationRules.validateSizeValue("0", fieldName: "Regular size"))
                == "Regular size must be greater than zero")
        #expect(failureMessage(ValidationRules.validateQuantityString("1000"))
                == "Quantity must be a whole number between 1 and 999")
        #expect(failureMessage(ValidationRules.validateNotes(String(repeating: "a", count: 1001)))
                == "Notes are too long (max 1000 characters)")
        #expect(failureMessage(ValidationRules.validateCategory(String(repeating: "a", count: 51)))
                == "Category is too long (max 50 characters)")

        // And pass a success through untouched
        #expect(try ValidationRules.validatePriceString(" 6.99 ").get() == Decimal(string: "6.99")!)
        #expect(try ValidationRules.validateProductName(" GF Bread ").get() == "GF Bread")
        #expect(try ValidationRules.validateSizeValue("").get() == nil)
        #expect(try ValidationRules.validateQuantityString("").get() == ValidationRules.minQuantity)
        #expect(try ValidationRules.validateNotes("  note ").get() == "note")
        #expect(try ValidationRules.validateCategory(nil).get() == nil)
    }
}
