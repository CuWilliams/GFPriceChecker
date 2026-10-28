//
//  ImageStorageService.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import UIKit
import Foundation

/// Service for storing and retrieving product and receipt images
///
/// Handles image persistence to the app's Documents directory with:
/// - UUID-based filenames for uniqueness
/// - Thumbnail generation for list performance
/// - JPEG compression for reasonable file sizes
/// - Organized subdirectories for products and receipts
@MainActor
final class ImageStorageService {

    // MARK: - Types

    /// Type of image being stored
    enum ImageType {
        case product
        case receipt

        var subdirectory: String {
            switch self {
            case .product: return "products"
            case .receipt: return "receipts"
            }
        }
    }

    /// Errors that can occur during image operations
    enum ImageStorageError: Error {
        case invalidImageData
        case failedToCreateDirectory
        case failedToSaveImage
        case failedToDeleteImage
    }

    // MARK: - Properties

    /// Shared singleton instance
    static let shared = ImageStorageService()

    /// Documents directory URL
    private let documentsDirectory: URL

    /// JPEG compression quality (0.0 to 1.0)
    private let compressionQuality: CGFloat = 0.7

    /// Maximum thumbnail width in pixels
    private let thumbnailMaxWidth: CGFloat = 200

    // MARK: - Initialization

