//
//  ReceiptCaptureViewModel.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-10-31.
//

import Foundation
import GFCore
import SwiftData
import UIKit

// MARK: - Receipt Step

/// One screen of receipt verification.
enum ReceiptStep: CaseIterable {
    case selectProducts
    case scanReceipt
    case reviewMatches
}

// MARK: - Receipt Capture View Model

/// The state and logic of receipt verification: pick unverified pairs, scan a
/// receipt, match each pair to a receipt line, then save.
///
/// This used to be 17 `@State` properties and eight private methods inside
/// `ReceiptCaptureView`, in the same position `ProductCaptureFlowView` was in
/// before `CaptureFlowViewModel` (`docs/SCRIPTED_DEMO_PIPELINE.md` §2 Blocker 2).
/// Out here the flow can be driven by method calls and unit-tested.
///
/// The OCR and image storage reach it through `Dependencies`, and the save takes
/// its `ModelContext`, so a test can run a whole verification with canned OCR
/// text and an in-memory store.
@Observable
@MainActor
final class ReceiptCaptureViewModel {

    // MARK: - Dependencies

    /// The services the flow calls out to, behind closures so tests can stand in for them.
    @MainActor
    struct Dependencies {
        /// Reads the receipt as one string, for store, date and total parsing.
        var extractReceiptText: (UIImage) async throws -> String

        /// Reads the receipt as tappable lines, for matching.
        var extractSelectableText: (UIImage) async throws -> [SelectableTextObservation]

        /// Persists the receipt image, returning its storage UUID.
        var saveImage: (UIImage) async -> String?

        /// The real services.
        static var live: Dependencies {
            Dependencies(
                extractReceiptText: { try await OCRService.shared.extractReceiptText(from: $0) },
                extractSelectableText: { try await OCRService.shared.extractSelectableText(from: $0) },
                saveImage: { await ImageStorageService.shared.saveImage($0, type: .receipt) }
            )
        }
    }

    private let dependencies: Dependencies

    // MARK: - Flow State

    /// Current step in the receipt capture flow
    var currentStep: ReceiptStep = .selectProducts

    /// The pairs on offer for verification. The view keeps this in step with its
    /// `@Query` of unverified pairs, through `refreshUnverifiedProducts(_:)`.
    var unverifiedProducts: [ProductPair] = []

    /// Follows the view's `@Query`, until the receipt is saved. Saving verifies
    /// the matched pairs, which drops them from the query, and the sheet would
    /// otherwise read "Verifying product 0 of 0" as it slides away.
    func refreshUnverifiedProducts(_ products: [ProductPair]) {
        guard !didSave else { return }
        unverifiedProducts = products
    }

    /// Selected product pairs to verify with this receipt
    var selectedProducts: Set<UUID> = []

    /// Track which product is currently being verified
    var currentVerificationIndex: Int = 0

    /// Store confirmed matches: ProductPair.id -> selected receipt line text
    var confirmedMatches: [UUID: String] = [:]

    /// The receipt line tapped for the current product, not yet confirmed.
    /// Held here rather than in the line selector so a scripted take can tap a
    /// line and the screen follows.
    private(set) var selectedReceiptLine: SelectableTextObservation?

    /// Set once the receipt has been written to the store — the view dismisses on it
    var didSave = false

    // MARK: - Scan and OCR

    /// Whether to show the document scanner
    var showingScanner = false

    /// Loading state during OCR processing
    var isProcessingOCR = false

    var receiptImage: UIImage?
    var receiptImageUUID: String?
    var receiptText: String = ""

    /// OCR observations for tap-to-select
    var receiptOCRObservations: [SelectableTextObservation] = []

    // MARK: - Parsed Fields

    var storeName: String = ""
    var purchaseDate: Date = Date()
    var totalAmount: String = ""

    // MARK: - Presentation

    var showingAlert = false
    var alertMessage = ""

    /// Receipt viewer state
    var showingReceiptViewer = false

    // MARK: - Initialization

    /// - Parameter dependencies: stand-ins for the OCR and image storage
    ///   services. `nil` uses the real ones. It is not defaulted to `.live`
    ///   directly because a default argument is evaluated in the caller's
    ///   isolation, and `.live` is main-actor isolated.
    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    // MARK: - Derived Values

    /// Products selected for verification
    var productsToVerify: [ProductPair] {
        unverifiedProducts.filter { selectedProducts.contains($0.id) }
    }

    /// Current product being verified
    var currentProductToVerify: ProductPair? {
        guard currentVerificationIndex < productsToVerify.count else { return nil }
        return productsToVerify[currentVerificationIndex]
    }

    /// Count of confirmed matches
    var confirmedCount: Int {
        confirmedMatches.count
    }

    // MARK: - Product Selection

