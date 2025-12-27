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

/// Represents a comparison between a gluten-free product and its non-gluten-free equivalent
///
/// This model is the core data structure for tracking price differentials that can be
/// claimed as medical expense deductions for celiac disease tax purposes with the CRA.
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

    /// UUID reference to the stored product image (for future image storage integration)
    var nonGFImageUUID: String?

    /// OCR confidence score for non-gluten-free product data extraction
    /// - Note: Range 0.0 (no confidence) to 1.0 (high confidence). Default 0.0 for manual entry.
    var nonGFOCRConfidence: Float

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
    /// - Note: Important for CRA audit trail and documentation requirements
    var verified: Bool

    // MARK: - Computed Properties

    /// The price differential between gluten-free and non-gluten-free products
    ///
    /// This is the amount that can potentially be claimed as a medical expense deduction.
    /// - Returns: The difference (gfPrice - nonGFPrice)
    var differential: Decimal {
        gfPrice - nonGFPrice
    }

    // MARK: - Initialization

    /// Creates a new product pair with the specified values
    ///
    /// - Parameters:
    ///   - gfProductName: Name of the gluten-free product (required)
    ///   - gfPrice: Price of the gluten-free product (required)
    ///   - gfSize: Size/quantity of the gluten-free product (optional)
    ///   - gfImageUUID: Image reference for the gluten-free product (optional)
    ///   - gfOCRConfidence: OCR confidence score for GF product (default: 0.0)
    ///   - nonGFProductName: Name of the non-gluten-free product (required)
    ///   - nonGFPrice: Price of the non-gluten-free product (required)
    ///   - nonGFSize: Size/quantity of the non-gluten-free product (optional)
    ///   - nonGFImageUUID: Image reference for the non-gluten-free product (optional)
    ///   - nonGFOCRConfidence: OCR confidence score for non-GF product (default: 0.0)
    ///   - id: Unique identifier (default: auto-generated UUID)
    ///   - createdDate: Creation timestamp (default: current date/time)
    ///   - category: Product category (optional)
    ///   - notes: Additional notes (optional)
    ///   - verified: Receipt verification status (default: false)
    init(
        gfProductName: String,
        gfPrice: Decimal,
        gfSize: String? = nil,
        gfImageUUID: String? = nil,
        gfOCRConfidence: Float = 0.0,
        nonGFProductName: String,
        nonGFPrice: Decimal,
        nonGFSize: String? = nil,
        nonGFImageUUID: String? = nil,
        nonGFOCRConfidence: Float = 0.0,
        id: UUID = UUID(),
        createdDate: Date = Date(),
        category: String? = nil,
        notes: String? = nil,
        verified: Bool = false
    ) {
        self.gfProductName = gfProductName
        self.gfPrice = gfPrice
        self.gfSize = gfSize
        self.gfImageUUID = gfImageUUID
        self.gfOCRConfidence = gfOCRConfidence

        self.nonGFProductName = nonGFProductName
        self.nonGFPrice = nonGFPrice
        self.nonGFSize = nonGFSize
        self.nonGFImageUUID = nonGFImageUUID
        self.nonGFOCRConfidence = nonGFOCRConfidence

        self.id = id
        self.createdDate = createdDate
        self.category = category
        self.notes = notes
        self.verified = verified
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension ProductPair {
    /// Sample product pair for testing and previews
    static var sample: ProductPair {
        ProductPair(
            gfProductName: "Udi's Gluten Free Bread",
            gfPrice: Decimal(string: "6.99")!,
            gfSize: "450g",
            gfOCRConfidence: 0.92,
            nonGFProductName: "Wonder Bread",
            nonGFPrice: Decimal(string: "3.49")!,
            nonGFSize: "450g",
            nonGFOCRConfidence: 0.95,
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
            nonGFProductName: "Barilla Regular Pasta",
            nonGFPrice: Decimal(string: "2.29")!,
            nonGFSize: "454g",
            category: "Pasta",
            verified: false
        )
    }
}
#endif

// MARK: - Preview

#Preview("ProductPair Sample") {
    let sample = ProductPair.sample

    VStack(spacing: 20) {
        VStack(alignment: .leading) {
            Text("Gluten-Free Product")
                .font(.headline)
            Text(sample.gfProductName)
            Text("$\(sample.gfPrice as NSDecimalNumber)")
                .foregroundStyle(.green)
        }

        Divider()

        VStack(alignment: .leading) {
            Text("Regular Product")
                .font(.headline)
            Text(sample.nonGFProductName)
            Text("$\(sample.nonGFPrice as NSDecimalNumber)")
                .foregroundStyle(.blue)
        }

        Divider()

        VStack(alignment: .leading) {
            Text("Price Differential")
                .font(.headline)
            Text("$\(sample.differential as NSDecimalNumber)")
                .font(.title)
                .foregroundStyle(.orange)
                .bold()
        }

        if sample.verified {
            Label("Receipt Verified", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
    .padding()
}
