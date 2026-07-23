//
//  ProductCaptureFlowView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import SwiftData

/// Guided flow for capturing and comparing GF vs non-GF products
///
/// Multi-step workflow:
/// 1. Introduction
/// 2. Capture GF product
/// 3. Review GF product (OCR data editable)
/// 4. Capture non-GF product
/// 5. Review non-GF product (OCR data editable)
/// 6. Finalize and save
struct ProductCaptureFlowView: View {

    // MARK: - Developer Configuration

    /// Developer toggle to enable/disable rectangle selection step in capture flow.
    /// When `false`: Scan → directly to Review (bypasses "Select Region" screen)
    /// When `true`: Scan → Select Region → Review (if rectangles detected)
    /// Set to `true` to re-enable rectangle-based OCR filtering during beta testing.
    private let rectangleSelectionEnabled = false

    private let commonCategories = [
        "None", "Bread", "Cereal", "Crackers", "Flour",
        "Pasta", "Sauce", "Snacks & Chips", "Soup & Broth"
    ]

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Current step in the capture flow
    @State private var currentStep: CaptureStep = .introduction

    /// Whether to show the document scanner
    @State private var showingScanner = false

    /// Loading state during OCR processing
    @State private var isProcessingOCR = false

    /// Loading state during save operation
    @State private var isSaving = false

    // GF Product Data
    @State private var gfImage: UIImage?
    @State private var gfImageUUID: String?
    @State private var gfProductName: String = ""
    @State private var gfPriceText: String = ""
    @State private var gfSizeText: String = ""

    // Non-GF Product Data
    @State private var nonGFImage: UIImage?
    @State private var nonGFImageUUID: String?
    @State private var nonGFProductName: String = ""
    @State private var nonGFPriceText: String = ""
    @State private var nonGFSizeText: String = ""

    // Size Unit (shared for both products)
    @State private var selectedUnit: SizeUnit? = nil

    // Size input mode per product
    @State private var gfSizeMode: SizeInputMode = .packageSize
    @State private var nonGFSizeMode: SizeInputMode = .packageSize

    // Unit price text for .unitPrice and .manual modes
    @State private var gfUnitPriceText: String = ""
    @State private var nonGFUnitPriceText: String = ""

    // Currency basis for unit price entry (cents vs dollars per unit)
    @State private var gfUnitPriceBasis: UnitPriceBasis = .cents
    @State private var nonGFUnitPriceBasis: UnitPriceBasis = .cents

    // Selected OCR row for size (used for highlight tracking)
    @State private var gfSelectedSizeObservationID: UUID?
    @State private var nonGFSelectedSizeObservationID: UUID?

    /// Identity for the review selector — regenerated on every fresh OCR run so
    /// the selector restarts at phase one instead of reusing the previous product's state
    @State private var reviewToken = UUID()

    // Additional Product Pair Data
    @State private var category: String = "None"
    @State private var notes: String = ""

    // OCR observations for tap-to-select
    @State private var gfOCRObservations: [SelectableTextObservation] = []
    @State private var nonGFOCRObservations: [SelectableTextObservation] = []

    // Rectangle detection for region selection
    @State private var gfDetectedRectangles: [DetectedRectangle] = []
    @State private var nonGFDetectedRectangles: [DetectedRectangle] = []
    @State private var gfSelectedRectangle: DetectedRectangle?
    @State private var nonGFSelectedRectangle: DetectedRectangle?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content
                stepView