    func toggleProductSelection(_ product: ProductPair) {
        if selectedProducts.contains(product.id) {
            selectedProducts.remove(product.id)
        } else {
            selectedProducts.insert(product.id)
        }
    }

    /// Selects all unverified products
    func selectAllProducts() {
        selectedProducts = Set(unverifiedProducts.map { $0.id })
    }

    /// Deselects all products
    func deselectAllProducts() {
        selectedProducts.removeAll()
    }

    // MARK: - Navigation

    /// Moves from product selection to the scan prompt.
    func continueToScan() {
        currentStep = .scanReceipt
    }

    /// Returns from the scan prompt to product selection.
    func backToProductSelection() {
        currentStep = .selectProducts
    }

    func openScanner() {
        showingScanner = true
    }

    func showReceiptViewer() {
        showingReceiptViewer = true
    }

    // MARK: - Matching

    /// The first receipt line containing a word of three or more letters from
    /// `product`'s GF name, offered as "Suggested" until a line is tapped.
    func suggestedReceiptLine(for product: ProductPair) -> SelectableTextObservation? {
        let searchTerms = product.gfProductName.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }

        return receiptOCRObservations.first { observation in
            let text = observation.text.lowercased()
            return searchTerms.contains { text.contains($0) }
        }
    }

    func selectReceiptLine(_ observation: SelectableTextObservation) {
        selectedReceiptLine = observation
    }

    /// Confirms the tapped line for the current product. Does nothing until a
    /// line has been tapped, as the disabled Confirm button does nothing.
    func confirmSelectedLine() {
        guard let line = selectedReceiptLine, let product = currentProductToVerify else { return }
        confirmMatch(for: product, withLine: line.text)
    }

    /// Confirms a match and moves to next product
    func confirmMatch(for product: ProductPair, withLine text: String) {
        confirmedMatches[product.id] = text
        currentVerificationIndex += 1
        selectedReceiptLine = nil
    }

    /// Skips current product without matching
    func skipProduct(_ product: ProductPair) {
        // Don't add to confirmedMatches
        currentVerificationIndex += 1
        selectedReceiptLine = nil
    }

    // MARK: - Scanning

    /// Handles the document scanner's result. `nil` means the user cancelled or
    /// the scan failed, which just closes the scanner.
    func handleScannedReceipt(_ image: UIImage?) async {
        guard let image else {
            showingScanner = false
            return
        }

        receiptImage = image
        showingScanner = false
        isProcessingOCR = true

        await processReceipt(image)
    }

    /// Processes receipt with OCR
    private func processReceipt(_ image: UIImage) async {
        do {
            // Extract full receipt text (for display and store/date parsing)
            let fullText = try await dependencies.extractReceiptText(image)
            receiptText = fullText

            // Extract selectable observations for tap-to-select
            let observations = try await dependencies.extractSelectableText(image)
            receiptOCRObservations = observations

            // Parse receipt metadata (keep this functionality)
            if let store = ReceiptParser.extractStoreName(from: fullText) {
                storeName = store
            }

            if let date = ReceiptParser.extractDate(from: fullText) {
                purchaseDate = date
            }

            if let total = ReceiptParser.extractTotal(from: fullText) {
                totalAmount = "\(total)"
            }

            // Reset verification state
            currentVerificationIndex = 0
            confirmedMatches = [:]
            selectedReceiptLine = nil

            isProcessingOCR = false
            currentStep = .reviewMatches

        } catch {
            isProcessingOCR = false
            alertMessage = "Failed to process receipt: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    // MARK: - Saving

    /// Confirms matches and saves receipt to SwiftData
    /// - Returns: `true` when the receipt was written, which is the view's cue to dismiss.
    @discardableResult
    func save(into modelContext: ModelContext) async -> Bool {
        // Save receipt image
        guard let image = receiptImage,
              let imageUUID = await dependencies.saveImage(image) else {
            alertMessage = "Failed to save receipt image"
            showingAlert = true
            return false
        }

        receiptImageUUID = imageUUID

        // Parse total amount
        let totalDecimal = totalAmount.isEmpty ? nil : Decimal(string: totalAmount)

        // Create Receipt
        let receipt = Receipt(
            purchaseDate: purchaseDate,
            storeName: storeName.isEmpty ? nil : storeName,
            receiptImageUUID: imageUUID,
            totalAmount: totalDecimal,
            extractedOCRText: receiptText
        )

        // Associate confirmed products with receipt
        for product in productsToVerify {
            if confirmedMatches[product.id] != nil {
                product.receipt = receipt
                product.verified = true
            }
        }

        modelContext.insert(receipt)

        do {
            try modelContext.save()
            didSave = true
            return true
        } catch {
            alertMessage = "Failed to save: \(error.localizedDescription)"
            showingAlert = true
            return false
        }
    }
}
