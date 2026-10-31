//
//  DataBackupService.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation
import GFCore
import SwiftData
import UIKit

/// Service for backing up and restoring all app data to/from JSON files
///
/// Backup includes:
/// - All ProductPair records
/// - All Receipt records
/// - Associated images (Base64 encoded)
/// - App settings
/// - Metadata (version, timestamp)
@MainActor
final class DataBackupService {

    // MARK: - Singleton

    static let shared = DataBackupService()
    private init() {}

    // MARK: - Backup Data Structures

    /// Complete backup package
    struct BackupData: Codable {
        let version: String
        let timestamp: Date
        let appVersion: String
        let productPairs: [ProductPairBackup]
        let receipts: [ReceiptBackup]
        let settings: SettingsBackup
    }

    /// ProductPair backup representation
    ///
    /// - Note: `gfSizeValue`, `nonGFSizeValue`, `sizeUnit` and `quantity` are optional so that
    ///   backup files written before those fields existed still decode — a missing
    ///   key is only tolerated by `JSONDecoder` for optional properties. The `version` gate in
    ///   `importBackup` is all-or-nothing and has never been bumped, so a non-optional new
    ///   field here would reject every older backup outright.
    struct ProductPairBackup: Codable {
        let id: UUID
        let gfProductName: String
        let gfPrice: String // Decimal as String for JSON compatibility
        let gfSize: String?
        let gfSizeValue: String? // Decimal as String
        let gfImageUUID: String?
        let gfImageData: String? // Base64 encoded image
        let gfOCRConfidence: Float

        let nonGFProductName: String
        let nonGFPrice: String // Decimal as String
        let nonGFSize: String?
        let nonGFSizeValue: String? // Decimal as String
        let nonGFImageUUID: String?
        let nonGFImageData: String? // Base64 encoded image
        let nonGFOCRConfidence: Float

        let sizeUnit: String? // SizeUnit raw value, shared by both products
        let quantity: Int? // Units purchased; nil in backups written before quantity existed

        let createdDate: Date
        let category: String?
        let notes: String?
        let verified: Bool
        let receiptID: UUID? // Reference to receipt by ID
    }

    /// Receipt backup representation
    struct ReceiptBackup: Codable {
        let id: UUID
        let purchaseDate: Date
        let storeName: String?
        let receiptImageUUID: String?
        let receiptImageData: String? // Base64 encoded image
        let totalAmount: String? // Decimal as String
        let extractedOCRText: String?
        let productPairIDs: [UUID] // References to product pairs
    }

    /// Settings backup representation
    struct SettingsBackup: Codable {
        let userName: String
        let accountantEmail: String
        let taxID: String
        let currencySymbol: String
        let defaultPaperSize: String
        let defaultDateRange: String
    }

    // MARK: - Export

