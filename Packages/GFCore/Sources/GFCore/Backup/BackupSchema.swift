//
//  BackupSchema.swift
//  GFCore
//
//  Moved from GFPriceChecker/Services/DataBackupService.swift on 2026-10-31 (#70).
//

import Foundation

// The JSON backup format. PRODUCT_DEFINITION.md §7 makes it the migration path between
// platforms, so these types are a shared contract: renaming a property renames a key, and
// every backup already written stops decoding. `BackupFormat` holds the coder settings and
// the version gate.
//
// Decimals are written as strings (`BackupFormat.string(from:)`), so no JSON number
// parser can round a price.

/// Complete backup package
public struct BackupData: Codable, Equatable, Sendable {
    public let version: String
    public let timestamp: Date
    public let appVersion: String
    public let productPairs: [ProductPairBackup]
    public let receipts: [ReceiptBackup]
    public let settings: SettingsBackup

    public init(
        version: String = BackupFormat.version,
        timestamp: Date,
        appVersion: String,
        productPairs: [ProductPairBackup],
        receipts: [ReceiptBackup],
        settings: SettingsBackup
    ) {
        self.version = version
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.productPairs = productPairs
        self.receipts = receipts
        self.settings = settings
    }
}

/// ProductPair backup representation
///
/// - Note: `gfSizeValue`, `nonGFSizeValue`, `sizeUnit` and `quantity` are optional so that
///   backup files written before those fields existed still decode — a missing
///   key is only tolerated by `JSONDecoder` for optional properties. The version gate in
///   `BackupFormat.decode` is all-or-nothing and has never been bumped, so a non-optional
///   new field here would reject every older backup outright.
public struct ProductPairBackup: Codable, Equatable, Sendable {
    public let id: UUID
    public let gfProductName: String
    public let gfPrice: String // Decimal as String for JSON compatibility
    public let gfSize: String?
    public let gfSizeValue: String? // Decimal as String
    public let gfImageUUID: String?
    public let gfImageData: String? // Base64 encoded image
    public let gfOCRConfidence: Float

    public let nonGFProductName: String
    public let nonGFPrice: String // Decimal as String
    public let nonGFSize: String?
    public let nonGFSizeValue: String? // Decimal as String
    public let nonGFImageUUID: String?
    public let nonGFImageData: String? // Base64 encoded image
    public let nonGFOCRConfidence: Float

    public let sizeUnit: String? // SizeUnit raw value, shared by both products
    public let quantity: Int? // Units purchased; nil in backups written before quantity existed

    public let createdDate: Date
    public let category: String?
    public let notes: String?
    public let verified: Bool
    public let receiptID: UUID? // Reference to receipt by ID

    public init(
        id: UUID,
        gfProductName: String,
        gfPrice: String,
        gfSize: String?,
        gfSizeValue: String?,
        gfImageUUID: String?,
        gfImageData: String?,
        gfOCRConfidence: Float,
        nonGFProductName: String,
        nonGFPrice: String,
        nonGFSize: String?,
        nonGFSizeValue: String?,
        nonGFImageUUID: String?,
        nonGFImageData: String?,
        nonGFOCRConfidence: Float,
        sizeUnit: String?,
        quantity: Int?,
        createdDate: Date,
        category: String?,
        notes: String?,
        verified: Bool,
        receiptID: UUID?
    ) {
        self.id = id
        self.gfProductName = gfProductName
        self.gfPrice = gfPrice
        self.gfSize = gfSize
        self.gfSizeValue = gfSizeValue
        self.gfImageUUID = gfImageUUID
        self.gfImageData = gfImageData
        self.gfOCRConfidence = gfOCRConfidence
        self.nonGFProductName = nonGFProductName
        self.nonGFPrice = nonGFPrice
        self.nonGFSize = nonGFSize
        self.nonGFSizeValue = nonGFSizeValue
        self.nonGFImageUUID = nonGFImageUUID
        self.nonGFImageData = nonGFImageData
        self.nonGFOCRConfidence = nonGFOCRConfidence
        self.sizeUnit = sizeUnit
        self.quantity = quantity
        self.createdDate = createdDate
        self.category = category
        self.notes = notes
        self.verified = verified
        self.receiptID = receiptID
    }

    /// Units purchased, reading a missing `quantity` as a single unit
    ///
    /// A record that predates quantity was always one unit. Anything else would inflate
    /// the amounts in a restored report.
    public var effectiveQuantity: Int {
        quantity ?? 1
    }
}

/// Receipt backup representation
public struct ReceiptBackup: Codable, Equatable, Sendable {
    public let id: UUID
    public let purchaseDate: Date
    public let storeName: String?
    public let receiptImageUUID: String?
    public let receiptImageData: String? // Base64 encoded image
    public let totalAmount: String? // Decimal as String
    public let extractedOCRText: String?
    public let productPairIDs: [UUID] // References to product pairs

    public init(
        id: UUID,
        purchaseDate: Date,
        storeName: String?,
        receiptImageUUID: String?,
        receiptImageData: String?,
        totalAmount: String?,
        extractedOCRText: String?,
        productPairIDs: [UUID]
    ) {
        self.id = id
        self.purchaseDate = purchaseDate
        self.storeName = storeName
        self.receiptImageUUID = receiptImageUUID
        self.receiptImageData = receiptImageData
        self.totalAmount = totalAmount
        self.extractedOCRText = extractedOCRText
        self.productPairIDs = productPairIDs
    }
}

/// Settings backup representation
///
/// Every field is a string, and an empty one means "not set": import leaves the current
/// setting alone rather than blanking it.
public struct SettingsBackup: Codable, Equatable, Sendable {
    public let userName: String
    public let accountantEmail: String
    public let taxID: String
    public let currencySymbol: String
    public let defaultPaperSize: String
    public let defaultDateRange: String

    public init(
        userName: String,
        accountantEmail: String,
        taxID: String,
        currencySymbol: String,
        defaultPaperSize: String,
        defaultDateRange: String
    ) {
        self.userName = userName
        self.accountantEmail = accountantEmail
        self.taxID = taxID
        self.currencySymbol = currencySymbol
        self.defaultPaperSize = defaultPaperSize
        self.defaultDateRange = defaultDateRange
    }
}