                // Loading overlay
                if isProcessingOCR {
                    ocrLoadingOverlay
                }
            }
            .navigationTitle(currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView { image in
                    handleScannedImage(image)
                }
            }
        }
    }

    // MARK: - Step Views

    @ViewBuilder
    private var stepView: some View {
        switch currentStep {
        case .introduction:
            introductionView
        case .captureGF:
            capturePlaceholderView(productType: "Gluten-Free")
        case .selectGFRectangle:
            if let image = gfImage {
                RectangleSelectorView(
                    image: image,
                    rectangles: gfDetectedRectangles,
                    onRectangleSelected: { rectangle in
                        handleRectangleSelection(rectangle, isGF: true)
                    },
                    onSkip: {
                        handleSkipRectangleSelection(isGF: true)
                    }
                )
            }
        case .reviewGF:
            reviewView(isGF: true)
        case .captureNonGF:
            capturePlaceholderView(productType: "Regular")
        case .selectNonGFRectangle:
            if let image = nonGFImage {
                RectangleSelectorView(
                    image: image,
                    rectangles: nonGFDetectedRectangles,
                    onRectangleSelected: { rectangle in
                        handleRectangleSelection(rectangle, isGF: false)
                    },
                    onSkip: {
                        handleSkipRectangleSelection(isGF: false)
                    }
                )
            }
        case .reviewNonGF:
            reviewView(isGF: false)
        case .finalize:
            finalizeView
        }
    }

    // MARK: - Introduction

    private var introductionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "camera.metering.center.weighted")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            Text("Capture Product Pair")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(number: 1, text: "Photograph shelf price tag (GF product)", icon: "tag.fill")
                instructionRow(number: 2, text: "Review and edit extracted data")
                instructionRow(number: 3, text: "Photograph shelf price tag (regular product)", icon: "tag.fill")
                instructionRow(number: 4, text: "Review and finalize")
            }
            .padding()

            // Guidance note
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Results")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Photograph shelf price tags for best OCR accuracy. They contain both product name and price clearly.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)

            Button {
                currentStep = .captureGF
                showingScanner = true
            } label: {
                Text("Start Capture")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    private func instructionRow(number: Int, text: String, icon: String? = nil) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())

            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
            }

            Text(text)
                .font(.body)

            Spacer()
        }
    }

    // MARK: - Capture Placeholder

    private func capturePlaceholderView(productType: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Scanning \(productType) Product")
                .font(.title2)
                .fontWeight(.semibold)

            // Guidance tip
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.blue)
                Text("💡 TIP: Photograph the shelf price tag for best OCR accuracy")
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)

            Text("Shelf tags contain both product name and price. You can also photograph product packaging if preferred.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
        .onAppear {
            // Scanner is shown via sheet, this is just a placeholder
        }
    }

    // MARK: - Review View

    /// Single-screen guided review: name → price → size in one uninterrupted pass
    ///
    /// The selector stays mounted for all three phases so the scan results never
    /// disappear mid-review. `reviewToken` gives each fresh scan a new identity,
    /// which resets the selector's phase when the user retakes a photo or moves
    /// on to the regular product.
    @ViewBuilder
    private func reviewView(isGF: Bool) -> some View {
        let observations = isGF ? gfOCRObservations : nonGFOCRObservations
        let image = isGF ? gfImage : nonGFImage

        if let image = image, !observations.isEmpty {
            OCRTextSelectorView(
                image: image,
                observations: observations,
                productName: isGF ? $gfProductName : $nonGFProductName,
                priceText: isGF ? $gfPriceText : $nonGFPriceText,
                sizeMode: isGF ? $gfSizeMode : $nonGFSizeMode,
                sizeText: isGF ? $gfSizeText : $nonGFSizeText,
                unitPriceText: isGF ? $gfUnitPriceText : $nonGFUnitPriceText,
                unitPriceBasis: isGF ? $gfUnitPriceBasis : $nonGFUnitPriceBasis,
                selectedUnit: $selectedUnit,
                selectedSizeObservationID: isGF ? gfSelectedSizeObservationID : nonGFSelectedSizeObservationID,
                onSizeRowTapped: { observation in
                    handleSizeRowTap(observation, isGF: isGF)
                },
                continueTitle: isGF ? "Continue to Regular Product" : "Continue to Finalize",
                onContinue: {
                    if isGF {
                        currentStep = .captureNonGF
                        showingScanner = true
                    } else {
                        currentStep = .finalize
                    }
                },
                onRetake: {
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
            )
            .id(reviewToken)
        } else {
            // Fallback: No OCR data, show manual entry prompt
            noOCRDataView(isGF: isGF)
        }
    }

    /// Clears every captured field for one product of the pair
    private func resetProductFields(isGF: Bool) {
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

    // MARK: - No OCR Data View

    private func noOCRDataView(isGF: Bool) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("No Text Detected")
                .font(.headline)

            Text("The scan didn't detect readable text. You can retake the photo or enter details manually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    if isGF {
                        currentStep = .captureGF
                    } else {
                        currentStep = .captureNonGF
                    }
                    showingScanner = true
                } label: {
                    Label("Retake Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // Allow manual entry by navigating forward
                    // User can use the Library tab for full manual entry
                    if isGF {
                        currentStep = .captureNonGF
                        showingScanner = true
                    } else {
                        currentStep = .finalize
                    }
                } label: {
                    Text("Skip for Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .padding()
    }

    // MARK: - Finalize View

    private var finalizeView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Review Product Pair")
                    .font(.headline)

                // Side-by-side comparison
                HStack(spacing: 16) {
                    // GF Product
                    VStack(spacing: 8) {
                        Text("Gluten-Free")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let image = gfImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .cornerRadius(8)
                        }

                        Text(gfProductName)
                            .font(.caption)
                            .lineLimit(2)

                        if let price = Decimal(string: gfPriceText) {
                            Text(price.formatted(.currency(code: "CAD")))
                                .font(.headline)
                                .foregroundStyle(.green)
                        }

                        if let unit = selectedUnit {
                            Group {
                                if gfSizeMode == .packageSize, !gfSizeText.isEmpty {
                                    Text("\(gfSizeText) \(unit.displayName)")
                                } else if gfSizeMode != .packageSize, !gfUnitPriceText.isEmpty {
                                    Text("$\(gfUnitPriceText)/\(unit.displayName)")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Non-GF Product
                    VStack(spacing: 8) {
                        Text("Regular")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let image = nonGFImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .cornerRadius(8)
                        }

                        Text(nonGFProductName)
                            .font(.caption)
                            .lineLimit(2)

                        if let price = Decimal(string: nonGFPriceText) {
                            Text(price.formatted(.currency(code: "CAD")))
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }

                        if let unit = selectedUnit {
                            Group {
                                if nonGFSizeMode == .packageSize, !nonGFSizeText.isEmpty {
                                    Text("\(nonGFSizeText) \(unit.displayName)")
                                } else if nonGFSizeMode != .packageSize, !nonGFUnitPriceText.isEmpty {
                                    Text("$\(nonGFUnitPriceText)/\(unit.displayName)")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Differential
                if let gfPrice = Decimal(string: gfPriceText),
                   let nonGFPrice = Decimal(string: nonGFPriceText) {
                    let differential = gfPrice - nonGFPrice
                    VStack(spacing: 4) {
                        Text("Package Price Differential")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(differential.formatted(.currency(code: "CAD")))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(differential >= 0 ? .red : .green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }

                // Unit price differential preview (uses same back-calc logic as saveProductPair)
                let previewGFSize: Decimal? = {
                    if gfSizeMode == .packageSize {
                        return Decimal(string: gfSizeText)
                    } else if let p = Decimal(string: gfPriceText),
                              let u = Decimal(string: gfUnitPriceText), u > 0 {
                        let uDollars = gfUnitPriceBasis == .cents ? u / 100 : u
                        return p / uDollars
                    }
                    return nil
                }()
                let previewNonGFSize: Decimal? = {
                    if nonGFSizeMode == .packageSize {
                        return Decimal(string: nonGFSizeText)
                    } else if let p = Decimal(string: nonGFPriceText),
                              let u = Decimal(string: nonGFUnitPriceText), u > 0 {
                        let uDollars = nonGFUnitPriceBasis == .cents ? u / 100 : u
                        return p / uDollars
                    }
                    return nil
                }()

                if let gfP = Decimal(string: gfPriceText),
                   let regP = Decimal(string: nonGFPriceText),
                   let gfV = previewGFSize, gfV > 0,
                   let regV = previewNonGFSize, regV > 0 {
                    let normDiff = ((gfP / gfV) - (regP / regV)) * gfV
                    VStack(spacing: 4) {
                        Text("Unit Price Differential")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(normDiff.formatted(.currency(code: "CAD")))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(normDiff >= 0 ? .orange : .green)
                        Text("Accounts for package size difference")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Unit price differential: \(normDiff.formatted(.currency(code: "CAD"))). This accounts for the difference in package sizes.")
                }

                // Category
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Category", selection: $category) {
                        ForEach(commonCategories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Product category")
                    .accessibilityHint("Choose a category to organise your products")
                }

                // Notes
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $notes)
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }

                // Save Button
                Button {
                    saveProductPair()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isSaving ? "Saving..." : "Save Product Pair")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSaving ? Color.gray : Color.green)
                    .cornerRadius(12)
                }
                .disabled(isSaving)
            }
            .padding()
        }
    }

    // MARK: - OCR Loading Overlay

    private var ocrLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Processing Image...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(Color.gray.opacity(0.9))
            .cornerRadius(16)
        }
    }

    // MARK: - Actions

    /// Handles image from document scanner
    private func handleScannedImage(_ image: UIImage?) {
        guard let image = image else { return }

        Task {
            isProcessingOCR = true
            reviewToken = UUID()

            // Save image to storage
            let uuid = await ImageStorageService.shared.saveImage(image, type: .product)

            // Detect rectangles only if feature is enabled
            let rectangles: [DetectedRectangle]
            if rectangleSelectionEnabled {
                rectangles = (try? await OCRService.shared.detectRectangles(in: image)) ?? []
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
                    let observations = (try? await OCRService.shared.extractSelectableText(from: image)) ?? []
                    gfOCRObservations = observations
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
                    let observations = (try? await OCRService.shared.extractSelectableText(from: image)) ?? []
                    nonGFOCRObservations = observations
                    currentStep = .reviewNonGF
                }

            default:
                break
            }

            isProcessingOCR = false
        }
    }

    /// Handles selection of a rectangle region for OCR
    private func handleRectangleSelection(_ rectangle: DetectedRectangle, isGF: Bool) {
        guard let image = isGF ? gfImage : nonGFImage else { return }

        Task {
            isProcessingOCR = true
            reviewToken = UUID()

            // Extract text from selected region only
            let observations = (try? await OCRService.shared.extractSelectableText(from: image, region: rectangle.boundingBox)) ?? []

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
    }

    /// Handles skipping rectangle selection and using full-image OCR
    private func handleSkipRectangleSelection(isGF: Bool) {
        guard let image = isGF ? gfImage : nonGFImage else { return }

        Task {
            isProcessingOCR = true
            reviewToken = UUID()

            // Extract text from full image
            let observations = (try? await OCRService.shared.extractSelectableText(from: image)) ?? []

            if isGF {
                gfSelectedRectangle = nil
                gfOCRObservations = observations
                currentStep = .reviewGF
            } else {
                nonGFSelectedRectangle = nil
                nonGFOCRObservations = observations
                currentStep = .reviewNonGF
            }

            isProcessingOCR = false
        }
    }

    // MARK: - Size OCR Parsing

    /// Extracts a numeric size and suggests a SizeUnit from text like "400g", "1.5 L", "12oz"
    private func parseSizeFromOCR(_ text: String) -> (value: String, unit: SizeUnit?) {
        let unitPatterns: [(pattern: String, unit: SizeUnit)] = [
            (#"(\d+\.?\d*)\s*fl\.?\s*oz"#, .flOunces),
            (#"(\d+\.?\d*)\s*kg"#, .kilograms),
            (#"(\d+\.?\d*)\s*mL"#, .milliliters),
            (#"(\d+\.?\d*)\s*L\b"#, .liters),
            (#"(\d+\.?\d*)\s*oz"#, .ounces),
            (#"(\d+\.?\d*)\s*lb"#, .pounds),
            (#"(\d+\.?\d*)\s*g\b"#, .grams),
            (#"(\d+\.?\d*)\s*count"#, .count),
        ]

        for (pattern, unit) in unitPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   match.numberOfRanges > 1,
                   let valRange = Range(match.range(at: 1), in: text) {
                    return (String(text[valRange]), unit)
                }
            }
        }
        // No pattern matched — return raw text for manual editing
        return (text, nil)
    }

    /// Extracts a unit price and suggests a SizeUnit from text like "$1.49/100g", "0.99/oz"
    private func parseUnitPriceFromOCR(_ text: String) -> (value: String, unit: SizeUnit?) {
        let unitPatterns: [(pattern: String, unit: SizeUnit)] = [
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*fl\.?\s*oz"#, .flOunces),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*kg"#, .kilograms),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*mL"#, .milliliters),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*L\b"#, .liters),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*oz"#, .ounces),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*lb"#, .pounds),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*g\b"#, .grams),
            (#"\$?(\d+\.?\d*)\s*/\s*\d*\s*count"#, .count),
        ]

        for (pattern, unit) in unitPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   match.numberOfRanges > 1,
                   let valRange = Range(match.range(at: 1), in: text) {
                    return (String(text[valRange]), unit)
                }
            }
        }
        return (text, nil)
    }

    /// Routes an OCR row tap to the correct size field based on the current mode
    private func handleSizeRowTap(_ obs: SelectableTextObservation, isGF: Bool) {
        let mode = isGF ? gfSizeMode : nonGFSizeMode
        if mode == .packageSize {
            let parsed = parseSizeFromOCR(obs.text)
            if isGF {
                gfSizeText = parsed.value
                gfSelectedSizeObservationID = obs.id
            } else {
                nonGFSizeText = parsed.value
                nonGFSelectedSizeObservationID = obs.id
            }
            if let u = parsed.unit, selectedUnit == nil { selectedUnit = u }
        } else {
            let parsed = parseUnitPriceFromOCR(obs.text)
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

    /// Saves the product pair to SwiftData
    private func saveProductPair() {
        guard let gfPrice = Decimal(string: gfPriceText),
              let nonGFPrice = Decimal(string: nonGFPriceText) else {
            print("❌ Invalid price format")
            return
        }

        isSaving = true

        // Compute size values based on the input mode chosen during review
        let finalGFSizeValue: Decimal?
        if gfSizeMode == .packageSize {
            finalGFSizeValue = Decimal(string: gfSizeText)
        } else {
            // Unit Price / Manual: back-calculate size = productPrice / unitPrice (in dollars)
            // If basis is cents, divide by 100 to convert to dollars before dividing
            if let price = Decimal(string: gfPriceText),
               let unitPrice = Decimal(string: gfUnitPriceText), unitPrice > 0 {
                let unitPriceInDollars = gfUnitPriceBasis == .cents ? unitPrice / 100 : unitPrice
                finalGFSizeValue = price / unitPriceInDollars
            } else {
                finalGFSizeValue = nil
            }
        }

        let finalNonGFSizeValue: Decimal?
        if nonGFSizeMode == .packageSize {
            finalNonGFSizeValue = Decimal(string: nonGFSizeText)
        } else {
            if let price = Decimal(string: nonGFPriceText),
               let unitPrice = Decimal(string: nonGFUnitPriceText), unitPrice > 0 {
                let unitPriceInDollars = nonGFUnitPriceBasis == .cents ? unitPrice / 100 : unitPrice
                finalNonGFSizeValue = price / unitPriceInDollars
            } else {
                finalNonGFSizeValue = nil
            }
        }

        let sizeUnitRaw: String? = (finalGFSizeValue != nil && finalNonGFSizeValue != nil) ? selectedUnit?.rawValue : nil

        // Build display strings for legacy size fields
        let unitSuffix = selectedUnit?.displayName ?? ""
        let gfDisplayNum = gfSizeMode == .packageSize ? gfSizeText : gfUnitPriceText
        let nonGFDisplayNum = nonGFSizeMode == .packageSize ? nonGFSizeText : nonGFUnitPriceText
        let gfSizeDisplay: String? = gfDisplayNum.isEmpty ? nil : "\(gfDisplayNum)\(unitSuffix)"
        let nonGFSizeDisplay: String? = nonGFDisplayNum.isEmpty ? nil : "\(nonGFDisplayNum)\(unitSuffix)"

        let productPair = ProductPair(
            gfProductName: gfProductName.trimmingCharacters(in: .whitespacesAndNewlines),
            gfPrice: gfPrice,
            gfSize: gfSizeDisplay,
            gfSizeValue: finalGFSizeValue,
            gfImageUUID: gfImageUUID,
            gfOCRConfidence: 0.0,
            nonGFProductName: nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines),
            nonGFPrice: nonGFPrice,
            nonGFSize: nonGFSizeDisplay,
            nonGFSizeValue: finalNonGFSizeValue,
            nonGFImageUUID: nonGFImageUUID,
            nonGFOCRConfidence: 0.0,
            sizeUnit: sizeUnitRaw,
            category: (category.isEmpty || category == "None") ? nil : category,
            notes: notes.isEmpty ? nil : notes,
            verified: false
        )

        modelContext.insert(productPair)

        do {
            try modelContext.save()
            print("✅ Saved ProductPair: \(productPair.gfProductName) vs \(productPair.nonGFProductName)")
            print("   Differential: $\(productPair.differential)")

            isSaving = false
            dismiss()
        } catch {
            print("❌ Save failed: \(error.localizedDescription)")
            isSaving = false
        }
    }
}

// MARK: - Size Input Mode

enum SizeInputMode: String, CaseIterable {
    case packageSize = "Package Size"
    case unitPrice = "Unit Price"
    case manual = "Manual"
}

// MARK: - Unit Price Basis

enum UnitPriceBasis: String, CaseIterable {
    case cents = "Cents (¢)"
    case dollars = "Dollars ($)"
}

// MARK: - Capture Step Enum

private enum CaptureStep {
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

#if DEBUG
// MARK: - Preview

#Preview {
    ProductCaptureFlowView()
        .modelContainer(for: [ProductPair.self], inMemory: true)
}
#endif
