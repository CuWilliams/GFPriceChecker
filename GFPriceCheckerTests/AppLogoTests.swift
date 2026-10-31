//
//  AppLogoTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-10-31.
//

import Testing
import UIKit
@testable import GFPriceChecker

/// Pins that `AppLogo` draws the GF monogram tile.
///
/// A missing asset fails quietly: `Image("…")` with no matching image set draws
/// nothing, so the launch screen, onboarding and PDF cover would lose their logo
/// with the build still green. This renders the logo the way the PDF cover does
/// and reads pixels back: brand blue inside the tile, transparent where its
/// rounded corner cuts away.
@MainActor
@Suite("App logo")
struct AppLogoTests {

    /// RGBA of one point of the rendered image, sampled at 1x.
    private func pixel(of image: UIImage, at point: CGPoint) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let cgImage = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let scale = CGFloat(cgImage.width) / image.size.width
        // CGContext's origin is bottom-left; shift so the sampled pixel lands at (0, 0).
        let x = point.x * scale
        let y = CGFloat(cgImage.height) - point.y * scale
        context.draw(cgImage, in: CGRect(x: -x, y: -y, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (bytes[0], bytes[1], bytes[2], bytes[3])
    }

    @Test("The PDF cover's 120 pt logo is the blue monogram tile with rounded corners")
    func pdfCoverLogoIsTheMonogram() throws {
        let image = AppLogo(size: 120).asUIImage(size: CGSize(width: 120, height: 120))
        #expect(image.size == CGSize(width: 120, height: 120))

        // Inside the tile, clear of the letters and the check: #0000FF.
        let tile = try pixel(of: image, at: CGPoint(x: 10, y: 60))
        #expect(tile.a == 255)
        #expect(tile.r < 20 && tile.g < 20 && tile.b > 235, "\(tile)")

        // The very corner falls outside the rounded rect.
        let corner = try pixel(of: image, at: CGPoint(x: 1, y: 1))
        #expect(corner.a == 0, "\(corner)")
    }
}
