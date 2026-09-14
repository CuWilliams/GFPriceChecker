//
//  SampleScanImages.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-09-13.
//

#if DEBUG
import UIKit

/// Synthetic shelf tags and receipts, drawn at runtime, for driving the capture
/// flows where there is no camera.
///
/// The Simulator has no `VNDocumentCameraViewController`, so until now the capture
/// flows dead-ended at the scanner sheet (see `docs/SCRIPTED_DEMO_PIPELINE.md`,
/// Blocker 1). `SubstituteScannerView` offers these in the camera's place.
///
/// They are *drawn*, not bundled, for three reasons: nothing binary lands in the
/// repo, the text is crisp enough that Vision reads it at high confidence every
/// time, and a new sample is a struct literal rather than a photo shoot.
///
/// The content is deliberately shaped to exercise the parsers rather than merely
/// survive them:
///
/// - The shelf price is the largest text on the tag, so `OCRService`'s spatial
///   ranking has to prefer it over the unit price sitting two lines below it.
/// - Sizes read `400 g` and unit prices `$1.87 /100 g`, which is what
///   `parseSizeFromOCR` and `parseUnitPriceFromOCR` match against.
/// - The receipt carries a store in `ReceiptParserService.commonStores`, an ISO
///   date, and a `TOTAL` line below a `SUBTOTAL` line it must not pick instead.
///   It prints in two columns with bare amounts, as receipts do, which is the
///   layout `extractTotal` could not read until issue #51.
///
/// Brands are invented. These images end up on screen in demo recordings, so no
/// real brand is put in a frame the project does not own.
enum SampleScanImages {

    // MARK: - Content

    /// A grocery shelf price tag.
    struct ShelfTag: Sendable {
        let brand: String
        /// Product name. Wraps to a second line when long.
        let name: String
        /// Shelf price, as printed: `"$7.49"`.
        let price: String
        /// Package size, in a form `parseSizeFromOCR` matches: `"400 g"`.
        let size: String
        /// Unit price, in a form `parseUnitPriceFromOCR` matches: `"$1.87 /100 g"`.
        let unitPrice: String
    }

    /// A grocery receipt.
    struct Receipt: Sendable {
        struct Line: Sendable {
            let name: String
            /// Bare amount without a currency symbol, as receipts print it.
            let amount: String
        }

        let store: String
        let address: String
        let city: String
        /// ISO `yyyy-MM-dd`, the first pattern `extractDate` tries.
        let date: String
        let time: String
        let lines: [Line]
        let subtotal: String
        let tax: String
        let total: String
    }

    /// How a receipt prints its label/amount rows.
    ///
    /// Both are shapes real receipts take, and they stress the parser
    /// differently, so the catalog can render either.
    enum RowStyle: Sendable {
        /// Label and amount one space apart, the row as a whole pushed to the
        /// right margin, amounts carrying whatever symbol the data holds.
        /// Vision reads the pair as one observation, so label and amount
        /// arrive on the same line of reassembled text.
        case inline

        /// Label at the left margin, bare amount right-aligned at the right
        /// one — the two-column layout receipts actually print. Vision returns
        /// each column as its own observation, so the label's line carries no
        /// amount at all. See issue #51.
        case twoColumn
    }

    // MARK: - Catalog

    static let glutenFreeBread = ShelfTag(
        brand: "NORTHFIELD",
        name: "Gluten Free White Bread",
        price: "$7.49",
        size: "400 g",
        unitPrice: "$1.87 /100 g"
    )

    static let regularBread = ShelfTag(
        brand: "PANTRY LANE",
        name: "White Sandwich Bread",
        price: "$3.29",
        size: "570 g",
        unitPrice: "$0.58 /100 g"
    )

    static let glutenFreePenne = ShelfTag(
        brand: "NORTHFIELD",
        name: "Gluten Free Penne",
        price: "$4.99",
        size: "340 g",
        unitPrice: "$1.47 /100 g"
    )

    static let regularPenne = ShelfTag(
        brand: "PANTRY LANE",
        name: "Penne Rigate",
        price: "$1.89",
        size: "900 g",
        unitPrice: "$0.21 /100 g"
    )

    /// A receipt covering all four tags above, so it can verify pairs built from them.
    static let groceryReceipt = Receipt(
        store: "LOBLAWS",
        address: "1234 QUEEN STREET WEST",
        city: "TORONTO ON  M6J 1J5",
        date: "2026-03-14",
        time: "14:32",
        lines: [
            .init(name: "NORTHFIELD GF WHITE BREAD", amount: "7.49"),
            .init(name: "PANTRY LANE WHITE BREAD", amount: "3.29"),
            .init(name: "NORTHFIELD GF PENNE", amount: "4.99"),
            .init(name: "PANTRY LANE PENNE RIGATE", amount: "1.89")
        ],
        subtotal: "$17.66",
        tax: "$2.30",
        total: "$19.96"
    )

