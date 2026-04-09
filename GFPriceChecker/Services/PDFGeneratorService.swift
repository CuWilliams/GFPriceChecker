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

        let simpleTotalDiff = calculateTotalDifferential(products: sortedProducts)
        let normalizedResult = calculateNormalizedDifferential(products: sortedProducts)

        let data = renderer.pdfData { context in
            // Page 1: Cover Page
            context.beginPage()
            drawCoverPage(
                context: context.cgContext,
                pageRect: pageRect,
                contentRect: contentRect,
                year: year,
                userName: userName,
                totalDifferential: simpleTotalDiff,
                normalizedTotal: normalizedResult.total,
                normalizedExcluded: normalizedResult.excludedCount,
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
        normalizedTotal: Decimal,
        normalizedExcluded: Int,
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

        // Primary: Size-Adjusted Total (CRA-recommended)
        let normalizedText = normalizedTotal.formatted(.currency(code: "CAD"))
        let normalizedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 40, weight: .bold),
            .foregroundColor: accentColor
        ]
        let normalizedSize = normalizedText.size(withAttributes: normalizedAttrs)
        normalizedText.draw(
            at: CGPoint(x: centerX - normalizedSize.width / 2, y: yPosition),
            withAttributes: normalizedAttrs
        )
        yPosition += 48

        let normalizedLabel = "Size-Adjusted Total (Recommended for CRA Line 33099)"
        let normalizedLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: secondaryColor
        ]
        let normalizedLabelSize = normalizedLabel.size(withAttributes: normalizedLabelAttrs)
        normalizedLabel.draw(
            at: CGPoint(x: centerX - normalizedLabelSize.width / 2, y: yPosition),
            withAttributes: normalizedLabelAttrs
        )
        yPosition += 28

        // Secondary: Simple Price Differential
        let totalText = totalDifferential.formatted(.currency(code: "CAD"))
        let totalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: primaryColor
        ]
        let totalSize = totalText.size(withAttributes: totalAttrs)
        totalText.draw(
            at: CGPoint(x: centerX - totalSize.width / 2, y: yPosition),
            withAttributes: totalAttrs
        )
        yPosition += 30

        let totalLabel = "Simple Price Differential Total (For Reference)"
        let totalLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: secondaryColor
        ]
        let totalLabelSize = totalLabel.size(withAttributes: totalLabelAttrs)
        totalLabel.draw(
            at: CGPoint(x: centerX - totalLabelSize.width / 2, y: yPosition),
            withAttributes: totalLabelAttrs
        )
        yPosition += 26

        // Excluded products note (if any)
        if normalizedExcluded > 0 {
            let excludedNote = "\(normalizedExcluded) product\(normalizedExcluded == 1 ? "" : "s") without size data not included in adjusted total"
            let excludedAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor.systemOrange
            ]
            let excludedSize = excludedNote.size(withAttributes: excludedAttrs)
            excludedNote.draw(
                at: CGPoint(x: centerX - excludedSize.width / 2, y: yPosition),
                withAttributes: excludedAttrs
            )
            yPosition += 20
        }

        yPosition += 14

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

        // Group by category — both simple and normalized differentials
        var categoryTotals: [String: Decimal] = [:]
        var categoryNormalized: [String: Decimal] = [:]
        var categoryCounts: [String: Int] = [:]

        for product in products {
            let category = product.category ?? "Uncategorized"
            categoryTotals[category, default: 0] += product.differential
            categoryCounts[category, default: 0] += 1
            if let nd = product.normalizedDifferential {
                categoryNormalized[category, default: 0] += nd
            }
        }

        // Sort by price differential (descending)
        let sortedCategories = categoryTotals.sorted { $0.value > $1.value }

        // Draw table with both metrics
        y = drawTable(
            context: context,
            contentRect: contentRect,
            yPosition: y,
            headers: ["Category", "Count", "Adj. Diff (CRA)", "Price Diff"],
            rows: sortedCategories.map { category, total in
                let adjTotal = categoryNormalized[category]?.formatted(.currency(code: "CAD")) ?? "—"
                return [
                    category,
                    String(categoryCounts[category] ?? 0),
                    adjTotal,
                    total.formatted(.currency(code: "CAD"))
                ]
            },
            columnWidths: [160, 60, 110, 110]
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

        // Group by month — both simple and normalized differentials
        let calendar = Calendar.current
        var monthlyTotals: [Date: Decimal] = [:]
        var monthlyNormalized: [Date: Decimal] = [:]
        var monthlyCounts: [Date: Int] = [:]

        for product in products {
            let components = calendar.dateComponents([.year, .month], from: product.reportingDate)
            guard let monthStart = calendar.date(from: components) else { continue }

            monthlyTotals[monthStart, default: 0] += product.differential
            monthlyCounts[monthStart, default: 0] += 1
            if let nd = product.normalizedDifferential {
                monthlyNormalized[monthStart, default: 0] += nd
            }
        }

        // Sort by date
        let sortedMonths = monthlyTotals.sorted { $0.key < $1.key }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"

        // Draw table with both metrics
        y = drawTable(
            context: context,
            contentRect: contentRect,
            yPosition: y,
            headers: ["Month", "Count", "Adj. Diff (CRA)", "Price Diff"],
            rows: sortedMonths.map { month, total in
                let adjTotal = monthlyNormalized[month]?.formatted(.currency(code: "CAD")) ?? "—"
                return [
                    dateFormatter.string(from: month),
                    String(monthlyCounts[month] ?? 0),
                    adjTotal,
                    total.formatted(.currency(code: "CAD"))
                ]
            },
            columnWidths: [160, 60, 110, 110]
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
                    if yPosition + estimatedRowHeight(for: product) > contentRect.maxY {
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

                // Receipt subtotals — both adjusted and simple
                let adjSubtotal = sortedProducts.compactMap(\.normalizedDifferential).reduce(Decimal.zero, +)
                let adjExcluded = sortedProducts.filter { $0.normalizedDifferential == nil }.count
                let priceSubtotal = sortedProducts.reduce(Decimal.zero) { $0 + $1.differential }

                let adjSubtotalText = "Adj. Subtotal (CRA): \(adjSubtotal.formatted(.currency(code: "CAD")))"
                let adjSubtotalAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: accentColor
                ]
                let adjSubtotalSize = adjSubtotalText.size(withAttributes: adjSubtotalAttrs)
                adjSubtotalText.draw(at: CGPoint(x: contentRect.maxX - adjSubtotalSize.width - 10, y: yPosition), withAttributes: adjSubtotalAttrs)
                yPosition += 16

                let priceSubtotalText = "Price Subtotal: \(priceSubtotal.formatted(.currency(code: "CAD")))"
                let priceSubtotalAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: secondaryColor
                ]
                let priceSubtotalSize = priceSubtotalText.size(withAttributes: priceSubtotalAttrs)
                priceSubtotalText.draw(at: CGPoint(x: contentRect.maxX - priceSubtotalSize.width - 10, y: yPosition), withAttributes: priceSubtotalAttrs)
                yPosition += 14

                if adjExcluded > 0 {
                    let excludedText = "\(adjExcluded) product\(adjExcluded == 1 ? "" : "s") without size data excluded from adjusted subtotal"
                    let excludedAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 9, weight: .light),
                        .foregroundColor: UIColor.systemOrange
                    ]
                    let excludedSize = excludedText.size(withAttributes: excludedAttrs)
                    excludedText.draw(at: CGPoint(x: contentRect.maxX - excludedSize.width - 10, y: yPosition), withAttributes: excludedAttrs)
                    yPosition += 12
                }

                yPosition += 8

                // MARK: - Receipt Image Section

                // Draw receipt image section (handles multi-page images and page breaks)
                drawReceiptImageSection(
                    context: context,
                    pageRect: pageRect,
                    contentRect: contentRect,
                    receipt: receipt,
                    verifiedProducts: sortedProducts,
                    receiptImage: receiptImages[receipt.id.uuidString],
                    yPosition: &yPosition,
                    pageNumber: &pageNumber
                )

                // yPosition and pageNumber are now updated by drawReceiptImageSection
            }
        }

        // MARK: - Unverified Products Section

        if !unverifiedProducts.isEmpty {
            // Check if we need a new page for unverified section (need space for title + warning + header)
            let unverifiedHeaderSpace: CGFloat = 130
            if yPosition + unverifiedHeaderSpace > contentRect.maxY || yPosition > contentRect.minY + 50 {
                // Start new page for unverified section (or if we're partway down a page)
                drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)
                context.beginPage()
                pageNumber += 1
                yPosition = contentRect.minY
            }

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
                if yPosition + estimatedRowHeight(for: product) > contentRect.maxY {
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

            // Unverified subtotals — both adjusted and simple
            let unvAdjSubtotal = unverifiedProducts.compactMap(\.normalizedDifferential).reduce(Decimal.zero, +)
            let unvAdjExcluded = unverifiedProducts.filter { $0.normalizedDifferential == nil }.count
            let unverifiedSubtotal = unverifiedProducts.reduce(Decimal.zero) { $0 + $1.differential }

            let unvAdjSubtotalText = "Adj. Subtotal (CRA): \(unvAdjSubtotal.formatted(.currency(code: "CAD")))"
            let unvAdjSubtotalAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.systemOrange
            ]
            let unvAdjSubtotalSize = unvAdjSubtotalText.size(withAttributes: unvAdjSubtotalAttrs)
            unvAdjSubtotalText.draw(at: CGPoint(x: contentRect.maxX - unvAdjSubtotalSize.width - 10, y: yPosition), withAttributes: unvAdjSubtotalAttrs)
            yPosition += 16

            let unvPriceSubtotalText = "Price Subtotal: \(unverifiedSubtotal.formatted(.currency(code: "CAD")))"
            let unvPriceSubtotalAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: secondaryColor
            ]
            let unvPriceSubtotalSize = unvPriceSubtotalText.size(withAttributes: unvPriceSubtotalAttrs)
            unvPriceSubtotalText.draw(at: CGPoint(x: contentRect.maxX - unvPriceSubtotalSize.width - 10, y: yPosition), withAttributes: unvPriceSubtotalAttrs)
            yPosition += 14

            if unvAdjExcluded > 0 {
                let excludedText = "\(unvAdjExcluded) product\(unvAdjExcluded == 1 ? "" : "s") without size data excluded from adjusted subtotal"
                let excludedAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .light),
                    .foregroundColor: UIColor.systemOrange
                ]
                let excludedSize = excludedText.size(withAttributes: excludedAttrs)
                excludedText.draw(at: CGPoint(x: contentRect.maxX - excludedSize.width - 10, y: yPosition), withAttributes: excludedAttrs)
                yPosition += 12
            }

            yPosition += 8
        }

        // Draw final footer
        drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: pageNumber)
    }

    /// Draws a receipt image section with verified products caption, handling multi-page images
    /// Returns the updated yPosition and pageNumber after drawing
    private func drawReceiptImageSection(
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        contentRect: CGRect,
        receipt: Receipt,
        verifiedProducts: [ProductPair],
        receiptImage: UIImage?,
        yPosition: inout CGFloat,
        pageNumber: inout Int
    ) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let titleText = "Receipt - \(receipt.storeName ?? "Unknown Store") - \(dateFormatter.string(from: receipt.purchaseDate))"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: primaryColor
        ]
        let titleHeight: CGFloat = 50
        let captionHeight: CGFloat = 60
        let minimumImageSpace: CGFloat = 150 // Minimum space needed to start drawing an image

        // Check if we need a new page for the title
        if yPosition + titleHeight + minimumImageSpace > contentRect.maxY {
            drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)
            context.beginPage()
            pageNumber += 1
            yPosition = contentRect.minY
        }

        // Draw title
        titleText.draw(at: CGPoint(x: contentRect.minX, y: yPosition), withAttributes: titleAttrs)
        yPosition += titleHeight

        // Draw receipt image (handling multi-page if needed)
        if let image = receiptImage {
            // Calculate scaled image dimensions with fixed width for compact display
            // Fixed receipt image width: 3 inches = 216 points (at 72 DPI)
            let maxReceiptWidth: CGFloat = 216
            let imageSize = image.size
            let aspectRatio = imageSize.height / imageSize.width
            let drawWidth = min(maxReceiptWidth, imageSize.width)
            let totalDrawHeight = drawWidth * aspectRatio
            let imageX = contentRect.minX + (contentRect.width - drawWidth) / 2

            var remainingHeight = totalDrawHeight
            var sourceYOffset: CGFloat = 0

            while remainingHeight > 0 {
                let availableHeight = contentRect.maxY - yPosition - captionHeight // Reserve space for caption on last chunk
                let isLastChunk = remainingHeight <= availableHeight

                // Determine how much to draw on this page
                let drawHeightOnPage: CGFloat
                if isLastChunk {
                    drawHeightOnPage = remainingHeight
                } else {
                    // Leave some space at bottom, but use most of available height
                    drawHeightOnPage = max(0, contentRect.maxY - yPosition - 20)
                    if drawHeightOnPage < minimumImageSpace {
                        // Not enough space on this page, start fresh on next page
                        drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)
                        context.beginPage()
                        pageNumber += 1
                        yPosition = contentRect.minY
                        continue
                    }
                }

                // Draw portion of image
                // Calculate the source rect (portion of original image to draw)
                let sourceYStart = sourceYOffset / totalDrawHeight * imageSize.height
                let sourceHeight = drawHeightOnPage / totalDrawHeight * imageSize.height
                let sourceRect = CGRect(x: 0, y: sourceYStart, width: imageSize.width, height: sourceHeight)

                // Crop the image to the source rect
                if let cgImage = image.cgImage,
                   let croppedCGImage = cgImage.cropping(to: sourceRect) {
                    let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
                    let destRect = CGRect(x: imageX, y: yPosition, width: drawWidth, height: drawHeightOnPage)
                    croppedImage.draw(in: destRect)
                }

                yPosition += drawHeightOnPage
                remainingHeight -= drawHeightOnPage
                sourceYOffset += drawHeightOnPage

                // If more to draw, start new page
                if remainingHeight > 0 {
                    drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)
                    context.beginPage()
                    pageNumber += 1
                    yPosition = contentRect.minY

                    // Draw continuation header
                    let continuationText = "Receipt (continued) - \(receipt.storeName ?? "Unknown Store")"
                    let continuationAttrs: [NSAttributedString.Key: Any] = [
                        .font: headingFont,
                        .foregroundColor: secondaryColor
                    ]
                    continuationText.draw(at: CGPoint(x: contentRect.minX, y: yPosition), withAttributes: continuationAttrs)
                    yPosition += 30
                }
            }

            yPosition += 20 // Space after image

        } else {
            // Image not available
            let noImageText = "Receipt Image Not Available"
            let noImageAttrs: [NSAttributedString.Key: Any] = [
                .font: headingFont,
                .foregroundColor: secondaryColor
            ]
            let noImageSize = noImageText.size(withAttributes: noImageAttrs)
            noImageText.draw(at: CGPoint(x: contentRect.minX + (contentRect.width - noImageSize.width) / 2, y: yPosition + 50), withAttributes: noImageAttrs)
            yPosition += 120
        }

        // Check if caption fits on current page
        if yPosition + captionHeight > contentRect.maxY {
            drawFooter(context: context.cgContext, pageRect: pageRect, pageNumber: pageNumber, totalPages: nil)
            context.beginPage()
            pageNumber += 1
            yPosition = contentRect.minY
        }

        // Caption: Verified Products
        let productNames = verifiedProducts.map { $0.gfProductName }.joined(separator: ", ")
        let caption = "Verified Products: \(productNames)"
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: secondaryColor
        ]
        let captionRect = CGRect(x: contentRect.minX, y: yPosition, width: contentRect.width, height: captionHeight)
        caption.draw(in: captionRect, withAttributes: captionAttrs)
        yPosition += captionHeight + 20
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

        // Grand totals — both adjusted and simple
        yPosition += 10
        let grandPriceTotal = calculateTotalDifferential(products: products)
        let grandNormalizedResult = calculateNormalizedDifferential(products: products)
        yPosition = drawGrandTotals(
            context: context.cgContext,
            contentRect: contentRect,
            yPosition: yPosition,
            normalizedTotal: grandNormalizedResult.total,
            priceTotal: grandPriceTotal
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
        let headers = ["Date", "GF Product", "GF $", "Regular", "Reg $", "Price Diff", "Adj. Diff (CRA)"]
        let columnWidths: [CGFloat] = [60, 100, 42, 100, 42, 54, 53]

        var x = contentRect.minX
        let y = yPosition

        // Background - darker blue for better contrast
        context.setFillColor(primaryColor.withAlphaComponent(0.15).cgColor)
        context.fill(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 20))

        // Headers - dark blue text on light blue background for contrast
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: primaryColor
        ]

        for (index, header) in headers.enumerated() {
            header.draw(at: CGPoint(x: x + 4, y: y + 4), withAttributes: headerAttrs)
            x += columnWidths[index]
        }

        return y + 22
    }

    /// Returns the estimated total height for a product row
    private func estimatedRowHeight(for product: ProductPair) -> CGFloat {
        return 20
    }

    private func drawTransactionRow(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat,
        product: ProductPair,
        dateFormatter: DateFormatter,
        isAlternate: Bool
    ) -> CGFloat {
        let columnWidths: [CGFloat] = [60, 100, 42, 100, 42, 54, 53]
        let rowHeight: CGFloat = 18

        var x = contentRect.minX
        let y = yPosition

        // Alternating row background
        if isAlternate {
            context.setFillColor(UIColor.systemGray6.cgColor)
            context.fill(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: rowHeight))
        }

        // Adjusted differential: show value if available, dash if not
        let adjDiffStr: String
        if let nd = product.normalizedDifferential {
            adjDiffStr = String(format: "%.2f", NSDecimalNumber(decimal: nd).doubleValue)
        } else {
            adjDiffStr = "—"
        }

        // Row data (7 columns — Store removed, Adj. Diff promoted to full column)
        let rowData = [
            dateFormatter.string(from: product.reportingDate),
            product.gfProductName.truncated(to: 14),
            String(format: "%.2f", NSDecimalNumber(decimal: product.gfPrice).doubleValue),
            product.nonGFProductName.truncated(to: 14),
            String(format: "%.2f", NSDecimalNumber(decimal: product.nonGFPrice).doubleValue),
            String(format: "%.2f", NSDecimalNumber(decimal: product.differential).doubleValue),
            adjDiffStr
        ]

        let cellAttrs: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: UIColor.label
        ]

        // Highlight the Adj. Diff column in green when available
        let adjCellAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: product.normalizedDifferential != nil ? accentColor : UIColor.systemGray3
        ]

        for (index, data) in rowData.enumerated() {
            let attrs = (index == 6) ? adjCellAttrs : cellAttrs
            data.draw(at: CGPoint(x: x + 4, y: y + 4), withAttributes: attrs)
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

    private func drawGrandTotals(
        context: CGContext,
        contentRect: CGRect,
        yPosition: CGFloat,
        normalizedTotal: Decimal,
        priceTotal: Decimal
    ) -> CGFloat {
        var y = yPosition

        // Background for both rows
        context.setFillColor(accentColor.withAlphaComponent(0.08).cgColor)
        context.fill(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 48))

        // Row 1: Size-Adjusted Grand Total (primary / CRA)
        let adjTotalText = "Size-Adjusted Grand Total (CRA Line 33099): \(normalizedTotal.formatted(.currency(code: "CAD")))"
        let adjTotalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: accentColor
        ]
        let adjSize = adjTotalText.size(withAttributes: adjTotalAttrs)
        adjTotalText.draw(
            at: CGPoint(x: contentRect.maxX - adjSize.width - 10, y: y + 6),
            withAttributes: adjTotalAttrs
        )
        y += 24

        // Row 2: Price Differential Grand Total (for reference)
        let priceTotalText = "Price Differential Grand Total (For Reference): \(priceTotal.formatted(.currency(code: "CAD")))"
        let priceTotalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: primaryColor
        ]
        let priceSize = priceTotalText.size(withAttributes: priceTotalAttrs)
        priceTotalText.draw(
            at: CGPoint(x: contentRect.maxX - priceSize.width - 10, y: y + 4),
            withAttributes: priceTotalAttrs
        )

        return y + 26
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

        // Header row - darker blue for better contrast
        context.setFillColor(primaryColor.withAlphaComponent(0.15).cgColor)
        context.fill(CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: rowHeight))

        var x = contentRect.minX
        // Dark blue text on light blue background for contrast
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: primaryColor
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

    private func calculateNormalizedDifferential(products: [ProductPair]) -> (total: Decimal, excludedCount: Int) {
        var total = Decimal.zero
        var excluded = 0
        for product in products {
            if let nd = product.normalizedDifferential {
                total += nd
            } else {
                excluded += 1
            }
        }
        return (total: total, excludedCount: excluded)
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
