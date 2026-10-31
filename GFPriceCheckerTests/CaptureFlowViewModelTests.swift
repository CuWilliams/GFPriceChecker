//
//  CaptureFlowViewModelTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-09-14.
//

import Foundation
import GFCore
import SwiftData
import Testing
import UIKit
@testable import GFPriceChecker

/// Covers `CaptureFlowViewModel` — the logic lifted out of `ProductCaptureFlowView`
/// in Stage 3 of `docs/SCRIPTED_DEMO_PIPELINE.md`.
///
/// None of this could be reached before the extraction: it was ~35 `@State`
/// properties and five private methods inside a 986-line view, and the whole of
/// it went untested. The camera, OCR and image storage reach the view model
/// through `Dependencies`, so every test here runs a real capture with canned
/// observations and no Vision framework.
@MainActor
@Suite("Capture flow view model")
struct CaptureFlowViewModelTests {

    // MARK: - Fixtures

    /// A 1×1 image. Nothing under test looks at the pixels — the view model
    /// hands images straight to the dependencies, which are fakes here.
    static func stubImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    nonisolated static func observation(_ text: String, y: CGFloat = 0.5) -> SelectableTextObservation {
        SelectableTextObservation(
            text: text,
            boundingBox: CGRect(x: 0.1, y: y, width: 0.5, height: 0.05),
            confidence: 0.95
        )
    }

