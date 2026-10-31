//
//  SummaryDashboardView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import SwiftUI
import GFCore
import SwiftData
import Charts

/// Summary dashboard displaying annual price differential statistics and charts
///
/// Provides a professional overview suitable for accountant review:
/// - Total annual differential (prominent)
/// - Tax year selector
/// - Statistics cards (products, verified status, average)
/// - Monthly spending chart
/// - Category breakdown chart
struct SummaryDashboardView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext

    // MARK: - Query

    /// All product pairs from database
    @Query(sort: \ProductPair.createdDate, order: .reverse)
    private var allProducts: [ProductPair]

    // MARK: - State

    /// Holds which toolbar sheet is up
    @Environment(AppRouter.self) private var router

    @State private var viewModel = ReportViewModel()

    // MARK: - Computed Properties

    /// Products reported in the selected year
    private var yearRows: [ReportRow] {
        viewModel.rowsForSelectedYear(from: allProducts)
    }

    /// Totals, averages and verification counts for the selected year
    private var totals: ReportTotals {
        ReportCalculator.totals(yearRows)
    }

    /// Text for an amount that may not exist: "—" for `nil`, never $0.00
    ///
    /// PRODUCT_DEFINITION.md §3: a missing comparison is not a zero-dollar comparison.
    static func displayAmount(_ value: Decimal?) -> String {
        value?.formatted(.cad) ?? "—"
    }

    /// Available years that have data
    private var availableYears: [Int] {
        viewModel.availableYears(from: allProducts)
    }

    // MARK: - Body

    var body: some View {
        @Bindable var router = router

        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    headerSection

                    // Statistics Cards
                    statisticsSection

                    // Monthly Chart
                    monthlyChartSection

                    // Category Chart
                    categoryChartSection
                }
                .padding()
            }
            .navigationTitle("Tax Summary")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.reportsSheet = .export
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        router.reportsSheet = .settings
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .sheet(item: $router.reportsSheet) { sheet in
                switch sheet {
                case .export:
                    ExportView()
                case .settings:
                    SettingsView()
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Year Selector
            Picker("Tax Year", selection: $viewModel.selectedYear) {
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.segmented)
            .disabled(availableYears.isEmpty)
            .accessibilityLabel("Tax year selector")

            // Dual Totals Display
            VStack(spacing: 8) {
                // Primary: Size-Adjusted Differential Total
                VStack(spacing: 2) {
                    Text("Size-Adjusted Differential Total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Size-adjusted differential total")

                    // No size data anywhere means no value, not $0.00
                    if let normalizedTotal = totals.totalNormalizedDifferential {
                        Text(normalizedTotal, format: .cad)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(normalizedTotal > 0 ? .green : .secondary)
                            .accessibilityLabel("Size-adjusted differential total: \(normalizedTotal.formatted(.cad))")
                            .accessibilityHint("Total adjusted for package size differences")
                    } else {
                        Text("—")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Size-adjusted differential total: not available")
                            .accessibilityHint("No products have size data to compare")
                    }
                }

                Divider()
                    .padding(.horizontal, 32)

                // Secondary: Simple Price Differential
                VStack(spacing: 2) {
                    Text("Package Price Differential (For Reference)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(totals.totalDifferential, format: .cad)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(totals.totalDifferential > 0 ? .blue : .secondary)
                        .accessibilityLabel("Price differential for reference: \(totals.totalDifferential.formatted(.cad))")
                }

                // Excluded products note
                if totals.normalizedExcludedCount > 0 {
                    Text("\(totals.normalizedExcludedCount) product\(totals.normalizedExcludedCount == 1 ? "" : "s") without size data excluded from adjusted total")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("\(totals.normalizedExcludedCount) products without size data are excluded from the adjusted total")
                }

                // `String(...)`, not the bare Int: a literal passed to `Text` is a
                // `LocalizedStringKey`, and interpolating an `Int` into one formats it with
                // the locale's grouping separator — so the year rendered as "2,026".
                Text(yearRows.isEmpty ? "No products for \(String(viewModel.selectedYear))" : "\(yearRows.count) product\(yearRows.count == 1 ? "" : "s") tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        VStack(spacing: 16) {
            Text("Statistics")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                // Total Products Card
                StatisticCard(
                    title: "Products",
                    value: "\(yearRows.count)",
                    icon: "basket.fill",
                    color: .blue
                )
                .accessibilityLabel("Products: \(yearRows.count)")

                // Average Size-Adjusted Differential Card (primary)
                let avgNormalized = totals.averageNormalizedDifferential
                StatisticCardDecimal(
                    title: "Avg. Size-Adj. Diff",
                    value: avgNormalized,
                    icon: "ruler",
                    color: .green
                )
                .accessibilityLabel("Average size-adjusted differential: \(avgNormalized.map { $0.formatted(.cad) } ?? "not available")")
                .accessibilityHint(avgNormalized == nil
                    ? "No products have size data to compare"
                    : "Average size-adjusted differential per item purchased")

                // Average Price Differential Card
                StatisticCardDecimal(
                    title: "Avg. Price Diff",
                    value: totals.averageDifferential,
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )
                .accessibilityLabel("Average price differential: \(totals.averageDifferential.formatted(.cad))")
                .accessibilityHint("Average price differential per unit purchased")

                // Verified Products Card
                StatisticCard(
                    title: "Verified",
                    value: "\(totals.verifiedCount) of \(yearRows.count)",
                    icon: "checkmark.seal.fill",
                    color: .green
                )
                .accessibilityLabel("Verified: \(totals.verifiedCount) of \(yearRows.count) products")

                // Unverified Products Card
                StatisticCard(
                    title: "Unverified",
                    value: "\(totals.unverifiedCount)",
                    icon: "exclamationmark.triangle.fill",
                    color: totals.unverifiedCount > 0 ? .yellow : .secondary
                )
                .accessibilityLabel("Unverified: \(totals.unverifiedCount) products")
            }
        }
    }

    // MARK: - Monthly Chart Section

    private var monthlyChartSection: some View {
        VStack(spacing: 16) {
            Text("Monthly Price Differentials")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if yearRows.isEmpty {
                emptyChartPlaceholder(message: "No monthly data for \(viewModel.selectedYear)")
            } else {
                monthlyChart
            }
        }
    }

    private var monthlyChart: some View {
        let months = viewModel.calculator.byMonth(yearRows)

        // Build flat array for dual-series chart. A month with no size data has no
        // size-adjusted bar rather than a $0 one.
        var chartItems: [MonthlyChartItem] = []
        for month in months {
            chartItems.append(MonthlyChartItem(month: month.key, amount: month.totals.totalDifferential, series: "Package Price Diff"))
        }
        for month in months {
            if let normTotal = month.totals.totalNormalizedDifferential {
                chartItems.append(MonthlyChartItem(month: month.key, amount: normTotal, series: "Size-Adjusted Diff"))
            }
        }

        return Chart(chartItems) { item in
            BarMark(
                x: .value("Month", item.month, unit: .month),
                y: .value("Amount", NSDecimalNumber(decimal: item.amount).doubleValue)
            )
            .foregroundStyle(by: .value("Series", item.series))
            .position(by: .value("Series", item.series))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale([
            "Size-Adjusted Diff": Color.green,
            "Package Price Diff": Color.blue
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.month(.abbreviated))
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Decimal(number), format: .cad.precision(.fractionLength(0)))
                    }
                }
                AxisGridLine()
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .accessibilityLabel("Monthly differential chart showing both size-adjusted and price differential by month")
        .frame(height: 220)
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Category Chart Section

    private var categoryChartSection: some View {
        VStack(spacing: 16) {
            Text("Top Categories")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if yearRows.isEmpty {
                emptyChartPlaceholder(message: "No category data for \(viewModel.selectedYear)")
            } else {
                categoryChart
            }
        }
    }

    private var categoryChart: some View {
        let topCategories = ReportCalculator.byCategory(yearRows).prefix(5)

        // Build flat array for dual-series chart (top 5 categories by price differential)
        var chartItems: [CategoryChartItem] = []
        for item in topCategories {
            chartItems.append(CategoryChartItem(category: item.key, amount: item.totals.totalDifferential, series: "Package Price Diff"))
            if let normTotal = item.totals.totalNormalizedDifferential {
                chartItems.append(CategoryChartItem(category: item.key, amount: normTotal, series: "Size-Adjusted Diff"))
            }
        }

        return Chart(chartItems) { item in
            BarMark(
                x: .value("Amount", NSDecimalNumber(decimal: item.amount).doubleValue),
                y: .value("Category", item.category)
            )
            .foregroundStyle(by: .value("Series", item.series))
            .position(by: .value("Series", item.series))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale([
            "Size-Adjusted Diff": Color.green,
            "Package Price Diff": Color.blue
        ])
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Decimal(number), format: .cad.precision(.fractionLength(0)))
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel()
                AxisGridLine()
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .accessibilityLabel("Category breakdown chart showing both size-adjusted and price differential per category")
        .frame(height: max(220, CGFloat(topCategories.count) * 60))
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Empty State

    private func emptyChartPlaceholder(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

// MARK: - Chart Data Models

/// Data point for dual-series monthly chart
private struct MonthlyChartItem: Identifiable {
    let id = UUID()
    let month: Date
    let amount: Decimal
    let series: String
}

/// Data point for dual-series category chart
private struct CategoryChartItem: Identifiable {
    let id = UUID()
    let category: String
    let amount: Decimal
    let series: String
}

// MARK: - Statistic Card Component

/// Reusable card for displaying a single statistic
private struct StatisticCard<Value: CVarArg>: View {
    let title: String
    let value: Value
    let format: (any FormatStyle<Value, String>)?
    let icon: String
    let color: Color

    init(
        title: String,
        value: Value,
        format: (any FormatStyle<Value, String>)? = nil,
        icon: String,
        color: Color
    ) {
        self.title = title
        self.value = value
        self.format = format
        self.icon = icon
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let format = format as? any FormatStyle<Decimal, String>,
               let decimalValue = value as? Decimal {
                Text(decimalValue, format: format)
                    .font(.title3)
                    .fontWeight(.semibold)
            } else if let decimalValue = value as? Decimal {
                Text(decimalValue.formatted(.number))
                    .font(.title3)
                    .fontWeight(.semibold)
            } else {
                Text(String(describing: value))
                    .font(.title3)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// Overload for String values
extension StatisticCard where Value == String {
    init(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) {
        self.title = title
        self.value = value
        self.format = nil
        self.icon = icon
        self.color = color
    }
}

/// Specialized statistic card for Decimal values (currency)
private struct StatisticCardDecimal: View {
    let title: String
    let value: Decimal?
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(SummaryDashboardView.displayAmount(value))
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

#if DEBUG
// MARK: - Preview

#Preview("With Data") {
    let container = try! ModelContainer(
        for: ProductPair.self, Receipt.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    // Create sample data
    let context = container.mainContext

    // Create products across multiple months
    let calendar = Calendar.current
    for month in 1...12 {
        let date = calendar.date(from: DateComponents(year: 2024, month: month, day: 15)) ?? Date()

        let product = ProductPair(
            gfProductName: "Product \(month)",
            gfPrice: Decimal(arc4random_uniform(10)) + 5,
            nonGFProductName: "Regular \(month)",
            nonGFPrice: Decimal(arc4random_uniform(5)) + 2,
            createdDate: date,
            category: ["Bread", "Pasta", "Flour", "Crackers", "Cookies"].randomElement(),
            verified: Bool.random()
        )
        context.insert(product)
    }

    return SummaryDashboardView()
        .environment(AppRouter())
        .modelContainer(container)
}

#Preview("Empty State") {
    SummaryDashboardView()
        .environment(AppRouter())
        .modelContainer(for: [ProductPair.self, Receipt.self], inMemory: true)
}
#endif
