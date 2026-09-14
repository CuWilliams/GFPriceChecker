//
//  EmptyLibraryYearUITests.swift
//  GFPriceCheckerUITests
//
//  Created by Claude Code on 2026-09-14.
//

import XCTest

/// Pins the tax year to plain digits on the dashboard's empty state.
///
/// `SwiftUI.Text` reads a string literal as a `LocalizedStringKey`, and an `Int` interpolated
/// into one is formatted with the locale's grouping separator — so `"No products for
/// \(selectedYear)"` put **"No products for 2,026"** on screen. Wrapping the year in
/// `String(...)` interpolates it as text instead and the separator goes away.
///
/// The empty state is not an edge case: the year picker only offers years that already have
/// products, so a library with nothing in it leaves `selectedYear` at the current year with
/// no products under it. That is the first screen a new user sees on the Reports tab, which
/// is why this is worth a test of its own before a field trial.
///
/// This has to be a UI test. The defect lives in how `Text` resolves a literal, and nothing
/// short of rendering one reveals it — a unit test can only re-check `String(year)`, which
/// was never the broken part.
final class EmptyLibraryYearUITests: XCTestCase {

    /// The fixture that empties the library, as a path on the **host**.
    ///
    /// `DemoSeed` reads the dataset straight off the Mac's filesystem rather than out of the
    /// app container, so this has to be a host path — and hardcoding one would tie the suite
    /// to a single machine. `#filePath` is the host path of this source file at build time,
    /// so walking up from it finds the repo wherever it was cloned.
    private var emptyDataset: String {
        URL(fileURLWithPath: #filePath)          // .../GFPriceCheckerUITests/<this file>
            .deletingLastPathComponent()         // .../GFPriceCheckerUITests
            .deletingLastPathComponent()         // repo root
            .appendingPathComponent("Tools/Demo/empty-dataset.json")
            .path
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyYearMessageUsesPlainDigits() throws {
        let year = Calendar.current.component(.year, from: Date())

        let app = XCUIApplication()
        app.launchEnvironment["GFPC_DEMO_DATASET"] = emptyDataset
        app.launch()

        // The seed clears the library and marks onboarding done, but a `.replace` import and
        // the app's own launch screen both have to settle before the tab bar is tappable.
        let reports = app.tabBars.buttons["Reports"]
        XCTAssertTrue(reports.waitForExistence(timeout: 30), "No Reports tab")
        for _ in 0..<3 {
            reports.tap()
            sleep(2)
            if reports.isSelected { break }
        }
        XCTAssertTrue(reports.isSelected, "Reports tab never became selected")

        let plain = "No products for \(year)"
        let grouped = "No products for \(year.formatted(.number.grouping(.automatic)))"

        XCTAssertTrue(
            app.staticTexts[plain].waitForExistence(timeout: 20),
            "Expected \"\(plain)\" on the empty dashboard"
        )
        // Named explicitly so a regression reads as the separator coming back rather than as
        // some unrelated string going missing.
        XCTAssertFalse(
            app.staticTexts[grouped].exists,
            "Year rendered with a grouping separator: \"\(grouped)\""
        )

        // The two chart placeholders take the same year through a `String` parameter, which
        // never had the defect. Asserted so that a future fix to the line above cannot
        // "tidy" them into the literal form that does.
        XCTAssertTrue(
            app.staticTexts["No monthly data for \(year)"].exists,
            "Monthly placeholder lost its plain year"
        )
        XCTAssertTrue(
            app.staticTexts["No category data for \(year)"].exists,
            "Category placeholder lost its plain year"
        )
    }
}
