//
//  ReceiptCaptureViewModelTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-10-31.
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import GFPriceChecker

/// Covers `ReceiptCaptureViewModel` — the logic lifted out of `ReceiptCaptureView`
/// for issue #90 (`docs/SCRIPTED_DEMO_PIPELINE.md` §2 Blocker 2).
///
/// Before the extraction this was 17 `@State` properties and eight private
/// methods inside the view, with no test coverage. OCR and image storage reach
/// the view model through `Dependencies`, and the save takes a `ModelContext`,
/// so every test here runs a real verification with canned OCR text and an
/// in-memory store.
@MainActor
@Suite("Receipt capture view model")
struct ReceiptCaptureViewModelTests {

    // MARK: - Fixtures

    /// Text the parser reads as a Loblaws receipt from 14 March 2026 totalling $19.96.
    static let receiptText = """
        LOBLAWS
        2026-03-14
        GF BREAD          6.99
        GF PASTA          5.49
        SUBTOTAL         17.66
        HST 13%           2.30
        TOTAL            19.96
        """

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

    struct OCRFailure: Error {}

    /// Records what the view model asked its dependencies for, and returns canned results.
    @MainActor
    final class DependencySpy {
        var receiptTextCount = 0
        var selectableTextCount = 0
        var savedImageCount = 0

        var receiptText = ReceiptCaptureViewModelTests.receiptText
        var observations = [
            ReceiptCaptureViewModelTests.observation("GF BREAD 6.99", y: 0.8),
            ReceiptCaptureViewModelTests.observation("GF PASTA 5.49", y: 0.7)
        ]
        var imageUUID: String? = "receipt-uuid"
        var failOCR = false

        var dependencies: ReceiptCaptureViewModel.Dependencies {
            ReceiptCaptureViewModel.Dependencies(
                extractReceiptText: { _ in
                    self.receiptTextCount += 1
                    if self.failOCR { throw OCRFailure() }
                    return self.receiptText
                },
                extractSelectableText: { _ in
                    self.selectableTextCount += 1
                    return self.observations
                },
                saveImage: { _ in
                    self.savedImageCount += 1
                    return self.imageUUID
                }
            )
        }
    }

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

    static func pair(_ name: String, in context: ModelContext) -> ProductPair {
        let pair = ProductPair(
            gfProductName: name,
            gfPrice: Decimal(string: "6.99")!,
            nonGFProductName: "Regular \(name)",
            nonGFPrice: Decimal(string: "3.49")!,
            verified: false
        )
        context.insert(pair)
        return pair
    }

    /// A view model wired to a spy, offering the given pairs.
    func makeFlow(products: [ProductPair] = []) -> (ReceiptCaptureViewModel, DependencySpy) {
        let spy = DependencySpy()
        let viewModel = ReceiptCaptureViewModel(dependencies: spy.dependencies)
        viewModel.unverifiedProducts = products
        return (viewModel, spy)
    }

    // MARK: - Whole Verification

    @Test("A whole verification links matched pairs and leaves skipped ones alone")
    func fullVerification() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let bread = Self.pair("GF Bread", in: context)
        let pasta = Self.pair("GF Pasta", in: context)
        let crackers = Self.pair("GF Crackers", in: context)
        let (flow, spy) = makeFlow(products: [bread, pasta, crackers])

        #expect(flow.currentStep == .selectProducts)

        // Pick two of the three
        flow.toggleProductSelection(bread)
        flow.toggleProductSelection(pasta)
        #expect(flow.productsToVerify.map(\.id) == [bread.id, pasta.id])

        flow.continueToScan()
        #expect(flow.currentStep == .scanReceipt)

        flow.openScanner()
        #expect(flow.showingScanner)

        await flow.handleScannedReceipt(Self.stubImage())
        #expect(flow.showingScanner == false)
        #expect(flow.isProcessingOCR == false)
        #expect(flow.currentStep == .reviewMatches)
        #expect(flow.receiptOCRObservations.count == 2)
        #expect(flow.storeName == "Loblaws")
        #expect(flow.totalAmount == "19.96")
        let day = Calendar.current.dateComponents([.year, .month, .day], from: flow.purchaseDate)
        #expect(day.year == 2026 && day.month == 3 && day.day == 14)

        // Match the bread, skip the pasta
        #expect(flow.currentProductToVerify?.id == bread.id)
        flow.confirmMatch(for: bread, withLine: "GF BREAD 6.99")
        #expect(flow.currentProductToVerify?.id == pasta.id)
        flow.skipProduct(pasta)
        #expect(flow.currentProductToVerify == nil)
        #expect(flow.confirmedCount == 1)

        let saved = await flow.save(into: context)
        #expect(saved)
        #expect(flow.didSave)
        #expect(flow.receiptImageUUID == "receipt-uuid")

