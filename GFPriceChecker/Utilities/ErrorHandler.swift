//
//  ErrorHandler.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation

/// Centralized error handling for the GFPriceChecker app
///
/// Provides:
/// - Custom error types for different failure scenarios
/// - User-friendly error messages
/// - Logging for debugging
/// - Recovery suggestions
@MainActor
final class ErrorHandler {

    // MARK: - Singleton

    static let shared = ErrorHandler()
    private init() {}

    // MARK: - Error Types

    /// Application-specific errors with user-friendly messages
    enum AppError: LocalizedError {
        // MARK: OCR Errors
        case ocrNoTextDetected
        case ocrLowConfidence
        case ocrInvalidImage
        case ocrProcessingFailed(String)

        // MARK: Image Storage Errors
        case imageStorageFull
        case imageCorrupted
        case imageSaveFailed
        case imageNotFound

        // MARK: Data Validation Errors
        case invalidPrice(String)
        case invalidProductName(String)
        case invalidDate(String)
        case emptyRequiredField(String)
        case priceTooHigh(Decimal)
        case priceNegative

        // MARK: Export Errors
        case exportNoData
        case exportFailed(String)
        case exportInsufficientStorage
        case pdfGenerationFailed(String)
        case csvGenerationFailed(String)

        // MARK: Import Errors
        case importInvalidFile
        case importCorruptedData
        case importVersionMismatch(String)
        case importFailed(String)

        // MARK: Network/Sharing Errors
        case sharingFailed
        case emailNotConfigured
        case fileAccessDenied

        // MARK: Database Errors
        case databaseSaveFailed
        case databaseDeleteFailed
        case databaseFetchFailed

        // MARK: User-Friendly Error Descriptions

        var errorDescription: String? {
            switch self {
            // OCR Errors
            case .ocrNoTextDetected:
                return "No text detected in the image"
            case .ocrLowConfidence:
                return "Image quality too low for accurate reading"
            case .ocrInvalidImage:
                return "Invalid or corrupted image"
            case .ocrProcessingFailed(let reason):
                return "Text recognition failed: \(reason)"

            // Image Storage Errors
            case .imageStorageFull:
                return "Not enough storage space for images"
            case .imageCorrupted:
                return "Image file is corrupted"
            case .imageSaveFailed:
                return "Failed to save image"
            case .imageNotFound:
                return "Image not found"

            // Data Validation Errors
            case .invalidPrice(let field):
                return "\(field) must be a valid dollar amount"
            case .invalidProductName(let field):
                return "\(field) cannot be empty"
            case .invalidDate(let reason):
                return "Invalid date: \(reason)"
            case .emptyRequiredField(let field):
                return "\(field) is required"
            case .priceTooHigh(let price):
                return "Price $\(price) seems unusually high. Please verify."
            case .priceNegative:
                return "Price cannot be negative"

            // Export Errors
            case .exportNoData:
                return "No data to export"
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            case .exportInsufficientStorage:
                return "Not enough storage space for export"
            case .pdfGenerationFailed(let reason):
                return "PDF generation failed: \(reason)"
            case .csvGenerationFailed(let reason):
                return "CSV generation failed: \(reason)"

            // Import Errors
            case .importInvalidFile:
                return "Invalid backup file format"
            case .importCorruptedData:
                return "Backup file is corrupted or incomplete"
            case .importVersionMismatch(let version):
                return "This backup was created with version \(version) and is not compatible"
            case .importFailed(let reason):
                return "Import failed: \(reason)"

            // Network/Sharing Errors
            case .sharingFailed:
                return "Unable to share file"
            case .emailNotConfigured:
                return "Email is not configured on this device"
            case .fileAccessDenied:
                return "Cannot access file. Please check permissions."

            // Database Errors
            case .databaseSaveFailed:
                return "Failed to save data"
            case .databaseDeleteFailed:
                return "Failed to delete data"
            case .databaseFetchFailed:
                return "Failed to load data"
            }
        }

        // MARK: Recovery Suggestions

