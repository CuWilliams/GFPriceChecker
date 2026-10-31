//
//  ProductImageCaptureView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import GFCore
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

    /// OCR extracted data
    @State private var extractedPrices: [PriceMatch] = []
    @State private var extractedProductName: String?
    @State private var isProcessingOCR = false

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

                    // Run OCR on captured image
                    if let image = image {
                        Task {
                            await runOCR(on: image)
                        }
                    }
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
        ScrollView {
            VStack(spacing: 16) {
                // Image preview
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding()

                // OCR Results Section
                if isProcessingOCR {
                    HStack {
                        ProgressView()
                        Text("Processing OCR...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    ocrResultsView
                }

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
    }

    // MARK: - OCR Results View

    @ViewBuilder
    private var ocrResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OCR Results")
                .font(.headline)
                .padding(.horizontal)

            // Product Name
            if let productName = extractedProductName {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Product Name:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(productName)
                        .font(.body)
                        .fontWeight(.medium)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Prices
            if !extractedPrices.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected Prices:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(extractedPrices.enumerated()), id: \.offset) { index, priceMatch in
                        HStack {
                            Text(priceMatch.amount.formatted(.cad))
                                .font(.body)
                                .fontWeight(.medium)

                            Spacer()

                            Text("Confidence: \(Int(priceMatch.confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // No results message
            if extractedProductName == nil && extractedPrices.isEmpty && !isProcessingOCR {
                Text("No text or prices detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
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
        }
    }

    /// Runs OCR on the captured image to extract product name and prices
    private func runOCR(on image: UIImage) async {
        isProcessingOCR = true
        extractedPrices = []
        extractedProductName = nil

        do {
            // Extract product name
            let productName = try await OCRService.shared.findProductName(in: image)
            extractedProductName = productName

            // Extract prices
            let prices = try await OCRService.shared.findPrices(in: image)
            extractedPrices = prices
        } catch {
            ErrorHandler.shared.log(error, context: "Product OCR")
        }

        isProcessingOCR = false
    }
}

#if DEBUG
// MARK: - Preview

#Preview {
    ProductImageCaptureView()
}
#endif