    /// The shelf tags with the catalog id each is offered under. `catalog` is
    /// built from this, so a tag cannot appear in the picker under one price
    /// and in a test under another.
    static let shelfTags: [(id: String, title: String, tag: ShelfTag)] = [
        ("gf-bread", "Gluten-Free Bread", glutenFreeBread),
        ("regular-bread", "Regular Bread", regularBread),
        ("gf-penne", "Gluten-Free Penne", glutenFreePenne),
        ("regular-penne", "Regular Penne", regularPenne)
    ]

    /// Everything offered in `SubstituteScannerView`, in the order a capture
    /// walkthrough uses it: gluten-free tag, its regular counterpart, then the
    /// receipt that verifies the pair.
    @MainActor
    static var catalog: [Sample] {
        shelfTags.map { entry in
            Sample(id: entry.id,
                   title: entry.title,
                   detail: "Shelf tag · \(entry.tag.price)",
                   image: { shelfTag(entry.tag) })
        } + [
            Sample(id: "receipt",
                   title: "Grocery Receipt",
                   detail: "\(groceryReceipt.store.capitalized) · \(groceryReceipt.lines.count) items · \(groceryReceipt.total)",
                   image: { receipt(groceryReceipt) })
        ]
    }

    /// One entry in the substitute scanner's picker. The image is built on demand
    /// so opening the sheet does not render all five.
    @MainActor
    struct Sample: Identifiable {
        let id: String
        let title: String
        let detail: String
        let image: @MainActor () -> UIImage
    }

    // MARK: - Shelf Tag Rendering

    private enum TagLayout {
        static let size = CGSize(width: 1000, height: 1300)
        static let margin: CGFloat = 80
    }

