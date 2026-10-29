import XCTest
@testable import Leftover

/// What the settings row is allowed to offer.
///
/// "Allow access…" used to be shown for every keychain-backed provider,
/// unconditionally. That put a remedy on screen next to a perfectly working
/// account, and — because the same row looked identical when the remedy *was*
/// needed — gave no way to tell a button that had nothing to do from one that
/// was failing to do it.
@MainActor
final class ProviderSummaryTests: XCTestCase {





    /// Before the first fetch nothing has been refused, so nothing is offered.
    ///
    /// The store seeds its snapshots at init rather than leaving them absent, so
    /// the row must reach its verdict from an actual refusal and not from the
    /// mere presence — or absence — of a reading.
    func testWithoutAFetchTheRowOffersNothing() {
        let store = makeStore(SwitchableProvider(outcome: .failure(.accessDenied)))

        XCTAssertFalse(store.providerSummaries.first?.wasRefusedAccess ?? true,
                       "a remedy was offered before anything had failed")
    }

    // MARK: - Helpers

    private func makeStore(_ provider: SwitchableProvider) -> UsageStore {
        let name = "ProviderSummaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults))
    }
}

/// A provider whose answer can be changed between refreshes, so a test can put
/// a good reading in the store's hands before taking access away.
private final class SwitchableProvider: UsageProvider, @unchecked Sendable {
    enum Outcome {
        case success
        case failure(UsageProviderError)
    }

    let id = "claude"
    let displayName = "Claude"
    let glyph = ProviderGlyph.claude
    var outcome: Outcome

    init(outcome: Outcome) { self.outcome = outcome }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        switch outcome {
        case .failure(let error):
            throw error
        case .success:
            return ProviderSnapshot(
                id: id, displayName: displayName, glyph: glyph,
                fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "session", label: "Current session",
                                      usedFraction: 0.42,
                                      resetsAt: Date().addingTimeInterval(3600))]
            )
        }
    }
    func account() -> ProviderAccount? { nil }
    nonisolated var signInRoute: SignInRoute { .guidance("—") }
    func signOut() async {}
    func presentSignIn() {}
    nonisolated func forgetCachedCredential() {}
}
