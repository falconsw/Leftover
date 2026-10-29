import XCTest
@testable import Leftover

/// The cost layer's seams into the app: the hover card reserves room for
/// the project rows, a credit-based Codex seat gets a Credits window, and the
/// money math anchors on the allowance rather than on token prices.
final class CostTests: XCTestCase {
    /// A Business seat reports no rolling windows; the spend control is its ring.
    func testCreditSeatGetsACreditsWindow() throws {
        let json = """
        {"plan_type":"business","rate_limit":null,"additional_rate_limits":null,"code_review_rate_limit":null,
         "spend_control":{"reached":false,"individual_limit":{"unit":"credit","limit":"2500","used":"310.13",
         "used_percent":12,"reset_at":1789430400}}}
        """
        let windows = try CodexUsage.windows(from: Data(json.utf8), now: Date(timeIntervalSince1970: 1_789_000_000))
        let credits = try XCTUnwrap(windows.first { $0.id == "credits" })
        XCTAssertEqual(credits.usedFraction ?? 0, 0.12, accuracy: 0.0001)
        XCTAssertEqual(credits.used, 310)
        XCTAssertEqual(credits.remaining, 2190)
        XCTAssertEqual(credits.resetsAt, Date(timeIntervalSince1970: 1_789_430_400))
    }



    /// The card's range follows the account's allowance, never "all time".
    @MainActor func testCostRangeNeverStartsOnAllTime() {
        UserDefaults.standard.set("allTime", forKey: "costRange")
        let account = CostAccount(id: "test-x", provider: "claude", name: "Test", configDirectory: URL(fileURLWithPath: "/nonexistent"))
        let model = CostModel(account: account)
        XCTAssertNotEqual(model.range, .allTime)
        UserDefaults.standard.removeObject(forKey: "costRange")
    }
}
