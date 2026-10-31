//
//  RecognizedText.swift
//  GFCore
//
//  Created by Claude Code on 2026-10-31 (#69).
//

import Foundation

/// A rectangle in normalized image coordinates (0-1), standing in for `CGRect`.
///
/// The origin is bottom-left, as Vision reports it: `y = 0` is the bottom of
/// the image and `y = 1` the top.
public struct NormalizedRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { min(x, x + width) }
    public var maxX: Double { max(x, x + width) }
    public var minY: Double { min(y, y + height) }
    public var maxY: Double { max(y, y + height) }

    /// Vertical centre: higher is nearer the top of the image
    public var midY: Double { y + height / 2 }

    /// Whether the two rectangles overlap, with `CGRect.intersects` semantics:
    /// rectangles that only share an edge or a corner do not intersect.
    public func intersects(_ other: NormalizedRect) -> Bool {
        minX < other.maxX && other.minX < maxX &&
            minY < other.maxY && other.minY < maxY
    }
}

/// One line of text as OCR read it: Vision's top candidate for an observation.
///
/// `text` is the candidate's string exactly as recognised, untrimmed; the
/// functions that consume it trim where they always have.
public struct RecognizedText: Sendable, Equatable {
    public let text: String
    public let confidence: Float
    public let box: NormalizedRect

    public init(text: String, confidence: Float, box: NormalizedRect) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }
}
