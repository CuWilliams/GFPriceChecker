//
//  ReportViewModel.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation
import GFCore

/// View model for the summary dashboard
///
/// Holds the selected tax year and hands the dashboard its rows. The totals, averages,
/// verification counts and groupings are `ReportCalculator`'s, in GFCore.
@Observable
@MainActor
final class ReportViewModel {

    // MARK: - Properties

    /// Currently selected tax year for filtering
    var selectedYear: Int

    /// Buckets years and months in the device's calendar and time zone
    let calculator: ReportCalculator

    // MARK: - Initialization

    init(selectedYear: Int? = nil, calendar: Calendar = .current) {
        self.calculator = ReportCalculator(calendar: calendar)
        self.selectedYear = selectedYear ?? calendar.component(.year, from: Date())
    }

    // MARK: - Rows

    /// The rows reported in the selected tax year
    /// - Parameter products: All products from SwiftData
    func rowsForSelectedYear(from products: [ProductPair]) -> [ReportRow] {
        calculator.rows(products.map(\.reportRow), inYear: selectedYear)
    }

    /// Returns list of years that have product data
    /// - Parameter products: All products from database
    /// - Returns: Sorted array of years (newest first)
    func availableYears(from products: [ProductPair]) -> [Int] {
        calculator.availableYears(products.map(\.reportRow))
    }
}
