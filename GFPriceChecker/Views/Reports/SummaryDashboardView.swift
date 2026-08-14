//
//  SummaryDashboardView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import SwiftUI
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

    @State private var viewModel = ReportViewModel()
    @State private var showingSettings = false
    @State private var showingExport = false

    // MARK: - Computed Properties

    /// Products filtered by selected year
    private var yearProducts: [ProductPair] {
        viewModel.filterByYear(products: allProducts)
    }

    /// Total price differential for selected year
    private var totalDifferential: Decimal {
        viewModel.calculateTotalDifferential(for: yearProducts)
    }

    /// Total normalized (size-adjusted) differential and excluded count for selected year
    private var normalizedResult: (total: Decimal, excludedCount: Int) {
        viewModel.calculateTotalNormalizedDifferential(for: yearProducts)
    }

    /// Available years that have data
    private var availableYears: [Int] {
        viewModel.availableYears(from: allProducts)
    }

    // MARK: - Body

    var body: some View {
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
                        showingExport = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingExport) {
                ExportView()
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
                // Primary: Unit Price Differential Total
                VStack(spacing: 2) {
                    Text("Unit Price Differential Total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Unit price differential total")

                    Text(normalizedResult.total, format: .currency(code: "CAD"))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(normalizedResult.total > 0 ? .green : .secondary)
                        .accessibilityLabel("Unit price differential total: \(normalizedResult.total.formatted(.currency(code: "CAD")))")
                        .accessibilityHint("Total adjusted for package size differences")
                }

                Divider()
                    .padding(.horizontal, 32)

                // Secondary: Simple Price Differential
                VStack(spacing: 2) {
                    Text("Package Price Differential (For Reference)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(totalDifferential, format: .currency(code: "CAD"))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(totalDifferential > 0 ? .blue : .secondary)
                        .accessibilityLabel("Price differential for reference: \(totalDifferential.formatted(.currency(code: "CAD")))")
                }

                // Excluded products note
                if normalizedResult.excludedCount > 0 {
                    Text("\(normalizedResult.excludedCount) product\(normalizedResult.excludedCount == 1 ? "" : "s") without size data excluded from adjusted total")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("\(normalizedResult.excludedCount) products without size data are excluded from the adjusted total")
                }

                Text(yearProducts.isEmpty ? "No products for \(viewModel.selectedYear)" : "\(yearProducts.count) product\(yearProducts.count == 1 ? "" : "s") tracked")
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
                    value: "\(yearProducts.count)",
                    icon: "basket.fill",
                    color: .blue
                )
                .accessibilityLabel("Products: \(yearProducts.count)")

                // Average Unit Price Differential Card (primary)
                let avgNormalized = viewModel.calculateAverageNormalizedDifferential(for: yearProducts)
                StatisticCardDecimal(
                    title: "Avg. Unit Price Diff",
                    value: avgNormalized ?? Decimal.zero,
                    icon: "ruler",
                    color: .green
                )
                .accessibilityLabel("Average unit price differential: \((avgNormalized ?? Decimal.zero).formatted(.currency(code: "CAD")))")
                .accessibilityHint("Average unit price differential per unit purchased")

                // Average Price Differential Card
                StatisticCardDecimal(
                    title: "Avg. Price Diff",
                    value: viewModel.calculateAverageDifferential(for: yearProducts),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )
                .accessibilityLabel("Average price differential: \(viewModel.calculateAverageDifferential(for: yearProducts).formatted(.currency(code: "CAD")))")
                .accessibilityHint("Average price differential per unit purchased")

                // Verified Products Card
                let stats = viewModel.verificationStats(products: yearProducts)
                StatisticCard(
                    title: "Verified",
                    value: "\(stats.verified) of \(yearProducts.count)",
                    icon: "checkmark.seal.fill",
                    color: .green
                )
                .accessibilityLabel("Verified: \(stats.verified) of \(yearProducts.count) products")

                // Unverified Products Card
                StatisticCard(
                    title: "Unverified",
                    value: "\(stats.unverified)",
                    icon: "exclamationmark.triangle.fill",
                    color: stats.unverified > 0 ? .yellow : .secondary
                )
                .accessibilityLabel("Unverified: \(stats.unverified) products")
            }
        }
    }

    // MARK: - Monthly Chart Section

    private var monthlyChartSection: some View {
        VStack(spacing: 16) {
            Text("Monthly Price Differentials")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if yearProducts.isEmpty {
                emptyChartPlaceholder(message: "No monthly data for \(viewModel.selectedYear)")
            } else {
                monthlyChart
            }
        }
    }

    private var monthlyChart: some View {
        let priceSummary = viewModel.monthlySummary(products: yearProducts)
        let normalizedSummary = viewModel.monthlyNormalizedSummary(products: yearProducts)

        // Build flat array for dual-series chart
        var chartItems: [MonthlyChartItem] = []
        for item in priceSummary {
            chartItems.append(MonthlyChartItem(month: item.month, amount: item.total, series: "Package Price Diff"))
        }
        for item in normalizedSummary {
            chartItems.append(MonthlyChartItem(month: item.month, amount: item.total, series: "Unit Price Diff"))
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
            "Unit Price Diff": Color.green,
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
                        Text(Decimal(number), format: .currency(code: "CAD").precision(.fractionLength(0)))
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

            if yearProducts.isEmpty {
                emptyChartPlaceholder(message: "No category data for \(viewModel.selectedYear)")
            } else {
                categoryChart
            }
        }
    }

    private var categoryChart: some View {
        let topCategories = viewModel.topCategories(products: yearProducts, limit: 5)
        let normalizedByCategory = viewModel.groupByCategoryNormalized(products: yearProducts)

        // Build flat array for dual-series chart (top 5 categories by price differential)
        var chartItems: [CategoryChartItem] = []
        for item in topCategories {
            chartItems.append(CategoryChartItem(category: item.category, amount: item.total, series: "Package Price Diff"))
            if let normTotal = normalizedByCategory[item.category] {
                chartItems.append(CategoryChartItem(category: item.category, amount: normTotal, series: "Unit Price Diff"))
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
            "Unit Price Diff": Color.green,
            "Package Price Diff": Color.blue
        ])
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Decimal(number), format: .currency(code: "CAD").precision(.fractionLength(0)))
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
    let value: Decimal
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

            Text(value, format: .currency(code: "CAD"))
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
        .modelContainer(container)
}

#Preview("Empty State") {
    SummaryDashboardView()
        .modelContainer(for: [ProductPair.self, Receipt.self], inMemory: true)
}
#endif
