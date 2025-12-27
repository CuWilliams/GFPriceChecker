//
//  ManualProductEntryView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import SwiftData

/// Form for manually entering or editing a product pair
///
/// Allows users to input gluten-free and non-gluten-free product information
/// with validation, category selection, and optional notes.
/// When a productPair is provided, the form operates in edit mode.
struct ManualProductEntryView: View {

    // MARK: - Properties

    /// Optional product pair to edit (nil for new entry)
    let productPair: ProductPair?

    // MARK: - Environment

    /// SwiftData model context for saving product pairs
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
            .navigationTitle(productPair == nil ? "Add Product Pair" : "Edit Product Pair")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                populateFieldsIfEditing()
            }
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

    // MARK: - Initialization

    /// Default initializer for new product entry
    init(productPair: ProductPair? = nil) {
        self.productPair = productPair
    }

    /// Populates form fields if editing an existing product
    private func populateFieldsIfEditing() {
        guard let productPair = productPair else { return }

        // GF Product
        gfProductName = productPair.gfProductName
        gfPriceText = String(describing: productPair.gfPrice)
        gfSize = productPair.gfSize ?? ""

        // Non-GF Product
        nonGFProductName = productPair.nonGFProductName
        nonGFPriceText = String(describing: productPair.nonGFPrice)
        nonGFSize = productPair.nonGFSize ?? ""

        // Optional fields
        category = productPair.category ?? "None"
        notes = productPair.notes ?? ""
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
        let errors = getValidationErrors(for: productType)

        if let nameError = errors.nameError {
            Text(nameError)
                .font(.caption)
                .foregroundStyle(.red)
        }

        if let priceError = errors.priceError {
            Text(priceError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    /// Gets validation errors for a product type
    private func getValidationErrors(for productType: ProductType) -> (nameError: String?, priceError: String?) {
        switch productType {
        case .gfProduct:
            let nameError = gfProductName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Product name is required"
                : nil
            let priceError = validatePrice(gfPriceText)
            return (nameError, priceError)
        case .nonGFProduct:
            let nameError = nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Product name is required"
                : nil
            let priceError = validatePrice(nonGFPriceText)
            return (nameError, priceError)
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

        if let existingProductPair = productPair {
            // Edit mode: Update existing product pair
            existingProductPair.gfProductName = gfProductName.trimmingCharacters(in: .whitespacesAndNewlines)
            existingProductPair.gfPrice = gfPrice
            existingProductPair.gfSize = gfSize.isEmpty ? nil : gfSize.trimmingCharacters(in: .whitespacesAndNewlines)

            existingProductPair.nonGFProductName = nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines)
            existingProductPair.nonGFPrice = nonGFPrice
            existingProductPair.nonGFSize = nonGFSize.isEmpty ? nil : nonGFSize.trimmingCharacters(in: .whitespacesAndNewlines)

            existingProductPair.category = category == "None" ? nil : category
            existingProductPair.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Create mode: Insert new product pair
            let newProductPair = ProductPair(
                gfProductName: gfProductName.trimmingCharacters(in: .whitespacesAndNewlines),
                gfPrice: gfPrice,
                gfSize: gfSize.isEmpty ? nil : gfSize.trimmingCharacters(in: .whitespacesAndNewlines),
                nonGFProductName: nonGFProductName.trimmingCharacters(in: .whitespacesAndNewlines),
                nonGFPrice: nonGFPrice,
                nonGFSize: nonGFSize.isEmpty ? nil : nonGFSize.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category == "None" ? nil : category,
                notes: notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            modelContext.insert(newProductPair)
        }

        // Dismiss the sheet
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    ManualProductEntryView()
        .modelContainer(for: ProductPair.self, inMemory: true)
}
