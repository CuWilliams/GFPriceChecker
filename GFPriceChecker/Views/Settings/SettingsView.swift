//
//  SettingsView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings view for user preferences and app configuration
///
/// Provides configuration options for:
/// - Personal information (name, accountant email, tax ID)
/// - Export preferences (paper size, date range defaults, currency)
/// - Data management (backup, restore, clear data)
/// - App information (version, about)
struct SettingsView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @Bindable private var settings = AppSettings.shared

    @State private var showingExportOptions = false
    @State private var showingImportPicker = false
    @State private var showingClearDataAlert = false
    @State private var clearDataConfirmationText = ""

    @State private var exportedData: Data?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var successMessage: String?
    @State private var showingSuccess = false

    @State private var isExporting = false
    @State private var isImporting = false

    @State private var showingOnboarding = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Personal Information Section
                personalInformationSection

                // Export Preferences Section
                exportPreferencesSection

                // Data Management Section
                dataManagementSection

                // About Section
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileExporter(
                isPresented: $showingExportOptions,
                document: BackupDocument(data: exportedData),
                contentType: .json,
                defaultFilename: "GFPriceChecker-Backup-\(formattedDate).json"
            ) { result in
                handleExportResult(result)
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .alert("Success", isPresented: $showingSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(successMessage ?? "Operation completed successfully")
            }
            .alert("Clear All Data", isPresented: $showingClearDataAlert) {
                TextField("Type DELETE to confirm", text: $clearDataConfirmationText)
                Button("Cancel", role: .cancel) {
                    clearDataConfirmationText = ""
                }
                Button("Delete Everything", role: .destructive) {
                    performClearData()
                }
                .disabled(clearDataConfirmationText != "DELETE")
            } message: {
                Text("This will permanently delete all products, receipts, and images. Your personal settings will be preserved. This action cannot be undone.")
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(isPresented: $showingOnboarding)
            }
        }
    }

    // MARK: - Sections

    private var personalInformationSection: some View {
        Section {
            TextField("Full Name", text: $settings.userName)
                .textContentType(.name)
                .autocorrectionDisabled()

            TextField("Accountant Email (Optional)", text: $settings.accountantEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()

            SecureField("Tax ID (Optional)", text: $settings.taxID)
                .textContentType(.none)
                .keyboardType(.numberPad)
        } header: {
            Text("Personal Information")
        } footer: {
            Text("Your name appears on PDF reports. Tax ID and accountant email are optional. All information is stored locally on your device.")
        }
    }

    private var exportPreferencesSection: some View {
        Section {
            Picker("Currency Symbol", selection: $settings.currencySymbol) {
                Text("$ CAD").tag("$ CAD")
                Text("$ USD").tag("$ USD")
            }

            Picker("Default Date Range", selection: $settings.defaultDateRange) {
                ForEach(DateRangePreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }

            Picker("PDF Paper Size", selection: $settings.defaultPaperSize) {
                ForEach(PaperSize.allCases, id: \.self) { size in
                    Text(size.rawValue).tag(size)
                }
            }
        } header: {
            Text("Export Preferences")
        } footer: {
            Text("These defaults are used when generating CSV and PDF exports.")
        }
    }

    private var dataManagementSection: some View {
        Section {
            // Export All Data
            Button {
                performExport()
            } label: {
                HStack {
                    Label("Export All Data", systemImage: "square.and.arrow.up")
                    Spacer()
                    if isExporting {
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)

            // Import Data
            Button {
                showingImportPicker = true
            } label: {
                HStack {
                    Label("Import Data", systemImage: "square.and.arrow.down")
                    Spacer()
                    if isImporting {
                        ProgressView()
                    }
                }
            }
            .disabled(isImporting)

            // Clear All Data
            Button(role: .destructive) {
                showingClearDataAlert = true
            } label: {
                Label("Clear All Data", systemImage: "trash")
            }
        } header: {
            Text("Data Management")
        } footer: {
            Text("Export creates a backup file with all products, receipts, and images. Import restores from a backup file. Clear All Data permanently deletes everything except your personal settings.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Build")
                Spacer()
                Text(appBuild)
                    .foregroundStyle(.secondary)
            }

            Button {
                showingOnboarding = true
            } label: {
                Label("How to Use", systemImage: "questionmark.circle")
            }

            Link(destination: URL(string: "mailto:support@gfpricechecker.app")!) {
                Label("Contact Support", systemImage: "envelope")
            }
        } header: {
            Text("About")
        } footer: {
            Text("GFPriceChecker helps track gluten-free product price differentials for Canadian tax deductions.")
        }
    }

    // MARK: - Helpers

    /// App version from bundle
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// App build number from bundle
    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// Formatted date for backup filename
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Data Management Actions

    private func performExport() {
        isExporting = true

        Task { @MainActor in
            do {
                let data = try await DataBackupService.shared.exportBackup(modelContext: modelContext)
                exportedData = data
                showingExportOptions = true
            } catch {
                errorMessage = "Failed to create backup: \(error.localizedDescription)"
                showingError = true
            }
            isExporting = false
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            successMessage = "Backup exported successfully!"
            showingSuccess = true
        case .failure(let error):
            errorMessage = "Failed to save backup file: \(error.localizedDescription)"
            showingError = true
        }
        exportedData = nil
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importData(from: url)
        case .failure(let error):
            errorMessage = "Failed to open backup file: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func importData(from url: URL) {
        isImporting = true

        // Request access to security-scoped resource (required for files outside app sandbox)
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Failed to access the backup file. Please ensure the file is accessible and try again."
            showingError = true
            isImporting = false
            return
        }

        // Read file data synchronously while we have access to the security-scoped resource
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            url.stopAccessingSecurityScopedResource()
            errorMessage = "Failed to read backup file: \(error.localizedDescription)"
            showingError = true
            isImporting = false
            return
        }

        // Stop accessing the resource now that we have the data
        url.stopAccessingSecurityScopedResource()

        // Process the backup data asynchronously
        Task { @MainActor in
            do {
                try await DataBackupService.shared.importBackup(
                    data: data,
                    modelContext: modelContext,
                    strategy: .merge // Merge with existing data
                )
                successMessage = "Backup imported successfully! Your data has been restored."
                showingSuccess = true
            } catch {
                errorMessage = "Failed to import backup: \(error.localizedDescription)"
                showingError = true
            }
            isImporting = false
        }
    }

    private func performClearData() {
        guard clearDataConfirmationText == "DELETE" else { return }

        Task { @MainActor in
            do {
                try DataBackupService.shared.clearAllData(modelContext: modelContext)
                successMessage = "All data has been deleted. Your personal settings have been preserved."
                showingSuccess = true
                clearDataConfirmationText = ""
            } catch {
                errorMessage = "Failed to clear data: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - Backup Document

/// Transferable document for exporting backup data
private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data?

    init(data: Data?) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = data else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(for: [ProductPair.self, Receipt.self], inMemory: true)
}
