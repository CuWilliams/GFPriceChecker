//
//  DocumentScannerSourceTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-09-14.
//

import Testing
import VisionKit
@testable import GFPriceChecker

/// Pins which scanner `DocumentScannerView` chooses.
///
/// This is the decision that was wrong the first time. The substitute scanner
/// and its sample images were all covered by tests and all green, while the flow
/// still dead-ended in the Simulator, because nothing asserted anything about
/// *choosing* the substitute — the guard consulted
/// `VNDocumentCameraViewController.isSupported`, which reports `true` in the
/// Simulator even though the controller there never returns an image.
///
/// A wrong answer here fails quietly: the user gets a sheet that does nothing.
/// So the table below is exhaustive over the three inputs, and one test asserts
/// the real environment resolves the way the flow needs it to.
@MainActor
@Suite("Document scanner source", .serialized)
struct DocumentScannerSourceTests {

    typealias Source = DocumentScannerView.Source

    // MARK: - The Decision Table

    @Test("A queued image always wins, device included")
    func queuedImageWins() {
        for cameraIsSupported in [true, false] {
            for isSimulator in [true, false] {
                let source = DocumentScannerView.source(
                    cameraIsSupported: cameraIsSupported,
                    isSimulator: isSimulator,
                    hasQueuedImages: true
                )
                #expect(
                    source == .substitute,
                    "supported: \(cameraIsSupported), simulator: \(isSimulator)"
                )
            }
        }
    }

    @Test("The Simulator never gets the camera, whatever isSupported claims")
    func simulatorNeverGetsTheCamera() {
        for cameraIsSupported in [true, false] {
            let source = DocumentScannerView.source(
                cameraIsSupported: cameraIsSupported,
                isSimulator: true,
                hasQueuedImages: false
            )
            #expect(source == .substitute, "isSupported was \(cameraIsSupported)")
        }
    }

    @Test("A device with a supported camera gets the camera")
    func deviceGetsTheCamera() {
        let source = DocumentScannerView.source(
            cameraIsSupported: true,
            isSimulator: false,
            hasQueuedImages: false
        )
        #expect(source == .documentCamera)
    }

    @Test("A device without a supported camera gets the substitute")
    func unsupportedDeviceGetsTheSubstitute() {
        let source = DocumentScannerView.source(
            cameraIsSupported: false,
            isSimulator: false,
            hasQueuedImages: false
        )
        #expect(source == .substitute)
    }

    // MARK: - This Environment

    /// The acceptance criterion for Stage 1, asserted where it can actually be
    /// checked: the test bundle runs in the Simulator, so the flows here must
    /// resolve to the substitute.
    @Test("The capture flows resolve to the substitute in the Simulator")
    func thisEnvironmentUsesTheSubstitute() throws {
        ScannerImageProvider.reset()
        defer { ScannerImageProvider.reset() }

        try #require(DocumentScannerView.isSimulator, "these tests assume a Simulator run")
        #expect(DocumentScannerView.resolvedSource == .substitute)
    }

    /// Records the fact that motivated the `isSimulator` branch. If a future OS
    /// starts reporting this honestly, this test goes red and the branch can be
    /// reconsidered rather than silently carried forever.
    @Test("isSupported still over-reports in the Simulator")
    func isSupportedOverReportsHere() {
        #expect(
            VNDocumentCameraViewController.isSupported,
            "isSupported now reports false in the Simulator — revisit DocumentScannerView.source"
        )
    }
}
