//
//  ReportViewModel.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation
import SwiftData

/// View model for calculating report statistics and aggregations
///
/// Provides calculation methods for the summary dashboard including:
/// - Total and average differentials
/// - Category breakdowns
/// - Monthly aggregations
/// - Verification statistics
@Observable
@MainActor
final class ReportViewModel {

    // MARK: - Properties

    /// Currently selected tax year for filtering
    var selectedYear: Int

    // MARK: - Initialization

    init(selectedYear: Int = Calendar.current.component(.year, from: Date())) {
        self.selectedYear = selectedYear
    }

    // MARK: - Date Filtering

    /// Filters products by the selected tax year
    /// - Parameter products: All products from SwiftData
    /// - Returns: Products with reporting dates in selected year
    func filterByYear(products: [ProductPair]) -> [ProductPair] {
        let calendar = Calendar.current
        return products.filter { product in
            let year = calendar.component(.year, from: product.reportingDate)
            return year == selectedYear
        }
    }

    /// Returns the date range for the selected tax year
    /// - Returns: Closed range from Jan 1 to Dec 31 of selected year
    func dateRangeForSelectedYear() -> ClosedRange<Date> {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: selectedYear, month: 1, day: 1)
        let endComponents = DateComponents(year: selectedYear, month: 12, day: 31, hour: 23, minute: 59, second: 59)

        let startDate = calendar.date(from: startComponents) ?? Date()
        let endDate = calendar.date(from: endComponents) ?? Date()

