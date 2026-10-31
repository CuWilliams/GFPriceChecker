//
//  CaptureFlowViewModel.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-09-14.
//

import Foundation
import GFCore
import SwiftData
import SwiftUI
import UIKit

// MARK: - Size Input Mode

enum SizeInputMode: String, CaseIterable {
    case packageSize = "Package Size"
    case unitPrice = "Unit Price"
    case manual = "Manual"
}

// MARK: - Capture Step

/// One screen of the guided product-pair capture.
///
/// The two `select…Rectangle` cases only occur when rectangle selection is
/// enabled — see `CaptureFlowViewModel.rectangleSelectionEnabled`.
enum CaptureStep: CaseIterable {
    case introduction
    case captureGF
    case selectGFRectangle
    case reviewGF
    case captureNonGF
    case selectNonGFRectangle
    case reviewNonGF
    case finalize

    var title: String {
        switch self {
        case .introduction:
            return "Capture Product Pair"
        case .captureGF:
            return "Scan GF Product"
        case .selectGFRectangle:
            return "Select GF Region"
        case .reviewGF:
            return "Review GF Product"
        case .captureNonGF:
            return "Scan Regular Product"
        case .selectNonGFRectangle:
            return "Select Regular Region"
        case .reviewNonGF:
            return "Review Regular Product"
        case .finalize:
            return "Finalize"
        }
    }
}

// MARK: - Capture Flow View Model

/// The state and logic of the guided GF-vs-regular capture flow.
///
/// This used to be ~35 `@State` properties and five private methods inside
/// `ProductCaptureFlowView`. Lifting it out buys two things the view could not
/// offer: the flow can be driven by method calls (which is what the scripted
/// demo director in `docs/SCRIPTED_DEMO_PIPELINE.md` Stage 5 needs), and the
/// app's most intricate logic becomes unit-testable.
///
/// Nothing here touches SwiftUI. The camera, OCR and image storage reach it
/// through `Dependencies`, so a test can run a whole capture end to end with
/// canned observations and no Vision framework at all.
@Observable
@MainActor
final class CaptureFlowViewModel {

    // MARK: - Dependencies

    /// The services the flow calls out to, behind closures so tests can stand in for them.
    @MainActor
    struct Dependencies {
        /// Persists a captured image, returning its storage UUID.
        var saveImage: (UIImage) async -> String?

        /// Detects candidate shelf-tag rectangles in an image.
        var detectRectangles: (UIImage) async -> [DetectedRectangle]

        /// Reads selectable text from an image, optionally restricted to a region.
        var extractText: (UIImage, CGRect?) async -> [SelectableTextObservation]

        /// The real services.
        static var live: Dependencies {
            Dependencies(
                saveImage: { await ImageStorageService.shared.saveImage($0, type: .product) },
                detectRectangles: { (try? await OCRService.shared.detectRectangles(in: $0)) ?? [] },
                extractText: { image, region in
                    if let region {
                        return (try? await OCRService.shared.extractSelectableText(from: image, region: region)) ?? []
                    }
                    return (try? await OCRService.shared.extractSelectableText(from: image)) ?? []
                }
            )
        }
    }

    private let dependencies: Dependencies

    // MARK: - Configuration

    /// Developer toggle for the rectangle selection step.
    ///
    /// When `false`: Scan → Review (bypasses "Select Region").
    /// When `true`: Scan → Select Region → Review (if rectangles are detected).
    let rectangleSelectionEnabled: Bool

    /// Categories offered in the finalize picker. `"None"` is the no-category sentinel.
    static let categoryOptions = [
        "None", "Bread", "Cereal", "Crackers", "Flour",
        "Pasta", "Sauce", "Snacks & Chips", "Soup & Broth"
    ]

    // MARK: - Flow State

    /// Current step in the capture flow
    var currentStep: CaptureStep = .introduction

    /// Whether to show the document scanner
    var showingScanner = false

    /// Loading state during OCR processing
    var isProcessingOCR = false

    /// Loading state during save operation
    var isSaving = false

    /// Set once the pair has been written to the store — the view dismisses on it
    var didSave = false

    // MARK: - GF Product Data

    var gfImage: UIImage?
    var gfImageUUID: String?
    var gfProductName: String = ""
    var gfPriceText: String = ""
    var gfSizeText: String = ""

    // MARK: - Non-GF Product Data

