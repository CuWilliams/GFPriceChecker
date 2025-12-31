//
//  ImageViewer.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-31.
//

import SwiftUI

/// Full-screen zoomable image viewer
///
/// Provides professional image viewing experience with:
/// - Pinch-to-zoom gesture (1.0x to 4.0x)
/// - Pan/drag gesture for navigation
/// - Double-tap to reset zoom
/// - Reset button in toolbar
/// - Black background for focus
struct ImageViewer: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    /// The image to display
    let image: UIImage

    /// Title for the navigation bar
    let title: String

    // MARK: - State

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // MARK: - Initializer

    /// Creates a new image viewer
    /// - Parameters:
    ///   - image: The image to display
    ///   - title: Navigation bar title (default: "Image")
    init(image: UIImage, title: String = "Image") {
        self.image = image
        self.title = title
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale *= delta
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    // Constrain scale
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                        }
                                    } else if scale > 4.0 {
                                        withAnimation {
                                            scale = 4.0
                                        }
                                    }
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            // Double-tap to reset zoom
                            withAnimation {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Reset zoom
                        withAnimation {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    } label: {
                        Label("Reset Zoom", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    // Create sample image for preview
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600))
    let sampleImage = renderer.image { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))

        let text = "Sample Receipt" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        text.draw(at: CGPoint(x: 100, y: 280), withAttributes: attributes)
    }

    return ImageViewer(image: sampleImage, title: "Receipt Image")
}
