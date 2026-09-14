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
/// Prefers VisionKit's `VNDocumentCameraViewController`, which gives native edge
/// detection, perspective correction and image-quality optimization. That
/// controller is unavailable in the Simulator, where this falls back to
/// `SubstituteScannerView` instead of presenting an empty sheet.
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
        if useDocumentCamera {
            DocumentCameraView(completion: completion)
        } else {
            SubstituteScannerView(completion: completion)
        }
    }

    /// Whether to present the real camera.
    ///
    /// In DEBUG a queued image wins even on a device: a scripted take supplies
    /// its own scans, and opening the camera would block it waiting for a tap.
    private var useDocumentCamera: Bool {
        #if DEBUG
        if ScannerImageProvider.hasPendingImages {
            return false
        }
        #endif
        return VNDocumentCameraViewController.isSupported
    }
}

/// SwiftUI wrapper for iOS document scanner
///
/// Only presented where `VNDocumentCameraViewController.isSupported` — see
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
            print("Document scanner failed: \(error.localizedDescription)")
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
