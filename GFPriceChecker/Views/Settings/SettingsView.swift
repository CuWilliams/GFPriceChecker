//
//  SettingsView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import SwiftUI

/// Settings view for user preferences and app configuration
///
/// Provides configuration options for:
/// - Personal information (name, accountant email)
/// - Export preferences (paper size, date range defaults)
/// - App information (version, about)
struct SettingsView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @Bindable private var settings = AppSettings.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Personal Information Section
                Section {
                    TextField("Full Name", text: $settings.userName)
                        .textContentType(.name)
                        .autocorrectionDisabled()

                    TextField("Accountant Email (Optional)", text: $settings.accountantEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Personal Information")
                } footer: {
                    Text("Your name appears on PDF reports. Accountant email is used as the default recipient for exports.")
                }

                // Export Preferences Section
                Section {
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

                // About Section
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
                } header: {
                    Text("About")
                } footer: {
                    Text("GFPriceChecker helps track gluten-free product price differentials for Canadian tax deductions.")
                }
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
}

// MARK: - Preview

#Preview {
    SettingsView()
}
