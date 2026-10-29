import XCTest
@testable import Leftover

/// The figure under the ring reads grey only when a window is actually
/// spent — the 5-hour or the weekly — and only in remaining mode. Grey means
/// "nothing usable", and neither staleness, nor a missing reading, nor an
/// unmeasured speed says that.
final class ProviderCellTests: XCTestCase {
    private let spentWeek = [
        LimitWindow(id: "session", label: "Session", usedFraction: 0.5),
        LimitWindow(id: "weekly_all", label: "Weekly", usedFraction: 1.0),
    ]
    private let spentSession = [
        LimitWindow(id: "session", label: "Session", usedFraction: 1.0),
        LimitWindow(id: "weekly_all", label: "Weekly", usedFraction: 0.3),
    ]

    private func snapshot(status: ProviderStatus = .ok,
                          windows: [LimitWindow]? = nil,
                          weeklyID: String? = nil) -> ProviderSnapshot {
        ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
                         fidelity: .official, status: status,
                         windows: windows ?? [LimitWindow(id: "session", label: "Session", usedFraction: 0.5)],
                         headlineID: "session", weeklyID: weeklyID)
    }









    func testShutRingsNeedTheSettingAndASpentWindow() {
        // A spent week shuts, on by default.
        let weekShut = ProviderRing(usedFraction: 0.3, glyph: .claude, weeklyExhausted: true)
        XCTAssertTrue(weekShut.showsShutRings)
        // A spent 5-hour with no block: the headline fraction alone shuts.
        let sessionShut = ProviderRing(usedFraction: 1.0, glyph: .claude)
        XCTAssertTrue(sessionShut.showsShutRings)
        // The setting off keeps every ring its own colour, however spent.
        let off = ProviderRing(usedFraction: 1.0, glyph: .claude,
                               weeklyExhausted: true, shutRingsWhenSpent: false)
        XCTAssertFalse(off.showsShutRings)
        // Nothing spent, nothing shut.
        let healthy = ProviderRing(usedFraction: 0.3, glyph: .claude)
        XCTAssertFalse(healthy.showsShutRings)
    }
}