    nonisolated static func rectangle(confidence: Float = 0.9) -> DetectedRectangle {
        DetectedRectangle(
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.4),
            confidence: confidence
        )
    }

    /// Records what the view model asked its dependencies for, so a test can
    /// assert on the region passed to OCR or on a service never being called.
    @MainActor
    final class DependencySpy {
        var savedImageCount = 0
        var detectRectanglesCount = 0
        /// One entry per `extractText` call: the region asked for, `nil` for the whole image.
        var extractRegions: [CGRect?] = []

        var imageUUID: String? = "stub-uuid"
        var rectanglesToReturn: [DetectedRectangle] = []
        var observationsToReturn: [SelectableTextObservation] = []

        var dependencies: CaptureFlowViewModel.Dependencies {
            CaptureFlowViewModel.Dependencies(
                saveImage: { _ in
                    self.savedImageCount += 1
                    return self.imageUUID
                },
                detectRectangles: { _ in
                    self.detectRectanglesCount += 1
                    return self.rectanglesToReturn
                },
                extractText: { _, region in
                    self.extractRegions.append(region)
                    return self.observationsToReturn
                }
            )
        }
    }

    /// A view model wired to a spy that returns one readable text row.
    func makeFlow(
        rectangleSelectionEnabled: Bool = false,
        observations: [SelectableTextObservation]? = nil
    ) -> (CaptureFlowViewModel, DependencySpy) {
        let spy = DependencySpy()
        spy.observationsToReturn = observations ?? [Self.observation("Sample")]
        let viewModel = CaptureFlowViewModel(
            dependencies: spy.dependencies,
            rectangleSelectionEnabled: rectangleSelectionEnabled
        )
        return (viewModel, spy)
    }

    // MARK: - Step Progression

    @Test("A whole capture walks introduction to finalize")
    func fullFlowProgression() async {
        let (flow, spy) = makeFlow()
        #expect(flow.currentStep == .introduction)
        #expect(flow.showingScanner == false)

        flow.startCapture()
        #expect(flow.currentStep == .captureGF)
        #expect(flow.showingScanner == true)

        await flow.handleScannedImage(Self.stubImage())
        #expect(flow.currentStep == .reviewGF)
        #expect(flow.gfImage != nil)
        #expect(flow.gfImageUUID == "stub-uuid")
        #expect(flow.gfOCRObservations.count == 1)
        #expect(flow.isProcessingOCR == false)

        flow.continueFromReview(isGF: true)
        #expect(flow.currentStep == .captureNonGF)

        await flow.handleScannedImage(Self.stubImage())
        #expect(flow.currentStep == .reviewNonGF)
        #expect(flow.nonGFImage != nil)
        #expect(flow.nonGFOCRObservations.count == 1)

        flow.continueFromReview(isGF: false)
        #expect(flow.currentStep == .finalize)

        #expect(spy.savedImageCount == 2)
        #expect(spy.extractRegions == [nil, nil], "Both scans should OCR the whole image")
    }

    @Test("A scan with no image in hand changes nothing")
    func nilScanIsIgnored() async {
        let (flow, spy) = makeFlow()
        flow.startCapture()

        await flow.handleScannedImage(nil)

        #expect(flow.currentStep == .captureGF)
        #expect(flow.gfImage == nil)
        #expect(spy.savedImageCount == 0)
    }

    @Test("A scan arriving on a step that captures nothing is dropped")
    func scanOutsideACaptureStepIsDropped() async {
        let (flow, _) = makeFlow()
        // .introduction is neither .captureGF nor .captureNonGF
        await flow.handleScannedImage(Self.stubImage())

        #expect(flow.currentStep == .introduction)
        #expect(flow.gfImage == nil)
        #expect(flow.nonGFImage == nil)
    }

    @Test("Each fresh scan gives the review selector a new identity")
    func reviewTokenChangesPerScan() async {
        let (flow, _) = makeFlow()
        let initial = flow.reviewToken

        flow.startCapture()
        await flow.handleScannedImage(Self.stubImage())
        let afterGF = flow.reviewToken
        #expect(afterGF != initial)

        flow.continueFromReview(isGF: true)
        await flow.handleScannedImage(Self.stubImage())
        #expect(flow.reviewToken != afterGF)
    }

    // MARK: - Rectangle Selection

    @Test("Rectangle detection is skipped entirely when the feature is off")
    func rectanglesNotDetectedWhenDisabled() async {
        let (flow, spy) = makeFlow(rectangleSelectionEnabled: false)
        spy.rectanglesToReturn = [Self.rectangle()]

        flow.startCapture()
        await flow.handleScannedImage(Self.stubImage())

        #expect(spy.detectRectanglesCount == 0)
        #expect(flow.currentStep == .reviewGF)
        #expect(flow.gfDetectedRectangles.isEmpty)
    }

    @Test("With the feature on, detected rectangles route through region selection")
    func rectangleSelectionStep() async {
        let (flow, spy) = makeFlow(rectangleSelectionEnabled: true)
        let rect = Self.rectangle()
        spy.rectanglesToReturn = [rect]

        flow.startCapture()
        await flow.handleScannedImage(Self.stubImage())

        #expect(spy.detectRectanglesCount == 1)
        #expect(flow.currentStep == .selectGFRectangle)
        #expect(flow.gfDetectedRectangles.count == 1)
        #expect(spy.extractRegions.isEmpty, "OCR waits for the region to be chosen")

        await flow.handleRectangleSelection(rect, isGF: true)

        #expect(flow.currentStep == .reviewGF)
        #expect(flow.gfSelectedRectangle?.id == rect.id)
        #expect(spy.extractRegions == [rect.boundingBox])
    }

    @Test("With the feature on but nothing detected, the scan falls back to full-image OCR")
    func rectangleSelectionSkippedWhenNoneDetected() async {
        let (flow, spy) = makeFlow(rectangleSelectionEnabled: true)
        spy.rectanglesToReturn = []

        flow.startCapture()
        await flow.handleScannedImage(Self.stubImage())

        #expect(spy.detectRectanglesCount == 1)
        #expect(flow.currentStep == .reviewGF)
        #expect(spy.extractRegions == [nil])
    }

    @Test("Skipping region selection OCRs the whole image and clears the selection")
    func skippingRegionSelection() async {
        let (flow, spy) = makeFlow(rectangleSelectionEnabled: true)
        let rect = Self.rectangle()
        spy.rectanglesToReturn = [rect]

        flow.startCapture()
        await flow.handleScannedImage(Self.stubImage())
        await flow.handleSkipRectangleSelection(isGF: true)

        #expect(flow.currentStep == .reviewGF)
        #expect(flow.gfSelectedRectangle == nil)
        #expect(spy.extractRegions == [nil])
    }

    // MARK: - Retake and Reset

    @Test("Retaking clears the product's fields and reopens the scanner")
    func retakeClearsFields() async {
        let (flow, _) = makeFlow()
        flow.startCapture()
        await flow.handleScannedImage(Self.stubImage())

        flow.gfProductName = "Northfield GF White Bread"
        flow.gfPriceText = "7.49"
        flow.gfSizeText = "500"
        flow.gfSizeMode = .unitPrice
        flow.gfUnitPriceBasis = .dollars
        flow.gfSelectedSizeObservationID = flow.gfOCRObservations.first?.id
        flow.showingScanner = false

        flow.retake(isGF: true)

        #expect(flow.gfProductName.isEmpty)
        #expect(flow.gfPriceText.isEmpty)
        #expect(flow.gfSizeText.isEmpty)
        #expect(flow.gfSizeMode == .packageSize)
        #expect(flow.gfUnitPriceBasis == .cents)
        #expect(flow.gfSelectedSizeObservationID == nil)
        #expect(flow.gfOCRObservations.isEmpty)
        #expect(flow.currentStep == .captureGF)
        #expect(flow.showingScanner == true)
    }

    @Test("Resetting one product leaves the other alone")
    func resetIsPerProduct() {
        let (flow, _) = makeFlow()
        flow.gfProductName = "GF"
        flow.nonGFProductName = "Regular"
        flow.nonGFPriceText = "4.29"

        flow.resetProductFields(isGF: true)

        #expect(flow.gfProductName.isEmpty)
        #expect(flow.nonGFProductName == "Regular")
        #expect(flow.nonGFPriceText == "4.29")
    }

    @Test("Skipping a product with no text moves on without clearing anything")
    func skipAfterNoText() {
        let (flow, _) = makeFlow()
        flow.currentStep = .reviewGF
        flow.gfProductName = "Partially typed"

        flow.skipProduct(isGF: true)

        #expect(flow.currentStep == .captureNonGF)
        #expect(flow.showingScanner == true)
        #expect(flow.gfProductName == "Partially typed")
    }

    // MARK: - OCR Row Taps

    @Test("A tapped row fills the size field in package-size mode")
    func sizeRowTapInPackageMode() {
        let (flow, _) = makeFlow()
        let obs = Self.observation("500 g")

        flow.handleSizeRowTap(obs, isGF: true)

        #expect(flow.gfSizeText == "500")
        #expect(flow.gfUnitPriceText.isEmpty)
        #expect(flow.gfSelectedSizeObservationID == obs.id)
        #expect(flow.selectedUnit == .grams)
    }

    @Test("A tapped row fills the unit price field in unit-price mode")
    func sizeRowTapInUnitPriceMode() {
        let (flow, _) = makeFlow()
        flow.nonGFSizeMode = .unitPrice
        let obs = Self.observation("$1.49/100g")

        flow.handleSizeRowTap(obs, isGF: false)

        #expect(flow.nonGFUnitPriceText == "1.49")
        #expect(flow.nonGFSizeText.isEmpty)
        #expect(flow.nonGFSelectedSizeObservationID == obs.id)
        #expect(flow.selectedUnit == .grams)
    }

    @Test("A tapped row never overrides a unit already chosen")
    func sizeRowTapDoesNotOverrideUnit() {
        let (flow, _) = makeFlow()
        flow.selectedUnit = .ounces

        flow.handleSizeRowTap(Self.observation("500 g"), isGF: true)

        #expect(flow.gfSizeText == "500")
        #expect(flow.selectedUnit == .ounces, "The unit is shared by the pair, so the first choice stands")
    }

    // MARK: - Review Taps

    @Test("Review taps fill name, then price, then size")
    func reviewTapsWalkThePhases() async {
        let name = Self.observation("Gluten Free White Bread", y: 0.8)
        let price = Self.observation("$7.49", y: 0.6)
        let size = Self.observation("400 g", y: 0.4)
        let (flow, _) = makeFlow(observations: [name, price, size])
        flow.startCapture()
        await flow.handleScannedImage(Self.stubImage())
        #expect(flow.gfReviewPhase == .selectingName)

        #expect(flow.handleReviewTap(name, isGF: true) == nil)
        #expect(flow.gfProductName == "Gluten Free White Bread")
        #expect(flow.gfSelectedNameObservationID == name.id)
        #expect(flow.gfReviewPhase == .selectingPrice)

        #expect(flow.handleReviewTap(price, isGF: true) == nil)
        #expect(flow.gfPriceText == "7.49", "The $ is dropped")
        #expect(flow.gfSelectedPriceObservationID == price.id)
        #expect(flow.gfReviewPhase == .selectingSize)

        #expect(flow.handleReviewTap(size, isGF: true) == nil)
        #expect(flow.gfSizeText == "400")
        #expect(flow.gfSelectedSizeObservationID == size.id)
        #expect(flow.gfReviewPhase == .selectingSize, "Size stays open so another row can be retapped")

        // The regular product's review is untouched
        #expect(flow.nonGFReviewPhase == .selectingName)
        #expect(flow.nonGFProductName.isEmpty)
    }

    @Test("A price with no decimal point is suggested, not set")
    func reviewTapSuggestsDecimal() {
        let (flow, _) = makeFlow()
        flow.handleReviewTap(Self.observation("Bread"), isGF: false)
        let price = Self.observation("1299")

        #expect(flow.handleReviewTap(price, isGF: false) == "$12.99")
        #expect(flow.nonGFPriceText.isEmpty)
        #expect(flow.nonGFReviewPhase == .selectingPrice)

        flow.confirmPrice(price, text: "$12.99", isGF: false)
        #expect(flow.nonGFPriceText == "12.99")
        #expect(flow.nonGFSelectedPriceObservationID == price.id)
        #expect(flow.nonGFReviewPhase == .selectingSize)
    }

    @Test("Skipping the size completes the review")
    func skipSizeCompletesReview() {
        let (flow, _) = makeFlow()
        flow.handleReviewTap(Self.observation("Bread"), isGF: true)
        flow.handleReviewTap(Self.observation("$3.29"), isGF: true)

        flow.skipSize(isGF: true)

        #expect(flow.gfReviewPhase == .complete)
        #expect(flow.gfSizeText.isEmpty)
    }

    @Test("A fresh scan, a retake or a clear starts the review over")
    func reviewResets() async {
        let name = Self.observation("Bread")
        let price = Self.observation("$3.29")
        let (flow, _) = makeFlow(observations: [name, price])
        flow.startCapture()
        await flow.handleScannedImage(Self.stubImage())

        func select() {
            flow.handleReviewTap(name, isGF: true)
            flow.handleReviewTap(price, isGF: true)
            #expect(flow.gfReviewPhase == .selectingSize)
        }
        func expectFresh(_ comment: Comment) {
            #expect(flow.gfReviewPhase == .selectingName, comment)
            #expect(flow.gfSelectedNameObservationID == nil, comment)
            #expect(flow.gfSelectedPriceObservationID == nil, comment)
        }

        select()
        flow.resetProductFields(isGF: true)
        expectFresh("Clear Selections")

        select()
        flow.retake(isGF: true)
        expectFresh("Retake")

        select()
        flow.currentStep = .captureGF
        await flow.handleScannedImage(Self.stubImage())
        expectFresh("A new scan")
    }

    @Test("Price text keeps only the first $d.dd it contains", arguments: [
        ("$7.49", "7.49"),
        ("SALE 4.99 ea", "4.99"),
        ("no price", "no price")
    ])
    func extractPrice(text: String, expected: String) {
        #expect(CaptureFlowViewModel.extractPrice(from: text) == expected)
    }

    // MARK: - Derived Values

    @Test("Package-size mode takes the size straight from the field")
    func sizeValueFromPackageSize() {
        let (flow, _) = makeFlow()
        flow.gfSizeMode = .packageSize
        flow.gfSizeText = "500"

        #expect(flow.gfSizeValue == Decimal(500))
    }

    @Test("Unit-price mode back-calculates size from price and unit price")
    func sizeValueBackCalculated() {
        let (flow, _) = makeFlow()
        flow.gfSizeMode = .unitPrice
        flow.gfPriceText = "5.00"

        // 50¢ per unit → $0.50 → 10 units for $5.00. The arithmetic, and its zero and
        // dollar cases, are GFCore's `PricingInputsTests`; this checks the mode routes there.
        flow.gfUnitPriceBasis = .cents
        flow.gfUnitPriceText = "50"
        #expect(flow.gfSizeValue == Decimal(10))

        flow.gfUnitPriceText = ""
        #expect(flow.gfSizeValue == nil)
    }

    @Test("The differentials come from the text fields through GFCore")
    func differentialsFromTextFields() {
        let (flow, _) = makeFlow()
        flow.gfPriceText = "6.00"
        flow.gfSizeText = "500"
        flow.nonGFPriceText = "4.00"
        flow.nonGFSizeText = "1000"

        #expect(flow.pricing == PricingInputs(
            gfPrice: Decimal(string: "6.00")!,
            nonGFPrice: Decimal(string: "4.00")!,
            gfSizeValue: 500,
            nonGFSizeValue: 1000
        ))
        #expect(flow.packagePriceDifferential == Decimal(2))
        #expect(flow.normalizedDifferential == Decimal(4))
    }

    @Test("There is nothing to compute until both prices parse")
    func differentialsNeedBothPrices() {
        let (flow, _) = makeFlow()
        flow.gfPriceText = "6.00"
        flow.gfSizeText = "500"
        flow.nonGFSizeText = "1000"

        #expect(flow.pricing == nil)
        #expect(flow.packagePriceDifferential == nil)
        #expect(flow.normalizedDifferential == nil)
    }

    @Test("The size-adjusted differential is unavailable until both sizes are known")
    func normalizedDifferentialNeedsBothSizes() {
        let (flow, _) = makeFlow()
        flow.gfPriceText = "6.00"
        flow.gfSizeText = "500"
        flow.nonGFPriceText = "4.00"

        #expect(flow.packagePriceDifferential != nil)
        #expect(flow.normalizedDifferential == nil)
    }

    @Test("A stored unit is only recorded when both sizes are known")
    func storedUnitNeedsBothSizes() {
        let (flow, _) = makeFlow()
        flow.selectedUnit = .grams
        flow.gfSizeText = "500"

        #expect(flow.storedSizeUnitRaw == nil)

        flow.nonGFSizeText = "1000"
        #expect(flow.storedSizeUnitRaw == "g")
    }

    @Test("The None category sentinel is stored as no category")
    func noneCategoryIsNil() {
        let (flow, _) = makeFlow()
        #expect(flow.category == "None")
        #expect(flow.storedCategory == nil)

        flow.category = ""
        #expect(flow.storedCategory == nil)

        flow.category = "Bread"
        #expect(flow.storedCategory == "Bread")
    }

    // MARK: - Saving

    /// An in-memory store. The container is returned alongside the context and
    /// must be held for as long as the context is used — letting it deallocate
    /// tears down the store and traps inside SwiftData on the next fetch.
    static func makeStore() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: ProductPair.self, Receipt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    @Test("Saving writes the pair the review screens describe")
    func saveWritesTheCapturedPair() throws {
        let (container, context) = try Self.makeStore()
        let (flow, _) = makeFlow()

        flow.gfProductName = "  Northfield GF White Bread  "
        flow.gfPriceText = "7.49"
        flow.gfSizeText = "500"
        flow.gfImageUUID = "gf-uuid"
        flow.nonGFProductName = "Store Brand White Bread"
        flow.nonGFPriceText = "4.29"
        flow.nonGFSizeText = "675"
        flow.nonGFImageUUID = "reg-uuid"
        flow.selectedUnit = .grams
        flow.category = "Bread"
        flow.notes = "Aisle 4"

        #expect(flow.canSave)
        #expect(flow.save(into: context))
        #expect(flow.didSave)
        #expect(flow.isSaving == false)

        let saved = try context.fetch(FetchDescriptor<ProductPair>())
        #expect(saved.count == 1)
        let pair = try #require(saved.first)

        #expect(pair.gfProductName == "Northfield GF White Bread", "Names are trimmed on the way in")
        #expect(pair.gfPrice == Decimal(string: "7.49"))
        #expect(pair.gfSizeValue == Decimal(500))
        #expect(pair.gfSize == "500g")
        #expect(pair.gfImageUUID == "gf-uuid")
        #expect(pair.nonGFProductName == "Store Brand White Bread")
        #expect(pair.nonGFPrice == Decimal(string: "4.29"))
        #expect(pair.nonGFSizeValue == Decimal(675))
        #expect(pair.nonGFSize == "675g")
        #expect(pair.sizeUnit == "g")
        #expect(pair.category == "Bread")
        #expect(pair.notes == "Aisle 4")
        #expect(pair.verified == false)
        #expect(pair.differential == Decimal(string: "3.20"))

        _ = container
    }

    @Test("Saving in unit-price mode stores the back-calculated size")
    func saveStoresBackCalculatedSize() throws {
        let (container, context) = try Self.makeStore()
        let (flow, _) = makeFlow()

        flow.gfProductName = "GF Pasta"
        flow.gfPriceText = "5.00"
        flow.gfSizeMode = .unitPrice
        flow.gfUnitPriceBasis = .cents
        flow.gfUnitPriceText = "50"
        flow.nonGFProductName = "Regular Pasta"
        flow.nonGFPriceText = "2.00"
        flow.nonGFSizeText = "500"
        flow.selectedUnit = .grams

        #expect(flow.save(into: context))

        let pair = try #require(try context.fetch(FetchDescriptor<ProductPair>()).first)
        #expect(pair.gfSizeValue == Decimal(10))
        #expect(pair.gfSize == "50g", "The legacy display string keeps the number the user typed")
        #expect(pair.nonGFSizeValue == Decimal(500))

        _ = container
    }

    @Test("Saving without both prices writes nothing")
    func saveRefusesWithoutPrices() throws {
        let (container, context) = try Self.makeStore()
        let (flow, _) = makeFlow()

        flow.gfProductName = "GF Bread"
        flow.gfPriceText = "7.49"
        flow.nonGFProductName = "Regular Bread"
        flow.nonGFPriceText = ""

        #expect(flow.canSave == false)
        #expect(flow.makeProductPair() == nil)
        #expect(flow.save(into: context) == false)
        #expect(flow.didSave == false)
        #expect(try context.fetch(FetchDescriptor<ProductPair>()).isEmpty)

        _ = container
    }

    @Test("Empty optional fields are stored as absent, not as empty strings")
    func emptyOptionalsAreNil() throws {
        let (container, context) = try Self.makeStore()
        let (flow, _) = makeFlow()

        flow.gfProductName = "GF Crackers"
        flow.gfPriceText = "5.99"
        flow.nonGFProductName = "Regular Crackers"
        flow.nonGFPriceText = "3.49"

        #expect(flow.save(into: context))

        let pair = try #require(try context.fetch(FetchDescriptor<ProductPair>()).first)
        #expect(pair.category == nil)
        #expect(pair.notes == nil)
        #expect(pair.gfSize == nil)
        #expect(pair.nonGFSize == nil)
        #expect(pair.sizeUnit == nil)

        _ = container
    }

    // MARK: - Step Titles

    @Test("Every step names itself for the navigation bar")
    func everyStepHasATitle() {
        for step in CaptureStep.allCases {
            #expect(step.title.isEmpty == false)
        }
        #expect(CaptureStep.introduction.title == "Capture Product Pair")
        #expect(CaptureStep.finalize.title == "Finalize")
    }
}