    /// Exports all app data to a JSON backup file
    ///
    /// - Parameter modelContext: SwiftData model context
    /// - Returns: JSON data ready to be saved
    /// - Throws: DataBackupError if export fails
    func exportBackup(modelContext: ModelContext) async throws -> Data {
        // Fetch all data
        let productPairDescriptor = FetchDescriptor<ProductPair>()
        let receiptDescriptor = FetchDescriptor<Receipt>()

        let productPairs = try modelContext.fetch(productPairDescriptor)
        let receipts = try modelContext.fetch(receiptDescriptor)

        // Convert to backup format
        var productPairBackups: [ProductPairBackup] = []
        for product in productPairs {
            let gfImageData = try await loadImageAsBase64(uuid: product.gfImageUUID, type: .product)
            let nonGFImageData = try await loadImageAsBase64(uuid: product.nonGFImageUUID, type: .product)

            let backup = ProductPairBackup(
                id: product.id,
                gfProductName: product.gfProductName,
                gfPrice: "\(product.gfPrice)",
                gfSize: product.gfSize,
                gfSizeValue: product.gfSizeValue.map { "\($0)" },
                gfImageUUID: product.gfImageUUID,
                gfImageData: gfImageData,
                gfOCRConfidence: product.gfOCRConfidence,
                nonGFProductName: product.nonGFProductName,
                nonGFPrice: "\(product.nonGFPrice)",
                nonGFSize: product.nonGFSize,
                nonGFSizeValue: product.nonGFSizeValue.map { "\($0)" },
                nonGFImageUUID: product.nonGFImageUUID,
                nonGFImageData: nonGFImageData,
                nonGFOCRConfidence: product.nonGFOCRConfidence,
                sizeUnit: product.sizeUnit,
                quantity: product.quantity,
                createdDate: product.createdDate,
                category: product.category,
                notes: product.notes,
                verified: product.verified,
                receiptID: product.receipt?.id
            )
            productPairBackups.append(backup)
        }

        var receiptBackups: [ReceiptBackup] = []
        for receipt in receipts {
            let receiptImageData = try await loadImageAsBase64(uuid: receipt.receiptImageUUID, type: .receipt)

            let backup = ReceiptBackup(
                id: receipt.id,
                purchaseDate: receipt.purchaseDate,
                storeName: receipt.storeName,
                receiptImageUUID: receipt.receiptImageUUID,
                receiptImageData: receiptImageData,
                totalAmount: receipt.totalAmount != nil ? "\(receipt.totalAmount!)" : nil,
                extractedOCRText: receipt.extractedOCRText,
                productPairIDs: receipt.productPairs.map { $0.id }
            )
            receiptBackups.append(backup)
        }

        // Get current settings
        let settings = AppSettings.shared
        let settingsBackup = SettingsBackup(
            userName: settings.userName,
            accountantEmail: settings.accountantEmail,
            taxID: settings.taxID,
            currencySymbol: settings.currencySymbol,
            defaultPaperSize: settings.defaultPaperSize.rawValue,
            defaultDateRange: settings.defaultDateRange.rawValue
        )

        // Create backup package
        let backup = BackupData(
            version: "1.0",
            timestamp: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            productPairs: productPairBackups,
            receipts: receiptBackups,
            settings: settingsBackup
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return try encoder.encode(backup)
    }

    // MARK: - Import

    /// Imports data from a JSON backup file
    ///
    /// - Parameters:
    ///   - data: JSON data to import
    ///   - modelContext: SwiftData model context
    ///   - strategy: Import strategy (replace or merge)
    /// - Throws: DataBackupError if import fails
    func importBackup(data: Data, modelContext: ModelContext, strategy: ImportStrategy) async throws {
        // Decode JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backup = try decoder.decode(BackupData.self, from: data)

        // Validate backup version
        guard backup.version == "1.0" else {
            throw DataBackupError.incompatibleVersion(backup.version)
        }

        // Clear existing data if replace strategy
        if strategy == .replace {
            try clearAllData(modelContext: modelContext)
        }

        // Create a mapping of IDs to restored objects
        var receiptMap: [UUID: Receipt] = [:]

        // Restore receipts first (since products reference them)
        for receiptBackup in backup.receipts {
            // Check if receipt already exists (for merge strategy)
            if strategy == .merge {
                let descriptor = FetchDescriptor<Receipt>(
                    predicate: #Predicate<Receipt> { $0.id == receiptBackup.id }
                )
                if let existing = try modelContext.fetch(descriptor).first {
                    receiptMap[receiptBackup.id] = existing
                    continue // Skip if already exists
                }
            }

            // Restore image if present
            var imageUUID: String?
            if let base64String = receiptBackup.receiptImageData {
                imageUUID = try await saveImageFromBase64(base64String: base64String, type: .receipt)
            }

            let receipt = Receipt(
                id: receiptBackup.id,
                purchaseDate: receiptBackup.purchaseDate,
                storeName: receiptBackup.storeName,
                receiptImageUUID: imageUUID ?? receiptBackup.receiptImageUUID,
                totalAmount: receiptBackup.totalAmount != nil ? Decimal(string: receiptBackup.totalAmount!) : nil,
                extractedOCRText: receiptBackup.extractedOCRText
            )

            modelContext.insert(receipt)
            receiptMap[receipt.id] = receipt
        }

        // Restore product pairs
        for productBackup in backup.productPairs {
            // Check if product already exists (for merge strategy)
            if strategy == .merge {
                let descriptor = FetchDescriptor<ProductPair>(
                    predicate: #Predicate<ProductPair> { $0.id == productBackup.id }
                )
                if try modelContext.fetch(descriptor).first != nil {
                    continue // Skip if already exists
                }
            }

            // Restore images if present
            var gfImageUUID: String?
            if let base64String = productBackup.gfImageData {
                gfImageUUID = try await saveImageFromBase64(base64String: base64String, type: .product)
            }

            var nonGFImageUUID: String?
            if let base64String = productBackup.nonGFImageData {
                nonGFImageUUID = try await saveImageFromBase64(base64String: base64String, type: .product)
            }

            // Find associated receipt
            let receipt = productBackup.receiptID != nil ? receiptMap[productBackup.receiptID!] : nil

            let product = ProductPair(
                gfProductName: productBackup.gfProductName,
                gfPrice: Decimal(string: productBackup.gfPrice) ?? 0,
                gfSize: productBackup.gfSize,
                gfSizeValue: productBackup.gfSizeValue.flatMap { Decimal(string: $0) },
                gfImageUUID: gfImageUUID ?? productBackup.gfImageUUID,
                gfOCRConfidence: productBackup.gfOCRConfidence,
                nonGFProductName: productBackup.nonGFProductName,
                nonGFPrice: Decimal(string: productBackup.nonGFPrice) ?? 0,
                nonGFSize: productBackup.nonGFSize,
                nonGFSizeValue: productBackup.nonGFSizeValue.flatMap { Decimal(string: $0) },
                nonGFImageUUID: nonGFImageUUID ?? productBackup.nonGFImageUUID,
                nonGFOCRConfidence: productBackup.nonGFOCRConfidence,
                sizeUnit: productBackup.sizeUnit,
                quantity: productBackup.quantity ?? 1,
                id: productBackup.id,
                createdDate: productBackup.createdDate,
                category: productBackup.category,
                notes: productBackup.notes,
                verified: productBackup.verified,
                receipt: receipt
            )

            modelContext.insert(product)

            // Add to receipt's product list if applicable
            if let receipt = receipt {
                receipt.productPairs.append(product)
            }
        }

        // Restore settings (don't override with empty values)
        let settings = AppSettings.shared
        if !backup.settings.userName.isEmpty {
            settings.userName = backup.settings.userName
        }
        if !backup.settings.accountantEmail.isEmpty {
            settings.accountantEmail = backup.settings.accountantEmail
        }
        if !backup.settings.taxID.isEmpty {
            settings.taxID = backup.settings.taxID
        }
        if !backup.settings.currencySymbol.isEmpty {
            settings.currencySymbol = backup.settings.currencySymbol
        }
        if let paperSize = PaperSize(rawValue: backup.settings.defaultPaperSize) {
            settings.defaultPaperSize = paperSize
        }
        if let dateRange = DateRangePreset(rawValue: backup.settings.defaultDateRange) {
            settings.defaultDateRange = dateRange
        }

        // Save context
        try modelContext.save()
    }

    // MARK: - Clear Data

    /// Clears all ProductPair and Receipt data (preserves settings)
    ///
    /// - Parameter modelContext: SwiftData model context
    /// - Throws: Error if deletion fails
    func clearAllData(modelContext: ModelContext) throws {
        // Delete all receipts
        let receiptDescriptor = FetchDescriptor<Receipt>()
        let receipts = try modelContext.fetch(receiptDescriptor)
        for receipt in receipts {
            // Delete receipt image
            if let uuid = receipt.receiptImageUUID {
                Task {
                    await ImageStorageService.shared.deleteImage(uuid: uuid, type: .receipt)
                }
            }
            modelContext.delete(receipt)
        }

        // Delete all product pairs
        let productDescriptor = FetchDescriptor<ProductPair>()
        let products = try modelContext.fetch(productDescriptor)
        for product in products {
            // Delete product images
            if let uuid = product.gfImageUUID {
                Task {
                    await ImageStorageService.shared.deleteImage(uuid: uuid, type: .product)
                }
            }
            if let uuid = product.nonGFImageUUID {
                Task {
                    await ImageStorageService.shared.deleteImage(uuid: uuid, type: .product)
                }
            }
            modelContext.delete(product)
        }

        try modelContext.save()
    }

    // MARK: - Helper Methods

    /// Loads an image as Base64 string
    private func loadImageAsBase64(uuid: String?, type: ImageStorageService.ImageType) async throws -> String? {
        guard let uuid = uuid else { return nil }

        guard let image = await ImageStorageService.shared.retrieveImage(uuid: uuid, type: type) else {
            return nil
        }

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }

        return imageData.base64EncodedString()
    }

