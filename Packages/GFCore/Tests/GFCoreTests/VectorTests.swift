//
//  VectorTests.swift
//  GFCoreTests
//
//  Created by Claude Code on 2026-10-31 (#71).
//

import Foundation
import Testing
import GFCore

/// The cross-platform test vectors, run against GFCore
///
/// The vectors are normative (PRODUCT_DEFINITION.md): any implementation of the product, on
/// any platform, must pass every one. Their source is `gfpricechecker/vectors/` in
/// shared-docs; `Vectors/` here is a vendored copy, kept identical by
/// `scripts/sync-vectors.sh`. Conventions — decimals as strings, how precision is matched,
/// float tolerance, dates — are in `Vectors/README.md`.
@Suite("Cross-platform vectors")
struct VectorTests {

    // MARK: - Pricing

    @Test("pricing.json: the differentials")
    func pricingPairs() throws {
        for testCase in try Vectors.load("pricing.json")["pairs"].array {
            let name = testCase["name"].string
            let pricing = Vectors.pricing(testCase["input"])
            let expected = testCase["expected"]
            let figures: [(String, Decimal?)] = [
                ("differential", pricing.differential),
                ("gfUnitPrice", pricing.gfUnitPrice),
                ("regularUnitPrice", pricing.regularUnitPrice),
                ("unitPriceDifferential", pricing.unitPriceDifferential),
                ("normalizedDifferential", pricing.normalizedDifferential),
                ("extendedDifferential", pricing.extendedDifferential),
                ("extendedNormalizedDifferential", pricing.extendedNormalizedDifferential),
            ]
            for (key, actual) in figures where expected.has(key) {
                Vectors.expectDecimal(actual, expected[key], "\(name): \(key)")
            }
        }
    }

    @Test("pricing.json: package size from a unit price")
    func pricingPackageSize() throws {
        for testCase in try Vectors.load("pricing.json")["packageSize"].array {
            let input = testCase["input"]
            let basis: UnitPriceBasis = input["basis"].string == "cents" ? .cents : .dollars
            let actual = PricingInputs.packageSize(
                price: Vectors.decimal(input["price"]),
                unitPrice: Vectors.decimal(input["unitPrice"]),
                basis: basis
            )
            Vectors.expectDecimal(actual, testCase["expected"], testCase["name"].string)
        }
    }

    @Test("pricing.json: size and unit price text")
    func pricingSizeText() throws {
        let vectors = try Vectors.load("pricing.json")
        for (group, parse) in [("parseSize", SizeTextParser.parseSize), ("parseUnitPrice", SizeTextParser.parseUnitPrice)] {
            for testCase in vectors[group].array {
                let input = testCase["input"].string
                let actual = parse(input)
                #expect(actual.value == testCase["expected"]["value"].string, "\(group): \(input)")
                #expect(actual.unit?.rawValue == testCase["expected"]["unit"].optionalString, "\(group): \(input)")
            }
        }
    }

    @Test("pricing.json: size units")
    func pricingSizeUnits() throws {
        let cases = try Vectors.load("pricing.json")["sizeUnits"].array
        #expect(cases.map { $0["unit"].string } == SizeUnit.allCases.map(\.rawValue))
        for testCase in cases {
            let unit = try #require(SizeUnit(rawValue: testCase["unit"].string))
            #expect(unit.unitPriceScaleFactor == Vectors.decimal(testCase["unitPriceScaleFactor"]), "\(unit)")
            #expect(unit.unitPriceLabel == testCase["unitPriceLabel"].string, "\(unit)")
        }
    }

    // MARK: - Reporting

    @Test("reporting.json: totals")
    func reportingTotals() throws {
        for testCase in try Vectors.load("reporting.json")["totals"].array {
            let totals = ReportCalculator.totals(Vectors.rows(testCase["input"]["rows"]))
            Vectors.expectTotals(totals, testCase["expected"], testCase["name"].string)
        }
    }

    @Test("reporting.json: year filter")
    func reportingYearFilter() throws {
        for testCase in try Vectors.load("reporting.json")["yearFilter"].array {
            let input = testCase["input"]
            let calculator = ReportCalculator(calendar: Vectors.calendar(input["timeZone"]))
            let kept = calculator.rows(Vectors.rows(input["rows"]), inYear: input["year"].int)
            #expect(kept.map(\.id) == testCase["expected"].array.map(Vectors.uuid), "\(testCase["name"].string)")
        }
    }