    var nonGFImage: UIImage?
    var nonGFImageUUID: String?
    var nonGFProductName: String = ""
    var nonGFPriceText: String = ""
    var nonGFSizeText: String = ""

    // MARK: - Size Entry

    /// Unit of measurement, shared by both products in the pair
    var selectedUnit: SizeUnit?

    var gfSizeMode: SizeInputMode = .packageSize
    var nonGFSizeMode: SizeInputMode = .packageSize

    /// Unit price text, used in `.unitPrice` and `.manual` modes
    var gfUnitPriceText: String = ""
    var nonGFUnitPriceText: String = ""

    /// Whether the entered unit price is in cents or dollars
    var gfUnitPriceBasis: UnitPriceBasis = .cents
    var nonGFUnitPriceBasis: UnitPriceBasis = .cents

    /// Selected OCR row for size (used for highlight tracking)
    var gfSelectedSizeObservationID: UUID?
    var nonGFSelectedSizeObservationID: UUID?

    // MARK: - Additional Product Pair Data

    var category: String = "None"
    var notes: String = ""

    // MARK: - OCR Results

    var gfOCRObservations: [SelectableTextObservation] = []
    var nonGFOCRObservations: [SelectableTextObservation] = []

    var gfDetectedRectangles: [DetectedRectangle] = []
    var nonGFDetectedRectangles: [DetectedRectangle] = []
    var gfSelectedRectangle: DetectedRectangle?
    var nonGFSelectedRectangle: DetectedRectangle?

    /// Identity for the review selector — regenerated on every fresh OCR run so
    /// the selector restarts at phase one instead of reusing the previous product's state
    private(set) var reviewToken = UUID()

    // MARK: - Initialization

    /// - Parameter dependencies: stand-ins for the camera, OCR and image
    ///   storage services. `nil` uses the real ones. It is not defaulted to
    ///   `.live` directly because a default argument is evaluated in the
    ///   caller's isolation, and `.live` is main-actor isolated.
    init(
        dependencies: Dependencies? = nil,
        rectangleSelectionEnabled: Bool = false
    ) {
        self.dependencies = dependencies ?? .live
        self.rectangleSelectionEnabled = rectangleSelectionEnabled
    }

    // MARK: - Navigation

    /// Leaves the introduction and opens the scanner for the GF product.
    func startCapture() {
        currentStep = .captureGF
        showingScanner = true
    }

    /// Advances past a completed review: GF goes on to scan the regular
    /// product, regular goes on to finalize.
    func continueFromReview(isGF: Bool) {
        if isGF {
            currentStep = .captureNonGF
            showingScanner = true
        } else {
            currentStep = .finalize
        }
    }

    /// Discards one product's captured fields and reopens the scanner for it.
    func retake(isGF: Bool) {
        resetProductFields(isGF: isGF)
        if isGF {
            gfOCRObservations = []
            currentStep = .captureGF
        } else {
            nonGFOCRObservations = []
            currentStep = .captureNonGF
        }
        showingScanner = true
    }

    /// Reopens the scanner for the same product without clearing what was captured.
    ///
    /// This is the "Retake Photo" button on the no-text-detected screen, where
    /// there is nothing captured to clear.
    func retakeAfterNoText(isGF: Bool) {
        currentStep = isGF ? .captureGF : .captureNonGF
        showingScanner = true
    }

    /// Moves on with this product's fields left empty, for filling in later.
    func skipProduct(isGF: Bool) {
        continueFromReview(isGF: isGF)
    }

    /// Clears every captured field for one product of the pair
    func resetProductFields(isGF: Bool) {
        if isGF {
            gfProductName = ""
            gfPriceText = ""
            gfSizeText = ""
            gfUnitPriceText = ""
            gfSizeMode = .packageSize
            gfUnitPriceBasis = .cents
            gfSelectedSizeObservationID = nil
        } else {
            nonGFProductName = ""
            nonGFPriceText = ""
            nonGFSizeText = ""
            nonGFUnitPriceText = ""
            nonGFSizeMode = .packageSize
            nonGFUnitPriceBasis = .cents
            nonGFSelectedSizeObservationID = nil
        }
    }

    // MARK: - Scanning