    private init() {
        // Get documents directory
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Unable to access documents directory")
        }
        self.documentsDirectory = documentsURL
    }

    // MARK: - Save Image

    /// Saves an image and creates a thumbnail
    ///
    /// - Parameters:
    ///   - image: The UIImage to save
    ///   - type: The type of image (product or receipt)
    /// - Returns: UUID string for the saved image, or nil if save failed
    func saveImage(_ image: UIImage, type: ImageType) async -> String? {
        let uuid = UUID().uuidString

        // Ensure subdirectory exists
        guard let subdirectoryURL = try? createSubdirectoryIfNeeded(for: type) else {
            return nil
        }

        // Save full image
        let fullImageURL = subdirectoryURL.appendingPathComponent("\(uuid).jpg")
        guard let fullImageData = image.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }

        do {
            try fullImageData.write(to: fullImageURL)
        } catch {
            ErrorHandler.shared.log(error, context: "Saving full image")
            return nil
        }

        // Create and save thumbnail
        if let thumbnail = createThumbnail(from: image) {
            let thumbnailURL = subdirectoryURL.appendingPathComponent("\(uuid)_thumb.jpg")
            if let thumbnailData = thumbnail.jpegData(compressionQuality: compressionQuality) {
                try? thumbnailData.write(to: thumbnailURL)
            }
        }

        return uuid
    }

    // MARK: - Retrieve Image

    /// Retrieves the full-size image by UUID
    ///
    /// - Parameters:
    ///   - uuid: The UUID string of the image
    ///   - type: The type of image (product or receipt)
    /// - Returns: UIImage if found, nil otherwise
    func retrieveImage(uuid: String, type: ImageType) async -> UIImage? {
        let subdirectoryURL = documentsDirectory.appendingPathComponent(type.subdirectory)
        let imageURL = subdirectoryURL.appendingPathComponent("\(uuid).jpg")

        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            return nil
        }

        guard let imageData = try? Data(contentsOf: imageURL) else {
            return nil
        }

        return UIImage(data: imageData)
    }

    /// Retrieves the thumbnail image by UUID
    ///
    /// - Parameters:
    ///   - uuid: The UUID string of the image
    ///   - type: The type of image (product or receipt)
    /// - Returns: UIImage thumbnail if found, nil otherwise
    func retrieveThumbnail(uuid: String, type: ImageType) async -> UIImage? {
        let subdirectoryURL = documentsDirectory.appendingPathComponent(type.subdirectory)
        let thumbnailURL = subdirectoryURL.appendingPathComponent("\(uuid)_thumb.jpg")

        guard FileManager.default.fileExists(atPath: thumbnailURL.path) else {
            return nil
        }

        guard let imageData = try? Data(contentsOf: thumbnailURL) else {
            return nil
        }

        return UIImage(data: imageData)
    }

    // MARK: - Delete Image

    /// Deletes both the full image and thumbnail
    ///
    /// - Parameters:
    ///   - uuid: The UUID string of the image to delete
    ///   - type: The type of image (product or receipt)
    /// - Returns: True if deletion was successful, false otherwise
    @discardableResult
    func deleteImage(uuid: String, type: ImageType) async -> Bool {
        let subdirectoryURL = documentsDirectory.appendingPathComponent(type.subdirectory)
        let imageURL = subdirectoryURL.appendingPathComponent("\(uuid).jpg")
        let thumbnailURL = subdirectoryURL.appendingPathComponent("\(uuid)_thumb.jpg")

        var success = true

        // Delete full image
        if FileManager.default.fileExists(atPath: imageURL.path) {
            do {
                try FileManager.default.removeItem(at: imageURL)
            } catch {
                ErrorHandler.shared.log(error, context: "Deleting image")
                success = false
            }
        }

        // Delete thumbnail
        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            do {
                try FileManager.default.removeItem(at: thumbnailURL)
            } catch {
                ErrorHandler.shared.log(error, context: "Deleting thumbnail")
                success = false
            }
        }

        return success
    }

    // MARK: - Helper Methods

    /// Creates subdirectory if it doesn't exist
    private func createSubdirectoryIfNeeded(for type: ImageType) throws -> URL {
        let subdirectoryURL = documentsDirectory.appendingPathComponent(type.subdirectory)

        if !FileManager.default.fileExists(atPath: subdirectoryURL.path) {
            try FileManager.default.createDirectory(
                at: subdirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        return subdirectoryURL
    }

    /// Creates a thumbnail from an image
    ///
    /// - Parameter image: The source image
    /// - Returns: Thumbnail UIImage with max width of thumbnailMaxWidth
    private func createThumbnail(from image: UIImage) -> UIImage? {
        let size = image.size

        // If image is already smaller than thumbnail size, return as-is
        if size.width <= thumbnailMaxWidth {
            return image
        }

        // Calculate new size maintaining aspect ratio
        let aspectRatio = size.height / size.width
        let thumbnailSize = CGSize(
            width: thumbnailMaxWidth,
            height: thumbnailMaxWidth * aspectRatio
        )

        // Create thumbnail
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }

        return thumbnail
    }

    // MARK: - Utility Methods

    /// Gets the total storage size used by images
    ///
    /// - Returns: Size in bytes, or nil if calculation fails
    nonisolated func getTotalStorageSize() async -> Int64? {
        var totalSize: Int64 = 0

        let productURL = await documentsDirectory.appendingPathComponent(ImageType.product.subdirectory)
        let receiptURL = await documentsDirectory.appendingPathComponent(ImageType.receipt.subdirectory)

        for directoryURL in [productURL, receiptURL] {
            guard let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) else {
                continue
            }

            while let fileURL = enumerator.nextObject() as? URL {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                      let fileSize = resourceValues.fileSize else {
                    continue
                }
                totalSize += Int64(fileSize)
            }

        }

        return totalSize
    }

    /// Clears all stored images (use with caution!)
    ///
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func clearAllImages() async -> Bool {
        let productURL = documentsDirectory.appendingPathComponent(ImageType.product.subdirectory)
        let receiptURL = documentsDirectory.appendingPathComponent(ImageType.receipt.subdirectory)

        var success = true

        for directoryURL in [productURL, receiptURL] {
            if FileManager.default.fileExists(atPath: directoryURL.path) {
                do {
                    try FileManager.default.removeItem(at: directoryURL)
                } catch {
                    ErrorHandler.shared.log(error, context: "Clearing image directory")
                    success = false
                }
            }
        }

        return success
    }
}
