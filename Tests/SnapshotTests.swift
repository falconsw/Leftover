import XCTest
@testable import Leftover

final class SnapshotTests: XCTestCase {
    private func window(_ id: String, _ used: Double) -> LimitWindow {
        LimitWindow(id: id, label: id, usedFraction: used, resetsAt: Date())
    }

    private func snapshot(_ windows: [LimitWindow], fidelity: Fidelity = .derived) -> ProviderSnapshot {
        ProviderSnapshot(id: "p", displayName: "P", glyph: .claude,
                         fidelity: fidelity, status: .ok, windows: windows)
    }

    func testHeadlineIsThePrimaryWindow() {
        let s = snapshot([window("session", 0.73), window("all", 0.07)])
        XCTAssertEqual(s.headline?.id, "session")
        XCTAssertEqual(s.usedFraction ?? -1, 0.73, accuracy: 0.0001)
    }

    /// The headline stays on the session even when another window is higher.
    /// Picking the highest made the ring mean "session" one minute and "weekly"
    /// the next, which reads as the number being wrong — and disagrees with
    /// Claude's own panel, which always leads with the session.
    func testHeadlineDoesNotJumpToAHigherWindow() {
        let s = snapshot([window("session", 0.22), window("weekly_all", 0.24)])
        XCTAssertEqual(s.headline?.id, "session")
        XCTAssertEqual(s.usedFraction ?? -1, 0.22, accuracy: 0.0001)
    }

    /// The ring and the tooltip's top row are the same window, always.
    func testHeadlineMatchesTheFirstRowShown() {
        let s = snapshot([window("session", 0.05), window("weekly_all", 0.9)])
        XCTAssertEqual(s.headline?.id, s.windows.first?.id)
    }



    /// Token counts are seven digits wide and the ring is 44 pt; requests and
    /// credits are small enough to stay verbatim.
    func testLargeCountsAreCompacted() {
        XCTAssertEqual(LimitWindow.compact(9_999), "9999")
        XCTAssertEqual(LimitWindow.compact(651_061), "651k")
        XCTAssertEqual(LimitWindow.compact(1_128_771), "1.1M")
        XCTAssertEqual(LimitWindow.compact(2_000_000), "2.0M")
    }


    func testOnlyOfficialNumbersAreShownUnqualified() {
        XCTAssertEqual(Fidelity.official.qualifier, "")
        XCTAssertEqual(Fidelity.derived.qualifier, "~")
        XCTAssertEqual(Fidelity.manual.qualifier, "~")
    }
}

/// The notch can show what is left instead of what is spent. The figure is
/// the tooltip's own left half, so the two never disagree by a point.
final class RemainingHeadlineTests: XCTestCase {
    private func snapshot(_ windows: [LimitWindow]) -> ProviderSnapshot {
        ProviderSnapshot(id: "p", displayName: "P", glyph: .claude,
                         fidelity: .official, status: .ok, windows: windows)
    }

    private func window(_ used: Double) -> LimitWindow {
        LimitWindow(id: "w", label: "W", usedFraction: used)
    }






}

/// The one rule behind the ring's sweep, the card's bars, and every flipped
/// figure: spent by default, what is left when the notch is set that way.
final class MeteredFractionTests: XCTestCase {
    func testSpentPassesThrough() {
        XCTAssertEqual(Percent.metered(0.125, showingRemaining: false), 0.125, accuracy: 1e-9)
        XCTAssertEqual(Percent.metered(0, showingRemaining: false), 0, accuracy: 1e-9)
    }

    func testRemainingComplements() {
        XCTAssertEqual(Percent.metered(0.125, showingRemaining: true), 0.875, accuracy: 1e-9)
        XCTAssertEqual(Percent.metered(0, showingRemaining: true), 1, accuracy: 1e-9)
        XCTAssertEqual(Percent.metered(1, showingRemaining: true), 0, accuracy: 1e-9)
    }

    /// Unclamped: callers draw 0…1, so an overspent limit reads empty rather
    /// than negative at the draw site, where the clamp belongs.
    func testOverspentStaysRawForTheCallerToClamp() {
        XCTAssertEqual(Percent.metered(1.28, showingRemaining: true), -0.28, accuracy: 1e-9)
        XCTAssertEqual(Percent.metered(1.28, showingRemaining: false), 1.28, accuracy: 1e-9)
    }
}

/// A spent weekly allowance shuts the headline with it, for every provider:
/// the headline's room is unusable, so the ring must not read green. The
/// headline keeps its own reading; the ring goes red and the card leads
/// with when the week lifts.
final class WeeklyExhaustionBlockTests: XCTestCase {
    private let reset = Date(timeIntervalSince1970: 1790553600)

    private func snapshot(headlineFraction: Double?, weeklyFraction: Double?,
                          weeklyID: String? = "weekly") -> ProviderSnapshot {
        var windows = [
            LimitWindow(id: "session", label: "Session", usedFraction: headlineFraction)
        ]
        if weeklyID != nil {
            windows.append(LimitWindow(id: "weekly", label: "Weekly",
                                       usedFraction: weeklyFraction, resetsAt: reset))
        }
        return ProviderSnapshot(id: "p", displayName: "P", glyph: .claude,
                                fidelity: .official, status: .ok, windows: windows,
                                headlineID: "session", weeklyID: weeklyID)
    }


    func testOverQuotaWeekBlocks() {
        XCTAssertNotNil(snapshot(headlineFraction: 0.2, weeklyFraction: 1.28).blockingSpentWeek().block)
    }

    func testNearlySpentWeekDoesNotBlock() {
        XCTAssertNil(snapshot(headlineFraction: 0.2, weeklyFraction: 0.999).blockingSpentWeek().block)
    }

    func testWeekWithoutADenominatorDoesNotBlock() {
        XCTAssertNil(snapshot(headlineFraction: 0.2, weeklyFraction: nil).blockingSpentWeek().block)
    }

    func testMissingWeekDoesNotBlock() {
        XCTAssertNil(snapshot(headlineFraction: 0.2, weeklyFraction: nil, weeklyID: nil).blockingSpentWeek().block)
    }

    func testAProviderBlockIsNeverReplaced() {
        let providerBlock = UsageBlock(reason: "Paused", resetsAt: nil)
        var s = snapshot(headlineFraction: 0.2, weeklyFraction: 1)
        s.block = providerBlock
        XCTAssertEqual(s.blockingSpentWeek().block, providerBlock)
    }

    func testSpentWeekBlocksEvenAsTheHeadline() throws {
        var s = snapshot(headlineFraction: 0.2, weeklyFraction: 1)
        s.headlineID = "weekly"
        let blocked = s.blockingSpentWeek()
        XCTAssertEqual(try XCTUnwrap(blocked.block).reason, "Weekly limit reached")
    }
}
