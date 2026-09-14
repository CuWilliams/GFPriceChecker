//
//  ScannerImageProvider.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-09-13.
//

#if DEBUG
import UIKit

/// The programmatic half of the no-camera seam: images handed to the next
/// scanner presentation instead of a tap.
///
/// `SubstituteScannerView` normally asks the developer to pick an image. When
/// this queue holds anything, it takes the head of the queue and returns it
/// without drawing UI at all, which is what lets a capture flow be driven
/// end to end with no human in it.
///
/// This is the injection point Stage 5 of `docs/SCRIPTED_DEMO_PIPELINE.md`
/// plugs the demo director into. Nothing in the app enqueues today; the tests
/// and any future script do.
///
/// DEBUG only, and `@MainActor` because the scanner drains it during a view
/// update.
@MainActor
enum ScannerImageProvider {

    private static var pending: [UIImage] = []

    /// Whether the next scanner presentation will supply an image on its own.
    static var hasPendingImages: Bool { !pending.isEmpty }

    /// Queues `images` to be returned by the next scanner presentations, in order.
    static func enqueue(_ images: UIImage...) {
        pending.append(contentsOf: images)
    }

    /// Takes the next queued image, if any.
    static func takeNext() -> UIImage? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    /// Drops anything still queued. Call between tests — the queue is process-wide.
    static func reset() {
        pending.removeAll()
    }
}
#endif
