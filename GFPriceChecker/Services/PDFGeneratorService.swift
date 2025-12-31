//
//  PDFGeneratorService.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2024-12-29.
//

import Foundation
import UIKit
import PDFKit

/// Service for generating professional PDF reports
///
/// Creates multi-page PDF reports suitable for CRA tax filing with:
/// - Branded cover page
/// - Summary statistics
/// - Detailed transaction table
/// - Professional styling (Helvetica, blues/grays)
@MainActor
final class PDFGeneratorService {

    // MARK: - Singleton

    static let shared = PDFGeneratorService()

    private init() {}

    // MARK: - Constants

    private let margin: CGFloat = 72 // 1 inch margins
    private let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
    private let headingFont = UIFont.systemFont(ofSize: 18, weight: .semibold)
    private let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
    private let captionFont = UIFont.systemFont(ofSize: 10, weight: .regular)

    private let primaryColor = UIColor.systemBlue
    private let secondaryColor = UIColor.systemGray
    private let accentColor = UIColor.systemGreen

    // MARK: - PDF Generation

    /// Generates a professional PDF report
    ///
    /// - Parameters:
    ///   - products: Product pairs to include in report
    ///   - receipts: Receipts to include images for in report
    ///   - year: Tax year for the report
    ///   - userName: User's name for cover page (optional)
    ///   - paperSize: Paper size (US Letter or A4)
    /// - Returns: URL of the generated temporary PDF file
    /// - Throws: Error if PDF generation fails
    func generatePDF(
        products: [ProductPair],
        receipts: [Receipt],
        year: Int,
        userName: String?,
        paperSize: PaperSize
    ) async throws -> URL {
        // Sort products by reporting date
        let sortedProducts = products.sorted { $0.reportingDate < $1.reportingDate }

        // Separate verified and unverified products
        let verifiedProducts = sortedProducts.filter { $0.verified }
        let unverifiedProducts = sortedProducts.filter { !$0.verified }

        // Group verified products by receipt
        var productsByReceipt: [String: [ProductPair]] = [:]
        for product in verifiedProducts {
            if let receiptID = product.receipt?.id.uuidString {
                productsByReceipt[receiptID, default: []].append(product)
            }
        }

        // Get unique receipts with products
        let receiptsWithProducts = receipts.filter { receipt in
            productsByReceipt[receipt.id.uuidString] != nil
        }

        print("📄 DEBUG: Generating PDF with \(receiptsWithProducts.count) receipts, \(verifiedProducts.count) verified products, \(unverifiedProducts.count) unverified products")

        // Pre-load receipt images (async loading before PDF generation)
        var receiptImages: [String: UIImage] = [:]
        for receipt in receiptsWithProducts {
            if let imageUUID = receipt.receiptImageUUID,
               let image = await ImageStorageService.shared.retrieveImage(uuid: imageUUID, type: .receipt) {
                receiptImages[receipt.id.uuidString] = image
                print("📄 DEBUG: Loaded image for receipt \(receipt.id.uuidString)")
            } else {
                print("📄 DEBUG: No image available for receipt \(receipt.id.uuidString)")
            }
        }

        // Calculate page bounds
        let pageRect = CGRect(origin: .zero, size: paperSize.size)
        let contentRect = pageRect.insetBy(dx: margin, dy: margin)

        // Create PDF metadata
        let pdfMetaData: [String: Any] = [
            kCGPDFContextCreator as String: "GFPriceChecker",
            kCGPDFContextAuthor as String: userName ?? "User",
            kCGPDFContextTitle as String: "GF Tax Differential Report - \(year)"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData

        // Generate PDF data
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            // Page 1: Cover Page
            context.beginPage()
            drawCoverPage(
                context: context.cgContext,
                pageRect: pageRect,
                contentRect: contentRect,
                year: year,
                userName: userName,
                totalDifferential: calculateTotalDifferential(products: sortedProducts),
                productCount: sortedProducts.count,
                receiptCount: receiptsWithProducts.count
            )

            // Page 2: Summary Statistics
            context.beginPage()
            drawSummaryPage(
                context: context.cgContext,
                pageRect: pageRect,
                contentRect: contentRect,
                products: sortedProducts,
                year: year,
                pageNumber: 2
            )

            // Page 3+: Detailed Transaction List with Receipt Images
            // Start new page for transaction details
            context.beginPage()
            drawTransactionAndReceiptPages(
                context: context,
                pageRect: pageRect,
                contentRect: contentRect,
                verifiedProducts: verifiedProducts,
                unverifiedProducts: unverifiedProducts,
                receiptsWithProducts: receiptsWithProducts,
                productsByReceipt: productsByReceipt,
                receiptImages: receiptImages,
                startingPageNumber: 3
            )
        }

        // Save to temporary file
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let filename = "GFPriceChecker_Report_\(year)_\(dateString).pdf"

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)

