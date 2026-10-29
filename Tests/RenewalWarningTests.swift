import XCTest
@testable import Leftover

/// The warning that says a saved login has aged out.
///
/// It exists because the failure it reports is invisible everywhere else: an
/// expired token leaves the last reading on screen, still roughly true, and
/// nothing about the ring says the number stopped moving. That is how a frozen
/// reading went twelve hours without being noticed. So the warning is tied to
/// the credential, never to whether there is a number.
@MainActor
final class RenewalWarningTests: XCTestCase {
    private final class Provider: UsageProvider, @unchecked Sendable {
        let id = "claude"
        let displayName = "Claude"
        let glyph = ProviderGlyph.claude
        /// Set to make the next fetch fail the way an aged-out token does.
        var tokenExpired = false

        func fetchSnapshot() async throws -> ProviderSnapshot {
            if tokenExpired { throw UsageProviderError.credentialExpired }
            return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                    fidelity: .official, status: .ok,
                                    windows: [LimitWindow(id: "w", label: "W",
                                                          usedFraction: 0.4)])
        }

        func signOut() async {}
    }

    private func store(_ provider: Provider) -> UsageStore {
        let name = "RenewalWarningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults))
    }

    private func warning(_ store: UsageStore) -> Bool {
        store.providerSummaries.first { $0.id == "claude" }?.needsSignInRenewal ?? false
    }

    // MARK: - Appearance


    func testItAppearsWhenARenewalFails() {
        let store = store(Provider())
        store.reportRenewalFailed(providerID: "claude")
        XCTAssertTrue(warning(store))
    }

    // MARK: - Persistence behind a stale reading


    /// Repeated failures do not pile up or flap.
    func testReportingTwiceChangesNothing() {
        let store = store(Provider())
        store.reportRenewalFailed(providerID: "claude")
        store.reportRenewalFailed(providerID: "claude")
        XCTAssertEqual(store.needsRenewal, ["claude"])
    }

    // MARK: - Disappearance


}
