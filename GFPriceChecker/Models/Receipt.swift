//
//  Receipt.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation
import SwiftData
import UIKit
import SwiftUI

/// Represents a receipt that can verify one or more product pairs
///
/// Receipts provide documentation for audits and establish purchase verification.
/// One receipt can be associated with multiple ProductPair objects from the same shopping trip.
@Model
final class Receipt {

    // MARK: - Properties

    /// Unique identifier for this receipt
    var id: UUID

    /// Date when the purchase was made
    /// - Note: This is required as it's essential for tax year calculations
    var purchaseDate: Date

    /// Name of the store where products were purchased
    /// - Note: Optional - may be extracted from OCR or entered manually
    var storeName: String?

    /// UUID reference to the stored receipt image
    /// - Note: Optional - receipts can be added without images for manual tracking
    var receiptImageUUID: String?

    /// Total amount shown on the receipt
    /// - Note: Uses Decimal for currency accuracy. Optional as it may not always be captured.
    var totalAmount: Decimal?

    /// Raw text extracted from receipt via OCR
    /// - Note: Optional - stored for debugging OCR accuracy and manual verification
    var extractedOCRText: String?

    /// Product pairs verified by this receipt
    ///
    /// This establishes a one-to-many relationship where one receipt can verify
    /// multiple product pairs from the same shopping trip.
    /// - Note: The inverse relationship is automatically maintained by SwiftData
    @Relationship(deleteRule: .nullify, inverse: \ProductPair.receipt)
    var productPairs: [ProductPair]

    // MARK: - Computed Properties

    /// Number of product pairs verified by this receipt
    var verifiedProductCount: Int {
        productPairs.count
    }

    /// Total differential amount for all products on this receipt
    /// - Returns: Sum of all product pair differentials
    var totalDifferential: Decimal {
        productPairs.reduce(Decimal.zero) { sum, pair in
            sum + pair.differential
        }
    }

    // MARK: - Initialization

    /// Creates a new receipt with the specified values
    ///
    /// - Parameters:
    ///   - id: Unique identifier (default: auto-generated UUID)
    ///   - purchaseDate: Date of purchase (default: current date)
    ///   - storeName: Name of the store (optional)
    ///   - receiptImageUUID: Reference to stored receipt image (optional)
    ///   - totalAmount: Total amount on receipt (optional)
    ///   - extractedOCRText: Raw OCR text from receipt (optional)
    ///   - productPairs: Array of associated product pairs (default: empty array)
    init(
        id: UUID = UUID(),
        purchaseDate: Date = Date(),
        storeName: String? = nil,
        receiptImageUUID: String? = nil,
        totalAmount: Decimal? = nil,
        extractedOCRText: String? = nil,
        productPairs: [ProductPair] = []
    ) {
        self.id = id
        self.purchaseDate = purchaseDate
        self.storeName = storeName
        self.receiptImageUUID = receiptImageUUID
        self.totalAmount = totalAmount
        self.extractedOCRText = extractedOCRText
        self.productPairs = productPairs
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension Receipt {
    /// Sample receipt for testing and previews
    static var sample: Receipt {
        let receipt = Receipt(
            purchaseDate: Date(),
            storeName: "Loblaws",
            totalAmount: Decimal(string: "47.83")!,
            extractedOCRText: "LOBLAWS\n123 Main St\nDate: 2024-12-27\n...",
            productPairs: []
        )
        return receipt
    }

    /// Sample receipt with associated product pairs
    static func sampleWithProducts() -> Receipt {
        let product1 = ProductPair(
            gfProductName: "Udi's GF Bread",
            gfPrice: Decimal(string: "6.99")!,
            nonGFProductName: "Wonder Bread",
            nonGFPrice: Decimal(string: "3.49")!,
            verified: true
        )

        let product2 = ProductPair(
            gfProductName: "Barilla GF Pasta",
            gfPrice: Decimal(string: "5.49")!,
            nonGFProductName: "Barilla Pasta",
            nonGFPrice: Decimal(string: "2.29")!,
            verified: true
        )

        let receipt = Receipt(
            purchaseDate: Date(),
            storeName: "Loblaws",
            totalAmount: Decimal(string: "47.83")!,
            productPairs: [product1, product2]
        )

        return receipt
    }
}
#endif