    /// Draws a shelf price tag.
    @MainActor
    static func shelfTag(_ tag: ShelfTag) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: TagLayout.size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: TagLayout.size)
            paper(in: context.cgContext, bounds: bounds)

            let content = bounds.insetBy(dx: TagLayout.margin, dy: TagLayout.margin)
            var y = content.minY

            y += draw(tag.brand,
                      font: .systemFont(ofSize: 58, weight: .heavy),
                      color: .darkGray,
                      in: CGRect(x: content.minX, y: y, width: content.width, height: 120))
            y += 16

            y += draw(tag.name,
                      font: .systemFont(ofSize: 76, weight: .semibold),
                      color: .black,
                      in: CGRect(x: content.minX, y: y, width: content.width, height: 260))
            y += 40

            rule(in: context.cgContext, y: y, from: content.minX, to: content.maxX)
            y += 50

            // The shelf price has to be the biggest thing on the tag: OCRService
            // weights font size at 50% when it ranks price candidates.
            y += draw(tag.price,
                      font: .systemFont(ofSize: 210, weight: .bold),
                      color: .black,
                      in: CGRect(x: content.minX, y: y, width: content.width, height: 280))
            y += 30

            y += draw(tag.size,
                      font: .systemFont(ofSize: 64, weight: .medium),
                      color: .black,
                      in: CGRect(x: content.minX, y: y, width: content.width, height: 100))
            y += 12

            _ = draw(tag.unitPrice,
                     font: .systemFont(ofSize: 48, weight: .regular),
                     color: .darkGray,
                     in: CGRect(x: content.minX, y: y, width: content.width, height: 90))
        }
    }

    // MARK: - Receipt Rendering

    private enum ReceiptLayout {
        static let size = CGSize(width: 900, height: 1500)
        static let margin: CGFloat = 70
        static let body: CGFloat = 34
        static let lineHeight: CGFloat = 52
    }

    /// Draws a receipt in the given row style.
    ///
    /// Defaults to `.twoColumn`, the way a receipt actually prints. It could
    /// not before issue #51 was fixed — `extractTotal` needed the label and a
    /// `$` amount on one line, which only `.inline` gave it — so the sample in
    /// the catalog, and with it every demo recording made from it, was drawn to
    /// suit the parser.
    @MainActor
    static func receipt(_ receipt: Receipt, style: RowStyle = .twoColumn) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: ReceiptLayout.size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: ReceiptLayout.size)
            paper(in: context.cgContext, bounds: bounds)

            let content = bounds.insetBy(dx: ReceiptLayout.margin, dy: ReceiptLayout.margin)
            var y = content.minY

            // Header. extractStoreName only reads the first five lines, so the
            // store name goes first and nothing precedes it.
            y += draw(receipt.store,
                      font: .monospacedSystemFont(ofSize: 62, weight: .bold),
                      color: .black,
                      in: CGRect(x: content.minX, y: y, width: content.width, height: 90),
                      alignment: .center)
            y += 10

            for line in [receipt.address, receipt.city] {
                y += draw(line,
                          font: .monospacedSystemFont(ofSize: ReceiptLayout.body, weight: .regular),
                          color: .black,
                          in: CGRect(x: content.minX, y: y, width: content.width, height: 60),
                          alignment: .center)
            }
            y += 30

            y += draw("\(receipt.date) \(receipt.time)",
                      font: .monospacedSystemFont(ofSize: ReceiptLayout.body, weight: .regular),
                      color: .black,
                      in: CGRect(x: content.minX, y: y, width: content.width, height: 60),
                      alignment: .center)
            y += 30

            rule(in: context.cgContext, y: y, from: content.minX, to: content.maxX)
            y += 30

            for line in receipt.lines {
                drawRow(line.name, line.amount, y: y, in: content, weight: .regular, style: style)
                y += ReceiptLayout.lineHeight
            }

            y += 20
            rule(in: context.cgContext, y: y, from: content.minX, to: content.maxX)
            y += 30

            drawRow("SUBTOTAL", receipt.subtotal, y: y, in: content, weight: .regular, style: style)
            y += ReceiptLayout.lineHeight
            drawRow("HST 13%", receipt.tax, y: y, in: content, weight: .regular, style: style)
            y += ReceiptLayout.lineHeight + 10

            // extractTotal scans upward for a line containing "total" that is
            // not "subtotal", so TOTAL has to sit below SUBTOTAL and be found
            // in spite of it.
            drawRow("TOTAL", receipt.total, y: y, in: content, weight: .bold, style: style)
            y += ReceiptLayout.lineHeight + 40

            _ = draw("THANK YOU FOR SHOPPING",
                     font: .monospacedSystemFont(ofSize: 34, weight: .regular),
                     color: .darkGray,
                     in: CGRect(x: content.minX, y: y, width: content.width, height: 60),
                     alignment: .center)
        }
    }

    /// Draws a receipt row.
    ///
    /// `.twoColumn` is how a receipt actually prints — label at the left
    /// margin, bare amount right-aligned at the right one — and Vision returns
    /// each column as its own observation across that gap. What was measured
    /// while building this, in descending order of what was tried:
    ///
    /// - Two columns, amount right-aligned at the margin: every amount comes
    ///   back as its own observation, so the label's line carries no amount.
    /// - Dot leaders across the gap: worse. Vision reads the run of dots as a
    ///   separate bullet token and splits into three.
    /// - A two-space gap: splits unpredictably — `PANTRY LANE WHITE BREAD 3.29`
    ///   held together while `NORTHFIELD GF WHITE BREAD 7.49` broke in two.
    /// - A single space: holds. It is ordinary word spacing, so there is no gap
    ///   for the recognizer to treat as a column break.
    ///
    /// `.inline` is that last case: the row pushed to the right margin as a
    /// unit so the amounts stay within a character or two of a column while
    /// the separator stays a single space, leaving only the labels ragged.
    ///
    /// Both layouts are kept because both are real. `.inline` is the one the
    /// parser could read before issue #51; `.twoColumn` is the one it could
    /// not, and `SubstituteScannerTests` runs the receipt tests over both so a
    /// fix cannot regress either.
    @MainActor
    private static func drawRow(
        _ label: String,
        _ amount: String,
        y: CGFloat,
        in content: CGRect,
        weight: UIFont.Weight,
        style: RowStyle
    ) {
        let font = UIFont.monospacedSystemFont(ofSize: ReceiptLayout.body, weight: weight)
        let row = CGRect(x: content.minX, y: y,
                         width: content.width, height: ReceiptLayout.lineHeight)

        switch style {
        case .inline:
            _ = draw("\(label) \(amount)", font: font, color: .black,
                     in: row, alignment: .right)

        case .twoColumn:
            // Real receipts print the amount bare; the symbol, if it appears at
            // all, is in the header.
            let bare = amount.replacingOccurrences(of: "$", with: "")
            _ = draw(label, font: font, color: .black, in: row, alignment: .left)
            _ = draw(bare, font: font, color: .black, in: row, alignment: .right)
        }
    }

    // MARK: - Drawing Primitives

    /// Fills the page and outlines it, so the scan reads as a piece of paper
    /// rather than as a screenshot.
    @MainActor
    private static func paper(in context: CGContext, bounds: CGRect) {
        context.setFillColor(UIColor(white: 0.98, alpha: 1).cgColor)
        context.fill(bounds)
        context.setStrokeColor(UIColor(white: 0.75, alpha: 1).cgColor)
        context.setLineWidth(6)
        context.stroke(bounds.insetBy(dx: 3, dy: 3))
    }

    @MainActor
    private static func rule(in context: CGContext, y: CGFloat, from minX: CGFloat, to maxX: CGFloat) {
        context.setStrokeColor(UIColor(white: 0.7, alpha: 1).cgColor)
        context.setLineWidth(3)
        context.move(to: CGPoint(x: minX, y: y))
        context.addLine(to: CGPoint(x: maxX, y: y))
        context.strokePath()
    }

    /// Draws text into `rect` and returns the height it actually used, so callers
    /// can stack elements without hard-coding where a wrapped line lands.
    @MainActor
    @discardableResult
    private static func draw(
        _ text: String,
        font: UIFont,
        color: UIColor,
        in rect: CGRect,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)

        let used = attributed.boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
        return ceil(used.height)
    }
}
#endif
