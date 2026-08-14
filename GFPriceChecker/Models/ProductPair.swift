//
//  ProductPair.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation
import SwiftData
import UIKit
import SwiftUI

/// Unit of measurement for product sizes
enum SizeUnit: String, CaseIterable, Sendable {
    case grams = "g"
    case kilograms = "kg"
    case milliliters = "mL"
    case liters = "L"
    case ounces = "oz"
    case pounds = "lb"
    case flOunces = "fl oz"
    case count = "count"

    var displayName: String { rawValue }

    /// Scaling factor for display: grams use $/100g convention; all other units display as-is
    var unitPriceScaleFactor: Decimal {
        self == .grams ? 100 : 1
    }

    /// Label used when displaying a unit price (e.g. "100g" for grams, "oz" for ounces)
    var unitPriceLabel: String {
        self == .grams ? "100g" : rawValue
    }
}

/// Represents a comparison between a gluten-free product and its non-gluten-free equivalent
///
/// This model is the core data structure for tracking price differentials between
/// gluten-free and regular products for celiac disease cost documentation.
///
/// - Important: Every stored property here is hand-duplicated in
///   `DataBackupService.ProductPairBackup`, and in the mapping code on both sides of it.
///   Adding a property without doing the same there compiles fine and ships fine — the
///   field is simply gone when the user restores a backup. This happened once already
///   with the unit-pricing fields (fixed in `b7216c9`). `DataBackupRoundTripTests` now
///   fails when the two drift apart; follow what that failure tells you rather than
///   updating the test's expected list to match.
@Model
final class ProductPair {

    // MARK: - Gluten-Free Product Properties

    /// Name of the gluten-free product
    var gfProductName: String

    /// Price of the gluten-free product in Canadian dollars
    /// - Note: Uses Decimal for currency accuracy (avoids floating-point precision errors)
    var gfPrice: Decimal

    /// Size or quantity of the gluten-free product (e.g., "450g", "12 oz")
    var gfSize: String?

    /// Numeric size of the gluten-free product (for unit price calculation)
    var gfSizeValue: Decimal?

    /// UUID reference to the stored product image (for future image storage integration)
    var gfImageUUID: String?

    /// OCR confidence score for gluten-free product data extraction
    /// - Note: Range 0.0 (no confidence) to 1.0 (high confidence). Default 0.0 for manual entry.
    var gfOCRConfidence: Float

    // MARK: - Non-Gluten-Free Product Properties

    /// Name of the non-gluten-free equivalent product
    var nonGFProductName: String

    /// Price of the non-gluten-free product in Canadian dollars
    /// - Note: Uses Decimal for currency accuracy (avoids floating-point precision errors)
    var nonGFPrice: Decimal

    /// Size or quantity of the non-gluten-free product (e.g., "450g", "12 oz")
    var nonGFSize: String?

    /// Numeric size of the non-gluten-free product (for unit price calculation)
    var nonGFSizeValue: Decimal?

    /// UUID reference to the stored product image (for future image storage integration)
    var nonGFImageUUID: String?

    /// OCR confidence score for non-gluten-free product data extraction
    /// - Note: Range 0.0 (no confidence) to 1.0 (high confidence). Default 0.0 for manual entry.
    var nonGFOCRConfidence: Float

    /// Shared unit of measurement for both size values (raw value of SizeUnit)
    var sizeUnit: String?

    // MARK: - Metadata Properties

    /// Unique identifier for this product pair
    var id: UUID

    /// Date and time when this product pair was created
    var createdDate: Date

    /// Optional category for organizing products (e.g., "Bread", "Pasta", "Flour")
    var category: String?

    /// Optional user notes or additional information
    var notes: String?

    /// Indicates whether this product pair has been verified with a receipt
    /// - Note: Important for audit trail and documentation requirements
    var verified: Bool

    /// Optional receipt that verifies this product pair
    ///
    /// When a product pair is verified with a receipt, this establishes a relationship
    /// to the Receipt object for audit trail purposes.
    /// - Note: Optional - product pairs can exist without receipt verification (manual entry)
    var receipt: Receipt?

    // MARK: - Computed Properties

    /// The price differential between gluten-free and non-gluten-free products
    ///
    /// This is the amount that can potentially be claimed as a medical expense deduction.
    /// - Returns: The difference (gfPrice - nonGFPrice)
    var differential: Decimal {
        gfPrice - nonGFPrice
    }

    /// The SizeUnit enum resolved from the raw sizeUnit string
    var resolvedSizeUnit: SizeUnit? {
        guard let raw = sizeUnit else { return nil }
        return SizeUnit(rawValue: raw)
    }

    /// Price per size unit for the GF product (nil if size is unavailable or zero)
    var gfUnitPrice: Decimal? {
        guard let s = gfSizeValue, s > 0 else { return nil }
        return gfPrice / s
    }

    /// Price per size unit for the regular product (nil if size is unavailable or zero)
    var regularUnitPrice: Decimal? {
        guard let s = nonGFSizeValue, s > 0 else { return nil }
        return nonGFPrice / s
    }

