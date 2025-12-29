//
//  SummaryDashboardView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import SwiftUI
import SwiftData
import Charts

/// Summary dashboard displaying annual tax differential statistics and charts
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

    /// Total differential for selected year
    private var totalDifferential: Decimal {
        viewModel.calculateTotalDifferential(for: yearProducts)
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

            // Total Differential - Prominent Display
            VStack(spacing: 4) {
                Text("Total Annual Differential")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(totalDifferential, format: .currency(code: "CAD"))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(totalDifferential > 0 ? .green : .secondary)

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

                // Average Differential Card
                StatisticCardDecimal(
                    title: "Average",
                    value: viewModel.calculateAverageDifferential(for: yearProducts),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )

                // Verified Products Card
                let stats = viewModel.verificationStats(products: yearProducts)
                StatisticCard(
                    title: "Verified",
                    value: "\(stats.verified) of \(yearProducts.count)",
                    icon: "checkmark.seal.fill",
                    color: .green
                )

                // Unverified Products Card
                StatisticCard(
                    title: "Unverified",
                    value: "\(stats.unverified)",
                    icon: "exclamationmark.triangle.fill",
                    color: stats.unverified > 0 ? .yellow : .secondary
                )
            }
        }
    }

    // MARK: - Monthly Chart Section

    private var monthlyChartSection: some View {
        VStack(spacing: 16) {
            Text("Monthly Differential")
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
        let monthlyData = viewModel.monthlySummary(products: yearProducts)

        return Chart(monthlyData, id: \.month) { item in
            BarMark(
                x: .value("Month", item.month, unit: .month),
                y: .value("Differential", NSDecimalNumber(decimal: item.total).doubleValue)
            )
            .foregroundStyle(.blue.gradient)
            .cornerRadius(4)
        }
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
        .frame(height: 200)
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

        return Chart(topCategories, id: \.category) { item in
            BarMark(
                x: .value("Differential", NSDecimalNumber(decimal: item.total).doubleValue),
                y: .value("Category", item.category)
            )
            .foregroundStyle(.green.gradient)
            .cornerRadius(4)
        }
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
        .frame(height: max(200, CGFloat(topCategories.count) * 50))
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
