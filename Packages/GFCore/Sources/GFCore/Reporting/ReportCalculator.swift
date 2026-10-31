//
//  ReportCalculator.swift
//  GFCore
//
//  Moved from GFPriceChecker/ViewModels/ReportViewModel.swift, the grouping and totals
//  in PDFGeneratorService.swift and ExportView.swift, and DateRangePreset.dateRange()
//  on 2026-10-31 (#68).
//

import Foundation

/// The totals for a set of report rows
///
/// Every surface that shows a total — the dashboard, the export preview, the CSV summary,
/// the PDF cover, subtotals and grand total — reads it from here, so they cannot disagree.
public struct ReportTotals: Hashable, Sendable {

    /// Number of rows (product pairs)
    public var count: Int

    /// Number of units purchased across all rows
    public var unitCount: Int

    /// Rows verified by a receipt
    public var verifiedCount: Int

    /// Sum of `extendedDifferential`
    public var totalDifferential: Decimal

    /// Sum of `extendedNormalizedDifferential` over the rows that have one
    ///
    /// `nil` when no row has size data, not zero: PRODUCT_DEFINITION.md §3 says a missing
    /// comparison is not a zero-dollar comparison. Show it as "—".
    public var totalNormalizedDifferential: Decimal?

    /// Rows left out of `totalNormalizedDifferential` for want of size data
    public var normalizedExcludedCount: Int

    /// Units purchased across the rows that have size data
    public var normalizedUnitCount: Int

    /// Rows with no receipt
    public var unverifiedCount: Int {
        count - verifiedCount
    }

    /// The differential per unit purchased, or zero when there are no units
    ///
    /// The denominator is total units, not row count, so the figure stays "average premium
    /// per item bought" rather than shifting meaning when quantities differ.
    public var averageDifferential: Decimal {
        guard unitCount > 0 else { return .zero }
        return totalDifferential / Decimal(unitCount)
    }

    /// The size-adjusted differential per unit purchased, over the rows with size data
    ///
    /// The denominator counts only those rows' units, so the result stays comparable to
    /// `averageDifferential`. `nil` when no row has size data.
    public var averageNormalizedDifferential: Decimal? {
        guard let total = totalNormalizedDifferential, normalizedUnitCount > 0 else { return nil }
        return total / Decimal(normalizedUnitCount)
    }

    public init(rows: [ReportRow]) {
        var unitCount = 0
        var verifiedCount = 0
        var total = Decimal.zero
        var normalizedTotal: Decimal?
        var excluded = 0
        var normalizedUnits = 0

        for row in rows {
            unitCount += row.pricing.quantity
            if row.verified { verifiedCount += 1 }
            total += row.pricing.extendedDifferential
            if let nd = row.pricing.extendedNormalizedDifferential {
                normalizedTotal = (normalizedTotal ?? .zero) + nd
                normalizedUnits += row.pricing.quantity
            } else {
                excluded += 1
            }
        }

        self.count = rows.count
        self.unitCount = unitCount
        self.verifiedCount = verifiedCount
        self.totalDifferential = total
        self.totalNormalizedDifferential = normalizedTotal
        self.normalizedExcludedCount = excluded
        self.normalizedUnitCount = normalizedUnits
    }
}

/// The rows sharing a category or a month, and their totals
public struct ReportGroup<Key: Hashable & Sendable>: Hashable, Sendable {
    public var key: Key
    public var totals: ReportTotals
}

/// Filtering, totals and grouping for the reports and exports
///
/// Years and months are calendar-dependent: a purchase at 23:30 on 31 December in
/// Vancouver is already 1 January in UTC. The calendar is therefore explicit, and the
/// app passes `Calendar.current` so reports follow the device's time zone.
public struct ReportCalculator: Sendable {

    public var calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    // MARK: - Filtering

    /// The calendar year `date` falls in
    public func year(of date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    /// Whether `date` falls in the calendar year `year`
    public func isDate(_ date: Date, inYear year: Int) -> Bool {
        self.year(of: date) == year
    }

    /// The rows reported in `year`
    public func rows(_ rows: [ReportRow], inYear year: Int) -> [ReportRow] {
        rows.filter { isDate($0.reportingDate, inYear: year) }
    }

    /// The rows reported within `range`, or every row when `range` is `nil`
    public static func rows(_ rows: [ReportRow], in range: ClosedRange<Date>?) -> [ReportRow] {
        guard let range else { return rows }
        return rows.filter { range.contains($0.reportingDate) }
    }

    /// The years that have rows, newest first
    public func availableYears(_ rows: [ReportRow]) -> [Int] {
        Set(rows.map { year(of: $0.reportingDate) }).sorted(by: >)
    }

    /// The dates `preset` covers as of `now`, or `nil` for all time
    public func dateRange(for preset: DateRangePreset, now: Date) -> ClosedRange<Date>? {
        switch preset {
        case .currentYear:
            let year = year(of: now)
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
            return nil
        }
    }

    // MARK: - Totals

    /// The totals over `rows`
    public static func totals(_ rows: [ReportRow]) -> ReportTotals {
        ReportTotals(rows: rows)
    }

    // MARK: - Grouping

    /// The rows grouped by category, largest package differential first
    ///
    /// Ties are broken by category name, so the order does not depend on hashing.
    public static func byCategory(_ rows: [ReportRow]) -> [ReportGroup<String>] {
        Dictionary(grouping: rows, by: \.categoryName)
            .map { ReportGroup(key: $0.key, totals: ReportTotals(rows: $0.value)) }
            .sorted {
                if $0.totals.totalDifferential != $1.totals.totalDifferential {
                    return $0.totals.totalDifferential > $1.totals.totalDifferential
                }
                return $0.key < $1.key
            }
    }

    /// The rows grouped by the first instant of their reporting month, oldest first
    public func byMonth(_ rows: [ReportRow]) -> [ReportGroup<Date>] {
        var grouped: [Date: [ReportRow]] = [:]
        for row in rows {
            let components = calendar.dateComponents([.year, .month], from: row.reportingDate)
            guard let monthStart = calendar.date(from: components) else { continue }
            grouped[monthStart, default: []].append(row)
        }
        return grouped
            .map { ReportGroup(key: $0.key, totals: ReportTotals(rows: $0.value)) }
            .sorted { $0.key < $1.key }
    }
}