        let receipts = try context.fetch(FetchDescriptor<Receipt>())
        let receipt = try #require(receipts.first)
        #expect(receipts.count == 1)
        #expect(receipt.storeName == "Loblaws")
        #expect(receipt.totalAmount == Decimal(string: "19.96"))
        #expect(receipt.receiptImageUUID == "receipt-uuid")
        #expect(receipt.extractedOCRText == Self.receiptText)

        #expect(bread.verified)
        #expect(bread.receipt?.id == receipt.id)
        #expect(pasta.verified == false, "a skipped pair stays unverified")
        #expect(pasta.receipt == nil)
        #expect(crackers.verified == false, "an unselected pair is untouched")
        #expect(crackers.receipt == nil)

        #expect(spy.receiptTextCount == 1)
        #expect(spy.selectableTextCount == 1)
        #expect(spy.savedImageCount == 1)
    }

    // MARK: - Selection

    @Test("Select all, deselect all and toggle")
    func selection() throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let bread = Self.pair("GF Bread", in: context)
        let pasta = Self.pair("GF Pasta", in: context)
        let (flow, _) = makeFlow(products: [bread, pasta])

        flow.selectAllProducts()
        #expect(flow.selectedProducts == [bread.id, pasta.id])

        flow.toggleProductSelection(bread)
        #expect(flow.selectedProducts == [pasta.id])

        flow.deselectAllProducts()
        #expect(flow.selectedProducts.isEmpty)
        #expect(flow.productsToVerify.isEmpty)
    }

    @Test("Back from the scan prompt returns to selection with the choice kept")
    func backToSelection() throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let bread = Self.pair("GF Bread", in: context)
        let (flow, _) = makeFlow(products: [bread])

        flow.toggleProductSelection(bread)
        flow.continueToScan()
        flow.backToProductSelection()

        #expect(flow.currentStep == .selectProducts)
        #expect(flow.selectedProducts == [bread.id])
    }

    // MARK: - Scanning

    @Test("A cancelled scan closes the scanner and reads nothing")
    func cancelledScan() async {
        let (flow, spy) = makeFlow()
        flow.continueToScan()
        flow.openScanner()

        await flow.handleScannedReceipt(nil)

        #expect(flow.showingScanner == false)
        #expect(flow.currentStep == .scanReceipt)
        #expect(flow.receiptImage == nil)
        #expect(spy.receiptTextCount == 0)
        #expect(spy.selectableTextCount == 0)
    }

    @Test("An OCR failure raises the alert and stays on the scan prompt")
    func ocrFailure() async {
        let (flow, spy) = makeFlow()
        spy.failOCR = true
        flow.continueToScan()

        await flow.handleScannedReceipt(Self.stubImage())

        #expect(flow.showingAlert)
        #expect(flow.alertMessage.hasPrefix("Failed to process receipt"))
        #expect(flow.isProcessingOCR == false)
        #expect(flow.currentStep == .scanReceipt)
    }

    @Test("A second scan starts the matching over")
    func rescanResetsMatches() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let bread = Self.pair("GF Bread", in: context)
        let (flow, _) = makeFlow(products: [bread])
        flow.selectAllProducts()

        await flow.handleScannedReceipt(Self.stubImage())
        flow.confirmMatch(for: bread, withLine: "GF BREAD 6.99")
        #expect(flow.confirmedCount == 1)

        await flow.handleScannedReceipt(Self.stubImage())
        #expect(flow.confirmedMatches.isEmpty)
        #expect(flow.currentVerificationIndex == 0)
        #expect(flow.currentProductToVerify?.id == bread.id)
    }

    @Test("Fields the parser cannot find are left for the user")
    func unparsedFields() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let bread = Self.pair("GF Bread", in: context)
        let (flow, spy) = makeFlow(products: [bread])
        spy.receiptText = "gf bread 6.99"
        flow.selectAllProducts()

        await flow.handleScannedReceipt(Self.stubImage())
        #expect(flow.storeName.isEmpty)
        #expect(flow.totalAmount.isEmpty)

        flow.confirmMatch(for: bread, withLine: "gf bread 6.99")
        #expect(await flow.save(into: context))

        let receipt = try #require(try context.fetch(FetchDescriptor<Receipt>()).first)
        #expect(receipt.storeName == nil)
        #expect(receipt.totalAmount == nil)
    }

    // MARK: - Saving

    @Test("A failed image save writes nothing")
    func imageSaveFailure() async throws {
        let (container, context) = try Self.makeStore()
        defer { withExtendedLifetime(container) {} }
        let bread = Self.pair("GF Bread", in: context)
        let (flow, spy) = makeFlow(products: [bread])
        spy.imageUUID = nil
        flow.selectAllProducts()

        await flow.handleScannedReceipt(Self.stubImage())
        flow.confirmMatch(for: bread, withLine: "GF BREAD 6.99")

        #expect(await flow.save(into: context) == false)
        #expect(flow.didSave == false)
        #expect(flow.showingAlert)
        #expect(flow.alertMessage == "Failed to save receipt image")
        #expect(try context.fetch(FetchDescriptor<Receipt>()).isEmpty)
        #expect(bread.verified == false)
    }
}
