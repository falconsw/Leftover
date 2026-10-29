import XCTest
@testable import Leftover

/// The rename from UsageNotch to Codenotch moved every setting into a new,
/// empty defaults domain — the migration is the difference between a rename
/// and what looks like a reset, so it is pinned here. (Round-trip and
/// first-launch basics live with the other PreferencesTests.)
@MainActor
final class PreferencesMigrationTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func setOldDomain(_ values: [String: Any], from name: String) {
        let old = UserDefaults(suiteName: name)!
        for (key, value) in values { old.set(value, forKey: key) }
        old.synchronize()
    }

    // MARK: Migration




    // MARK: Defaults


    /// MiniMax is discovered like everyone else, and stays off until switched
    /// on. Claude and Codex are the only families that default on.
    func testMiniMaxStaysOffAfterReconcile() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "minimax"])
        XCTAssertEqual(preferences.connectedProviders, ["claude", "codex"])
        XCTAssertFalse(preferences.isConnected("minimax"))
        XCTAssertTrue(preferences.isConnected("claude"))

        let again = Preferences(defaults: UserDefaults(suiteName: name)!)
        again.reconcile(discoveredIDs: ["claude", "codex", "cursor", "glm", "deepseek", "minimax"])
        XCTAssertFalse(again.isConnected("minimax"))
        XCTAssertFalse(again.isConnected("cursor"))
        XCTAssertFalse(again.isConnected("deepseek"))
        XCTAssertTrue(again.isConnected("claude"))
    }

    /// Kiro is discovered like everyone else, and stays off until switched on.
    /// Claude and Codex are the only families that default on.
    func testKiroStaysOffAfterReconcile() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "kiro"])
        XCTAssertFalse(preferences.isConnected("kiro"))
        XCTAssertTrue(preferences.isConnected("claude"))

        let again = Preferences(defaults: UserDefaults(suiteName: name)!)
        again.reconcile(discoveredIDs: ["claude", "codex", "cursor", "glm", "kiro", "deepseek"])
        XCTAssertFalse(again.isConnected("kiro"))
        XCTAssertFalse(again.isConnected("cursor"))
        XCTAssertFalse(again.isConnected("deepseek"))
        XCTAssertTrue(again.isConnected("claude"))
    }

    func testAFirstLaunchSeedsClaudeAndCodexOnceDiscovered() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "cursor", "glm", "kiro", "minimax", "claude-work"])
        XCTAssertEqual(preferences.connectedProviders, ["claude", "codex", "claude-work"])
        XCTAssertFalse(preferences.isConnected("cursor"))
        XCTAssertFalse(preferences.isConnected("kiro"))
        XCTAssertFalse(preferences.isConnected("minimax"))

        let again = Preferences(defaults: UserDefaults(suiteName: name)!)
        again.reconcile(discoveredIDs: ["claude", "codex", "cursor", "glm", "kiro", "minimax", "claude-work", "deepseek"])
        XCTAssertFalse(again.isConnected("cursor"))
        XCTAssertFalse(again.isConnected("kiro"))
        XCTAssertFalse(again.isConnected("minimax"))
        XCTAssertFalse(again.isConnected("deepseek"))
        XCTAssertTrue(again.isConnected("claude"))
    }

    func testHiddenProvidersInvertAgainstWhatThisMacHas() {
        let (fresh, _) = makeDefaults()
        fresh.set(["glm", "cursor"], forKey: "hiddenProviders")
        let preferences = Preferences(defaults: fresh)
        XCTAssertFalse(preferences.isConnected("glm"))
        XCTAssertTrue(preferences.isConnected("claude"))
        preferences.reconcile(discoveredIDs: ["claude", "codex", "cursor", "glm"])
        XCTAssertEqual(preferences.connectedProviders, ["claude", "codex"])
        XCTAssertFalse(preferences.isConnected("cursor"))
        XCTAssertTrue(preferences.isConnected("claude"))
    }

    func testANewClaudeProfileTurnsOnWithoutReopeningCursor() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "cursor"])
        XCTAssertFalse(preferences.isConnected("cursor"))

        let later = Preferences(defaults: UserDefaults(suiteName: name)!)
        later.reconcile(discoveredIDs: ["claude", "codex", "cursor", "claude-work"])
        XCTAssertTrue(later.isConnected("claude-work"))
        XCTAssertFalse(later.isConnected("cursor"))
    }

    /// A 1.9 install with nothing hidden still shows each loaded model after
    /// the invert. Model cells are not providers: they are absent from the
    /// on-list, and absence there must not mean off.
    func testAnUpgradeDoesNotHideLoadedModels() {
        let (fresh, _) = makeDefaults()
        fresh.set([String](), forKey: "hiddenProviders")
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "ollama-local"])
        let model = "ollama-local:model:qwen3:8b"
        XCTAssertFalse(preferences.disconnectedIDs(among: [
            "claude", "codex", "ollama-local", model
        ]).contains(model))
        XCTAssertTrue(preferences.isConnected(model))
        XCTAssertTrue(preferences.isConnected("ollama-local"))
        XCTAssertTrue(preferences.disabledModels.isEmpty)
    }

    /// Model ids on the old off-list stay off. They are not inverted onto
    /// `connectedProviders`.
    func testAHiddenModelStaysHiddenAfterTheOnListInvert() {
        let (fresh, name) = makeDefaults()
        fresh.set(["glm", "ollama-local:model:qwen3"], forKey: "hiddenProviders")
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "glm", "ollama-local"])
        XCTAssertFalse(preferences.isConnected("glm"))
        XCTAssertTrue(preferences.isConnected("ollama-local"))
        XCTAssertFalse(preferences.isConnected("ollama-local:model:qwen3"))
        XCTAssertEqual(preferences.disabledModels, ["ollama-local:model:qwen3"])
        XCTAssertFalse(preferences.connectedProviders.contains { Preferences.isModelCell($0) })

        let again = Preferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertFalse(again.isConnected("ollama-local:model:qwen3"))
        XCTAssertTrue(again.isConnected("ollama-local"))
    }

    /// An invert that already wrote `connectedProviders` still left model ids
    /// on `hiddenProviders`. Those hides must not be forgotten.
    func testModelHidesSurviveAPreviousInvertThatDroppedThem() {
        let (fresh, _) = makeDefaults()
        fresh.set(["claude", "codex", "ollama-local"], forKey: "connectedProviders")
        fresh.set(["claude", "codex", "ollama-local"], forKey: "seenProviders")
        fresh.set(["ollama-local:model:qwen3"], forKey: "hiddenProviders")
        let preferences = Preferences(defaults: fresh)
        XCTAssertFalse(preferences.isConnected("ollama-local:model:qwen3"))
        XCTAssertTrue(preferences.isConnected("ollama-local"))
        XCTAssertEqual(preferences.disabledModels, ["ollama-local:model:qwen3"])
    }

    /// Recomputing the store off-list after a provider toggle must not hide
    /// models that nobody hid.
    func testSwitchingAProviderDoesNotHideLoadedModels() {
        let (fresh, _) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "cursor", "ollama-local"])
        let model = "ollama-local:model:qwen3:8b"
        XCTAssertTrue(preferences.isConnected(model))
        preferences.setConnected(true, for: "cursor")
        XCTAssertTrue(preferences.isConnected(model))
        XCTAssertFalse(preferences.disconnectedIDs(among: [
            "claude", "codex", "cursor", "ollama-local", model
        ]).contains(model))
        XCTAssertTrue(preferences.disabledModels.isEmpty)
    }

    /// A newly loaded model is on until hidden, and hiding it does not put it
    /// on the provider on-list.
    func testALoadedModelStaysOffTheProviderOnList() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "ollama-local"])
        let model = "ollama-local:model:qwen3:8b"
        XCTAssertTrue(preferences.isConnected(model))
        preferences.setConnected(false, for: model)
        XCTAssertEqual(preferences.disabledModels, [model])
        XCTAssertFalse(preferences.connectedProviders.contains(model))
        XCTAssertFalse(preferences.seenProviders.contains(model))

        let hidden = Preferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertFalse(hidden.isConnected(model))
        hidden.setConnected(true, for: model)
        XCTAssertTrue(hidden.disabledModels.isEmpty)

        let shown = Preferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertTrue(shown.isConnected(model))
        XCTAssertFalse(shown.connectedProviders.contains(model))
    }


    func testTurningOffTheHolidayRuleSurvivesARelaunch() {
        let (fresh, name) = makeDefaults()
        XCTAssertTrue(Preferences(defaults: fresh).deepSeekPricingSchedule.offPeakOnChineseHolidays)

        var schedule = DeepSeekPricing.Schedule.current
        schedule.offPeakOnChineseHolidays = false
        Preferences(defaults: fresh).deepSeekPricingSchedule = schedule

        let reloaded = Preferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertFalse(reloaded.deepSeekPricingSchedule.offPeakOnChineseHolidays)
    }

    /// Off by default, and it has to stay chosen once it is chosen: an extra
    /// arc in a 44pt circle changes how every reading looks, so it is not
    /// something to switch on for somebody, nor to forget they switched on.
    func testTheWeeklyRingIsOffUntilAskedForAndThenSurvivesARelaunch() {
        let (fresh, name) = makeDefaults()
        XCTAssertEqual(Preferences(defaults: fresh).weeklyRing, .off)

        Preferences(defaults: fresh).weeklyRing = .outside

        XCTAssertEqual(Preferences(defaults: UserDefaults(suiteName: name)!).weeklyRing, .outside)
    }

    /// The arc is what every existing install already shows, so the disc has
    /// to be asked for, and has to stay chosen once it is.
    func testTheWorkingIndicatorIsTheArcUntilAskedForAndThenSurvivesARelaunch() {
        let (fresh, name) = makeDefaults()
        XCTAssertEqual(Preferences(defaults: fresh).busyIndicatorStyle, .arc)

        Preferences(defaults: fresh).busyIndicatorStyle = .breath

        XCTAssertEqual(Preferences(defaults: UserDefaults(suiteName: name)!).busyIndicatorStyle, .breath)
    }


    /// On by default — a spent window pretending its rings are usable is the
    /// worse surprise — and it has to stay off across a relaunch once asked.
    func testShutRingsDefaultOnAndSurviveARelaunch() {
        let (fresh, name) = makeDefaults()
        XCTAssertTrue(Preferences(defaults: fresh).shutRingsWhenSpent)

        Preferences(defaults: fresh).shutRingsWhenSpent = false

        XCTAssertFalse(Preferences(defaults: UserDefaults(suiteName: name)!).shutRingsWhenSpent)
    }

    /// Manual by default — the manual arrangement is what dragging built —
    /// and once somebody picks a sort, it has to stay picked across a
    /// relaunch.
    func testAutoOrderStaysManualUntilAskedForAndThenSurvivesARelaunch() {
        let (fresh, name) = makeDefaults()
        XCTAssertEqual(Preferences(defaults: fresh).ringOrder, .manual)

        Preferences(defaults: fresh).ringOrder = .remaining

        XCTAssertEqual(Preferences(defaults: UserDefaults(suiteName: name)!).ringOrder, .remaining)
    }

    /// Off by default — rings disappearing unasked would strand the manual
    /// arrangement — and once somebody flips it, it has to stay flipped
    /// across a relaunch.
    func testDepletedAccountsStayVisibleUntilAskedToHideAndThenSurvivesARelaunch() {
        let (fresh, name) = makeDefaults()
        XCTAssertFalse(Preferences(defaults: fresh).hideDepletedAccounts)

        Preferences(defaults: fresh).hideDepletedAccounts = true

        XCTAssertTrue(Preferences(defaults: UserDefaults(suiteName: name)!).hideDepletedAccounts)
    }



    // MARK: The slider, and which control is in charge





}

@MainActor
final class NotchPositionPersistenceTests: XCTestCase {
}

/// Limits in the menu bar: off until asked for, remembered once chosen, and
/// never mixed up with which providers are read.
@MainActor
final class MenuBarLimitsPreferenceTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "MenuBarLimitsPreferenceTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    private func reopen(_ name: String) throws -> Preferences {
        Preferences(defaults: try XCTUnwrap(UserDefaults(suiteName: name)))
    }





}

/// One channel for every notification. The notch is the default because it
/// is what every earlier version did; the choice has to survive a relaunch.
@MainActor
final class NotificationChannelPreferenceTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "PreferencesTests.channel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }



}

/// How small the notch may be made.
final class NotchScaleRangeTests: XCTestCase {


}
