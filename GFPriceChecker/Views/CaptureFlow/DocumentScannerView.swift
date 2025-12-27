//
//  DocumentScannerView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import VisionKit

/// SwiftUI wrapper for iOS document scanner
///
/// Uses VisionKit's VNDocumentCameraViewController to provide native
/// document scanning with automatic edge detection, perspective correction,
/// and image quality optimization.
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
struct DocumentScannerView: UIViewControllerRepresentable {

    // MARK: - Properties

    /// Completion handler called when user finishes scanning
    /// - Parameter image: The scanned UIImage, or nil if cancelled
    let completion: (UIImage?) -> Void

    /// Environment dismiss action to close the scanner
    @Environment(\.dismiss) private var dismiss

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

        let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        /// Called when user successfully scans a document
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Get the first scanned page
            guard scan.pageCount > 0 else {
                parent.completion(nil)
                parent.dismiss()
                return
            }

            // Return the first scanned image
            let image = scan.imageOfPage(at: 0)
            parent.completion(image)
            parent.dismiss()
        }

        /// Called when user cancels scanning
        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            parent.completion(nil)
            parent.dismiss()
        }

        /// Called when scanning fails
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            print("Document scanner failed: \(error.localizedDescription)")
            parent.completion(nil)
            parent.dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    Button("Scan Document") {
        // Preview can't actually show scanner
    }
}
