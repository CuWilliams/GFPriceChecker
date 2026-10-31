//
//  ReportRow.swift
//  GFCore
//
//  Created by Claude Code on 2026-10-31 (#68).
//

import Foundation

/// One product pair as the reports and exports see it: a value snapshot with no
/// SwiftData behind it.
///
/// `ProductPair.reportRow` builds one of these. `ReportCalculator` and `CSVExporter`
/// work over `[ReportRow]`, so the totals, groupings and CSV can be tested without a
/// `ModelContainer`.
public struct ReportRow: Hashable, Sendable {

    /// Identifies the product pair this row was taken from
    public var id: UUID

    /// The date the pair is reported under: the receipt's purchase date when there is
    /// one, otherwise the date the pair was created
    public var reportingDate: Date

    /// Prices, sizes and quantity — every figure the arithmetic needs
    public var pricing: PricingInputs

    public var gfProductName: String
    public var gfSize: String?
    public var nonGFProductName: String
    public var nonGFSize: String?

    /// Raw value of the pair's shared `SizeUnit`, as stored
    public var sizeUnit: String?

    /// The pair's category; `nil` reports as `ReportRow.uncategorized`
    public var category: String?

    /// Whether a receipt verifies the pair
    public var verified: Bool

    /// Name of the store on the verifying receipt
    public var storeName: String?

    public var notes: String?

    /// The category every row without one is grouped and exported under
    public static let uncategorized = "Uncategorized"

    public init(
        id: UUID = UUID(),
        reportingDate: Date,
        pricing: PricingInputs,
        gfProductName: String,
        gfSize: String? = nil,
        nonGFProductName: String,
        nonGFSize: String? = nil,
        sizeUnit: String? = nil,
        category: String? = nil,
        verified: Bool = false,
        storeName: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.reportingDate = reportingDate
        self.pricing = pricing
        self.gfProductName = gfProductName
        self.gfSize = gfSize
        self.nonGFProductName = nonGFProductName
        self.nonGFSize = nonGFSize
        self.sizeUnit = sizeUnit
        self.category = category
        self.verified = verified
        self.storeName = storeName
        self.notes = notes
    }

    /// The category this row is grouped under
    public var categoryName: String {
        category ?? Self.uncategorized
    }

    /// The `SizeUnit` resolved from `sizeUnit`, or `nil` if it is missing or unknown
    public var resolvedSizeUnit: SizeUnit? {
        sizeUnit.flatMap(SizeUnit.init(rawValue:))
    }
}
