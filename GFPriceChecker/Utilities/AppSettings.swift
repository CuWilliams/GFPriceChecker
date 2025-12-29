//
//  AppSettings.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation
import SwiftUI

/// Paper size options for PDF export
enum PaperSize: String, CaseIterable, Codable {
    case usLetter = "US Letter"
    case a4 = "A4"

    /// Page dimensions in points (72 points = 1 inch)
    var size: CGSize {
        switch self {
        case .usLetter:
            return CGSize(width: 612, height: 792) // 8.5" x 11"
        case .a4:
            return CGSize(width: 595, height: 842) // 210mm x 297mm
        }
    }
}

/// Date range preset options for exports
enum DateRangePreset: String, CaseIterable, Codable {
    case currentYear = "Current Year"
    case lastTwelveMonths = "Last 12 Months"
    case allTime = "All Time"

    /// Calculates the date range for this preset
    /// - Returns: Closed range of dates, or nil for all time
    func dateRange() -> ClosedRange<Date>? {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .currentYear:
            let year = calendar.component(.year, from: now)
            let startComponents = DateComponents(year: year, month: 1, day: 1)
            let endComponents = DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59)
            guard let start = calendar.date(from: startComponents),
                  let end = calendar.date(from: endComponents) else {
                return nil
            }
            return start...end

        case .lastTwelveMonths:
            guard let start = calendar.date(byAdding: .month, value: -12, to: now) else {
                return nil
            }
            return start...now

        case .allTime:
            return nil // No filtering
        }
    }
}

/// Application-wide settings and preferences
///
/// Uses @AppStorage for persistent user preferences.
/// These settings are used across export and reporting features.
@Observable
final class AppSettings {

    // MARK: - Personal Information

    /// User's full name for PDF reports
    @ObservationIgnored
    @AppStorage("userName") var userName: String = ""

    /// Default email address for accountant
    @ObservationIgnored
    @AppStorage("accountantEmail") var accountantEmail: String = ""

    // MARK: - Export Preferences

    /// Default paper size for PDF exports
    @ObservationIgnored
    @AppStorage("defaultPaperSize") private var paperSizeRaw: String = PaperSize.usLetter.rawValue

    var defaultPaperSize: PaperSize {
        get {
            PaperSize(rawValue: paperSizeRaw) ?? .usLetter
        }
        set {
            paperSizeRaw = newValue.rawValue
        }
    }

    /// Default date range for exports
    @ObservationIgnored
    @AppStorage("defaultDateRange") private var dateRangeRaw: String = DateRangePreset.currentYear.rawValue

    var defaultDateRange: DateRangePreset {
        get {
            DateRangePreset(rawValue: dateRangeRaw) ?? .currentYear
        }
        set {
            dateRangeRaw = newValue.rawValue
        }
    }

    // MARK: - Initialization

    /// Shared singleton instance
    static let shared = AppSettings()

    private init() {}
}