        try data.write(to: fileURL)

        return fileURL
    }

    // MARK: - Cover Page

    private func drawCoverPage(
        context: CGContext,
        pageRect: CGRect,
        contentRect: CGRect,
        year: Int,
        userName: String?,
        totalDifferential: Decimal,
        productCount: Int,
        receiptCount: Int
    ) {
        let centerX = pageRect.width / 2
        var yPosition: CGFloat = margin + 80

        // App Logo
        let logo = AppLogo(size: 120).asUIImage(size: CGSize(width: 120, height: 120))
        let logoRect = CGRect(x: centerX - 60, y: yPosition, width: 120, height: 120)
        logo.draw(in: logoRect)
        yPosition += 140

        // App Title
        let appTitle = "GFPriceChecker"
        let appTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 32, weight: .bold),
            .foregroundColor: primaryColor
        ]
        let appTitleSize = appTitle.size(withAttributes: appTitleAttrs)
        appTitle.draw(
            at: CGPoint(x: centerX - appTitleSize.width / 2, y: yPosition),
            withAttributes: appTitleAttrs
        )
        yPosition += 50

        // Subtitle
        let subtitle = "Gluten-Free Tax Differential Report"
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: headingFont,
            .foregroundColor: secondaryColor
        ]
        let subtitleSize = subtitle.size(withAttributes: subtitleAttrs)
        subtitle.draw(
            at: CGPoint(x: centerX - subtitleSize.width / 2, y: yPosition),
            withAttributes: subtitleAttrs
        )
        yPosition += 80

        // Tax Year
        let yearText = "Tax Year: \(year)"
        let yearAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.label
        ]
        let yearSize = yearText.size(withAttributes: yearAttrs)
        yearText.draw(
            at: CGPoint(x: centerX - yearSize.width / 2, y: yPosition),
            withAttributes: yearAttrs
        )
        yPosition += 40

        // Prepared For
        if let userName = userName, !userName.isEmpty {
            let preparedText = "Prepared for: \(userName)"
            let preparedAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.label
            ]
            let preparedSize = preparedText.size(withAttributes: preparedAttrs)
            preparedText.draw(
                at: CGPoint(x: centerX - preparedSize.width / 2, y: yPosition),
                withAttributes: preparedAttrs
            )
            yPosition += 30
        }

        // Generation Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let generatedText = "Generated: \(dateFormatter.string(from: Date()))"
        let generatedAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: secondaryColor
        ]
        let generatedSize = generatedText.size(withAttributes: generatedAttrs)
        generatedText.draw(
            at: CGPoint(x: centerX - generatedSize.width / 2, y: yPosition),
            withAttributes: generatedAttrs
        )
        yPosition += 80

        // Total Differential (Prominent)
        let totalText = totalDifferential.formatted(.currency(code: "CAD"))
        let totalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: accentColor
        ]
        let totalSize = totalText.size(withAttributes: totalAttrs)
        totalText.draw(
            at: CGPoint(x: centerX - totalSize.width / 2, y: yPosition),
            withAttributes: totalAttrs
        )
        yPosition += 60

        let totalLabel = "Total Annual Differential"
        let totalLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: secondaryColor
        ]
        let totalLabelSize = totalLabel.size(withAttributes: totalLabelAttrs)
        totalLabel.draw(
            at: CGPoint(x: centerX - totalLabelSize.width / 2, y: yPosition),
            withAttributes: totalLabelAttrs
        )
        yPosition += 40

        // Product and Receipt Summary
        let summaryText = "\(productCount) products verified with \(receiptCount) receipts"
        let summaryAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: secondaryColor
        ]
        let summarySize = summaryText.size(withAttributes: summaryAttrs)
        summaryText.draw(
            at: CGPoint(x: centerX - summarySize.width / 2, y: yPosition),
            withAttributes: summaryAttrs
        )

        // Footer
        drawFooter(
            context: context,
            pageRect: pageRect,
            pageNumber: 1,
            totalPages: nil
        )
    }

    // MARK: - Summary Page

    private func drawSummaryPage(
        context: CGContext,
        pageRect: CGRect,
        contentRect: CGRect,
        products: [ProductPair],
        year: Int,
        pageNumber: Int
    ) {
        var yPosition = contentRect.minY

        // Page Title
        let title = "Summary Statistics"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: primaryColor
        ]
        title.draw(at: CGPoint(x: contentRect.minX, y: yPosition), withAttributes: titleAttrs)
        yPosition += 40

        // Category Breakdown Section
        yPosition = drawCategoryBreakdown(
            context: context,
            contentRect: contentRect,
            yPosition: yPosition,
            products: products
        )
        yPosition += 30

        // Monthly Summary Section
        yPosition = drawMonthlySummary(
            context: context,
            contentRect: contentRect,
            yPosition: yPosition,
            products: products
        )
        yPosition += 30

        // Verification Statistics
        yPosition = drawVerificationStats(
            context: context,
            contentRect: contentRect,
            yPosition: yPosition,
            products: products
        )

        // Footer
        drawFooter(
            context: context,
            pageRect: pageRect,
            pageNumber: pageNumber,
            totalPages: nil
        )
    }

    private func drawCategoryBreakdown(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat,
        products: [ProductPair]
    ) -> CGFloat {
        var y = yPosition

        // Section Heading
        let heading = "Breakdown by Category"
        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: headingFont,
            .foregroundColor: UIColor.label
        ]
        heading.draw(at: CGPoint(x: contentRect.minX, y: y), withAttributes: headingAttrs)
        y += 30

        // Group by category
        var categoryTotals: [String: Decimal] = [:]
        var categoryCounts: [String: Int] = [:]

        for product in products {
            let category = product.category ?? "Uncategorized"
            categoryTotals[category, default: 0] += product.differential
            categoryCounts[category, default: 0] += 1
        }

        // Sort by total (descending)
        let sortedCategories = categoryTotals.sorted { $0.value > $1.value }

        // Draw table
        y = drawTable(
            context: context,
            contentRect: contentRect,
            yPosition: y,
            headers: ["Category", "Count", "Total Differential"],
            rows: sortedCategories.map { category, total in
                [
                    category,
                    String(categoryCounts[category] ?? 0),
                    total.formatted(.currency(code: "CAD"))
                ]
            },
            columnWidths: [200, 80, 150]
        )

        return y
    }

    private func drawMonthlySummary(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat,
        products: [ProductPair]
    ) -> CGFloat {
        var y = yPosition

        // Section Heading
        let heading = "Monthly Summary"
        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: headingFont,
            .foregroundColor: UIColor.label
        ]
        heading.draw(at: CGPoint(x: contentRect.minX, y: y), withAttributes: headingAttrs)
        y += 30

        // Group by month
        let calendar = Calendar.current
        var monthlyTotals: [Date: Decimal] = [:]
        var monthlyCounts: [Date: Int] = [:]

        for product in products {
            let components = calendar.dateComponents([.year, .month], from: product.reportingDate)
            guard let monthStart = calendar.date(from: components) else { continue }

            monthlyTotals[monthStart, default: 0] += product.differential
            monthlyCounts[monthStart, default: 0] += 1
        }

        // Sort by date
        let sortedMonths = monthlyTotals.sorted { $0.key < $1.key }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"

        // Draw table
        y = drawTable(
            context: context,
            contentRect: contentRect,
            yPosition: y,
            headers: ["Month", "Count", "Total"],
            rows: sortedMonths.map { month, total in
                [
                    dateFormatter.string(from: month),
                    String(monthlyCounts[month] ?? 0),
                    total.formatted(.currency(code: "CAD"))
                ]
            },
            columnWidths: [200, 80, 150]
        )

        return y
    }

    private func drawVerificationStats(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat,
        products: [ProductPair]
    ) -> CGFloat {
        var y = yPosition

        // Section Heading
        let heading = "Verification Status"
        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: headingFont,
            .foregroundColor: UIColor.label
        ]
        heading.draw(at: CGPoint(x: contentRect.minX, y: y), withAttributes: headingAttrs)
        y += 30

        let verified = products.filter { $0.verified }.count
        let unverified = products.count - verified

        // Draw table
        y = drawTable(
            context: context,
            contentRect: contentRect,
            yPosition: y,
            headers: ["Status", "Count", "Percentage"],
            rows: [
                ["Verified with Receipt", String(verified), "\(Int(Double(verified) / Double(products.count) * 100))%"],
                ["Unverified", String(unverified), "\(Int(Double(unverified) / Double(products.count) * 100))%"],
                ["Total", String(products.count), "100%"]
            ],
            columnWidths: [200, 80, 150]
        )

        return y
    }

    // MARK: - Transaction Pages

    /// Draws transaction pages with receipt images inserted after each receipt's products
    private func drawTransactionAndReceiptPages(
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        contentRect: CGRect,
        verifiedProducts: [ProductPair],
        unverifiedProducts: [ProductPair],
        receiptsWithProducts: [Receipt],
        productsByReceipt: [String: [ProductPair]],
        receiptImages: [String: UIImage],
        startingPageNumber: Int
    ) {
        var pageNumber = startingPageNumber
        var yPosition = contentRect.minY
        var isFirstPage = true

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // MARK: - Verified Products by Receipt

        if !receiptsWithProducts.isEmpty {
            // Sort receipts by purchase date
            let sortedReceipts = receiptsWithProducts.sorted { $0.purchaseDate < $1.purchaseDate }

            for receipt in sortedReceipts {
                guard let products = productsByReceipt[receipt.id.uuidString] else { continue }
                let sortedProducts = products.sorted { $0.reportingDate < $1.reportingDate }

                // Draw receipt section header
                if yPosition + 100 > contentRect.maxY {
                    // Start new page if not enough space
                    drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)
                    context.beginPage()
                    pageNumber += 1
                    yPosition = contentRect.minY
                    isFirstPage = false
                }

                // Page title on first page only
                if isFirstPage {
                    let title = "Verified Products with Receipts"
                    let titleAttrs: [NSAttributedString.Key: Any] = [
                        .font: titleFont,
                        .foregroundColor: primaryColor
                    ]
                    title.draw(at: CGPoint(x: contentRect.minX, y: yPosition), withAttributes: titleAttrs)
                    yPosition += 40
                    isFirstPage = false
                }

                // Receipt header
                let receiptTitle = "Receipt - \(receipt.storeName ?? "Unknown Store") - \(dateFormatter.string(from: receipt.purchaseDate))"
                let receiptTitleAttrs: [NSAttributedString.Key: Any] = [
                    .font: headingFont,
                    .foregroundColor: secondaryColor
                ]
                receiptTitle.draw(at: CGPoint(x: contentRect.minX, y: yPosition), withAttributes: receiptTitleAttrs)
                yPosition += 30

                // Table header
                yPosition = drawTransactionHeader(context: context.cgContext, contentRect: contentRect, yPosition: yPosition)

                // Draw products for this receipt
                for (index, product) in sortedProducts.enumerated() {
                    if yPosition + 20 > contentRect.maxY {
                        drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)
                        context.beginPage()
                        pageNumber += 1
                        yPosition = contentRect.minY
                        // Re-draw header on new page
                        yPosition = drawTransactionHeader(context: context.cgContext, contentRect: contentRect, yPosition: yPosition)
                    }

                    yPosition = drawTransactionRow(
                        context: context.cgContext,
                        contentRect: contentRect,
                        yPosition: yPosition,
                        product: product,
                        dateFormatter: dateFormatter,
                        isAlternate: index % 2 == 0
                    )
                }

                yPosition += 10

                // Receipt subtotal
                let subtotal = sortedProducts.reduce(Decimal.zero) { $0 + $1.differential }
                let subtotalText = "Receipt Subtotal: \(subtotal.formatted(.currency(code: "CAD")))"
                let subtotalAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: accentColor
                ]
                let subtotalSize = subtotalText.size(withAttributes: subtotalAttrs)
                subtotalText.draw(at: CGPoint(x: contentRect.maxX - subtotalSize.width - 10, y: yPosition), withAttributes: subtotalAttrs)
                yPosition += 30

                // MARK: - Receipt Image Page

                // Start new page for receipt image
                drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)
                context.beginPage()
                pageNumber += 1

                drawReceiptImagePage(
                    context: context.cgContext,
                    pageRect: pageRect,
                    contentRect: contentRect,
                    receipt: receipt,
                    verifiedProducts: sortedProducts,
                    receiptImage: receiptImages[receipt.id.uuidString]
                )

                drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)

                // Prepare for next receipt or section
                yPosition = contentRect.minY
            }
        }

        // MARK: - Unverified Products Section

        if !unverifiedProducts.isEmpty {
            // Start new page for unverified section
            context.beginPage()
            pageNumber += 1
            yPosition = contentRect.minY

            let unverifiedTitle = "Unverified Products (No Receipt)"
            let unverifiedTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.systemRed
            ]
            unverifiedTitle.draw(at: CGPoint(x: contentRect.minX, y: yPosition), withAttributes: unverifiedTitleAttrs)
            yPosition += 30

            // Warning message
            let warningText = "⚠️ These products lack receipt verification. Consider obtaining receipts for tax documentation."
            let warningAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.systemOrange
            ]
            let warningRect = CGRect(x: contentRect.minX, y: yPosition, width: contentRect.width, height: 40)
            warningText.draw(in: warningRect, withAttributes: warningAttrs)
            yPosition += 50

            // Table header
            yPosition = drawTransactionHeader(context: context.cgContext, contentRect: contentRect, yPosition: yPosition)

            // Draw unverified products
            for (index, product) in unverifiedProducts.enumerated() {
                if yPosition + 20 > contentRect.maxY {
                    drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)
                    context.beginPage()
                    pageNumber += 1
                    yPosition = contentRect.minY
                    yPosition = drawTransactionHeader(context: context.cgContext, contentRect: contentRect, yPosition: yPosition)
                }

                yPosition = drawTransactionRow(
                    context: context.cgContext,
                    contentRect: contentRect,
                    yPosition: yPosition,
                    product: product,
                    dateFormatter: dateFormatter,
                    isAlternate: index % 2 == 0
                )
            }

            yPosition += 10

            // Unverified subtotal
            let unverifiedSubtotal = unverifiedProducts.reduce(Decimal.zero) { $0 + $1.differential }
            let unverifiedSubtotalText = "Unverified Subtotal: \(unverifiedSubtotal.formatted(.currency(code: "CAD")))"
            let unverifiedSubtotalAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.systemOrange
            ]
            let unverifiedSubtotalSize = unverifiedSubtotalText.size(withAttributes: unverifiedSubtotalAttrs)
            unverifiedSubtotalText.draw(at: CGPoint(x: contentRect.maxX - unverifiedSubtotalSize.width - 10, y: yPosition), withAttributes: unverifiedSubtotalAttrs)
            yPosition += 30
        }

        // Draw final footer
        drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: pageNumber)
    }

    /// Draws a receipt image page with verified products caption
    private func drawReceiptImagePage(
        context: CGContext,
        pageRect: CGRect,
        contentRect: CGRect,
        receipt: Receipt,
        verifiedProducts: [ProductPair],
        receiptImage: UIImage?
    ) {
        var yPosition = contentRect.minY

        // Page title
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let title = "Receipt - \(receipt.storeName ?? "Unknown Store") - \(dateFormatter.string(from: receipt.purchaseDate))"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: primaryColor
        ]
        title.draw(at: CGPoint(x: contentRect.minX, y: yPosition), withAttributes: titleAttrs)
        yPosition += 50

        // Draw receipt image
        if let image = receiptImage {
            // Calculate image size to fit page (maintain aspect ratio)
            let maxImageHeight = contentRect.height - 150 // Leave space for title and caption
            let imageSize = image.size
            let aspectRatio = imageSize.height / imageSize.width

            var drawWidth = contentRect.width
            var drawHeight = drawWidth * aspectRatio

            if drawHeight > maxImageHeight {
                drawHeight = maxImageHeight
                drawWidth = drawHeight / aspectRatio
            }

            let imageX = contentRect.minX + (contentRect.width - drawWidth) / 2
            let imageRect = CGRect(x: imageX, y: yPosition, width: drawWidth, height: drawHeight)
            image.draw(in: imageRect)
            yPosition += drawHeight + 20

        } else {
            // Image not available
            let noImageText = "Receipt Image Not Available"
            let noImageAttrs: [NSAttributedString.Key: Any] = [
                .font: headingFont,
                .foregroundColor: secondaryColor
            ]
            let noImageSize = noImageText.size(withAttributes: noImageAttrs)
            noImageText.draw(at: CGPoint(x: contentRect.minX + (contentRect.width - noImageSize.width) / 2, y: yPosition + 100), withAttributes: noImageAttrs)
            yPosition += 200
        }

        // Caption: Verified Products
        let productNames = verifiedProducts.map { $0.gfProductName }.joined(separator: ", ")
        let caption = "Verified Products: \(productNames)"
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: secondaryColor
        ]
        let captionRect = CGRect(x: contentRect.minX, y: yPosition, width: contentRect.width, height: 60)
        caption.draw(in: captionRect, withAttributes: captionAttrs)
    }

    private func drawTransactionPages(
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        contentRect: CGRect,
        products: [ProductPair],
        startingPageNumber: Int
    ) {
        var pageNumber = startingPageNumber
        var yPosition = contentRect.minY
        var isFirstPage = true

        // Group products by category for subtotals
        var currentCategory: String?
        var categorySubtotal: Decimal = 0

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for (index, product) in products.enumerated() {
            let category = product.category ?? "Uncategorized"

            // Check if we need a new page
            if yPosition + 60 > contentRect.maxY {
                // Draw footer on current page
                drawFooter(
                    context: context.cgContext,
                    pageRect: pageRect,
                    pageNumber: pageNumber,
                    totalPages: nil
                )

                // Start new page
                context.beginPage()
                pageNumber += 1
                yPosition = contentRect.minY
                isFirstPage = false
            }

            // Page title on first page only
            if isFirstPage {
                let title = "Detailed Transaction List"
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: titleFont,
                    .foregroundColor: primaryColor
                ]
                title.draw(at: CGPoint(x: contentRect.minX, y: yPosition), withAttributes: titleAttrs)
                yPosition += 40

                // Table headers
                yPosition = drawTransactionHeader(
                    context: context.cgContext,
                    contentRect: contentRect,
                    yPosition: yPosition
                )

                isFirstPage = false
            }

            // Check for category change (draw subtotal)
            if let prevCategory = currentCategory, prevCategory != category {
                yPosition = drawCategorySubtotal(
                    context: context.cgContext,
                    contentRect: contentRect,
                    yPosition: yPosition,
                    category: prevCategory,
                    subtotal: categorySubtotal
                )
                categorySubtotal = 0
            }

            currentCategory = category
            categorySubtotal += product.differential

            // Draw transaction row
            yPosition = drawTransactionRow(
                context: context.cgContext,
                contentRect: contentRect,
                yPosition: yPosition,
                product: product,
                dateFormatter: dateFormatter,
                isAlternate: index % 2 == 0
            )
        }

        // Draw final category subtotal
        if let category = currentCategory {
            yPosition = drawCategorySubtotal(
                context: context.cgContext,
                contentRect: contentRect,
                yPosition: yPosition,
                category: category,
                subtotal: categorySubtotal
            )
        }

        // Grand total
        yPosition += 10
        let grandTotal = calculateTotalDifferential(products: products)
        yPosition = drawGrandTotal(
            context: context.cgContext,
            contentRect: contentRect,
            yPosition: yPosition,
            total: grandTotal
        )

        // Footer on last page
        drawFooter(
            context: context.cgContext,
            pageRect: pageRect,
            pageNumber: pageNumber,
            totalPages: pageNumber
        )
    }

    private func drawTransactionHeader(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat
    ) -> CGFloat {
        let headers = ["Date", "GF Product", "GF $", "Regular Product", "Reg $", "Diff", "Store"]
        let columnWidths: [CGFloat] = [70, 100, 50, 100, 50, 50, 80]

        var x = contentRect.minX
        let y = yPosition

        // Background
        context.setFillColor(primaryColor.withAlphaComponent(0.1).cgColor)
        context.fill(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 20))

        // Headers
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.label
        ]

        for (index, header) in headers.enumerated() {
            header.draw(at: CGPoint(x: x + 4, y: y + 4), withAttributes: headerAttrs)
            x += columnWidths[index]
        }

        return y + 22
    }

    private func drawTransactionRow(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat,
        product: ProductPair,
        dateFormatter: DateFormatter,
        isAlternate: Bool
    ) -> CGFloat {
        let columnWidths: [CGFloat] = [70, 100, 50, 100, 50, 50, 80]
        let rowHeight: CGFloat = 18

        var x = contentRect.minX
        let y = yPosition

        // Alternating row background
        if isAlternate {
            context.setFillColor(UIColor.systemGray6.cgColor)
            context.fill(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: rowHeight))
        }

        // Row data
        let rowData = [
            dateFormatter.string(from: product.reportingDate),
            product.gfProductName.truncated(to: 15),
            String(format: "%.2f", NSDecimalNumber(decimal: product.gfPrice).doubleValue),
            product.nonGFProductName.truncated(to: 15),
            String(format: "%.2f", NSDecimalNumber(decimal: product.nonGFPrice).doubleValue),
            String(format: "%.2f", NSDecimalNumber(decimal: product.differential).doubleValue),
            product.receipt?.storeName?.truncated(to: 12) ?? ""
        ]

        let cellAttrs: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: UIColor.label
        ]

        for (index, data) in rowData.enumerated() {
            data.draw(at: CGPoint(x: x + 4, y: y + 4), withAttributes: cellAttrs)
            x += columnWidths[index]
        }

        // Border
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(0.5)
        context.stroke(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: rowHeight))

        return y + rowHeight
    }

    private func drawCategorySubtotal(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat,
        category: String,
        subtotal: Decimal
    ) -> CGFloat {
        let y = yPosition + 5
        let subtotalText = "\(category) Subtotal: \(subtotal.formatted(.currency(code: "CAD")))"
        let subtotalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: secondaryColor
        ]

        let textSize = subtotalText.size(withAttributes: subtotalAttrs)
        subtotalText.draw(
            at: CGPoint(x: contentRect.maxX - textSize.width - 10, y: y),
            withAttributes: subtotalAttrs
        )

        return y + 20
    }

    private func drawGrandTotal(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat,
        total: Decimal
    ) -> CGFloat {
        let y = yPosition

        // Background
        context.setFillColor(accentColor.withAlphaComponent(0.1).cgColor)
        context.fill(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 25))

        let totalText = "Grand Total: \(total.formatted(.currency(code: "CAD")))"
        let totalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: accentColor
        ]

        let textSize = totalText.size(withAttributes: totalAttrs)
        totalText.draw(
            at: CGPoint(x: contentRect.maxX - textSize.width - 10, y: y + 6),
            withAttributes: totalAttrs
        )

        return y + 30
    }

    // MARK: - Table Helper

    private func drawTable(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat,
        headers: [String],
        rows: [[String]],
        columnWidths: [CGFloat]
    ) -> CGFloat {
        var y = yPosition
        let rowHeight: CGFloat = 20

        // Header row
        context.setFillColor(primaryColor.withAlphaComponent(0.1).cgColor)
        context.fill(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: rowHeight))

        var x = contentRect.minX
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.label
        ]

        for (index, header) in headers.enumerated() {
            header.draw(at: CGPoint(x: x + 8, y: y + 4), withAttributes: headerAttrs)
            x += columnWidths[index]
        }

        y += rowHeight

        // Data rows
        let cellAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.label
        ]

        for (rowIndex, row) in rows.enumerated() {
            // Alternating background
            if rowIndex % 2 == 0 {
                context.setFillColor(UIColor.systemGray6.cgColor)
                context.fill(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: rowHeight))
            }

            x = contentRect.minX
            for (colIndex, cell) in row.enumerated() {
                cell.draw(at: CGPoint(x: x + 8, y: y + 4), withAttributes: cellAttrs)
                x += columnWidths[colIndex]
            }

            // Row border
            context.setStrokeColor(UIColor.systemGray4.cgColor)
            context.setLineWidth(0.5)
            context.stroke(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: rowHeight))

            y += rowHeight
        }

        return y + 10
    }

    // MARK: - Footer

    private func drawFooter(
        context: CGContext,
        pageRect: CGRect,
        pageNumber: Int,
        totalPages: Int?
    ) {
        let footerY = pageRect.height - margin + 20

        // Page number
        let pageText: String
        if let totalPages = totalPages {
            pageText = "Page \(pageNumber) of \(totalPages)"
        } else {
            pageText = "Page \(pageNumber)"
        }

        let pageAttrs: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: secondaryColor
        ]
        let pageSize = pageText.size(withAttributes: pageAttrs)
        pageText.draw(
            at: CGPoint(x: pageRect.width / 2 - pageSize.width / 2, y: footerY),
            withAttributes: pageAttrs
        )

        // Generated by text
        let generatedText = "Generated by GFPriceChecker"
        let generatedSize = generatedText.size(withAttributes: pageAttrs)
        generatedText.draw(
            at: CGPoint(x: pageRect.width - margin - generatedSize.width, y: footerY),
            withAttributes: pageAttrs
        )
    }

    // MARK: - Helpers

    private func calculateTotalDifferential(products: [ProductPair]) -> Decimal {
        products.reduce(Decimal.zero) { $0 + $1.differential }
    }
}

// MARK: - String Extension

extension String {
    func truncated(to length: Int, addEllipsis: Bool = true) -> String {
        if self.count <= length {
            return self
        }
        let endIndex = self.index(self.startIndex, offsetBy: length)
        let truncated = String(self[..<endIndex])
        return addEllipsis ? truncated + "..." : truncated
    }
}