        return startDate...endDate
    }

    // MARK: - Basic Statistics

    /// Calculates the total differential for given products
    /// - Parameter products: Products to sum
    /// - Returns: Total price differential
    func calculateTotalDifferential(for products: [ProductPair]) -> Decimal {
        products.reduce(Decimal.zero) { sum, product in
            sum + product.differential
        }
    }

    /// Calculates the average differential per product
    /// - Parameter products: Products to average
    /// - Returns: Average differential, or zero if no products
    func calculateAverageDifferential(for products: [ProductPair]) -> Decimal {
        guard !products.isEmpty else { return Decimal.zero }
        let total = calculateTotalDifferential(for: products)
        return total / Decimal(products.count)
    }

    /// Counts verified vs unverified products
    /// - Parameter products: Products to analyze
    /// - Returns: Tuple with verified and unverified counts
    func verificationStats(products: [ProductPair]) -> (verified: Int, unverified: Int) {
        let verified = products.filter { $0.verified }.count
        let unverified = products.count - verified
        return (verified: verified, unverified: unverified)
    }

    // MARK: - Unit Price Differential Statistics

    /// Calculates the total size-adjusted (normalized) differential for given products
    ///
    /// Products without size data cannot be normalized and are excluded from the total.
    /// This is the primary figure for unit price differential reporting.
    /// - Parameter products: Products to sum
    /// - Returns: Tuple with total normalized differential and count of excluded products
    func calculateTotalNormalizedDifferential(for products: [ProductPair]) -> (total: Decimal, excludedCount: Int) {
        var total = Decimal.zero
        var excluded = 0
        for product in products {
            if let nd = product.normalizedDifferential {
                total += nd
            } else {
                excluded += 1
            }
        }
        return (total: total, excludedCount: excluded)
    }

    /// Calculates the average size-adjusted differential per eligible product
    /// - Parameter products: Products to average
    /// - Returns: Average normalized differential, or nil if no products have size data
    func calculateAverageNormalizedDifferential(for products: [ProductPair]) -> Decimal? {
        let eligible = products.compactMap(\.normalizedDifferential)
        guard !eligible.isEmpty else { return nil }
        return eligible.reduce(Decimal.zero, +) / Decimal(eligible.count)
    }

    // MARK: - Category Analysis

    /// Groups products by category and sums differentials
    /// - Parameter products: Products to group
    /// - Returns: Dictionary mapping category name to total differential
    func groupByCategory(products: [ProductPair]) -> [String: Decimal] {
        var categoryTotals: [String: Decimal] = [:]

        for product in products {
            let category = product.category ?? "Uncategorized"
            let currentTotal = categoryTotals[category] ?? Decimal.zero
            categoryTotals[category] = currentTotal + product.differential
        }

        return categoryTotals
    }

    /// Groups products by category and sums normalized differentials (excludes products without size data)
    /// - Parameter products: Products to group
    /// - Returns: Dictionary mapping category name to total normalized differential
    func groupByCategoryNormalized(products: [ProductPair]) -> [String: Decimal] {
        var categoryTotals: [String: Decimal] = [:]

        for product in products {
            guard let nd = product.normalizedDifferential else { continue }
            let category = product.category ?? "Uncategorized"
            categoryTotals[category, default: Decimal.zero] += nd
        }

        return categoryTotals
    }

    /// Returns top categories by total differential
    /// - Parameters:
    ///   - products: Products to analyze
    ///   - limit: Maximum number of categories to return
    /// - Returns: Array of tuples sorted by total (descending)
    func topCategories(products: [ProductPair], limit: Int = 5) -> [(category: String, total: Decimal)] {
        let categoryTotals = groupByCategory(products: products)

        let sorted = categoryTotals.map { (category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }

        return Array(sorted.prefix(limit))
    }

    // MARK: - Monthly Analysis

    /// Groups products by month and sums differentials
    /// - Parameter products: Products to group
    /// - Returns: Dictionary mapping first day of month to total differential
    func groupByMonth(products: [ProductPair]) -> [Date: Decimal] {
        var monthlyTotals: [Date: Decimal] = [:]
        let calendar = Calendar.current

        for product in products {
            // Get first day of month for this product
            let components = calendar.dateComponents([.year, .month], from: product.reportingDate)
            guard let monthStart = calendar.date(from: components) else { continue }

            let currentTotal = monthlyTotals[monthStart] ?? Decimal.zero
            monthlyTotals[monthStart] = currentTotal + product.differential
        }

        return monthlyTotals
    }

    /// Groups products by month and sums normalized differentials (excludes products without size data)
    /// - Parameter products: Products to group
    /// - Returns: Dictionary mapping first day of month to total normalized differential
    func groupByMonthNormalized(products: [ProductPair]) -> [Date: Decimal] {
        var monthlyTotals: [Date: Decimal] = [:]
        let calendar = Calendar.current

        for product in products {
            guard let nd = product.normalizedDifferential else { continue }
            let components = calendar.dateComponents([.year, .month], from: product.reportingDate)
            guard let monthStart = calendar.date(from: components) else { continue }

            monthlyTotals[monthStart, default: Decimal.zero] += nd
        }

        return monthlyTotals
    }

    /// Returns monthly data sorted chronologically
    /// - Parameter products: Products to analyze
    /// - Returns: Array of tuples with month and total, sorted by date
    func monthlySummary(products: [ProductPair]) -> [(month: Date, total: Decimal)] {
        let monthlyTotals = groupByMonth(products: products)

        return monthlyTotals.map { (month: $0.key, total: $0.value) }
            .sorted { $0.month < $1.month }
    }

    /// Returns monthly normalized differential data sorted chronologically
    /// - Parameter products: Products to analyze
    /// - Returns: Array of tuples with month and normalized total, sorted by date
    func monthlyNormalizedSummary(products: [ProductPair]) -> [(month: Date, total: Decimal)] {
        let monthlyTotals = groupByMonthNormalized(products: products)

        return monthlyTotals.map { (month: $0.key, total: $0.value) }
            .sorted { $0.month < $1.month }
    }

    // MARK: - Available Years

    /// Returns list of years that have product data
    /// - Parameter products: All products from database
    /// - Returns: Sorted array of years (newest first)
    func availableYears(from products: [ProductPair]) -> [Int] {
        let calendar = Calendar.current
        let years = Set(products.map { calendar.component(.year, from: $0.reportingDate) })
        return years.sorted(by: >)
    }
}

// MARK: - ProductPair Extension

extension ProductPair {
    /// Effective date for reporting purposes
    ///
    /// Uses receipt purchase date if available (verified products),
    /// otherwise falls back to product creation date.
    /// This ensures accurate tax year assignment.
    var reportingDate: Date {
        receipt?.purchaseDate ?? createdDate
    }
}
