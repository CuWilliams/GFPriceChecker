//
//  AppLogo.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import SwiftUI

/// App logo component for branding
///
/// Displays the GFPriceChecker logo.
/// Can be rendered to UIImage for use in PDF reports.
struct AppLogo: View {
    var size: CGFloat = 100

    var body: some View {
        Image("GFPC_Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
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

#if DEBUG
// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AppLogo(size: 100)
        AppLogo(size: 60)
        AppLogo(size: 40)
    }
    .padding()
}
#endif
