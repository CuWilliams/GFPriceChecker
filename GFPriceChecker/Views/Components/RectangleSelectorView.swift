//
//  RectangleSelectorView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-01-15.
//

import SwiftUI
import UIKit

/// A view that displays detected rectangles on an image and allows tap-to-select
///
/// Useful for selecting specific rectangular regions like shelf price tags
/// before performing OCR text extraction.
struct RectangleSelectorView: View {

    // MARK: - Properties

    /// The scanned image to display
    let image: UIImage

    /// Detected rectangles to outline
    let rectangles: [DetectedRectangle]

    /// Callback when user selects a rectangle
    let onRectangleSelected: (DetectedRectangle) -> Void

    /// Callback when user chooses to skip rectangle selection
    let onSkip: () -> Void

    // MARK: - State

    @State private var selectedRectangle: DetectedRectangle?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // Instructions header
            instructionsHeader

            // Image with rectangle overlays
            GeometryReader { geometry in
                ZStack {
                    // Base image
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    // Rectangle overlays
                    ForEach(rectangles) { rectangle in
                        rectangleOverlay(
                            rectangle: rectangle,
                            imageSize: image.size,
                            containerSize: geometry.size,
                            isSelected: selectedRectangle?.id == rectangle.id
                        )
                        .onTapGesture {
                            handleRectangleTap(rectangle)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            // Rectangle count info
            Text("Tap a rectangle to select the area for OCR")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Action buttons
            actionButtons
        }
        .padding()
    }

    // MARK: - View Components

    private var instructionsHeader: some View {
        VStack(spacing: 8) {
            Text("Select Region")
                .font(.headline)
                .foregroundColor(.blue)

            Text("Found \(rectangles.count) rectangular region\(rectangles.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Skip Selection") {
                onSkip()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Skip rectangle selection")
            .accessibilityHint("Use full image for OCR instead of selecting a region")

            Button("Use Selected Region") {
                if let selected = selectedRectangle {
                    onRectangleSelected(selected)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedRectangle == nil)
            .accessibilityLabel("Use selected region")
            .accessibilityHint("Extract text only from the selected rectangular area")
        }
    }

    // MARK: - Helper Methods

    private func rectangleOverlay(
        rectangle: DetectedRectangle,
        imageSize: CGSize,
        containerSize: CGSize,
        isSelected: Bool
    ) -> some View {
        let index = (rectangles.firstIndex(where: { $0.id == rectangle.id }) ?? 0) + 1
        return RectangleOverlayShape(
            rectangle: rectangle,
            imageSize: imageSize,
            containerSize: containerSize,
            isSelected: isSelected,
            index: index
        )
    }

    private func handleRectangleTap(_ rectangle: DetectedRectangle) {
        selectedRectangle = rectangle
    }
}

// MARK: - Rectangle Overlay Shape

private struct RectangleOverlayShape: View {
    let rectangle: DetectedRectangle
    let imageSize: CGSize
    let containerSize: CGSize
    let isSelected: Bool
    let index: Int

    private var frame: CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        let displayWidth: CGFloat
        let displayHeight: CGFloat

        if imageAspect > containerAspect {
            displayWidth = containerSize.width
            displayHeight = containerSize.width / imageAspect
        } else {
            displayHeight = containerSize.height
            displayWidth = containerSize.height * imageAspect
        }

        let xOffset = (containerSize.width - displayWidth) / 2
        let yOffset = (containerSize.height - displayHeight) / 2

        let swiftUIY = 1.0 - rectangle.boundingBox.origin.y - rectangle.boundingBox.height

        let rectX = xOffset + rectangle.boundingBox.origin.x * displayWidth
        let rectY = yOffset + swiftUIY * displayHeight
        let rectW = rectangle.boundingBox.width * displayWidth
        let rectH = rectangle.boundingBox.height * displayHeight

        return CGRect(x: rectX, y: rectY, width: rectW, height: rectH)
    }

    var body: some View {
        let f = frame
        let strokeColor: Color = isSelected ? .green : .blue
        let fillColor: Color = isSelected ? Color.green.opacity(0.1) : Color.blue.opacity(0.05)
        let lineWidth: CGFloat = isSelected ? 4 : 2

        Rectangle()
            .stroke(strokeColor, lineWidth: lineWidth)
            .background(Rectangle().fill(fillColor))
            .contentShape(Rectangle())
            .frame(width: f.width, height: f.height)
            .position(x: f.midX, y: f.midY)
            .accessibilityLabel("Rectangle \(index)")
            .accessibilityHint("Tap to select this region for text extraction")
    }
}

#if DEBUG
// MARK: - Preview

#Preview {
    RectangleSelectorView(
        image: createSampleImage(),
        rectangles: createSampleRectangles(),
        onRectangleSelected: { rectangle in
            print("Selected rectangle with area: \(rectangle.area)")
        },
        onSkip: {
            print("Skipped rectangle selection")
        }
    )
}

// MARK: - Preview Helpers

private func createSampleImage() -> UIImage {
    let size = CGSize(width: 400, height: 300)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    UIColor.systemGray6.setFill()
    UIRectFill(CGRect(origin: .zero, size: size))

    // Draw some sample "text" areas
    UIColor.white.setFill()
    UIRectFill(CGRect(x: 50, y: 50, width: 300, height: 80))
    UIRectFill(CGRect(x: 50, y: 150, width: 200, height: 60))

    let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    UIGraphicsEndImageContext()
    return image
}

private func createSampleRectangles() -> [DetectedRectangle] {
    [
        DetectedRectangle(
            boundingBox: CGRect(x: 0.125, y: 0.55, width: 0.75, height: 0.27),
            confidence: 0.95
        ),
        DetectedRectangle(
            boundingBox: CGRect(x: 0.125, y: 0.2, width: 0.5, height: 0.2),
            confidence: 0.88
        )
    ]
}
#endif
