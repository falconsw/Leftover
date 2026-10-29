import XCTest
@testable import Leftover

@MainActor
final class OllamaPreferencesTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "OllamaPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testFreshAndUpstreamUsersKeepInventoryEnabledWithoutStartingRelay() {
        let store = defaults()
        let fresh = Preferences(defaults: store)
        XCTAssertFalse(fresh.isConnected("ollama-local"))
        XCTAssertFalse(fresh.ollamaMetricsEnabled)
        fresh.setConnected(false, for: "ollama-local")
        let next = Preferences(defaults: store)
        XCTAssertFalse(next.isConnected("ollama-local"))
        XCTAssertFalse(next.ollamaMetricsEnabled)
    }

    func testLegacyEnabledRelayChoiceSurvivesAndCanonicalDisconnectionWins() {
        let store = defaults()
        store.set(true, forKey: "introducedOllama")
        XCTAssertTrue(Preferences(defaults: store).ollamaMetricsEnabled)
        store.set(["ollama-local"], forKey: "hiddenProviders")
        XCTAssertFalse(Preferences(defaults: store).ollamaMetricsEnabled)
    }

    func testUnrelatedOllamaIDIsNotRenamedWithoutLegacySentinel() {
        let store = defaults()
        store.set(["ollama"], forKey: "hiddenProviders")
        store.set(["ollama", "codex"], forKey: "providerOrder")
        let preferences = Preferences(defaults: store)
        XCTAssertFalse(preferences.isConnected("ollama"))
        XCTAssertEqual(preferences.providerOrder, ["ollama", "codex"])
        XCTAssertTrue(preferences.isConnected("ollama-local"))
    }
}
