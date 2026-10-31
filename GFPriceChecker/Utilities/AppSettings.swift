//
//  AppSettings.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation
import GFCore
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

    /// Tax ID or Social Insurance Number (optional, stored securely)
    @ObservationIgnored
    @AppStorage("taxID") var taxID: String = ""

    // MARK: - Export Preferences

    /// Currency symbol preference for exports
    @ObservationIgnored
    @AppStorage("currencySymbol") var currencySymbol: String = "$ CAD"

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

    // MARK: - Onboarding

    /// Whether the user has completed the onboarding flow
    @ObservationIgnored
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false

    // MARK: - Initialization

    /// Shared singleton instance
    static let shared = AppSettings()

    private init() {}
}