        var recoverySuggestion: String? {
            switch self {
            // OCR Errors
            case .ocrNoTextDetected:
                return "Try taking a clearer photo with better lighting, or enter the information manually."
            case .ocrLowConfidence:
                return "Ensure the product label is well-lit and in focus. You can also enter the information manually."
            case .ocrInvalidImage:
                return "Please try scanning the image again."
            case .ocrProcessingFailed:
                return "You can enter the product information manually instead."

            // Image Storage Errors
            case .imageStorageFull:
                return "Free up storage space on your device, or continue without saving images."
            case .imageCorrupted:
                return "Try scanning the image again."
            case .imageSaveFailed:
                return "Check available storage space or try again later."
            case .imageNotFound:
                return "The image may have been deleted. You can add a new image if needed."

            // Data Validation Errors
            case .invalidPrice:
                return "Enter a valid price (e.g., 6.99)."
            case .invalidProductName:
                return "Please enter a product name."
            case .invalidDate:
                return "Please select a valid date."
            case .emptyRequiredField:
                return "This field is required to continue."
            case .priceTooHigh:
                return "Double-check the price. If correct, you can proceed."
            case .priceNegative:
                return "Enter a positive price amount."

            // Export Errors
            case .exportNoData:
                return "Add some products before exporting."
            case .exportFailed:
                return "Please try again. If the problem persists, contact support."
            case .exportInsufficientStorage:
                return "Free up storage space on your device and try again."
            case .pdfGenerationFailed, .csvGenerationFailed:
                return "Try reducing the date range or contact support if the issue persists."

            // Import Errors
            case .importInvalidFile:
                return "Make sure you're selecting a valid GFPriceChecker backup file (.json)."
            case .importCorruptedData:
                return "The backup file may be damaged. Try a different backup."
            case .importVersionMismatch:
                return "Update the app to import this backup, or export a new backup from the original device."
            case .importFailed:
                return "Try the import again. If it fails, the backup file may be corrupted."

            // Network/Sharing Errors
            case .sharingFailed:
                return "Check your network connection and try again."
            case .emailNotConfigured:
                return "Set up an email account in Settings app, or use another sharing method."
            case .fileAccessDenied:
                return "Grant file access permissions in Settings."

            // Database Errors
            case .databaseSaveFailed:
                return "Please try again. If the problem persists, restart the app."
            case .databaseDeleteFailed:
                return "Please try again or restart the app."
            case .databaseFetchFailed:
                return "Try restarting the app. If the problem persists, contact support."
            }
        }
    }

    // MARK: - Error Logging

    /// Logs an error for debugging
    ///
    /// - Parameters:
    ///   - error: The error to log
    ///   - context: Additional context about where the error occurred
    func log(_ error: Error, context: String) {
        #if DEBUG
        print("❌ ERROR [\(context)]: \(error.localizedDescription)")
        if let appError = error as? AppError, let suggestion = appError.recoverySuggestion {
            print("💡 SUGGESTION: \(suggestion)")
        }
        #endif
    }

    /// Logs an error with file and line information
    ///
    /// - Parameters:
    ///   - error: The error to log
    ///   - file: Source file where error occurred
    ///   - line: Line number where error occurred
    func log(_ error: Error, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        log(error, context: "\(fileName):\(line)")
    }

    // MARK: - Error Handling Helpers

    /// Converts a generic error to an AppError if possible
    ///
    /// - Parameter error: The error to convert
    /// - Returns: AppError or the original error
    func convertToAppError(_ error: Error) -> Error {
        if let appError = error as? AppError {
            return appError
        }

        // Convert common error types
        let nsError = error as NSError
        switch nsError.domain {
        case NSCocoaErrorDomain:
            if nsError.code == NSFileWriteOutOfSpaceError {
                return AppError.exportInsufficientStorage
            } else if nsError.code == NSFileReadNoPermissionError {
                return AppError.fileAccessDenied
            }
        default:
            break
        }

        // Return original error if no conversion available
        return error
    }

    /// Creates a user-presentable error message
    ///
    /// - Parameter error: The error to format
    /// - Returns: User-friendly error message
    func userMessage(for error: Error) -> String {
        let convertedError = convertToAppError(error)

        if let appError = convertedError as? AppError {
            var message = appError.localizedDescription
            if let suggestion = appError.recoverySuggestion {
                message += "\n\n\(suggestion)"
            }
            return message
        }

        // Fallback for unknown errors
        return "An unexpected error occurred. Please try again."
    }
}

// MARK: - Error Context

/// Context information for error reporting
struct ErrorContext {
    let operation: String
    let fileName: String
    let lineNumber: Int

    static func current(
        operation: String,
        file: String = #file,
        line: Int = #line
    ) -> ErrorContext {
        let fileName = (file as NSString).lastPathComponent
        return ErrorContext(
            operation: operation,
            fileName: fileName,
            lineNumber: line
        )
    }
}
