import XCTest
@testable import Leftover

final class LocalTokenLedgerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = LMStudioLogFixtures.zone
        return calendar
    }

    private func prediction(_ instance: String = "qwen", at: Date, input: Int? = 10, output: Int? = 100,
                            reasoning: Int? = nil, rate: Double? = nil, drafts: (Int, Int)? = nil) -> LocalPrediction {
        LocalPrediction(instance: instance, at: at, inputTokens: input, outputTokens: output,
                        reasoningTokens: reasoning, tokensPerSecond: rate,
                        draftTokens: drafts?.0, acceptedDraftTokens: drafts?.1)
    }



    func testSharesAreAbsentRatherThanZeroWhenNothingWasCounted() {
        var totals = LocalTokenLedger.Totals()
        XCTAssertNil(totals.reasoningShare)
        XCTAssertNil(totals.draftAcceptance)
        totals.add(prediction(at: Date(), output: 10, reasoning: 0))
        XCTAssertEqual(totals.reasoningShare, 0)
        XCTAssertNil(totals.draftAcceptance, "no drafts is not 0% accepted")
        let summary = LocalTokenLedger.Summary(today: LocalTokenLedger.Totals(), last: nil)
        XCTAssertEqual(summary.reasoningShareText, "—")
        XCTAssertEqual(summary.draftAcceptanceText, "—")
        XCTAssertEqual(summary.contextText(contextLength: 4096), "—")
        XCTAssertNil(summary.contextFraction(contextLength: 4096))
    }

    func testTheContextFractionIsTheLastPromptAgainstTheLoadedWindow() throws {
        let summary = LocalTokenLedger.Summary(today: LocalTokenLedger.Totals(),
                                               last: prediction(at: Date(), input: 1024, output: 1))
        XCTAssertEqual(try XCTUnwrap(summary.contextFraction(contextLength: 4096)), 0.25, accuracy: 0.0001)
        XCTAssertEqual(summary.contextText(contextLength: 4096), "25% · 1024")
        XCTAssertEqual(summary.contextFraction(contextLength: 512), 1, "a truncated prompt reads as a full window")
        XCTAssertNil(summary.contextFraction(contextLength: nil))
        XCTAssertNil(summary.contextFraction(contextLength: 0))
        XCTAssertEqual(summary.contextText(contextLength: nil), "1024 tokens")
        let large = LocalTokenLedger.Summary(today: LocalTokenLedger.Totals(),
                                             last: prediction(at: Date(), input: 131_072, output: 1))
        XCTAssertEqual(large.contextText(contextLength: 262_144), "50% · 131k")
    }

    func testTheNewestResponseKeepsTheCellWhateverOrderLinesArrive() {
        let earlier = LMStudioLogFixtures.date(2026, 9, 10, 9, 0, 0)
        let later = earlier.addingTimeInterval(60)
        var ledger = LocalTokenLedger(calendar: calendar)
        ledger.record(prediction(at: later, input: 2))
        ledger.record(prediction(at: earlier, input: 1))
        XCTAssertEqual(ledger.last["qwen"]?.inputTokens, 2)
        ledger.record(prediction(at: later, input: 3), as: "lmstudio:model:qwen")
        XCTAssertEqual(ledger.last["lmstudio:model:qwen"]?.inputTokens, 3, "a key names the entry")
        XCTAssertEqual(ledger.last["qwen"]?.inputTokens, 2)
    }

    func testOldDaysAgeOut() throws {
        let today = LMStudioLogFixtures.date(2026, 9, 10, 12, 0, 0)
        let ancient = calendar.date(byAdding: .day, value: -(LocalTokenLedger.retentionDays + 1), to: today)!
        let recent = calendar.date(byAdding: .day, value: -(LocalTokenLedger.retentionDays - 1), to: today)!
        var ledger = LocalTokenLedger(calendar: calendar)
        ledger.record(prediction(at: ancient))
        ledger.record(prediction(at: recent))
        ledger.record(prediction(at: today))
        XCTAssertNil(ledger.totals(for: "qwen", on: ancient))
        XCTAssertNotNil(ledger.totals(for: "qwen", on: recent))
        XCTAssertEqual(ledger.days["qwen"]?.count, 2)
    }
}

final class LocalModelPerformanceSourcesTests: XCTestCase {


}