    /// Saves a Base64 encoded image to storage
    private func saveImageFromBase64(base64String: String, type: ImageStorageService.ImageType) async throws -> String {
        guard let imageData = Data(base64Encoded: base64String) else {
            throw DataBackupError.invalidImageData
        }

        guard let image = UIImage(data: imageData) else {
            throw DataBackupError.invalidImageData
        }

        // Use ImageStorageService to save (it will handle subdirectories)
        guard let uuid = await ImageStorageService.shared.saveImage(image, type: type) else {
            throw DataBackupError.exportFailed("Failed to save restored image")
        }
        return uuid
    }
}

// MARK: - Import Strategy

extension DataBackupService {
    /// Strategy for importing backup data
    enum ImportStrategy {
        /// Replace all existing data with backup data
        case replace
        /// Merge backup data with existing data (skip duplicates by ID)
        case merge
    }
}

// MARK: - Errors

extension DataBackupService {
    enum DataBackupError: LocalizedError {
        case incompatibleVersion(String)
        case invalidImageData
        case exportFailed(String)
        case importFailed(String)

        var errorDescription: String? {
            switch self {
            case .incompatibleVersion(let version):
                return "This backup was created with an incompatible version (\(version)). Cannot restore."
            case .invalidImageData:
                return "Could not decode image data from backup."
            case .exportFailed(let reason):
                return "Backup export failed: \(reason)"
            case .importFailed(let reason):
                return "Backup import failed: \(reason)"
            }
        }
    }
}