    @Test("reporting.json: available years")
    func reportingAvailableYears() throws {
        for testCase in try Vectors.load("reporting.json")["availableYears"].array {
            let input = testCase["input"]
            let calculator = ReportCalculator(calendar: Vectors.calendar(input["timeZone"]))
            #expect(
                calculator.availableYears(Vectors.rows(input["rows"])) == testCase["expected"].array.map(\.int),
                "\(testCase["name"].string)"
            )
        }
    }

    @Test("reporting.json: range filter")
    func reportingRangeFilter() throws {
        for testCase in try Vectors.load("reporting.json")["rangeFilter"].array {
            let input = testCase["input"]
            let range = input["range"].isNull
                ? nil
                : Vectors.date(input["range"]["start"])...Vectors.date(input["range"]["end"])
            let kept = ReportCalculator.rows(Vectors.rows(input["rows"]), in: range)
            #expect(kept.map(\.id) == testCase["expected"].array.map(Vectors.uuid), "\(testCase["name"].string)")
        }
    }

    @Test("reporting.json: export date ranges")
    func reportingDateRange() throws {
        for testCase in try Vectors.load("reporting.json")["dateRange"].array {
            let input = testCase["input"]
            let name = testCase["name"].string
            let preset = try #require(DateRangePreset(rawValue: input["preset"].string), "\(name)")
            let calculator = ReportCalculator(calendar: Vectors.calendar(input["timeZone"]))
            let range = calculator.dateRange(for: preset, now: Vectors.date(input["now"]))
            if testCase["expected"].isNull {
                #expect(range == nil, "\(name)")
            } else {
                #expect(range?.lowerBound == Vectors.date(testCase["expected"]["start"]), "\(name): start")
                #expect(range?.upperBound == Vectors.date(testCase["expected"]["end"]), "\(name): end")
            }
        }
    }

    @Test("reporting.json: by category")
    func reportingByCategory() throws {
        for testCase in try Vectors.load("reporting.json")["byCategory"].array {
            let groups = ReportCalculator.byCategory(Vectors.rows(testCase["input"]["rows"]))
            Vectors.expectGroups(groups.map { ($0.key, $0.totals) }, testCase["expected"], key: "key",
                                 keyValue: \.string, testCase["name"].string)
        }
    }

    @Test("reporting.json: by month")
    func reportingByMonth() throws {
        for testCase in try Vectors.load("reporting.json")["byMonth"].array {
            let input = testCase["input"]
            let calculator = ReportCalculator(calendar: Vectors.calendar(input["timeZone"]))
            let groups = calculator.byMonth(Vectors.rows(input["rows"]))
            Vectors.expectGroups(groups.map { ($0.key, $0.totals) }, testCase["expected"], key: "monthStart",
                                 keyValue: Vectors.date, testCase["name"].string)
        }
    }

    @Test("reporting.json: the demo dataset")
    func reportingDemoDataset() throws {
        let testCase = try Vectors.load("reporting.json")["demoDataset"]
        let input = testCase["input"]
        let expected = testCase["expected"]
        let rows = Vectors.rows(input["rows"])
        let calculator = ReportCalculator(calendar: Vectors.calendar(input["timeZone"]))
        let totals = ReportCalculator.totals(rows)

        Vectors.expectTotals(totals, expected["totals"], "demo totals")
        Vectors.expectTotals(totals, expected["totalsAsDisplayed"], "demo totals as displayed")
        #expect(calculator.availableYears(rows) == expected["availableYears"].array.map(\.int))
        Vectors.expectGroups(ReportCalculator.byCategory(rows).map { ($0.key, $0.totals) }, expected["byCategory"],
                             key: "key", keyValue: \.string, "demo by category")
        Vectors.expectGroups(calculator.byMonth(rows).map { ($0.key, $0.totals) }, expected["byMonth"],
                             key: "monthStart", keyValue: Vectors.date, "demo by month")
    }

    // MARK: - CSV

    @Test("csv.json: headers")
    func csvHeaders() throws {
        #expect(CSVExporter.headers == (try Vectors.load("csv.json"))["headers"].array.map(\.string))
    }

    @Test("csv.json: files")
    func csvFiles() throws {
        for testCase in try Vectors.load("csv.json")["files"].array {
            let input = testCase["input"]
            let csv = CSVExporter.generate(rows: Vectors.rows(input["rows"]), timeZone: Vectors.timeZone(input["timeZone"]))
            let expected = testCase["expected"].string
            #expect(csv == expected, "\(testCase["name"].string)")
            if csv != expected {
                let actualLines = csv.components(separatedBy: "\n")
                let expectedLines = expected.components(separatedBy: "\n")
                for (index, pair) in zip(actualLines, expectedLines).enumerated() where pair.0 != pair.1 {
                    Issue.record("\(testCase["name"].string), line \(index + 1)\n  got:      \(pair.0)\n  expected: \(pair.1)")
                    break
                }
            }
        }
    }

    // MARK: - Receipt parsing

    @Test("receipt-parsing.json: store name")
    func receiptStoreName() throws {
        for testCase in try Vectors.load("receipt-parsing.json")["storeName"].array {
            let input = testCase["input"].string
            #expect(ReceiptParser.extractStoreName(from: input) == testCase["expected"].optionalString, "\(input)")
        }
    }

    @Test("receipt-parsing.json: date")
    func receiptDate() throws {
        // A receipt date has no time zone: it is that calendar day wherever the device is
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for testCase in try Vectors.load("receipt-parsing.json")["date"].array {
            let input = testCase["input"].string
            let actual = ReceiptParser.extractDate(from: input).map(formatter.string(from:))
            #expect(actual == testCase["expected"].optionalString, "\(input)")
        }
    }

    @Test("receipt-parsing.json: line items")
    func receiptLineItems() throws {
        for testCase in try Vectors.load("receipt-parsing.json")["lineItems"].array {
            let name = testCase["name"].string
            let items = ReceiptParser.extractLineItems(from: testCase["input"].string)
            let expected = testCase["expected"].array
            #expect(items.count == expected.count, "\(name): \(items)")
            for (item, want) in zip(items, expected) {
                #expect(item.productName == want["productName"].string, "\(name)")
                #expect(item.price == Vectors.decimal(want["price"]), "\(name): \(item.productName)")
                Vectors.expectFloat(item.confidence, want["confidence"], "\(name): \(item.productName)")
            }
        }
    }

    @Test("receipt-parsing.json: total")
    func receiptTotal() throws {
        for testCase in try Vectors.load("receipt-parsing.json")["total"].array {
            let actual = ReceiptParser.extractTotal(from: testCase["input"].string)
            #expect(actual == Vectors.optionalDecimal(testCase["expected"]), "\(testCase["name"].string)")
        }
    }

    @Test("receipt-parsing.json: matching")
    func receiptMatching() throws {
        for testCase in try Vectors.load("receipt-parsing.json")["matching"].array {
            let name = testCase["name"].string
            let candidates = testCase["input"]["candidates"].array.map {
                MatchCandidate(id: Vectors.uuid($0["id"]), name: $0["name"].string, price: Vectors.decimal($0["price"]))
            }
            let lineItems = testCase["input"]["lineItems"].array.map {
                ReceiptLineItem(productName: $0["productName"].string, price: Vectors.decimal($0["price"]),
                                confidence: $0["confidence"].float)
            }
            let results = ReceiptParser.matchProducts(candidates, to: lineItems)
            let expected = testCase["expected"].array
            #expect(results.count == expected.count, "\(name)")
            for (result, want) in zip(results, expected) {
                #expect(result.candidate.id == Vectors.uuid(want["candidateId"]), "\(name)")
                let index = want["matchedLineItem"]
                #expect(result.matchedLineItem == (index.isNull ? nil : lineItems[index.int]), "\(name)")
                Vectors.expectFloat(result.matchConfidence, want["matchConfidence"], "\(name)")
                #expect("\(result.matchQuality)" == want["matchQuality"].string, "\(name)")
                #expect(result.isAutoSuggested == want["isAutoSuggested"].bool, "\(name)")
            }
        }
    }

    @Test("receipt-parsing.json: match quality bands")
    func receiptMatchQuality() throws {
        let candidate = MatchCandidate(id: UUID(), name: "", price: 0)
        for testCase in try Vectors.load("receipt-parsing.json")["matchQuality"].array {
            let result = ProductMatchResult(candidate: candidate, matchedLineItem: nil, matchConfidence: testCase["input"].float)
            #expect("\(result.matchQuality)" == testCase["expected"]["matchQuality"].string, "\(testCase["input"].float)")
            #expect(result.isAutoSuggested == testCase["expected"]["isAutoSuggested"].bool, "\(testCase["input"].float)")
        }
    }

    // MARK: - Price ranking

    @Test("price-ranking.json: price candidates")
    func rankingPrices() throws {
        for testCase in try Vectors.load("price-ranking.json")["prices"].array {
            let name = testCase["name"].string
            let matches = PriceRanking.prices(in: testCase["input"].array.map(Vectors.recognizedText))
            let expected = testCase["expected"].array
            #expect(matches.count == expected.count, "\(name): \(matches.map(\.amount))")
            for (match, want) in zip(matches, expected) {
                #expect(match.amount == Vectors.decimal(want["amount"]), "\(name)")
                #expect(match.hasPrefix == want["hasPrefix"].bool, "\(name): \(match.amount)")
                Vectors.expectDouble(match.fontSize, want["fontSize"], "\(name): \(match.amount) font size")
                Vectors.expectDouble(match.verticalPosition, want["verticalPosition"], "\(name): \(match.amount) position")
                Vectors.expectFloat(match.rankingScore, want["rankingScore"], "\(name): \(match.amount) score")
                #expect("\(match.quality)" == want["quality"].string, "\(name): \(match.amount)")
            }
        }
    }

    @Test("price-ranking.json: price quality")
    func rankingPriceQuality() throws {
        for testCase in try Vectors.load("price-ranking.json")["priceQuality"].array {
            let confidence = testCase["input"].float
            #expect("\(PriceQuality(confidence: confidence))" == testCase["expected"].string, "\(confidence)")
        }
    }

    @Test("price-ranking.json: product name")
    func rankingProductName() throws {
        for testCase in try Vectors.load("price-ranking.json")["productName"].array {
            let actual = PriceRanking.productName(in: testCase["input"].array.map(Vectors.recognizedText))
            #expect(actual == testCase["expected"].optionalString, "\(testCase["name"].string)")
        }
    }

    @Test("price-ranking.json: selectable text")
    func rankingSelectableText() throws {
        for testCase in try Vectors.load("price-ranking.json")["selectableText"].array {
            let input = testCase["input"]
            let region = input["region"].isNull ? nil : Vectors.rect(input["region"])
            let actual = TextOrdering.selectableText(input["observations"].array.map(Vectors.recognizedText), in: region)
            #expect(actual.map(\.text) == testCase["expected"].array.map(\.string), "\(testCase["name"].string)")
        }
    }

    @Test("price-ranking.json: receipt text")
    func rankingReceiptText() throws {
        let regions: [String: TextOrdering.ReceiptRegion] = ["top": .top, "middle": .middle, "bottom": .bottom]
        for testCase in try Vectors.load("price-ranking.json")["receiptText"].array {
            let input = testCase["input"]
            let region = input["region"].isNull ? nil : regions[input["region"].string]
            let actual = TextOrdering.receiptText(input["observations"].array.map(Vectors.recognizedText), region: region)
            #expect(actual == testCase["expected"].string, "\(testCase["name"].string)")
        }
    }

    @Test("price-ranking.json: rectangle intersection")
    func rankingIntersects() throws {
        for testCase in try Vectors.load("price-ranking.json")["intersects"].array {
            let a = Vectors.rect(testCase["input"]["a"])
            let b = Vectors.rect(testCase["input"]["b"])
            #expect(a.intersects(b) == testCase["expected"].bool, "\(testCase["name"].string)")
            #expect(b.intersects(a) == testCase["expected"].bool, "\(testCase["name"].string), reversed")
        }
    }

    // MARK: - Validation

    @Test("validation.json: limits")
    func validationLimits() throws {
        let limits = try Vectors.load("validation.json")["limits"]
        #expect(Validation.minPrice == Vectors.decimal(limits["minPrice"]))
        #expect(Validation.maxPrice == Vectors.decimal(limits["maxPrice"]))
        #expect(Validation.minSizeValue == Vectors.decimal(limits["minSizeValue"]))
        #expect(Validation.maxSizeValue == Vectors.decimal(limits["maxSizeValue"]))
        #expect(Validation.minQuantity == limits["minQuantity"].int)
        #expect(Validation.maxQuantity == limits["maxQuantity"].int)
        #expect(Validation.minProductNameLength == limits["minProductNameLength"].int)
        #expect(Validation.maxProductNameLength == limits["maxProductNameLength"].int)
        #expect(Validation.maxSizeTextLength == limits["maxSizeTextLength"].int)
        #expect(Validation.maxNotesLength == limits["maxNotesLength"].int)
        #expect(Validation.maxCategoryLength == limits["maxCategoryLength"].int)
        #expect(Validation.maxStoreNameLength == limits["maxStoreNameLength"].int)
    }

    @Test("validation.json: prices")
    func validationPrices() throws {
        let vectors = try Vectors.load("validation.json")
        for testCase in vectors["price"].array {
            let input = testCase["input"].string
            Vectors.expectResult(Validation.validatePrice(Vectors.decimal(testCase["input"])), testCase["expected"],
                                 value: Vectors.decimal, "price \(input)")
        }
        for testCase in vectors["priceString"].array {
            let input = testCase["input"]
            Vectors.expectResult(
                Validation.validatePriceString(input["text"].string, fieldName: input["fieldName"].string),
                testCase["expected"], value: Vectors.decimal, "price string \(input["text"].string.debugDescription)"
            )
        }
    }

    @Test("validation.json: product names")
    func validationProductNames() throws {
        for testCase in try Vectors.load("validation.json")["productName"].array {
            let input = testCase["input"]
            Vectors.expectResult(
                Validation.validateProductName(input["text"].string, fieldName: input["fieldName"].string),
                testCase["expected"], value: \.string, "product name \(input["text"].string.prefix(20).debugDescription)"
            )
        }
    }

    @Test("validation.json: dates")
    func validationDates() throws {
        for testCase in try Vectors.load("validation.json")["date"].array {
            let input = testCase["input"]
            let calendar = Vectors.calendar(input["timeZone"])
            let date = Vectors.date(input["date"])
            let now = Vectors.date(input["now"])
            let name = testCase["name"].string
            Vectors.expectResult(Validation.validateDate(date, now: now, calendar: calendar), testCase["expected"],
                                 value: Vectors.date, name)
            Vectors.expectResult(Validation.validatePurchaseDate(date, now: now, calendar: calendar), testCase["expected"],
                                 value: Vectors.date, "\(name), as a purchase date")
        }
    }

    @Test("validation.json: size values and quantities")
    func validationNumbers() throws {
        let vectors = try Vectors.load("validation.json")
        for testCase in vectors["sizeValue"].array {
            let input = testCase["input"]
            Vectors.expectResult(
                Validation.validateSizeValue(input["text"].string, fieldName: input["fieldName"].string),
                testCase["expected"], value: Vectors.optionalDecimal, "size value \(input["text"].string.debugDescription)"
            )
        }
        for testCase in vectors["quantity"].array {
            let input = testCase["input"]
            Vectors.expectResult(
                Validation.validateQuantityString(input["text"].string, fieldName: input["fieldName"].string),
                testCase["expected"], value: \.int, "quantity \(input["text"].string.debugDescription)"
            )
        }
    }

    @Test("validation.json: optional text and email")
    func validationOptionalText() throws {
        let vectors = try Vectors.load("validation.json")
        let rules: [(String, (String?) -> Result<String?, ValidationError>)] = [
            ("size", Validation.validateSize),
            ("notes", Validation.validateNotes),
            ("category", Validation.validateCategory),
            ("storeName", Validation.validateStoreName),
            ("email", Validation.validateEmail),
        ]
        for (group, validate) in rules {
            for testCase in vectors[group].array {
                let input = testCase["input"].optionalString
                Vectors.expectResult(validate(input), testCase["expected"], value: \.optionalString,
                                     "\(group) \(String(describing: input?.prefix(20)))")
            }
        }
    }

    @Test("validation.json: product pairs")
    func validationProductPairs() throws {
        for testCase in try Vectors.load("validation.json")["productPair"].array {
            let input = testCase["input"]
            let result = Validation.validateProductPair(
                gfProductName: input["gfProductName"].string,
                gfPrice: Vectors.decimal(input["gfPrice"]),
                nonGFProductName: input["nonGFProductName"].string,
                nonGFPrice: Vectors.decimal(input["nonGFPrice"]),
                category: input["category"].optionalString,
                notes: input["notes"].optionalString
            )
            let name = testCase["name"].string
            switch result {
            case .success:
                #expect(testCase["expected"]["valid"].bool, "\(name): passed")
            case .failure(let error):
                #expect(error == Vectors.validationError(testCase["expected"]), "\(name)")
            }
        }
    }

    // MARK: - Backup

    @Test("backup: reading each file")
    func backupFiles() throws {
        for testCase in try Vectors.load("backup/backup.json")["files"].array {
            let name = testCase["name"].string
            let data = try Vectors.data("backup/" + testCase["file"].string)
            let expected = testCase["expected"]

            guard !expected.has("error") else {
                do {
                    _ = try BackupFormat.decode(data)
                    Issue.record("\(name): decoded, but should have been refused")
                } catch let error as BackupFormatError {
                    #expect(expected["error"].string == "incompatibleVersion", "\(name): \(error)")
                    #expect(error == .incompatibleVersion(expected["version"].string), "\(name)")
                } catch {
                    #expect(expected["error"].string == "malformed", "\(name): \(error)")
                }
                continue
            }

            let backup = try BackupFormat.decode(data)
            #expect(backup.version == expected["version"].string, "\(name)")
            #expect(backup.appVersion == expected["appVersion"].string, "\(name)")
            #expect(backup.timestamp == Vectors.date(expected["timestamp"]), "\(name)")
            #expect(backup.productPairs.count == expected["productPairCount"].int, "\(name)")
            #expect(backup.receipts.count == expected["receiptCount"].int, "\(name)")

            let settings = expected["settings"]
            #expect(backup.settings == SettingsBackup(
                userName: settings["userName"].string,
                accountantEmail: settings["accountantEmail"].string,
                taxID: settings["taxID"].string,
                currencySymbol: settings["currencySymbol"].string,
                defaultPaperSize: settings["defaultPaperSize"].string,
                defaultDateRange: settings["defaultDateRange"].string
            ), "\(name)")

            for want in expected["productPairs"].array {
                let pair = backup.productPairs[want["index"].int]
                let label = "\(name): pair \(want["index"].int)"
                #expect(pair.id == Vectors.uuid(want["id"]), "\(label)")
                #expect(pair.gfProductName == want["gfProductName"].string, "\(label)")
                #expect(pair.gfPrice == want["gfPrice"].string, "\(label)")
                #expect(pair.gfSize == want["gfSize"].optionalString, "\(label)")
                #expect(pair.gfSizeValue == want["gfSizeValue"].optionalString, "\(label)")
                #expect(pair.nonGFProductName == want["nonGFProductName"].string, "\(label)")
                #expect(pair.nonGFPrice == want["nonGFPrice"].string, "\(label)")
                #expect(pair.nonGFSize == want["nonGFSize"].optionalString, "\(label)")
                #expect(pair.nonGFSizeValue == want["nonGFSizeValue"].optionalString, "\(label)")
                #expect(pair.sizeUnit == want["sizeUnit"].optionalString, "\(label)")
                #expect(pair.quantity == (want["quantity"].isNull ? nil : want["quantity"].int), "\(label)")
                #expect(pair.effectiveQuantity == want["effectiveQuantity"].int, "\(label)")
                #expect(pair.createdDate == Vectors.date(want["createdDate"]), "\(label)")
                #expect(pair.category == want["category"].optionalString, "\(label)")
                #expect(pair.notes == want["notes"].optionalString, "\(label)")
                #expect(pair.verified == want["verified"].bool, "\(label)")
                #expect(pair.receiptID == (want["receiptID"].isNull ? nil : Vectors.uuid(want["receiptID"])), "\(label)")
            }
            for want in expected["receipts"].array {
                let receipt = backup.receipts[want["index"].int]
                let label = "\(name): receipt \(want["index"].int)"
                #expect(receipt.id == Vectors.uuid(want["id"]), "\(label)")
                #expect(receipt.purchaseDate == Vectors.date(want["purchaseDate"]), "\(label)")
                #expect(receipt.storeName == want["storeName"].optionalString, "\(label)")
                #expect(receipt.totalAmount == want["totalAmount"].optionalString, "\(label)")
                #expect(receipt.productPairIDs == want["productPairIDs"].array.map(Vectors.uuid), "\(label)")
            }

            // Every file that reads survives being written and read again
            #expect(try BackupFormat.decode(BackupFormat.encode(backup)) == backup, "\(name): round trip")
        }
    }

    @Test("backup: decimal strings")
    func backupDecimalStrings() throws {
        for testCase in try Vectors.load("backup/backup.json")["decimalStrings"].array {
            let input = testCase["input"].string
            #expect(BackupFormat.decimal(from: input) == Vectors.optionalDecimal(testCase["expected"]), "\(input.debugDescription)")
        }
    }

    // MARK: - Coverage

    @Test("Every vector file is run")
    func everyFileIsRun() throws {
        let root = try Vectors.directory()
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let present = Set(enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" }
            .map { $0.path.replacingOccurrences(of: root.path + "/", with: "") })

        let backupFiles = try Vectors.load("backup/backup.json")["files"].array.map { "backup/" + $0["file"].string }
        let run = Set(Vectors.groupFiles + backupFiles)
        #expect(present == run, "Not run: \(present.subtracting(run).sorted()); missing: \(run.subtracting(present).sorted())")
    }
}

