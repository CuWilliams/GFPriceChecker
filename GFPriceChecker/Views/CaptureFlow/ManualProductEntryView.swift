//
//  ManualProductEntryView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import SwiftData

/// Form for manually entering a new product pair
///
/// Allows users to input gluten-free and non-gluten-free product information
/// with validation, category selection, and optional notes.
struct ManualProductEntryView: View {

    // MARK: - Environment

    /// SwiftData model context for saving new product pairs
    @Environment(\.modelContext) private var modelContext

    /// Dismiss action to close the sheet
    @Environment(\.dismiss) private var dismiss

    // MARK: - State - Gluten-Free Product

    @State private var gfProductName: String = ""
    @State private var gfPriceText: String = ""
    @State private var gfSize: String = ""

    // MARK: - State - Non-Gluten-Free Product

    @State private var nonGFProductName: String = ""
    @State private var nonGFPriceText: String = ""
    @State private var nonGFSize: String = ""

    // MARK: - State - Optional Fields

    @State private var category: String = "None"
    @State private var notes: String = ""

    // MARK: - State - Validation

    @State private var showingValidationErrors: Bool = false

    // MARK: - Constants

    private let commonCategories = [
        "None",
        "Bread",
        "Pasta",
        "Flour",
        "Crackers",
        "Cookies",
        "Cereal",
        "Pizza",
        "Sauce"
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Gluten-Free Product
                Section {
                    TextField("Product Name", text: $gfProductName)
                        .autocorrectionDisabled()

                    HStack {
                        Text("$")
                        TextField("0.00", text: $gfPriceText)
                            .keyboardType(.decimalPad)
                    }

                    TextField("Size (optional)", text: $gfSize)
                        .autocorrectionDisabled()

                    if showingValidationErrors {
                        validationMessages(for: .gfProduct)
                    }
                } header: {
                    Text("Gluten-Free Product")
                }

                // Section 2: Non-Gluten-Free Product
                Section {
                    TextField("Product Name", text: $nonGFProductName)
                        .autocorrectionDisabled()

                    HStack {
                        Text("$")
                        TextField("0.00", text: $nonGFPriceText)
                            .keyboardType(.decimalPad)
                    }

                    TextField("Size (optional)", text: $nonGFSize)
                        .autocorrectionDisabled()

                    if showingValidationErrors {
                        validationMessages(for: .nonGFProduct)
                    }
                } header: {
                    Text("Non-Gluten-Free Equivalent")
                }

                // Section 3: Category
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(commonCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                } header: {
                    Text("Category")
                }

                // Section 4: Optional Notes
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: {
                    Text("Notes (Optional)")
                }
            }
            .navigationTitle("Add Product Pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProductPair()
                    }
                }
            }
        }
    }

    // MARK: - Validation Messages

    /// Product type for validation
    private enum ProductType {
        case gfProduct
        case nonGFProduct
    }

    /// Returns validation error messages for a product type
    @ViewBuilder
    private func validationMessages(for productType: ProductType) -> some View {
        let nameError: String?
        let priceError: String?

        switch productType {
        case .gfProduct:
            nameError = gfProductName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Product name is required"
                : nil
            priceError = validatePrice(gfPriceText)
        case .nonGFProduct:
            nameError = nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Product name is required"
                : nil
            priceError = validatePrice(nonGFPriceText)
        }

        if let nameError {
            Text(nameError)
                .font(.caption)
                .foregroundStyle(.red)
        }

        if let priceError {
            Text(priceError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Validation Logic

    /// Validates a price string
    /// - Returns: Error message if invalid, nil if valid
    private func validatePrice(_ priceText: String) -> String? {
        let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return "Price is required"
        }

        guard let decimal = Decimal(string: trimmed), decimal > 0 else {
            return "Price must be greater than 0"
        }

        return nil
    }

    /// Checks if all form inputs are valid
    private var isFormValid: Bool {
        // GF Product validation
        guard !gfProductName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        guard validatePrice(gfPriceText) == nil else {
            return false
        }

        // Non-GF Product validation
        guard !nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        guard validatePrice(nonGFPriceText) == nil else {
            return false
        }

        return true
    }

    // MARK: - Actions

    /// Saves the product pair to SwiftData
    private func saveProductPair() {
        // Show validation errors if form is invalid
        guard isFormValid else {
            showingValidationErrors = true
            return
        }

        // Convert price strings to Decimal
        guard let gfPrice = Decimal(string: gfPriceText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let nonGFPrice = Decimal(string: nonGFPriceText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            showingValidationErrors = true
            return
        }

        // Create new ProductPair
        let productPair = ProductPair(
            gfProductName: gfProductName.trimmingCharacters(in: .whitespacesAndNewlines),
            gfPrice: gfPrice,
            gfSize: gfSize.isEmpty ? nil : gfSize.trimmingCharacters(in: .whitespacesAndNewlines),
            nonGFProductName: nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines),
            nonGFPrice: nonGFPrice,
            nonGFSize: nonGFSize.isEmpty ? nil : nonGFSize.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category == "None" ? nil : category,
            notes: notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        // Insert into SwiftData
        modelContext.insert(productPair)

        // Dismiss the sheet
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    ManualProductEntryView()
        .modelContainer(for: ProductPair.self, inMemory: true)
}