    /// Handles image from document scanner
    func handleScannedImage(_ image: UIImage?) async {
        guard let image = image else { return }

        isProcessingOCR = true
        reviewToken = UUID()

        // Save image to storage
        let uuid = await dependencies.saveImage(image)

        // Detect rectangles only if feature is enabled
        let rectangles: [DetectedRectangle]
        if rectangleSelectionEnabled {
            rectangles = await dependencies.detectRectangles(image)
        } else {
            rectangles = []
        }

        switch currentStep {
        case .captureGF:
            gfImage = image
            gfImageUUID = uuid

            if rectangleSelectionEnabled && !rectangles.isEmpty {
                // Rectangle selection enabled and rectangles detected - let user select region
                gfDetectedRectangles = rectangles
                currentStep = .selectGFRectangle
            } else {
                // Feature disabled or no rectangles - proceed with full-image OCR
                gfOCRObservations = await dependencies.extractText(image, nil)
                currentStep = .reviewGF
            }

        case .captureNonGF:
            nonGFImage = image
            nonGFImageUUID = uuid

            if rectangleSelectionEnabled && !rectangles.isEmpty {
                // Rectangle selection enabled and rectangles detected - let user select region
                nonGFDetectedRectangles = rectangles
                currentStep = .selectNonGFRectangle
            } else {
                // Feature disabled or no rectangles - proceed with full-image OCR
                nonGFOCRObservations = await dependencies.extractText(image, nil)
                currentStep = .reviewNonGF
            }

        default:
            break
        }

        isProcessingOCR = false
    }

    /// Handles selection of a rectangle region for OCR
    func handleRectangleSelection(_ rectangle: DetectedRectangle, isGF: Bool) async {
        await runRegionOCR(rectangle: rectangle, isGF: isGF)
    }

    /// Handles skipping rectangle selection and using full-image OCR
    func handleSkipRectangleSelection(isGF: Bool) async {
        await runRegionOCR(rectangle: nil, isGF: isGF)
    }

    /// Reads text from the captured image — the whole of it, or one selected
    /// rectangle — and moves on to the matching review step.
    private func runRegionOCR(rectangle: DetectedRectangle?, isGF: Bool) async {
        guard let image = isGF ? gfImage : nonGFImage else { return }

        isProcessingOCR = true
        reviewToken = UUID()

        let observations = await dependencies.extractText(image, rectangle?.boundingBox)

        if isGF {
            gfSelectedRectangle = rectangle
            gfOCRObservations = observations
            currentStep = .reviewGF
        } else {
            nonGFSelectedRectangle = rectangle
            nonGFOCRObservations = observations
            currentStep = .reviewNonGF
        }

        isProcessingOCR = false
    }

    // MARK: - Size Row Taps

    /// Routes an OCR row tap to the correct size field based on the current mode
    func handleSizeRowTap(_ obs: SelectableTextObservation, isGF: Bool) {
        let mode = isGF ? gfSizeMode : nonGFSizeMode
        if mode == .packageSize {
            let parsed = SizeTextParser.parseSize(obs.text)
            if isGF {
                gfSizeText = parsed.value
                gfSelectedSizeObservationID = obs.id
            } else {
                nonGFSizeText = parsed.value
                nonGFSelectedSizeObservationID = obs.id
            }
            if let u = parsed.unit, selectedUnit == nil { selectedUnit = u }
        } else {
            let parsed = SizeTextParser.parseUnitPrice(obs.text)
            if isGF {
                gfUnitPriceText = parsed.value
                gfSelectedSizeObservationID = obs.id
            } else {
                nonGFUnitPriceText = parsed.value
                nonGFSelectedSizeObservationID = obs.id
            }
            if let u = parsed.unit, selectedUnit == nil { selectedUnit = u }
        }
    }

    // MARK: - Derived Values

    var gfPrice: Decimal? { Decimal(string: gfPriceText) }
    var nonGFPrice: Decimal? { Decimal(string: nonGFPriceText) }

    /// The GF package size, taken from the field the active mode fills.
    ///
    /// In `.unitPrice` and `.manual` modes nothing records the size directly,
    /// so it is back-calculated as `price / unitPrice`, with the unit price
    /// converted to dollars first when the basis is cents.
    var gfSizeValue: Decimal? {
        sizeValue(
            mode: gfSizeMode,
            sizeText: gfSizeText,
            priceText: gfPriceText,
            unitPriceText: gfUnitPriceText,
            basis: gfUnitPriceBasis
        )
    }

    /// The regular product's package size — see `gfSizeValue`.
    var nonGFSizeValue: Decimal? {
        sizeValue(
            mode: nonGFSizeMode,
            sizeText: nonGFSizeText,
            priceText: nonGFPriceText,
            unitPriceText: nonGFUnitPriceText,
            basis: nonGFUnitPriceBasis
        )
    }