// MARK: - Loading and matching

/// A JSON value, read without a schema so one runner can walk every vector file
private enum JSON: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSON].self))
        }
    }

    /// A missing key reads as null, as the vectors' README says
    subscript(key: String) -> JSON {
        if case .object(let object) = self { return object[key] ?? .null }
        return .null
    }

    func has(_ key: String) -> Bool {
        if case .object(let object) = self { return object[key] != nil }
        return false
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var array: [JSON] {
        if case .array(let array) = self { return array }
        Issue.record("Expected an array, found \(self)")
        return []
    }

    var string: String {
        if case .string(let string) = self { return string }
        Issue.record("Expected a string, found \(self)")
        return ""
    }

    var optionalString: String? {
        isNull ? nil : string
    }

    var bool: Bool {
        if case .bool(let bool) = self { return bool }
        Issue.record("Expected a Boolean, found \(self)")
        return false
    }

    var double: Double {
        if case .number(let number) = self { return number }
        Issue.record("Expected a number, found \(self)")
        return .nan
    }

    var float: Float { Float(double) }

    var int: Int {
        let number = double
        guard let int = Int(exactly: number) else {
            Issue.record("Expected an integer, found \(number)")
            return 0
        }
        return int
    }
}

private enum Vectors {

    /// The files this suite runs, besides the backup files `backup/backup.json` names
    static let groupFiles = [
        "pricing.json", "reporting.json", "csv.json", "receipt-parsing.json",
        "price-ranking.json", "validation.json", "backup/backup.json",
    ]

