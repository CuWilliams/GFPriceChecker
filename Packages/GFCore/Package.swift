// swift-tools-version: 6.0

// GFCore holds the app's platform-independent behaviour — see docs/SHARED_CORE.md.
//
// Boundary rule: Foundation only. No SwiftUI, UIKit, SwiftData, Vision, PDFKit,
// CoreGraphics or NSPredicate, so the package builds and tests on macOS with
// `swift test` and could compile for Android.

import PackageDescription

let package = Package(
    name: "GFCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "GFCore", targets: ["GFCore"])
    ],
    targets: [
        .target(name: "GFCore"),
        .testTarget(name: "GFCoreTests", dependencies: ["GFCore"])
    ]
)
