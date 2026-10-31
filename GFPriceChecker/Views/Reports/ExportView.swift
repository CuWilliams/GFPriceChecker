//
//  ExportView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import SwiftUI
import GFCore
import SwiftData
import UniformTypeIdentifiers

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

    /// All of the export's state and logic lives in `ExportViewModel`;
    /// this view only draws it.
    @State private var viewModel = ExportViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Format Selection
                    formatSection

                    // PDF-specific options
                    if viewModel.exportFormat == .pdf {
                        pdfOptionsSection
                    }

                    // Date Range Section (CSV only)
                    if viewModel.exportFormat == .csv {
                        dateRangeSection
                    }

                    // Export Summary
                    summarySection

                    // Preview Section (CSV only)
                    if viewModel.exportFormat == .csv {
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
            .alert("Export Error", isPresented: $viewModel.showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .alert("Unverified Products Found", isPresented: $viewModel.showingUnverifiedWarning) {
                Button("Continue Export", role: .none) {
                    Task {
                        // Small delay to ensure alert is fully dismissed before presenting share sheet
                        try? await Task.sleep(for: .milliseconds(300))
                        await viewModel.confirmUnverifiedExport()
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelUnverifiedExport()
                }
            } message: {
                Text("\(viewModel.unverifiedProductCount) product(s) lack receipt verification. These will appear in a separate \"Unverified Products\" section. For complete tax documentation, consider obtaining receipts for all products.")
            }
            .sheet(isPresented: $viewModel.showingShareSheet) {
                if !viewModel.shareItems.isEmpty {
                    ShareSheet(items: viewModel.shareItems)
                }
            }
            .onChange(of: allProducts, initial: true) { _, products in
                viewModel.products = products
            }
            .onChange(of: allReceipts, initial: true) { _, receipts in
                viewModel.receipts = receipts
            }
        }
    }

    // MARK: - Format Section

    private var formatSection: some View {
        VStack(spacing: 16) {
            Text("Export Format")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Format", selection: $viewModel.exportFormat) {
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
                Picker("Tax Year", selection: $viewModel.pdfYear) {
                    ForEach(viewModel.availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)

                // Paper Size Picker
                Picker("Paper Size", selection: $viewModel.paperSize) {
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

    // MARK: - Date Range Section

    private var dateRangeSection: some View {
        VStack(spacing: 16) {
            Text("Date Range")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                // Preset or Custom Toggle
                Picker("Range Type", selection: $viewModel.useCustomRange) {
                    Text("Preset").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)

                if viewModel.useCustomRange {
                    // Custom date pickers, each bounded by the other so the start can't pass the end
                    DatePicker(
                        "Start Date",
                        selection: $viewModel.customStartDate,
                        in: ...viewModel.customEndDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "End Date",
                        selection: $viewModel.customEndDate,
                        in: viewModel.customStartDate...,
                        displayedComponents: .date
                    )
                } else {
                    // Preset picker
                    Picker("Date Range", selection: $viewModel.selectedPreset) {
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
                    Text("\(viewModel.exportSummary.count)")
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
                    if let normalizedTotal = viewModel.exportSummary.totalNormalizedDifferential {
                        Text(normalizedTotal, format: .cad)
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
                    Text(viewModel.exportSummary.totalDifferential, format: .cad)
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
                Text("First \(min(10, viewModel.previewRows.count)) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.previewRows.isEmpty {
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
    ///   middle at the top edge and "... and N more rows" at the bottom. `viewModel.previewRows`
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
                ForEach(viewModel.previewRows, id: \.id) { row in
                    csvPreviewRow(for: row)
                }

                if viewModel.filteredRows.count > 10 {
                    Text("... and \(viewModel.filteredRows.count - 10) more rows")
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

    private func csvPreviewRow(for row: ReportRow) -> some View {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let line = [
            dateFormatter.string(from: row.reportingDate),
            String(row.pricing.quantity),
            row.gfProductName,
            String(describing: row.pricing.gfPrice),
            row.nonGFProductName,
            String(describing: row.pricing.nonGFPrice),
            String(describing: row.pricing.differential),
            String(describing: row.pricing.extendedDifferential),
            row.categoryName,
            row.storeName ?? "",
            row.verified ? "Yes" : "No"
        ].joined(separator: ",")

        return Text(line)
            .font(.system(.caption2, design: .monospaced))
            .lineLimit(1)
    }

    // MARK: - Export Actions Section

    private var exportActionsSection: some View {
        VStack(spacing: 16) {
            Text("Export Options")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // All three end in the share sheet — see `ExportViewModel.export()`
            VStack(spacing: 12) {
                // Save to Files Button
                Button {
                    Task {
                        await viewModel.export()
                    }
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text("Save to Files")
                        Spacer()
                        if viewModel.isGenerating {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!viewModel.canExport)

                // Share Button
                Button {
                    Task {
                        await viewModel.export()
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                        Spacer()
                        if viewModel.isGenerating {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!viewModel.canExport)

                // Email Button
                Button {
                    Task {
                        await viewModel.export()
                    }
                } label: {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Email")
                        Spacer()
                        if viewModel.isGenerating {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!viewModel.canExport)
            }
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