    private func sizeValue(
        mode: SizeInputMode,
        sizeText: String,
        priceText: String,
        unitPriceText: String,
        basis: UnitPriceBasis
    ) -> Decimal? {
        if mode == .packageSize {
            return Decimal(string: sizeText)
        }
        guard let price = Decimal(string: priceText),
              let unitPrice = Decimal(string: unitPriceText) else {
            return nil
        }
        return PricingInputs.packageSize(price: price, unitPrice: unitPrice, basis: basis)
    }

    /// The pair's figures for GFCore's arithmetic — `nil` until both prices parse.
    var pricing: PricingInputs? {
        guard let gfPrice, let nonGFPrice else { return nil }
        return PricingInputs(
            gfPrice: gfPrice,
            nonGFPrice: nonGFPrice,
            gfSizeValue: gfSizeValue,
            nonGFSizeValue: nonGFSizeValue
        )
    }

    /// Straight price difference between the two packages, ignoring their sizes.
    var packagePriceDifferential: Decimal? { pricing?.differential }

    /// Price difference after normalizing for package size, expressed per GF package —
    /// the spec's `normalizedDifferential`, shown as "Size-Adjusted Differential". Not a
    /// unit price differential, which is a rate.
    ///
    /// `nil` unless both prices and both sizes are known and positive.
    var normalizedDifferential: Decimal? { pricing?.normalizedDifferential }

    /// Legacy display string for the GF size field, e.g. `"400g"`.
    var gfSizeDisplay: String? { sizeDisplay(mode: gfSizeMode, sizeText: gfSizeText, unitPriceText: gfUnitPriceText) }

    /// Legacy display string for the regular size field — see `gfSizeDisplay`.
    var nonGFSizeDisplay: String? { sizeDisplay(mode: nonGFSizeMode, sizeText: nonGFSizeText, unitPriceText: nonGFUnitPriceText) }

    private func sizeDisplay(mode: SizeInputMode, sizeText: String, unitPriceText: String) -> String? {
        let number = mode == .packageSize ? sizeText : unitPriceText
        guard !number.isEmpty else { return nil }
        return "\(number)\(selectedUnit?.displayName ?? "")"
    }

    /// The unit stored on the pair — only meaningful when both sizes are known.
    var storedSizeUnitRaw: String? {
        (gfSizeValue != nil && nonGFSizeValue != nil) ? selectedUnit?.rawValue : nil
    }

    /// The category to store, with the `"None"` sentinel mapped to no category.
    var storedCategory: String? {
        (category.isEmpty || category == "None") ? nil : category
    }

    /// Whether `save(into:)` has the two prices it needs.
    var canSave: Bool { gfPrice != nil && nonGFPrice != nil }

    // MARK: - Saving

    /// Builds the `ProductPair` the current state describes.
    ///
    /// `nil` when either price is missing or unparseable, which is the one
    /// thing the flow refuses to save without.
    func makeProductPair() -> ProductPair? {
        guard let gfPrice, let nonGFPrice else { return nil }

        return ProductPair(
            gfProductName: gfProductName.trimmingCharacters(in: .whitespacesAndNewlines),
            gfPrice: gfPrice,
            gfSize: gfSizeDisplay,
            gfSizeValue: gfSizeValue,
            gfImageUUID: gfImageUUID,
            gfOCRConfidence: 0.0,
            nonGFProductName: nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines),
            nonGFPrice: nonGFPrice,
            nonGFSize: nonGFSizeDisplay,
            nonGFSizeValue: nonGFSizeValue,
            nonGFImageUUID: nonGFImageUUID,
            nonGFOCRConfidence: 0.0,
            sizeUnit: storedSizeUnitRaw,
            category: storedCategory,
            notes: notes.isEmpty ? nil : notes,
            verified: false
        )
    }

    /// Saves the product pair to SwiftData
    /// - Returns: `true` when the pair was written, which is the view's cue to dismiss.
    @discardableResult
    func save(into modelContext: ModelContext) -> Bool {
        guard let productPair = makeProductPair() else {
            return false
        }

        isSaving = true

        modelContext.insert(productPair)

        do {
            try modelContext.save()
            isSaving = false
            didSave = true
            return true
        } catch {
            ErrorHandler.shared.log(error, context: "Saving product pair")
            isSaving = false
            return false
        }
    }
}
