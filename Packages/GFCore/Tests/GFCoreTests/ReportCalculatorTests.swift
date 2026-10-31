//
//  ReportCalculatorTests.swift
//  GFCoreTests
//
//  Moved from GFPriceCheckerTests/QuantityReportingTests.swift and
//  SpecConformanceTests.swift on 2026-10-31 (#68).
//

import Foundation
import Testing
import GFCore

/// Guards the report totals and groupings against silent under-reporting.
///
/// A missed `extendedDifferential` compiles, ships, and simply reports a smaller number,
/// so these tests use a quantity of 3 and assert exact totals rather than "greater than
/// zero". Every aggregation the dashboard and the exports depend on is covered.
@Suite("Report calculator")
struct ReportCalculatorTests {

    // MARK: - Fixture

    /// Per unit: differential 7.99 − 3.49 = 4.50, size-adjusted (0.019975 − 0.01745) × 400
    /// = 1.01. Both exact, so totals can be compared with `==`.
    private static let perUnitNormalized = Decimal(string: "1.01")!

    /// Toronto, so year and month boundaries are not UTC's
    private static let toronto = TimeZone(identifier: "America/Toronto")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = toronto
        return calendar
    }

    private let calculator = ReportCalculator(calendar: Self.calendar)

    private func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try #require(Self.calendar.date(from: components))
    }

    private func makeRow(
        quantity: Int,
        withSizeData: Bool = true,
        category: String? = "Bread",
        verified: Bool = false,
        reportingDate: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> ReportRow {
        ReportRow(
            reportingDate: reportingDate,
            pricing: PricingInputs(
                gfPrice: Decimal(string: "7.99")!,
                nonGFPrice: Decimal(string: "3.49")!,
                gfSizeValue: withSizeData ? 400 : nil,
                nonGFSizeValue: withSizeData ? 200 : nil,
                quantity: quantity
            ),
            gfProductName: "GF Bread",
            nonGFProductName: "Regular Bread",
            sizeUnit: withSizeData ? SizeUnit.grams.rawValue : nil,
            category: category,
            verified: verified
        )
    }

    // MARK: - Totals

    @Test("Totals sum extended differentials")
    func totalsUseExtendedAmounts() {
        let totals = ReportCalculator.totals([makeRow(quantity: 3)])
        #expect(totals.totalDifferential == Decimal(string: "13.50")!)
        #expect(totals.totalNormalizedDifferential == Decimal(string: "3.03")!)
        #expect(totals.normalizedExcludedCount == 0)
    }

    @Test("Averages divide by units purchased, not by row count")
    func averagesDivideByUnitCount() {
        // Three rows, nine units, every unit carrying the same $4.50 premium. The average
        // premium per item is therefore $4.50. Dividing by row count instead would give
        // $13.50 — the discrepancy is what this test exists to catch.
        let totals = ReportCalculator.totals([
            makeRow(quantity: 3),
            makeRow(quantity: 1),
            makeRow(quantity: 5, withSizeData: false)
        ])

        #expect(totals.totalDifferential == Decimal(string: "40.50")!)
        #expect(totals.averageDifferential == Decimal(string: "4.50")!)

        // The sizeless row contributes to neither the normalized total nor its denominator,
        // so the normalized average stays $1.01 across the four eligible units.
        #expect(totals.totalNormalizedDifferential == Decimal(string: "4.04")!)
        #expect(totals.normalizedExcludedCount == 1)
        #expect(totals.averageNormalizedDifferential == Self.perUnitNormalized)
    }

    @Test("Verification counts")
    func verificationCounts() {
        let totals = ReportCalculator.totals([
            makeRow(quantity: 1, verified: true),
            makeRow(quantity: 2, verified: false),
            makeRow(quantity: 1, verified: false)
        ])
        #expect(totals.count == 3)
        #expect(totals.unitCount == 4)
        #expect(totals.verifiedCount == 1)
        #expect(totals.unverifiedCount == 2)
    }

    // MARK: - Missing Size Data

    @Test("No size data anywhere means no normalized total, not zero")
    func normalizedTotalIsNilWithoutSizeData() {
        let totals = ReportCalculator.totals([
            makeRow(quantity: 2, withSizeData: false),
            makeRow(quantity: 1, withSizeData: false)
        ])
        #expect(totals.totalNormalizedDifferential == nil)
        #expect(totals.averageNormalizedDifferential == nil)
        #expect(totals.normalizedExcludedCount == 2)
    }

    @Test("An empty list has no normalized total and a zero package total")
    func emptyTotals() {
        let totals = ReportCalculator.totals([])
        #expect(totals.totalNormalizedDifferential == nil)
        #expect(totals.normalizedExcludedCount == 0)
        #expect(totals.totalDifferential == .zero)
        #expect(totals.averageDifferential == .zero)
    }

    /// The other half of the rule: one sized row is enough for a real total, and the
    /// sizeless one is excluded rather than counted as zero.
    @Test("A partly sized list totals only the sized rows")
    func normalizedTotalCountsSizedRowsOnly() {
        let totals = ReportCalculator.totals([
            makeRow(quantity: 2),
            makeRow(quantity: 1, withSizeData: false)
        ])
        #expect(totals.totalNormalizedDifferential == Decimal(string: "2.02")!)
        #expect(totals.normalizedExcludedCount == 1)
    }

    // MARK: - Grouping

    @Test("Category grouping reflects quantity, largest first")
    func categoryGroupingUsesExtendedAmounts() {
        let groups = ReportCalculator.byCategory([
            makeRow(quantity: 1, category: "Pasta"),
            makeRow(quantity: 3, category: "Bread"),
            makeRow(quantity: 2, withSizeData: false, category: nil)
        ])

        #expect(groups.map(\.key) == ["Bread", "Uncategorized", "Pasta"])
        #expect(groups[0].totals.totalDifferential == Decimal(string: "13.50")!)
        #expect(groups[0].totals.totalNormalizedDifferential == Decimal(string: "3.03")!)
        #expect(groups[1].totals.totalDifferential == Decimal(string: "9.00")!)
        #expect(groups[1].totals.totalNormalizedDifferential == nil)
        #expect(groups[2].totals.totalDifferential == Decimal(string: "4.50")!)
        #expect(groups[2].totals.totalNormalizedDifferential == Self.perUnitNormalized)
    }

    @Test("Categories with equal totals are ordered by name")
    func categoryTiesAreOrderedByName() {
        let groups = ReportCalculator.byCategory([
            makeRow(quantity: 1, category: "Pasta"),
            makeRow(quantity: 1, category: "Crackers"),
            makeRow(quantity: 1, category: "Bread")
        ])
        #expect(groups.map(\.key) == ["Bread", "Crackers", "Pasta"])
    }

    @Test("Monthly grouping reflects quantity, oldest first")
    func monthlyGroupingUsesExtendedAmounts() throws {
        let march = try date(year: 2025, month: 3, day: 10)
        let april = try date(year: 2025, month: 4, day: 2)

        let groups = calculator.byMonth([
            makeRow(quantity: 1, reportingDate: april),
            makeRow(quantity: 3, reportingDate: march)
        ])

        #expect(groups.map(\.key) == [try date(year: 2025, month: 3, day: 1, hour: 0),
                                      try date(year: 2025, month: 4, day: 1, hour: 0)])
        #expect(groups[0].totals.totalDifferential == Decimal(string: "13.50")!)
        #expect(groups[0].totals.totalNormalizedDifferential == Decimal(string: "3.03")!)
        #expect(groups[1].totals.totalDifferential == Decimal(string: "4.50")!)
        #expect(groups[1].totals.totalNormalizedDifferential == Self.perUnitNormalized)
    }

    // MARK: - Calendar

    /// 23:30 on 31 December in Toronto is 04:30 on 1 January in UTC. The year, the month
    /// and the filter must all follow the calendar the calculator was given.
    @Test("Years and months follow the calculator's calendar, not UTC")
    func bucketsFollowTheGivenCalendar() throws {
        let newYearsEve = try date(year: 2025, month: 12, day: 31, hour: 23, minute: 30)
        let row = makeRow(quantity: 1, reportingDate: newYearsEve)

        #expect(calculator.year(of: newYearsEve) == 2025)
        #expect(calculator.rows([row], inYear: 2025).count == 1)
        #expect(calculator.rows([row], inYear: 2026).isEmpty)
        #expect(calculator.byMonth([row]).map(\.key) == [try date(year: 2025, month: 12, day: 1, hour: 0)])

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(ReportCalculator(calendar: utc).year(of: newYearsEve) == 2026)
    }

    @Test("Available years are distinct, newest first")
    func availableYearsNewestFirst() throws {
        let rows = [
            makeRow(quantity: 1, reportingDate: try date(year: 2024, month: 6, day: 1)),
            makeRow(quantity: 1, reportingDate: try date(year: 2026, month: 1, day: 1)),
            makeRow(quantity: 1, reportingDate: try date(year: 2024, month: 2, day: 1))
        ]
        #expect(calculator.availableYears(rows) == [2026, 2024])
    }

    @Test("A date range filter is inclusive, and nil keeps every row")
    func dateRangeFilter() throws {
        let start = try date(year: 2025, month: 1, day: 1, hour: 0)
        let end = try date(year: 2025, month: 6, day: 30)
        let rows = [
            makeRow(quantity: 1, reportingDate: start),
            makeRow(quantity: 1, reportingDate: end),
            makeRow(quantity: 1, reportingDate: end.addingTimeInterval(1))
        ]
        #expect(ReportCalculator.rows(rows, in: start...end).count == 2)
        #expect(ReportCalculator.rows(rows, in: nil).count == 3)
    }

    // MARK: - Date Range Presets

    @Test("Current Year runs from 1 January to the last second of 31 December")
    func currentYearPreset() throws {
        let now = try date(year: 2025, month: 7, day: 15)
        let range = try #require(calculator.dateRange(for: .currentYear, now: now))
        #expect(range.lowerBound == (try date(year: 2025, month: 1, day: 1, hour: 0)))
        #expect(range.upperBound == (try date(year: 2025, month: 12, day: 31, hour: 23, minute: 59))
            .addingTimeInterval(59))
    }

    @Test("Last 12 Months ends now")
    func lastTwelveMonthsPreset() throws {
        let now = try date(year: 2025, month: 7, day: 15)
        let range = try #require(calculator.dateRange(for: .lastTwelveMonths, now: now))
        #expect(range.lowerBound == (try date(year: 2024, month: 7, day: 15)))
        #expect(range.upperBound == now)
    }

    @Test("All Time has no range")
    func allTimePreset() {
        #expect(calculator.dateRange(for: .allTime, now: Date()) == nil)
    }

    /// The raw values are persisted in `@AppStorage` and in backups.
    @Test("Preset raw values are stable")
    func presetRawValues() {
        #expect(DateRangePreset.allCases.map(\.rawValue) == ["Current Year", "Last 12 Months", "All Time"])
    }
}
