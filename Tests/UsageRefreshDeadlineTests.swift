import XCTest
@testable import Leftover

/// A refresh must never be able to wedge the store.
///
/// This is from life: a keychain authorization prompt went unanswered, the
/// Claude fetch behind it blocked on `SecItemCopyMatching`, the pass never
/// returned, and `isRefreshing` stayed true. Every tick for the next eighty
/// minutes logged "refresh skipped: one already in flight" and the app quietly
/// stopped reading anything at all, while still looking perfectly alive.
@MainActor
final class UsageRefreshDeadlineTests: XCTestCase {
    /// Hangs until it is let go, the way a blocked keychain read does.
    private final class BlockingProvider: UsageProvider, @unchecked Sendable {
        let id: String
        let displayName = "Blocked"
        let glyph = ProviderGlyph.claude
        private(set) var calls = 0
        private var resume: CheckedContinuation<Void, Never>?

        init(id: String = "blocked") { self.id = id }

        func fetchSnapshot() async throws -> ProviderSnapshot {
            calls += 1
            await withCheckedContinuation { self.resume = $0 }
            return Self.reading(id: id, displayName: displayName, glyph: glyph, used: 0.9)
        }

        func release() { resume?.resume(); resume = nil }
        func signOut() async {}

        static func reading(id: String, displayName: String, glyph: ProviderGlyph,
                            used: Double) -> ProviderSnapshot {
            ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                             fidelity: .official, status: .ok,
                             windows: [LimitWindow(id: "w", label: "W", usedFraction: used)])
        }
    }

    /// Answers at once, so a pass around a blocked one can be seen to complete.
    private final class QuickProvider: UsageProvider, @unchecked Sendable {
        let id: String
        let displayName = "Quick"
        let glyph = ProviderGlyph.openai
        private(set) var calls = 0
        var fails = false

        init(id: String = "quick") { self.id = id }

        func fetchSnapshot() async throws -> ProviderSnapshot {
            calls += 1
            if fails { throw UsageProviderError.badResponse(status: 500) }
            return BlockingProvider.reading(id: id, displayName: displayName,
                                            glyph: glyph, used: 0.2)
        }

        func signOut() async {}
    }

    private func store(_ providers: [any UsageProvider],
                       deadline: TimeInterval = 0.25) -> UsageStore {
        let name = "UsageRefreshDeadlineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return UsageStore(providers: providers, refreshDeadline: deadline,
                          archive: UsageArchive(defaults: defaults))
    }

    private func settle(_ seconds: Double = 0.8) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Success


    // MARK: - Error


    // MARK: - Timeout


    /// The abandoned provider says so rather than sitting there looking fine.
    func testAnAbandonedProviderSaysItGotNoResponse() async {
        let blocked = BlockingProvider()
        let store = store([blocked])
        store.refreshNow()
        await settle()
        XCTAssertEqual(store.snapshots.first { $0.id == "blocked" }?.status,
                       .error("no response"))
        blocked.release()
    }

    // MARK: - No concurrency

    func testASecondRefreshIsRefusedWhileOneIsRunning() async {
        let blocked = BlockingProvider()
        let store = store([blocked], deadline: 30)
        store.refreshNow()
        store.refreshNow()
        await settle(0.2)
        XCTAssertEqual(blocked.calls, 1, "the second must not start a second pass")
        blocked.release()
    }

    /// Refused, but not turned away empty-handed: the second caller is given
    /// the pass that is running, so it can wait for the same readings. The
    /// menu's Refresh all says "Refreshing…" for as long as that takes.
    func testASecondCallerIsHandedThePassAlreadyRunning() async {
        let blocked = BlockingProvider()
        let store = store([blocked], deadline: 30)
        let first = store.refreshNow()
        let second = store.refreshNow()
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        await settle(0.2)
        blocked.release()
    }

    // MARK: - Recovery




}
