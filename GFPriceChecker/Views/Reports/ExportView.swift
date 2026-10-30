//
//  ExportView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Export format options
enum ExportFormat: String, CaseIterable {
    case csv = "CSV"
    case pdf = "PDF"
}

/// Export view for generating and sharing CSV/PDF reports
///
/// Provides export functionality with:
/// - Date range filtering
/// - Preview of export data
/// - Three export methods: Save to Files, Share, Email
struct ExportView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Query

    /// All product pairs from database
    @Query(sort: \ProductPair.createdDate, order: .reverse)
    private var allProducts: [ProductPair]

    /// All receipts from database
    @Query(sort: \Receipt.purchaseDate, order: .reverse)
    private var allReceipts: [Receipt]

    // MARK: - State

    @State private var exportFormat: ExportFormat = .csv
    @State private var selectedPreset: DateRangePreset = AppSettings.shared.defaultDateRange
    @State private var customStartDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var useCustomRange = false

    // PDF-specific state
    @State private var pdfYear = Calendar.current.component(.year, from: Date())
    @State private var paperSize: PaperSize = AppSettings.shared.defaultPaperSize

    @State private var isGenerating = false
    @State private var generatedCSVURL: URL?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Unverified products warning
    @State private var showingUnverifiedWarning = false
    @State private var unverifiedProductCount = 0
    @State private var pendingExportAction: ExportAction?
    @State private var userConfirmedExport = false

    // Document picker state
    @State private var showingDocumentPicker = false

    // Share sheet state
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []

    // Export action type for warning flow
    private enum ExportAction {
        case saveToFiles
        case share
        case email
    }

    // MARK: - Computed Properties

    /// Current date range based on preset or custom selection
    private var currentDateRange: ClosedRange<Date>? {
        if useCustomRange {
            return customStartDate...customEndDate
        } else {
            return selectedPreset.dateRange()
        }
    }

    /// Products filtered by current date range
    private var filteredProducts: [ProductPair] {
        guard let range = currentDateRange else { return allProducts }

        return allProducts.filter { product in
            range.contains(product.reportingDate)
        }
    }

    /// Preview of first 10 products
    private var previewProducts: [ProductPair] {
        Array(filteredProducts.sorted { $0.reportingDate < $1.reportingDate }.prefix(10))
    }

    /// Export summary statistics
    private var exportSummary: (count: Int, normalizedDifferential: Decimal?, packagePriceDifferential: Decimal) {
        let productsToExport: [ProductPair]

        switch exportFormat {
        case .csv:
            productsToExport = filteredProducts
        case .pdf:
            let calendar = Calendar.current
            productsToExport = allProducts.filter { product in
                calendar.component(.year, from: product.reportingDate) == pdfYear
            }
        }

        let packageTotal = productsToExport.reduce(Decimal.zero) { $0 + $1.extendedDifferential }
        let normalizedTotal = ReportViewModel.calculateTotalNormalizedDifferential(for: productsToExport).total
        return (count: productsToExport.count, normalizedDifferential: normalizedTotal, packagePriceDifferential: packageTotal)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Format Selection
                    formatSection

                    // PDF-specific options
                    if exportFormat == .pdf {
                        pdfOptionsSection
                    }

                    // Date Range Section (CSV only)
                    if exportFormat == .csv {
                        dateRangeSection
                    }

                    // Export Summary
                    summarySection

                    // Preview Section (CSV only)
                    if exportFormat == .csv {
                        previewSection
                    }

                    // Export Actions
                    exportActionsSection
                }
                .padding()
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Export Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .alert("Unverified Products Found", isPresented: $showingUnverifiedWarning) {
                Button("Continue Export", role: .none) {
                    // User confirmed - set flag to trigger export via .onChange()
                    userConfirmedExport = true
                }
                Button("Cancel", role: .cancel) {
                    pendingExportAction = nil
                    userConfirmedExport = false
                }
            } message: {
                Text("\(unverifiedProductCount) product(s) lack receipt verification. These will appear in a separate \"Unverified Products\" section. For complete tax documentation, consider obtaining receipts for all products.")
            }
            .onChange(of: userConfirmedExport) { oldValue, newValue in
                // When user confirms the warning, perform the pending export
                if newValue == true, let action = pendingExportAction {
                    userConfirmedExport = false // Reset flag
                    pendingExportAction = nil

                    // Perform export after alert dismisses
                    Task {
                        // Small delay to ensure alert is fully dismissed before presenting share sheet
                        try? await Task.sleep(for: .milliseconds(300))

                        switch action {
                        case .saveToFiles:
                            await performSaveToFiles()
                        case .share:
                            await performShare()
                        case .email:
                            await performEmail()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if !shareItems.isEmpty {
                    ShareSheet(items: shareItems)
                }
            }
        }
    }

    // MARK: - Format Section

    private var formatSection: some View {
        VStack(spacing: 16) {
            Text("Export Format")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Format", selection: $exportFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - PDF Options Section

    private var pdfOptionsSection: some View {
        VStack(spacing: 16) {
            Text("PDF Options")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                // Year Picker
                Picker("Tax Year", selection: $pdfYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)

                // Paper Size Picker
                Picker("Paper Size", selection: $paperSize) {
                    ForEach(PaperSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    /// Available years from product data
    private var availableYears: [Int] {
        let calendar = Calendar.current
        let years = Set(allProducts.map { calendar.component(.year, from: $0.reportingDate) })
        return years.sorted(by: >)
    }

    // MARK: - Date Range Section

    private var dateRangeSection: some View {
        VStack(spacing: 16) {
            Text("Date Range")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                // Preset or Custom Toggle
                Picker("Range Type", selection: $useCustomRange) {
                    Text("Preset").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)

                if useCustomRange {
                    // Custom date pickers
                    DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                } else {
                    // Preset picker
                    Picker("Date Range", selection: $selectedPreset) {
                        ForEach(DateRangePreset.allCases, id: \.self) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(spacing: 16) {
            Text("Export Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                // Product Count
                VStack(spacing: 4) {
                    Text("\(exportSummary.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text("Products")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 40)

                // Primary: Size-Adjusted Differential Total
                VStack(spacing: 4) {
                    if let normalizedTotal = exportSummary.normalizedDifferential {
                        Text(normalizedTotal, format: .currency(code: "CAD"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    } else {
                        Text("—")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                    Text("Size-Adjusted Differential")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 40)

                // Secondary: Package Price Differential Total
                VStack(spacing: 4) {
                    Text(exportSummary.packagePriceDifferential, format: .currency(code: "CAD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    Text("Package Price Diff")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Text("First \(min(10, previewProducts.count)) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if previewProducts.isEmpty {
                emptyPreviewPlaceholder
            } else {
                csvPreview
            }
        }
    }

    private var emptyPreviewPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No products in selected date range")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    /// - Note: Deliberately unbounded in height. A `.frame(maxHeight: 200)` used to cap this,
    ///   but the box only scrolls horizontally, so the eleven rows it holds overflowed a
    ///   200pt window with no way to reach what spilled: the header was sliced through the
    ///   middle at the top edge and "... and N more rows" at the bottom. `previewProducts`
    ///   already bounds the content at ten rows, and the enclosing `ScrollView` scrolls, so
    ///   the cap bought nothing and cost the two lines that frame what the rows mean. Height
    ///   has to stay free for Dynamic Type as well — any fixed cap re-clips at larger sizes.
    private var csvPreview: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 4) {
                // Header
                Text("Date,Qty,GF Product,GF Price,Non-GF Product,Non-GF Price,Differential,Ext. Differential,Category,Store,Verified")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                Divider()

                // Rows
                ForEach(previewProducts, id: \.id) { product in
                    csvPreviewRow(for: product)
                }

                if filteredProducts.count > 10 {
                    Text("... and \(filteredProducts.count - 10) more rows")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func csvPreviewRow(for product: ProductPair) -> some View {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let row = [
            dateFormatter.string(from: product.reportingDate),
            String(product.quantity),
            product.gfProductName,
            String(describing: product.gfPrice),
            product.nonGFProductName,
            String(describing: product.nonGFPrice),
            String(describing: product.differential),
            String(describing: product.extendedDifferential),
            product.category ?? "Uncategorized",
            product.receipt?.storeName ?? "",
            product.verified ? "Yes" : "No"
        ].joined(separator: ",")

        return Text(row)
            .font(.system(.caption2, design: .monospaced))
            .lineLimit(1)
    }

    // MARK: - Export Actions Section

    private var exportActionsSection: some View {
        VStack(spacing: 16) {
            Text("Export Options")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                // Save to Files Button
                Button {
                    Task {
                        await generateAndSaveToFiles()
                    }
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text("Save to Files")
                        Spacer()
                        if isGenerating {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isGenerating || exportSummary.count == 0)

                // Share Button
                Button {
                    Task {
                        await generateAndShare()
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                        Spacer()
                        if isGenerating {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isGenerating || exportSummary.count == 0)

                // Email Button
                Button {
                    Task {
                        await generateAndEmail()
                    }
                } label: {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Email")
                        Spacer()
                        if isGenerating {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isGenerating || exportSummary.count == 0)
            }
        }
    }

    // MARK: - Export Actions

    /// Generate export file and save to Files app
    private func generateAndSaveToFiles() async {
        // Check for unverified products in PDF export
        if exportFormat == .pdf {
            if await checkForUnverifiedProducts() {
                pendingExportAction = .saveToFiles
                return
            }
        }

        await performSaveToFiles()
    }

    /// Generate export file and show share sheet
    private func generateAndShare() async {
        // Check for unverified products in PDF export
        if exportFormat == .pdf {
            if await checkForUnverifiedProducts() {
                pendingExportAction = .share
                return
            }
        }

        await performShare()
    }

    /// Generate export file and open email with attachment
    private func generateAndEmail() async {
        // Check for unverified products in PDF export
        if exportFormat == .pdf {
            if await checkForUnverifiedProducts() {
                pendingExportAction = .email
                return
            }
        }

        await performEmail()
    }

    /// Check for unverified products and show warning if found
    /// Returns true if warning was shown (export should be deferred), false if export should proceed
    private func checkForUnverifiedProducts() async -> Bool {
        // Filter products by PDF year
        let calendar = Calendar.current
        let yearProducts = allProducts.filter { product in
            calendar.component(.year, from: product.reportingDate) == pdfYear
        }

        // Check for unverified products
        let unverifiedCount = yearProducts.filter { !$0.verified }.count
        if unverifiedCount > 0 {
            await MainActor.run {
                unverifiedProductCount = unverifiedCount
                showingUnverifiedWarning = true
            }
            return true // Warning shown, defer export
        }

        return false // No warning, proceed with export
    }

    /// Perform the pending export action after user confirms warning
    private func performPendingExport() async {
        guard let action = pendingExportAction else { return }
        pendingExportAction = nil

        switch action {
        case .saveToFiles:
            await performSaveToFiles()
        case .share:
            await performShare()
        case .email:
            await performEmail()
        }
    }

    /// Actually perform save to files (after warning check)
    private func performSaveToFiles() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let fileURL = try await generateExportFile()

            // Present document picker to save file
            await MainActor.run {
                showingDocumentPicker = true
                // Note: Document picker for save is handled via UIDocumentPickerViewController
                // For now, we'll use share sheet as fallback since SwiftUI doesn't have native file save
                shareItems = [fileURL]
                showingShareSheet = true
            }
        } catch {
            errorMessage = "Failed to generate \(exportFormat.rawValue): \(error.localizedDescription)"
            showingError = true
        }
    }

    /// Actually perform share (after warning check)
    private func performShare() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let fileURL = try await generateExportFile()

            await MainActor.run {
                shareItems = [fileURL]
                showingShareSheet = true
            }
        } catch {
            errorMessage = "Failed to generate \(exportFormat.rawValue): \(error.localizedDescription)"
            showingError = true
        }
    }

    /// Actually perform email (after warning check)
    private func performEmail() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let fileURL = try await generateExportFile()

            // Note: mailto: URLs cannot attach files directly
            // We'll use share sheet instead, which allows email with attachment
            await MainActor.run {
                shareItems = [fileURL]
                showingShareSheet = true
            }
        } catch {
            errorMessage = "Failed to generate \(exportFormat.rawValue): \(error.localizedDescription)"
            showingError = true
        }
    }

    /// Generates export file based on selected format
    private func generateExportFile() async throws -> URL {
        switch exportFormat {
        case .csv:
            return try await CSVExportService.shared.generateCSV(
                products: allProducts,
                dateRange: currentDateRange
            )

        case .pdf:
            // Filter products by PDF year
            let calendar = Calendar.current
            let yearProducts = allProducts.filter { product in
                calendar.component(.year, from: product.reportingDate) == pdfYear
            }

            // Filter receipts by PDF year
            let yearReceipts = allReceipts.filter { receipt in
                calendar.component(.year, from: receipt.purchaseDate) == pdfYear
            }

            // Generate PDF (unverified products check already done upstream)
            return try await PDFGeneratorService.shared.generatePDF(
                products: yearProducts,
                receipts: yearReceipts,
                year: pdfYear,
                userName: AppSettings.shared.userName,
                paperSize: paperSize
            )
        }
    }
}

// MARK: - Share Sheet

/// UIKit share sheet wrapper for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#if DEBUG
// MARK: - Preview

#Preview {
    let container = try! ModelContainer(
        for: ProductPair.self, Receipt.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    // Create sample data
    let context = container.mainContext
    for i in 1...5 {
        let product = ProductPair(
            gfProductName: "GF Product \(i)",
            gfPrice: Decimal(i * 2 + 5),
            nonGFProductName: "Regular Product \(i)",
            nonGFPrice: Decimal(i + 2),
            category: "Bread",
            verified: i % 2 == 0
        )
        context.insert(product)
    }

    return ExportView()
        .modelContainer(container)
}
#endif