    static func directory() throws -> URL {
        try #require(Bundle.module.url(forResource: "Vectors", withExtension: nil))
    }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: directory().appendingPathComponent(path))
    }

    static func load(_ path: String) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: data(path))
    }

    // MARK: Values

    static func decimal(_ json: JSON) -> Decimal {
        guard let decimal = Decimal(string: json.string, locale: Locale(identifier: "en_US_POSIX")) else {
            Issue.record("Not a decimal: \(json)")
            return .nan
        }
        return decimal
    }

    static func optionalDecimal(_ json: JSON) -> Decimal? {
        json.isNull ? nil : decimal(json)
    }

    static func uuid(_ json: JSON) -> UUID {
        guard let uuid = UUID(uuidString: json.string) else {
            Issue.record("Not a UUID: \(json)")
            return UUID()
        }
        return uuid
    }

    static func date(_ json: JSON) -> Date {
        guard let date = ISO8601DateFormatter().date(from: json.string) else {
            Issue.record("Not an ISO 8601 instant: \(json)")
            return .distantPast
        }
        return date
    }

    static func timeZone(_ json: JSON) -> TimeZone {
        guard let timeZone = TimeZone(identifier: json.string) else {
            Issue.record("Not a time zone: \(json)")
            return .gmt
        }
        return timeZone
    }

    static func calendar(_ json: JSON) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone(json)
        return calendar
    }

    static func pricing(_ json: JSON) -> PricingInputs {
        PricingInputs(
            gfPrice: decimal(json["gfPrice"]),
            nonGFPrice: decimal(json["nonGFPrice"]),
            gfSizeValue: optionalDecimal(json["gfSizeValue"]),
            nonGFSizeValue: optionalDecimal(json["nonGFSizeValue"]),
            quantity: json["quantity"].isNull ? 1 : json["quantity"].int
        )
    }

    static func rows(_ json: JSON) -> [ReportRow] {
        json.array.map { row in
            ReportRow(
                id: uuid(row["id"]),
                reportingDate: date(row["reportingDate"]),
                pricing: pricing(row),
                gfProductName: row["gfProductName"].optionalString ?? "",
                gfSize: row["gfSize"].optionalString,
                nonGFProductName: row["nonGFProductName"].optionalString ?? "",
                nonGFSize: row["nonGFSize"].optionalString,
                sizeUnit: row["sizeUnit"].optionalString,
                category: row["category"].optionalString,
                verified: row["verified"].isNull ? false : row["verified"].bool,
                storeName: row["storeName"].optionalString,
                notes: row["notes"].optionalString
            )
        }
    }

    static func rect(_ json: JSON) -> NormalizedRect {
        NormalizedRect(x: json["x"].double, y: json["y"].double, width: json["width"].double, height: json["height"].double)
    }

    static func recognizedText(_ json: JSON) -> RecognizedText {
        RecognizedText(text: json["text"].string, confidence: json["confidence"].float, box: rect(json["box"]))
    }

    static func validationError(_ json: JSON) -> ValidationError? {
        let field = json["field"].optionalString ?? ""
        let max = json["max"]
        switch json["error"].string {
        case "priceNegative": return .priceNegative
        case "invalidPrice": return .invalidPrice(field: field)
        case "priceTooHigh": return .priceTooHigh(decimal(json["value"]))
        case "emptyRequiredField": return .emptyRequiredField(field: field)
        case "emptyProductName": return .emptyProductName(field: field)
        case "productNameTooLong": return .productNameTooLong(field: field, max: max.int)
        case "dateInFuture": return .dateInFuture
        case "dateBeforeEarliest": return .dateBeforeEarliest
        case "sizeNotANumber": return .sizeNotANumber(field: field)
        case "sizeNotPositive": return .sizeNotPositive(field: field)
        case "sizeTooSmall": return .sizeTooSmall(field: field)
        case "sizeTooLarge": return .sizeTooLarge(field: field, max: decimal(max))
        case "invalidQuantity": return .invalidQuantity(field: field)
        case "sizeTextTooLong": return .sizeTextTooLong(max: max.int)
        case "notesTooLong": return .notesTooLong(max: max.int)
        case "categoryTooLong": return .categoryTooLong(max: max.int)
        case "storeNameTooLong": return .storeNameTooLong(max: max.int)
        case "invalidEmail": return .invalidEmail
        case let other:
            Issue.record("Unknown validation error \(other)")
            return nil
        }
    }

    // MARK: Matching

    /// Rounds half-even to the expected string's places, then compares by value
    ///
    /// An expected value written in full matches exactly; one cut at 10 places, or shown at
    /// 2, matches the actual value rounded the same way.
    static func expectDecimal(_ actual: Decimal?, _ expected: JSON, _ comment: String,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        guard !expected.isNull else {
            #expect(actual == nil, "\(comment): expected nothing", sourceLocation: sourceLocation)
            return
        }
        let text = expected.string
        let places = text.split(separator: ".").dropFirst().first?.count ?? 0
        guard var value = actual else {
            Issue.record("\(comment): expected \(text), got nothing", sourceLocation: sourceLocation)
            return
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, places, .bankers)
        #expect(rounded == decimal(expected), "\(comment): \(actual!) rounds to \(rounded)", sourceLocation: sourceLocation)
    }

    static func expectDouble(_ actual: Double, _ expected: JSON, _ comment: String,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(actual - expected.double) <= 0.0001, "\(comment): \(actual)", sourceLocation: sourceLocation)
    }

    static func expectFloat(_ actual: Float, _ expected: JSON, _ comment: String,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        expectDouble(Double(actual), expected, comment, sourceLocation: sourceLocation)
    }

    /// Checks the totals fields the expectation names, and only those
    static func expectTotals(_ totals: ReportTotals, _ expected: JSON, _ comment: String,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        let counts: [(String, Int)] = [
            ("count", totals.count), ("unitCount", totals.unitCount), ("verifiedCount", totals.verifiedCount),
            ("unverifiedCount", totals.unverifiedCount), ("normalizedExcludedCount", totals.normalizedExcludedCount),
            ("normalizedUnitCount", totals.normalizedUnitCount),
        ]
        for (key, actual) in counts where expected.has(key) {
            #expect(actual == expected[key].int, "\(comment): \(key)", sourceLocation: sourceLocation)
        }
        let amounts: [(String, Decimal?)] = [
            ("totalDifferential", totals.totalDifferential),
            ("totalNormalizedDifferential", totals.totalNormalizedDifferential),
            ("averageDifferential", totals.averageDifferential),
            ("averageNormalizedDifferential", totals.averageNormalizedDifferential),
        ]
        for (key, actual) in amounts where expected.has(key) {
            expectDecimal(actual, expected[key], "\(comment): \(key)", sourceLocation: sourceLocation)
        }
    }

    static func expectGroups<Key: Equatable>(_ groups: [(Key, ReportTotals)], _ expected: JSON, key: String,
                                             keyValue: (JSON) -> Key, _ comment: String,
                                             sourceLocation: SourceLocation = #_sourceLocation) {
        let expected = expected.array
        #expect(groups.map(\.0) == expected.map { keyValue($0[key]) }, "\(comment): keys", sourceLocation: sourceLocation)
        for ((groupKey, totals), want) in zip(groups, expected) {
            expectTotals(totals, want, "\(comment): \(groupKey)", sourceLocation: sourceLocation)
        }
    }

    /// `{"ok": value}` or `{"error": case, …}`
    static func expectResult<Value: Equatable>(_ result: Result<Value, ValidationError>, _ expected: JSON,
                                               value: (JSON) -> Value, _ comment: String,
                                               sourceLocation: SourceLocation = #_sourceLocation) {
        if expected.has("ok") {
            #expect(result == .success(value(expected["ok"])), "\(comment)", sourceLocation: sourceLocation)
        } else if let error = validationError(expected) {
            #expect(result == .failure(error), "\(comment)", sourceLocation: sourceLocation)
        }
    }
}
