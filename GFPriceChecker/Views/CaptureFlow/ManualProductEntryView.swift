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
    @State private var errorMessage: String?
    @State private var showingError: Bool = false

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
                        .accessibilityLabel("Gluten-free product name")
                        .accessibilityHint("Enter the name of the gluten-free product")

                    HStack {
                        Text("$")
                            .accessibilityHidden(true)
                        TextField("0.00", text: $gfPriceText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Gluten-free product price")
                            .accessibilityHint("Enter price in dollars")
                    }

                    TextField("Size (optional)", text: $gfSize)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Gluten-free product size")
                        .accessibilityHint("Optional. Enter size like 450g or 12oz")

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
                        .accessibilityLabel("Regular product name")
                        .accessibilityHint("Enter the name of the regular non-gluten-free product")

                    HStack {
                        Text("$")
                            .accessibilityHidden(true)
                        TextField("0.00", text: $nonGFPriceText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Regular product price")
                            .accessibilityHint("Enter price in dollars")
                    }

                    TextField("Size (optional)", text: $nonGFSize)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Regular product size")
                        .accessibilityHint("Optional. Enter size like 450g or 12oz")

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
                    .accessibilityLabel("Product category")
                    .accessibilityHint("Optional. Choose a category to organize your products")
                } header: {
                    Text("Category")
                }

                // Section 4: Optional Notes
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .accessibilityLabel("Notes")
                        .accessibilityHint("Optional. Add any additional notes about this product pair")
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
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Discard changes and close")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProductPair()
                    }
                    .accessibilityLabel("Save product pair")
                    .accessibilityHint("Save this product comparison")
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please check your input and try again.")
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

    /// Validates a price string using ValidationRules
    /// - Parameters:
    ///   - priceText: The price as a string
    ///   - fieldName: The field name for error messages
    /// - Returns: Error message if invalid, nil if valid
    private func validatePrice(_ priceText: String, fieldName: String = "Price") -> String? {
        switch ValidationRules.validatePriceString(priceText, fieldName: fieldName) {
        case .success:
            return nil
        case .failure(let error):
            return error.localizedDescription
        }
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

    /// Saves the product pair to SwiftData with comprehensive validation
    private func saveProductPair() {
        // Validate GF product name
        let validatedGFName: String
        switch ValidationRules.validateProductName(gfProductName, fieldName: "Gluten-free product name") {
        case .success(let name):
            validatedGFName = name
        case .failure(let error):
            errorMessage = ErrorHandler.shared.userMessage(for: error)
            showingError = true
            showingValidationErrors = true
            return
        }

        // Validate GF price
        let validatedGFPrice: Decimal
        switch ValidationRules.validatePriceString(gfPriceText, fieldName: "Gluten-free price") {
        case .success(let price):
            validatedGFPrice = price
        case .failure(let error):
            errorMessage = ErrorHandler.shared.userMessage(for: error)
            showingError = true
            showingValidationErrors = true
            return
        }

        // Validate non-GF product name
        let validatedNonGFName: String
        switch ValidationRules.validateProductName(nonGFProductName, fieldName: "Regular product name") {
        case .success(let name):
            validatedNonGFName = name
        case .failure(let error):
            errorMessage = ErrorHandler.shared.userMessage(for: error)
            showingError = true
            showingValidationErrors = true
            return
        }

        // Validate non-GF price
        let validatedNonGFPrice: Decimal
        switch ValidationRules.validatePriceString(nonGFPriceText, fieldName: "Regular price") {
        case .failure(let error):
            errorMessage = ErrorHandler.shared.userMessage(for: error)
            showingError = true
            showingValidationErrors = true
            return
        case .success(let price):
            validatedNonGFPrice = price
        }

        // Validate optional fields
        let validatedGFSize: String?
        switch ValidationRules.validateSize(gfSize) {
        case .success(let size):
            validatedGFSize = size
        case .failure(let error):
            errorMessage = ErrorHandler.shared.userMessage(for: error)
            showingError = true
            return
        }

        let validatedNonGFSize: String?
        switch ValidationRules.validateSize(nonGFSize) {
        case .success(let size):
            validatedNonGFSize = size
        case .failure(let error):
            errorMessage = ErrorHandler.shared.userMessage(for: error)
            showingError = true
            return
        }

        let validatedNotes: String?
        switch ValidationRules.validateNotes(notes) {
        case .success(let validNotes):
            validatedNotes = validNotes
        case .failure(let error):
            errorMessage = ErrorHandler.shared.userMessage(for: error)
            showingError = true
            return
        }

        let validatedCategory: String?
        let categoryValue = category == "None" ? nil : category
        switch ValidationRules.validateCategory(categoryValue) {
        case .success(let validCategory):
            validatedCategory = validCategory
        case .failure(let error):
            errorMessage = ErrorHandler.shared.userMessage(for: error)
            showingError = true
            return
        }

        // Save to database
        do {
            if let existingProductPair = productPair {
                // Edit mode: Update existing product pair
                existingProductPair.gfProductName = validatedGFName
                existingProductPair.gfPrice = validatedGFPrice
                existingProductPair.gfSize = validatedGFSize

                existingProductPair.nonGFProductName = validatedNonGFName
                existingProductPair.nonGFPrice = validatedNonGFPrice
                existingProductPair.nonGFSize = validatedNonGFSize

                existingProductPair.category = validatedCategory
                existingProductPair.notes = validatedNotes

                try modelContext.save()
            } else {
                // Create mode: Insert new product pair
                let newProductPair = ProductPair(
                    gfProductName: validatedGFName,
                    gfPrice: validatedGFPrice,
                    gfSize: validatedGFSize,
                    nonGFProductName: validatedNonGFName,
                    nonGFPrice: validatedNonGFPrice,
                    nonGFSize: validatedNonGFSize,
                    category: validatedCategory,
                    notes: validatedNotes
                )
                modelContext.insert(newProductPair)
                try modelContext.save()
            }

            // Dismiss the sheet
            dismiss()
        } catch {
            ErrorHandler.shared.log(error, context: "ManualProductEntryView.saveProductPair")
            errorMessage = ErrorHandler.shared.userMessage(for: ErrorHandler.AppError.databaseSaveFailed)
            showingError = true
        }
    }
}

// MARK: - Preview

#Preview {
    ManualProductEntryView()
        .modelContainer(for: ProductPair.self, inMemory: true)
}
