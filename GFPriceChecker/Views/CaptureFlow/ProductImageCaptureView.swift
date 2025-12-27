//
//  ProductImageCaptureView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI

/// View for capturing product images using document scanner
///
/// Demonstrates integration between DocumentScannerView and ImageStorageService.
/// Users can scan a product image, preview it, and save it to storage.
struct ProductImageCaptureView: View {

    // MARK: - State

    /// Controls the visibility of the document scanner
    @State private var showingScanner = false

    /// The captured image from scanner
    @State private var capturedImage: UIImage?

    /// UUID of saved image (if saved)
    @State private var savedImageUUID: String?

    /// Loading state during save operation
    @State private var isSaving = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = capturedImage {
                    // Show captured image
                    capturedImageView(image)
                } else {
                    // Show placeholder
                    emptyStateView
                }
            }
            .navigationTitle("Capture Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan", systemImage: "camera")
                    }
                }

                if capturedImage != nil && savedImageUUID == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                await saveImage()
                            }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView { image in
                    capturedImage = image
                    savedImageUUID = nil // Reset saved state when new image captured
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Image Captured")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the camera button to scan a product image")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Captured Image View

    private func capturedImageView(_ image: UIImage) -> some View {
        VStack(spacing: 16) {
            // Image preview
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 400)
                .cornerRadius(12)
                .shadow(radius: 4)
                .padding()

            // Status message
            if let uuid = savedImageUUID {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Saved with ID: \(uuid.prefix(8))...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    /// Saves the captured image using ImageStorageService
    private func saveImage() async {
        guard let image = capturedImage else { return }

        isSaving = true

        // Save image using ImageStorageService
        let uuid = await ImageStorageService.shared.saveImage(image, type: .product)

        isSaving = false

        if let uuid = uuid {
            savedImageUUID = uuid
            print("✅ Image saved with UUID: \(uuid)")

            // Verify thumbnail was created
            if let thumbnail = await ImageStorageService.shared.retrieveThumbnail(uuid: uuid, type: .product) {
                print("✅ Thumbnail created: \(thumbnail.size)")
            }
        } else {
            print("❌ Failed to save image")
        }
    }
}

// MARK: - Preview

#Preview {
    ProductImageCaptureView()
}
