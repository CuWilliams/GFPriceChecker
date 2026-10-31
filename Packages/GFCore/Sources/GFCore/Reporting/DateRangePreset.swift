//
//  DateRangePreset.swift
//  GFCore
//
//  Moved from GFPriceChecker/Utilities/AppSettings.swift on 2026-10-31 (#68).
//

import Foundation

/// Date range preset options for exports
///
/// The raw values are persisted (`@AppStorage` and backups), so they must not change.
/// `ReportCalculator.dateRange(for:now:)` turns a preset into dates.
public enum DateRangePreset: String, CaseIterable, Codable, Sendable {
    case currentYear = "Current Year"
    case lastTwelveMonths = "Last 12 Months"
    case allTime = "All Time"
}
