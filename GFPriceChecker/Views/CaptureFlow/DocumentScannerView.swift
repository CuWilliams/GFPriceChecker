//
//  DocumentScannerView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import VisionKit

/// Scans a document and hands back one image.
///
/// On a device it presents VisionKit's `VNDocumentCameraViewController`, which
/// gives native edge detection, perspective correction and image-quality
/// optimization. In the Simulator it presents `SubstituteScannerView` instead,
/// which sources an image from the photo library or a drawn sample.
///
/// Note that the Simulator is detected by `targetEnvironment(simulator)`, not by
/// `VNDocumentCameraViewController.isSupported` — that reports `true` in the
/// Simulator while the controller still never returns an image. See
/// `source(cameraIsSupported:isSimulator:hasQueuedImages:)`.
///
/// Because the choice is made here, all three call sites get the fallback
/// without knowing about it, and behaviour on a physical device is unchanged.
///
/// Usage:
/// ```swift
/// @State private var showingScanner = false
///
/// Button("Scan Document") {
///     showingScanner = true
/// }
/// .sheet(isPresented: $showingScanner) {
///     DocumentScannerView { image in
///         // Handle scanned image
///     }
/// }
/// ```
struct DocumentScannerView: View {

    // MARK: - Properties

    /// Completion handler called when user finishes scanning
    /// - Parameter image: The scanned UIImage, or nil if cancelled
    let completion: (UIImage?) -> Void

    // MARK: - Body

    var body: some View {
        switch Self.resolvedSource {
        case .documentCamera:
            DocumentCameraView(completion: completion)
        case .substitute:
            SubstituteScannerView(completion: completion)
        }
    }

    // MARK: - Source Selection

    /// Where the image comes from.
    enum Source: Equatable {
        case documentCamera
        case substitute
    }

    /// Picks a source from the facts about the current environment.
    ///
    /// Pure, and separate from the view, because this decision is the one thing
    /// here that can be wrong without anything failing loudly: pick the camera
    /// where it does not work and the flow simply stops at a sheet that never
    /// returns an image.
    ///
    /// - Parameters:
    ///   - cameraIsSupported: `VNDocumentCameraViewController.isSupported`.
    ///   - isSimulator: whether this build is running in the Simulator.
    ///   - hasQueuedImages: whether `ScannerImageProvider` has an image waiting.
    static func source(
        cameraIsSupported: Bool,
        isSimulator: Bool,
        hasQueuedImages: Bool
    ) -> Source {
        // A queued image wins everywhere, device included: a scripted take
        // supplies its own scans, and the camera would block it awaiting a tap.
        if hasQueuedImages {
            return .substitute
        }

        // `isSupported` is not a usable signal for the Simulator. Measured on
        // iOS 26 / Xcode 26.1.1, it returns **true** there, and presenting the
        // controller anyway gets a sheet that never produces an image. So the
        // Simulator is excluded on its own terms, before `isSupported` is
        // consulted at all.
        if isSimulator {
            return .substitute
        }

        return cameraIsSupported ? .documentCamera : .substitute
    }

    /// `source(cameraIsSupported:isSimulator:hasQueuedImages:)` applied to this
    /// build and this moment.
    static var resolvedSource: Source {
        #if DEBUG
        let queued = ScannerImageProvider.hasPendingImages
        #else
        let queued = false
        #endif

        return source(
            cameraIsSupported: VNDocumentCameraViewController.isSupported,
            isSimulator: isSimulator,
            hasQueuedImages: queued
        )
    }

    /// Whether this build is running in the Simulator.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

/// SwiftUI wrapper for iOS document scanner
///
/// Only presented on a device with a supported camera — see
/// `DocumentScannerView`, which is what callers use.
private struct DocumentCameraView: UIViewControllerRepresentable {

    // MARK: - Properties

    let completion: (UIImage?) -> Void

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    /// Coordinator to handle VNDocumentCameraViewController delegate callbacks
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {

        let parent: DocumentCameraView

        init(_ parent: DocumentCameraView) {
            self.parent = parent
        }

        /// Called when user successfully scans a document
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Get the first scanned page
            guard scan.pageCount > 0 else {
                controller.dismiss(animated: true) {
                    self.parent.completion(nil)
                }
                return
            }

            // Return the first scanned image
            let image = scan.imageOfPage(at: 0)
            controller.dismiss(animated: true) {
                self.parent.completion(image)
            }
        }

        /// Called when user cancels scanning
        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            controller.dismiss(animated: true) {
                self.parent.completion(nil)
            }
        }

        /// Called when scanning fails
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            ErrorHandler.shared.log(error, context: "Document scanner")
            controller.dismiss(animated: true) {
                self.parent.completion(nil)
            }
        }
    }
}

#if DEBUG
// MARK: - Preview

#Preview {
    DocumentScannerView { _ in }
}
#endif