    /// Size-adjusted differential: the GF premium per purchase normalized for package size
    ///
    /// Formula: (gfUnitPrice - regularUnitPrice) × gfSize
    /// Example: GF $7.99/400g vs Regular $3.99/675g → ($0.01997 - $0.00591) × 400 = $5.63
    /// Returns nil when size data is incomplete for either product.
    var normalizedDifferential: Decimal? {
        guard let gfU = gfUnitPrice,
              let regU = regularUnitPrice,
              let s = gfSizeValue else { return nil }
        return (gfU - regU) * s
    }

    /// Price difference per unit between GF and regular products (nil if size data incomplete)
    var unitPriceDifferential: Decimal? {
        guard let gfU = gfUnitPrice, let regU = regularUnitPrice else { return nil }
        return gfU - regU
    }

    /// True when both size values and a unit are available to compute unit pricing
    var hasUnitPricingData: Bool {
        gfSizeValue != nil && nonGFSizeValue != nil && sizeUnit != nil
    }

    // MARK: - Initialization

    /// Creates a new product pair with the specified values
    ///
    /// - Parameters:
    ///   - gfProductName: Name of the gluten-free product (required)
    ///   - gfPrice: Price of the gluten-free product (required)
    ///   - gfSize: Size/quantity of the gluten-free product as display string (optional)
    ///   - gfSizeValue: Numeric size of the gluten-free product (optional)
    ///   - gfImageUUID: Image reference for the gluten-free product (optional)
    ///   - gfOCRConfidence: OCR confidence score for GF product (default: 0.0)
    ///   - nonGFProductName: Name of the non-gluten-free product (required)
    ///   - nonGFPrice: Price of the non-gluten-free product (required)
    ///   - nonGFSize: Size/quantity of the non-gluten-free product as display string (optional)
    ///   - nonGFSizeValue: Numeric size of the non-gluten-free product (optional)
    ///   - nonGFImageUUID: Image reference for the non-gluten-free product (optional)
    ///   - nonGFOCRConfidence: OCR confidence score for non-GF product (default: 0.0)
    ///   - sizeUnit: Shared unit of measurement for both size values (optional)
    ///   - id: Unique identifier (default: auto-generated UUID)
    ///   - createdDate: Creation timestamp (default: current date/time)
    ///   - category: Product category (optional)
    ///   - notes: Additional notes (optional)
    ///   - verified: Receipt verification status (default: false)
    ///   - receipt: Associated receipt for verification (optional)
    init(
        gfProductName: String,
        gfPrice: Decimal,
        gfSize: String? = nil,
        gfSizeValue: Decimal? = nil,
        gfImageUUID: String? = nil,
        gfOCRConfidence: Float = 0.0,
        nonGFProductName: String,
        nonGFPrice: Decimal,
        nonGFSize: String? = nil,
        nonGFSizeValue: Decimal? = nil,
        nonGFImageUUID: String? = nil,
        nonGFOCRConfidence: Float = 0.0,
        sizeUnit: String? = nil,
        id: UUID = UUID(),
        createdDate: Date = Date(),
        category: String? = nil,
        notes: String? = nil,
        verified: Bool = false,
        receipt: Receipt? = nil
    ) {
        self.gfProductName = gfProductName
        self.gfPrice = gfPrice
        self.gfSize = gfSize
        self.gfSizeValue = gfSizeValue
        self.gfImageUUID = gfImageUUID
        self.gfOCRConfidence = gfOCRConfidence

        self.nonGFProductName = nonGFProductName
        self.nonGFPrice = nonGFPrice
        self.nonGFSize = nonGFSize
        self.nonGFSizeValue = nonGFSizeValue
        self.nonGFImageUUID = nonGFImageUUID
        self.nonGFOCRConfidence = nonGFOCRConfidence

        self.sizeUnit = sizeUnit
        self.id = id
        self.createdDate = createdDate
        self.category = category
        self.notes = notes
        self.verified = verified
        self.receipt = receipt
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension ProductPair {
    /// Sample product pair for testing and previews
    static var sample: ProductPair {
        ProductPair(
            gfProductName: "Udi's Gluten Free Bread",
            gfPrice: Decimal(string: "7.99")!,
            gfSize: "400g",
            gfSizeValue: 400,
            gfOCRConfidence: 0.92,
            nonGFProductName: "Wonder Bread",
            nonGFPrice: Decimal(string: "3.99")!,
            nonGFSize: "675g",
            nonGFSizeValue: 675,
            nonGFOCRConfidence: 0.95,
            sizeUnit: SizeUnit.grams.rawValue,
            category: "Bread",
            notes: "Regular weekly purchase at Loblaws",
            verified: true
        )
    }

    /// Sample unverified product pair for testing
    static var sampleUnverified: ProductPair {
        ProductPair(
            gfProductName: "Barilla Gluten Free Pasta",
            gfPrice: Decimal(string: "5.49")!,
            gfSize: "340g",
            gfSizeValue: 340,
            nonGFProductName: "Barilla Regular Pasta",
            nonGFPrice: Decimal(string: "2.29")!,
            nonGFSize: "454g",
            nonGFSizeValue: 454,
            sizeUnit: SizeUnit.grams.rawValue,
            category: "Pasta",
            verified: false
        )
    }
}
#endif
