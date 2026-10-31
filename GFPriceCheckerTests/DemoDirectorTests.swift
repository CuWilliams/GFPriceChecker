//
//  DemoDirectorTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-10-31.
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import GFPriceChecker

/// Covers Stage 5's director: the files the shell waits on, registration, and
/// the primitives a script is built from.
///
/// What these cannot show is a take: that the curtain covers the seed, that
/// the sheets register as they appear, and that the recording cuts where it
/// should. That was checked by running `Tools/Demo/play.sh tour` against the
/// seeded Simulator and recording it; see `Tools/Demo/README.md`.
@MainActor
@Suite("Demo director")
struct DemoDirectorTests {

    /// Holds the container alive alongside its context
    @MainActor
    struct Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
    }

    static func makeStore() throws -> Store {
        let container = try ModelContainer(
            for: ProductPair.self, Receipt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return Store(container: container)
    }

    /// A path in a fresh temporary directory, with nothing at it yet
    static func scratchPath(_ name: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoDirectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name).path
    }

    static func director(doneFile: String? = nil, stillFile: String? = nil,
                         stillMark: String? = nil) -> DemoDirector {
        DemoDirector(scriptName: "tour", doneFilePath: doneFile, stillFilePath: stillFile,
                     stillMark: stillMark, stillHoldSeconds: 0)
    }

    final class StubViewModel {}

    // MARK: - Done file

    @Test("A finished script writes done and its name")
    func doneFileOnSuccess() throws {
        let path = try Self.scratchPath("tour.done")
        Self.director(doneFile: path).finish(failure: nil)

        #expect(try String(contentsOfFile: path, encoding: .utf8) == "done tour\n")
    }

    @Test("A failed script writes the done file anyway, with the error")
    func doneFileOnFailure() throws {
        let path = try Self.scratchPath("tour.done")
        Self.director(doneFile: path).finish(failure: DemoDirector.DemoError.notRegistered("ExportViewModel"))

        #expect(try String(contentsOfFile: path, encoding: .utf8) == "failed tour: no ExportViewModel registered\n")
    }

    // MARK: - Stills

    @Test("Without a still file, still() writes nothing")
    func stillIsANoOpInAVideoTake() async {
        let director = Self.director()
        await director.still()
        #expect(!director.isCapturing(DemoDirector.tileMark))
    }

    @Test("A stills run writes the still file at its mark, and only there")
    func stillWritesAtItsMark() async throws {
        let path = try Self.scratchPath("tour.still")
        let director = Self.director(stillFile: path, stillMark: "store")

        await director.still()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(!director.isCapturing(DemoDirector.tileMark))

        await director.still("store")
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(director.isCapturing("store"))
    }

    @Test("An empty still mark means the tile")
    func emptyStillMarkIsTheTile() async throws {
        let path = try Self.scratchPath("tour.still")
        let director = Self.director(stillFile: path, stillMark: "")

        await director.still()
        #expect(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Captions

    /// A clock the test moves by hand
    final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        func advance(_ seconds: Double) { now = now.addingTimeInterval(seconds) }
    }

    static func captioned(_ clock: Clock, file: String? = nil) -> DemoDirector {
        DemoDirector(scriptName: "tour", doneFilePath: nil, stillFilePath: nil, stillMark: nil,
                     stillHoldSeconds: 0, captionsFilePath: file, clock: { clock.now })
    }

    @Test("Reading time is a second plus 0.3 s a word, and never under 1.5 s")
    func readingSeconds() {
        #expect(DemoDirector.readingSeconds(for: "Hi") == 1.5)
        #expect(DemoDirector.readingSeconds(for: "one two three four five six seven eight nine ten") == 4.0)
    }

    @Test("A caption runs from when it is shown to the next, timed from the curtain lifting")
    func captionsAreTimedFromTheLift() async {
        let clock = Clock()
        let director = Self.captioned(clock)
        clock.advance(10)          // the seed, behind the curtain
        director.curtainLifted()

        clock.advance(1)
        await director.caption("Capturing a product pair")
        clock.advance(5)
        await director.caption("Scan the tag")
        clock.advance(2)
        await director.caption(nil)
        clock.advance(3)
        await director.caption("Saved")

        #expect(director.cues == [
            .init(start: 1, end: 6, text: "Capturing a product pair"),
            .init(start: 6, end: 8, text: "Scan the tag"),
        ])
    }

    /// The script moves on as fast as its action does; the caption waits for
    /// its reader. Its end is read off the director's clock, which the test
    /// holds still, so what shows the wait is the time it took.
    @Test("A caption replaced before it can be read is held for the rest of its reading time")
    func captionsAreNotCutShort() async {
        let clock = Clock()
        let director = Self.captioned(clock)
        director.curtainLifted()

        await director.caption("Hi")                    // needs 1.5 s
        clock.advance(1.2)
        let started = ContinuousClock.now
        await director.caption("Next")
        #expect(ContinuousClock.now - started >= .milliseconds(250))

        clock.advance(1.5)
        let unheld = ContinuousClock.now
        await director.caption(nil)
        #expect(ContinuousClock.now - unheld < .milliseconds(250))
    }

    @Test("finish closes the caption still up and writes the captions file")
    func finishWritesCaptions() async throws {
        let path = try Self.scratchPath("tour.cues.json")
        let clock = Clock()
        let director = Self.captioned(clock, file: path)
        director.curtainLifted()
        await director.caption("Exporting your records")
        clock.advance(4)

        director.finish(failure: nil)

        struct File: Decodable { let script: String; let cues: [DemoDirector.Cue] }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(file.script == "tour")
        #expect(file.cues == [.init(start: 0, end: 4, text: "Exporting your records")])
    }

    // MARK: - Registration

    @Test("screen(_:) returns the registered view model")
    func screenReturnsRegistered() async throws {
        let director = Self.director()
        let viewModel = StubViewModel()
        director.register(viewModel)

        #expect(try await director.screen(StubViewModel.self, timeout: 0.1) === viewModel)
    }

    @Test("screen(_:) throws when nothing registers in time")
    func screenTimesOut() async {
        await #expect(throws: DemoDirector.DemoError.self) {
            try await Self.director().screen(StubViewModel.self, timeout: 0.1)
        }
    }

    /// Every view that registers is a sheet, and `show(_:)` dismisses every
    /// sheet, so a view model registered before a push is a dismissed one.
    @Test("push forgets every registered view model, and moves the router")
    func pushForgetsRegistrations() async throws {
        let store = try Self.makeStore()
        let router = AppRouter()
        let director = Self.director()
        director.attach(router: router, context: store.context)
        director.register(StubViewModel())

        await director.push(.export)

        #expect(router.selectedTab == .reports)
        #expect(router.reportsSheet == .export)
        await #expect(throws: DemoDirector.DemoError.self) {
            try await director.screen(StubViewModel.self, timeout: 0.1)
        }
    }

    // MARK: - Destinations and scripts

    @Test("destination(_:) resolves names as the route hook does")
    func destinationResolves() throws {
        let store = try Self.makeStore()
        let pair = ProductPair(gfProductName: "GF Bread", gfPrice: 6.99,
                               nonGFProductName: "Bread", nonGFPrice: 3.49,
                               createdDate: .now, category: "Bakery")
        store.context.insert(pair)
        let director = Self.director()
        director.attach(router: AppRouter(), context: store.context)

        #expect(try director.destination("export") == .export)
        #expect(try director.destination("product") == .product(pair))
        #expect(throws: DemoDirector.DemoError.self) { try director.destination("nowhere") }
    }

    @Test("destination(_:) throws before the director is attached")
    func destinationNeedsAContext() {
        #expect(throws: DemoDirector.DemoError.self) { try Self.director().destination("export") }
    }

    @Test("An unknown script throws rather than playing nothing")
    func unknownScriptThrows() async {
        await #expect(throws: DemoDirector.DemoError.self) {
            try await DemoScripts.run("nowhere", on: Self.director())
        }
    }

    /// The receipt take taps each pair's "Suggested" line, so its pairs must
    /// suggest their own lines on the drawn receipt, and not the regular
    /// product's line or the store's address.
    @Test("receipt-management's pairs each suggest their own line on the drawn receipt")
    func receiptPairsMatchTheReceipt() async throws {
        let store = try Self.makeStore()
        let director = Self.director()
        director.attach(router: AppRouter(), context: store.context)

        try await DemoScripts.prepare("receipt-management", on: director)

        let pairs = try store.context.fetch(FetchDescriptor<ProductPair>(sortBy: [SortDescriptor(\.createdDate)]))
        #expect(pairs.map(\.gfProductName) == ["Gluten Free White Bread", "Gluten Free Penne"])
        #expect(pairs.allSatisfy { !$0.verified })

        let receipt = SampleScanImages.groceryReceipt
        let flow = ReceiptCaptureViewModel()
        flow.receiptOCRObservations = ([receipt.store, receipt.address, receipt.city] + receipt.lines.map(\.name))
            .map { SelectableTextObservation(text: $0, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.05), confidence: 1) }

        #expect(pairs.map { flow.suggestedReceiptLine(for: $0)?.text } ==
                ["NORTHFIELD GF WHITE BREAD", "NORTHFIELD GF PENNE"])
    }

    /// reporting-exporting's prepare only moves between tabs
    @Test("Only receipt-management's prepare adds to the store")
    func otherScriptsPrepareNothing() async throws {
        let store = try Self.makeStore()
        let director = Self.director()
        director.attach(router: AppRouter(), context: store.context)

        for name in DemoScripts.names where name != "receipt-management" {
            try await DemoScripts.prepare(name, on: director)
        }

        #expect(try store.context.fetchCount(FetchDescriptor<ProductPair>()) == 0)
    }

    /// `bootstrapIfRequested` checks `GFPC_DEMO_SCRIPT` against `names`, so a
    /// script `run` dispatches but `names` omits could never be launched.
    @Test("Every listed script is one run dispatches", arguments: DemoScripts.names)
    func listedScriptsDispatch(name: String) {
        #expect(DemoScripts.script(named: name) != nil, "\(name) is listed but not dispatched")
    }
}
