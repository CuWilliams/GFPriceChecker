//
//  AppLogo.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import SwiftUI

/// App logo component for branding
///
/// Displays the GFPriceChecker logo with wheat symbol and price tag.
/// Can be rendered to UIImage for use in PDF reports.
struct AppLogo: View {
    var size: CGFloat = 100

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // Wheat symbol with slash (gluten-free indicator)
            ZStack {
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-15))

                // Slash through wheat
                Rectangle()
                    .fill(.white)
                    .frame(width: size * 0.6, height: size * 0.08)
                    .rotationEffect(.degrees(45))
            }

            // Price tag icon overlay
            Image(systemName: "tag.fill")
                .font(.system(size: size * 0.25))
                .foregroundStyle(.orange)
                .offset(x: size * 0.25, y: size * 0.25)
        }
    }
}

extension AppLogo {
    /// Renders the logo as a UIImage for use in PDFs
    /// - Parameter size: Size of the rendered image
    /// - Returns: UIImage of the logo
    @MainActor
    func asUIImage(size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        let renderer = ImageRenderer(content: self.frame(width: size.width, height: size.height))
        renderer.scale = 3.0 // High resolution for PDF
        return renderer.uiImage ?? UIImage()
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AppLogo(size: 100)
        AppLogo(size: 60)
        AppLogo(size: 40)
    }
    .padding()
}
