import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var feed: PanelFeed?
    private var store: UsageStore?
    private var newMenuBar: MenuBarController?
    private var activityCoordinator: ActivityCoordinator?
    private var piResponseMonitor: PiResponseMonitor?
    private var ollamaRelay: OllamaActivityRelay?
    private var lmstudioMetrics: LMStudioMetrics?
    private var omlxMetrics: OMLXMetrics?
    private var preferences: Preferences?
    private var settings: SettingsWindowController?
    private var whatsNew: WhatsNewWindowController?
    private var thresholdNotifier: ThresholdNotifier?
    private var resetWatcher: UsageResetWatcher?
    private var limitWatcher: UsageLimitWatcher?
    /// Keeps the Claude keychain token from ageing out on a Mac where the CLI
    /// is never run by hand. See `ClaudeTokenRefresher`.
    private var tokenRefresher: ClaudeTokenRefresher?
    private var cancellables = Set<AnyCancellable>()
    /// Turns the monitors' running commentary into the one event worth
    /// interrupting for: an agent that has just stopped working.
    private var completions = SessionCompletionWatcher()
    /// Which providers were working as of the last thing a monitor said, so the
    /// moment one stops can be told apart from the many moments it is still
    /// going. Held here rather than asked of `ActivityCoordinator`, which
    /// reports the state after the change and cannot answer what it was before.
    private var busyProviderIDs: Set<String> = []

    /// Quit any copy of Leftover that was already running.
    ///
    /// A second copy would put a second item in the menu bar and poll every
    /// provider twice. A build in `DerivedData`, a staged release and
    /// `/Applications` are separate bundles at separate paths, so the system
    /// launches each as its own process rather than activating the one that is
    /// already up.
    ///
    /// The newcomer wins, deliberately. Quitting the *new* copy instead would
    /// be the wrong way round while developing: the whole point of launching a
    /// fresh build is to replace the one already running.
    ///
    /// Only strictly older instances are asked to go, which is what keeps two
    /// simultaneous launches from each terminating the other and leaving none.
    private static func retireOlderInstances() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let launched = NSRunningApplication.current.launchDate ?? Date()
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        where other.processIdentifier != mine && (other.launchDate ?? .distantPast) < launched {
            Log.usage.info("retiring an older instance (pid \(other.processIdentifier, privacy: .public))")
            if !other.terminate() { other.forceTerminate() }
        }
    }

    /// The snapshots as the rings draw them: the vendor's own, with the weekly
    /// window leading where that is switched on, and the daily pace laid over
    /// that where it is. The menu bar and the alert watchers are deliberately fed the
    /// vendor's own order instead — see their sink.
    static func drawn(_ snapshots: [ProviderSnapshot], weekly: Bool, paced: Bool)
    -> [ProviderSnapshot] {
        DailyPace.apply(to: WeeklyHeadline.apply(to: snapshots, enabled: weekly), enabled: paced)
    }

    /// Every Claude Code configuration directory on this Mac — `~/.claude` and
    /// any `~/.claude-<slug>` — found once at launch. Each gets a usage
    /// provider and a session monitor of its own, keyed by the same id, so a
    /// work login's sessions spin the work ring and nobody else's.
    private let claudeProfiles = ClaudeProfile.discover()
    private let codexProfiles = CodexProfile.discover()
    private let antigravityProfiles = AntigravityProfile.discover()
    private let commandCodeProfiles = CommandCodeProfile.discover()
    /// Held as concrete providers, not just handed to the store: the token
    /// refresher needs to ask one of them how long its token has left, and the
    /// protocol has no business carrying that.
    private var claudeProviders: [ClaudeOAuthProvider] = []
    /// MiniMax Platform sign-in sheet. Not a UsageProvider — that is MiniMaxProvider.
    private var miniMaxWeb: WebSessionProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu bar app: no Dock icon. The Settings window brings it forward when needed.
        NSApp.setActivationPolicy(.accessory)
        Self.retireOlderInstances()
        MacNotifications.installPresenter()

        let preferences = Preferences()
        self.preferences = preferences

        // The app's own look: the Mac's, unless the user has asked for one.
        // Applied to the application rather than to a window, so every
        // window the app opens — the settings, What's New — wears it.
        NSApp.appearance = preferences.appTheme.appearance
        preferences.$appTheme
            .receive(on: RunLoop.main)
            .sink { theme in
                NSApp.appearance = theme.appearance
            }
            .store(in: &cancellables)

        if !preferences.hidesDockIcon {
            NSApp.setActivationPolicy(.regular)
        }
        preferences.$hidesDockIcon
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { hides in
                // Leaving the Dock deactivates the app and takes the settings
                // window behind whatever is in front, while the switch that
                // did it is still under the pointer.
                let window = NSApp.keyWindow
                NSApp.setActivationPolicy(hides ? .accessory : .regular)
                NSApp.activate(ignoringOtherApps: true)
                window?.makeKeyAndOrderFront(nil)
            }
            .store(in: &cancellables)

        let feed = PanelFeed()
        self.feed = feed

        // `LEFTOVER_DEMO=1` puts the design frame's three providers and one
        // local model on screen with its numbers, for screenshots and for
        // eyeballing the layout.
        // The queued local model and the stale ring are there so the busy
        // indicator's two edge cases can be eyeballed.
        let isDemo = ProcessInfo.processInfo.environment["LEFTOVER_DEMO"] == "1"
        if isDemo {
            feed.setSnapshots(Fixtures.snapshots())
            for (id, sessions) in Fixtures.sessions() {
                feed.setSessions(providerID: id, sessions: sessions)
            }
            feed.setLocalActivities(Fixtures.localActivities())
            let menuBar = MenuBarController(
                model: feed.model,
                refresh: { _ in nil },
                onSettings: { [weak self] in self?.openSettings() },
                onOpen: {},
                preferences: preferences)
            self.newMenuBar = menuBar
            // Opened once so a screenshot needs no click on the menu bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { menuBar.open() }
        } else {
            // DeepSeek's Platform usage page is a browser-session provider:
            // login is explicit, stays in Leftover's own WKWebView store, and
            // the page-local requests are refreshed only after that login.
            let deepSeek = WebSessionProvider(site: Sites.deepSeek)
            // QianwenAI's Token Plan is the same kind of provider: no usage API
            // to call, only a console, readable after the user signs in inside
            // this app's own WKWebView. Unlike MiniMax's sheet below, its ring
            // *is* this adapter, so it belongs in `webProviders` — exactly once.
            let qianwen = WebSessionProvider(site: Sites.qianwen)
            let qoder = WebSessionProvider(site: Sites.qoder(region: preferences.qoderRegion))
            // MiniMax's ring is MiniMaxProvider. The sheet is the same kind of
            // WebView DeepSeek uses, but it must not join `webProviders`:
            // those are appended to `allProviders`, and two adapters with
            // id `minimax` would both poll, both draw a row, and fight over
            // the same archive key. Region is applied here and again when
            // Settings changes it, because the fetch URLs live on the site.
            let miniMaxWeb = WebSessionProvider(site: Sites.minimax(region: preferences.minimaxRegion))
            self.miniMaxWeb = miniMaxWeb
            let webProviders: [WebSessionProvider] = [deepSeek, qianwen, qoder]
            // Cursor reads the editor's session, or cursor-agent's if the
            // editor is missing — never a browser one: signing into
            // cursor.com separately created a second, empty account.
            //
            // Built *after* preferences and told what is switched off, so the
            // very first list it draws already excludes them. Constructed first,
            // it drew every provider from the archive and only dropped the
            // switched-off ones once the binding below delivered.
            Log.usage.info("claude profiles: \(self.claudeProfiles.map(\.displayPath).joined(separator: ", "), privacy: .public)")
            Log.usage.info("codex profiles: \(self.codexProfiles.map(\.displayPath).joined(separator: ", "), privacy: .public)")
            Log.usage.info("antigravity profiles: \(self.antigravityProfiles.map(\.displayPath).joined(separator: ", "), privacy: .public)")
            // Named together rather than one by one: a name derived from the
            // signed-in address can collide with another profile's, and a lone
            // profile needs no name beyond "Claude" — only a caller holding
            // every profile can see either.
            let claudeNames = ClaudeProfile.displayNames(for: claudeProfiles)
            let claudeProviders = claudeProfiles.map {
                ClaudeOAuthProvider(profile: $0, displayName: claudeNames[$0.id])
            }
            self.claudeProviders = claudeProviders
            let allProviders: [UsageProvider] = claudeProviders
                + [CursorLocalProvider()]
                + codexProfiles.map { CodexLocalProvider(profile: $0) }
                + antigravityProfiles.map { AntigravityProvider(profile: $0) }
                + [GLMProvider(), MiniMaxProvider(web: miniMaxWeb), GrokLocalProvider(), GrokBotProvider(), DevinLocalProvider(), OpenCodeProvider()]
                + commandCodeProfiles.map { CommandCodeProvider(profile: $0) }
                + [GitHubCopilotProvider(), KimiProvider(), KiroProvider(), AmpProvider(),
                   ApifyProvider(), KiloProvider(), HiggsfieldProvider(),
                   MuseLocalProvider(),
                   OllamaLocalProvider(endpoint: URL(string: preferences.ollamaEndpoint)!),
                   LMStudioLocalProvider(endpoint: URL(string: preferences.lmstudioEndpoint)!),
                   OMLXLocalProvider(endpoint: URL(string: preferences.omlxEndpoint)!),
                   OllamaProvider(),
                   // A closure, not the value: the provider is an actor and
                   // re-reads the budget on every fetch, so a ceiling typed
                   // into Settings applies without a restart.
                   GeminiAPIProvider(budget: {
                       Preferences.storedGeminiAPIMonthlyTokenBudget()
                   })]
                + webProviders
            preferences.reconcile(discoveredIDs: allProviders.map(\.id))
            let store = UsageStore(
                providers: allProviders,
                disconnected: preferences.disconnectedIDs(among: allProviders.map(\.id)),
                // Passed at construction, not left to the sink below, for the
                // same reason `disconnected` is: the sink delivers a run loop
                // turn later, so without this every launch draws the built-in
                // order for a frame and then visibly shuffles.
                order: preferences.providerOrder
            )
            Costs.attach(to: store)
            deepSeek.onAuthenticated = { [weak store] in
                store?.providerAuthenticationChanged(providerID: "deepseek")
            }
            qianwen.onAuthenticated = { [weak store] in
                store?.providerAuthenticationChanged(providerID: "qianwenai")
            }
            qoder.onAuthenticated = { [weak store] in
                store?.providerAuthenticationChanged(providerID: "qoder")
            }
            miniMaxWeb.onAuthenticated = { [weak store] in
                store?.providerAuthenticationChanged(providerID: "minimax")
            }

            let relay = OllamaActivityRelay()
            self.ollamaRelay = relay
            // A single publisher chain exceeds Swift's type-checking time limit.
            let relayPreferences = Publishers.CombineLatest3(
                preferences.$connectedProviders,
                preferences.$ollamaEndpoint,
                preferences.$ollamaMetricsEnabled)
            let relayConfiguration = relayPreferences.map { values in
                (enabled: values.0.contains("ollama-local") && values.2, endpoint: values.1)
            }.eraseToAnyPublisher()
            relayConfiguration
                .removeDuplicates { $0.enabled == $1.enabled && $0.endpoint == $1.endpoint }
                .receive(on: RunLoop.main)
                .sink { [weak relay, weak feed] configuration in
                    feed?.setLocalMetricsEnabled(configuration.enabled)
                    relay?.configure(enabled: configuration.enabled, endpoint: configuration.endpoint)
                }
                .store(in: &cancellables)
            relay.$thinkingModels
                .receive(on: RunLoop.main)
                .sink { [weak feed, weak store] models in
                    let previous = feed?.thinkingModels ?? [:]
                    feed?.setThinkingModels(models)
                    if models.keys.contains(where: { previous[$0] == nil }) { store?.refresh(providerID: "ollama-local") }
                }
                .store(in: &cancellables)

            relay.$performances
                .receive(on: RunLoop.main)
                .sink { [weak feed, weak store] measurements in
                    feed?.setPerformances(measurements)
                    if !measurements.isEmpty { store?.refresh(providerID: "ollama-local") }
                }
                .store(in: &cancellables)

            // LM Studio needs no relay: its own socket says what each model is
            // doing and its own log says what every request cost. Monitoring
            // follows the provider's switch, and the address follows Settings.
            let lmstudio = LMStudioMetrics()
            self.lmstudioMetrics = lmstudio
            // Split like the relay's chain above, and for the same reason.
            let lmstudioPreferences = Publishers.CombineLatest(
                preferences.$connectedProviders, preferences.$lmstudioEndpoint)
            let lmstudioConfiguration = lmstudioPreferences.map { values in
                (enabled: values.0.contains(LMStudioMetrics.providerID), endpoint: values.1)
            }.eraseToAnyPublisher()
            lmstudioConfiguration
                .removeDuplicates { $0.enabled == $1.enabled && $0.endpoint == $1.endpoint }
                .receive(on: RunLoop.main)
                .sink { [weak lmstudio] configuration in
                    lmstudio?.configure(enabled: configuration.enabled, endpoint: configuration.endpoint)
                }
                .store(in: &cancellables)
            lmstudio.$activities
                .receive(on: RunLoop.main)
                .sink { [weak feed] in feed?.setLocalActivities($0, source: LMStudioMetrics.providerID) }
                .store(in: &cancellables)
            lmstudio.$performances
                .receive(on: RunLoop.main)
                .sink { [weak feed, weak store] measurements in
                    feed?.setPerformances(measurements, source: LMStudioMetrics.providerID)
                    if !measurements.isEmpty { store?.refresh(providerID: LMStudioMetrics.providerID) }
                }
                .store(in: &cancellables)
            lmstudio.$ledger
                .receive(on: RunLoop.main)
                .sink { [weak feed] in feed?.setLedger($0, source: LMStudioMetrics.providerID) }
                .store(in: &cancellables)

            // oMLX the same way: its admin activity endpoint says what each
            // model is doing, its server log says what every request cost.
            let omlx = OMLXMetrics()
            self.omlxMetrics = omlx
            // Split like the relay's chain above, and for the same reason.
            let omlxPreferences = Publishers.CombineLatest(
                preferences.$connectedProviders, preferences.$omlxEndpoint)
            let omlxConfiguration = omlxPreferences.map { values in
                (enabled: values.0.contains(OMLXMetrics.providerID), endpoint: values.1)
            }.eraseToAnyPublisher()
            omlxConfiguration
                .removeDuplicates { $0.enabled == $1.enabled && $0.endpoint == $1.endpoint }
                .receive(on: RunLoop.main)
                .sink { [weak omlx] configuration in
                    omlx?.configure(enabled: configuration.enabled, endpoint: configuration.endpoint)
                }
                .store(in: &cancellables)
            omlx.$activities
                .receive(on: RunLoop.main)
                .sink { [weak feed] in feed?.setLocalActivities($0, source: OMLXMetrics.providerID) }
                .store(in: &cancellables)
            omlx.$performances
                .receive(on: RunLoop.main)
                .sink { [weak feed, weak store] measurements in
                    feed?.setPerformances(measurements, source: OMLXMetrics.providerID)
                    if !measurements.isEmpty { store?.refresh(providerID: OMLXMetrics.providerID) }
                }
                .store(in: &cancellables)
            omlx.$ledger
                .receive(on: RunLoop.main)
                .sink { [weak feed] in feed?.setLedger($0, source: OMLXMetrics.providerID) }
                .store(in: &cancellables)

            let settings = SettingsWindowController(
                preferences: preferences,
                // A closure so the sheet re-reads accounts each time it comes
                // forward; a snapshot here is what made a switched account keep
                // showing the old address until the app restarted.
                providers: { [weak store] in store?.providerSummaries ?? [] },
                signOut: { [weak store] in store?.signOut(providerID: $0) },
                signIn: { [weak store] in store?.signIn(providerID: $0) ?? false },
                switchAccount: { [weak store] in
                    store?.openAccountSource(providerID: $0, switching: true) ?? false
                },
                retry: { [weak store] in store?.reauthorize(providerID: $0) },
                sendTestNotification: { [weak self] in
                    self?.sendTestNotification()
                },
                usageStore: store
            )
            self.settings = settings

            // What changed, once per version — including on a fresh install,
            // where it is the introduction.
            let whatsNew = WhatsNewWindowController(
                preferences: preferences, version: AppVersion.current
            )
            self.whatsNew = whatsNew

            // An agent app has no dock icon and no window: installed and
            // launched, it shows four empty rings on a screen edge and no
            // reason to look at them. Once, on the very first run, it opens the
            // one place that explains what to connect.
            //
            // Sequenced behind What's New rather than beside it: two windows
            // arriving together is one to dismiss before you can read either.
            let introduce = { [weak settings] in
                guard preferences.isFirstLaunch else { return }
                settings?.show()
            }
            whatsNew.onDismiss = introduce
            if !whatsNew.showIfNeeded() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: introduce)
            }

            preferences.$deepSeekPricingEnabled
                .receive(on: RunLoop.main)
                .sink { [weak feed] in feed?.model.deepSeekPricingEnabled = $0 }
                .store(in: &cancellables)

            preferences.$deepSeekPricingSchedule
                .receive(on: RunLoop.main)
                .sink { [weak feed] in feed?.model.deepSeekPricingSchedule = $0 }
                .store(in: &cancellables)

            preferences.$qoderRegion
                .dropFirst()
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak qoder, weak store] region in
                    guard let qoder else { return }
                    store?.providerContextChanged(providerID: "qoder") {
                        qoder.apply(site: Sites.qoder(region: region))
                    }
                }
                .store(in: &cancellables)

            // The holiday check is a network request, so it runs only for
            // someone who has DeepSeek on and is shown its pricing. Received on
            // the run loop so `isConnected` reads the value just published.
            Publishers.CombineLatest3(preferences.$deepSeekPricingEnabled,
                                      preferences.$deepSeekPricingSchedule,
                                      preferences.$connectedProviders)
                .receive(on: RunLoop.main)
                .sink { [weak preferences] enabled, schedule, _ in
                    let active = enabled && schedule.offPeakOnChineseHolidays
                        && (preferences?.isConnected("deepseek") ?? false)
                    ChineseHolidays.shared.setActive(active)
                }
                .store(in: &cancellables)

            preferences.$minimaxRegion
                .dropFirst()
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak miniMaxWeb, weak store] region in
                    miniMaxWeb?.apply(site: Sites.minimax(region: region))
                    store?.refresh(providerID: "minimax")
                }
                .store(in: &cancellables)

            Publishers.CombineLatest(preferences.$connectedProviders, preferences.$disabledModels)
                .receive(on: RunLoop.main)
                .sink { [weak store, weak preferences] _, _ in
                    guard let store, let preferences else { return }
                    store.disconnected = preferences.disconnectedIDs(among: store.knownIDs)
                }
                .store(in: &cancellables)

            preferences.$accountNicknames
                .receive(on: RunLoop.main)
                .sink { [weak store] in store?.nicknames = $0 }
                .store(in: &cancellables)

            preferences.$ollamaEndpoint
                .receive(on: RunLoop.main)
                .sink { [weak store] address in
                    guard let endpoint = try? OllamaEndpoint.parse(address) else { return }
                    store?.updateOllamaEndpoint(endpoint)
                }
                .store(in: &cancellables)

            preferences.$lmstudioEndpoint
                .receive(on: RunLoop.main)
                .sink { [weak store] address in
                    guard let endpoint = try? LMStudioEndpoint.parse(address) else { return }
                    store?.updateLMStudioEndpoint(endpoint)
                }
                .store(in: &cancellables)

            preferences.$omlxEndpoint
                .receive(on: RunLoop.main)
                .sink { [weak store] address in
                    guard let endpoint = try? OMLXEndpoint.parse(address) else { return }
                    store?.updateOMLXEndpoint(endpoint)
                }
                .store(in: &cancellables)

            preferences.$providerOrder
                .receive(on: RunLoop.main)
                .sink { [weak store] in store?.order = $0 }
                .store(in: &cancellables)

            // Redraw the Gemini API ring against the new ceiling.
            //
            // `dropFirst` because `@Published` publishes the value it is given
            // at init, and a refresh there would race the store's first poll.
            // `receive(on:)` because `@Published` emits in `willSet` — the hop
            // to the next run loop pass is what lets the `didSet` persist the
            // number before the provider's closure goes looking for it.
            preferences.$geminiAPIMonthlyTokenBudget
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak store] _ in store?.refresh(providerID: "gemini-api") }
                .store(in: &cancellables)

            // Limit crossings become notifications here rather than inside
            // the store: the store fetches, the notifier decides what is
            // worth interrupting someone for, and neither needs to know the
            // other.
            let notifier = ThresholdNotifier(
                isMuted: { [weak preferences] in preferences?.isMutedAlerts(for: $0) ?? false },
                deliver: { ThresholdAlerts.deliver($0) }
            )
            self.thresholdNotifier = notifier

            let resetWatcher = UsageResetWatcher(
                isMuted: { [weak preferences] in preferences?.isMutedAlerts(for: $0) ?? false },
                deliver: { [weak self] event in
                    MainActor.assumeIsolated {
                        self?.announceUsageReset(event: event)
                    }
                }
            )
            self.resetWatcher = resetWatcher

            let limitWatcher = UsageLimitWatcher(
                isMuted: { [weak preferences] in preferences?.isMutedAlerts(for: $0) ?? false },
                deliver: { [weak self] event in
                    MainActor.assumeIsolated {
                        self?.announceUsageLimit(event: event)
                    }
                }
            )
            self.limitWatcher = limitWatcher

            // The daily-pace window is laid over the store's snapshots here,
            // on the way out, rather than inside a provider: it is a reading
            // of a preference as much as of the account, and the store keeps
            // what the vendor said. Paired with the preference so flipping the
            // toggle redraws at once, without a fetch. The weekly-first ring
            // is laid the same way, and for the same reasons — see `drawn`.
            // Auto-order rides along after the derivations, so "most left"
            // means the window actually leading each ring.
            // The preferences ride as one publisher: `combineLatest` takes four
            // publishers at most, and the snapshots plus the four display
            // choices are five.
            let displayOptions = preferences.$claudeDailyPaceRing.combineLatest(
                preferences.$weeklyHeadline, preferences.$ringOrder,
                preferences.$hideDepletedAccounts)
            store.$panelSnapshots
                .combineLatest(displayOptions)
                .receive(on: RunLoop.main)
                .sink { [weak feed] snapshots, options in
                    let (paced, weekly, order, hideDepleted) = options
                    // Before the derivations: the daily pace ring is advisory,
                    // not a spending gate, and judging off it would hide an
                    // account that overspent today's share while the session
                    // still has room.
                    let usable = hideDepleted ? snapshots.filter { !$0.isDepleted } : snapshots
                    var drawn = Self.drawn(usable, weekly: weekly, paced: paced)
                    switch order {
                    case .deficit:   drawn = ProviderOrder.byBurnDeficit(drawn, now: Date())
                    case .remaining: drawn = ProviderOrder.byRemainingUsage(drawn)
                    case .manual:    break
                    }
                    feed?.setSnapshots(drawn)
                }
                .store(in: &cancellables)

            // Not `drawn`: the weekly-first ring is for the rings alone. The
            // menu bar already shows the week beside the short window, under a
            // "Weekly Limit" label that would name the session after a swap.
            // The alert watchers track one headline per provider and tell
            // "session" from "week" by which window leads, so a swap under them
            // re-fires thresholds, announces a reset that did not happen, and
            // leaves a spent session with no "available again" to follow it.
            store.$snapshots
                .combineLatest(preferences.$claudeDailyPaceRing)
                .receive(on: RunLoop.main)
                .sink { snapshots, paced in
                    let snapshots = DailyPace.apply(to: snapshots, enabled: paced)
                    notifier.observe(snapshots)
                    resetWatcher.observe(snapshots)
                    limitWatcher.observe(snapshots)
                }
                .store(in: &cancellables)
            store.start()
            store.$refreshing
                .receive(on: RunLoop.main)
                .sink { [weak feed] ids in feed?.setRefreshing(ids) }
                .store(in: &cancellables)

            // LEFTOVER_DISCOVER=<url> loads that page in the signed-in WebView
            // and logs the API calls it makes — for finding an undocumented
            // endpoint by watching the site rather than guessing at path names.
            if let target = ProcessInfo.processInfo.environment["LEFTOVER_DISCOVER"],
               let url = URL(string: target),
               let provider = webProviders.first(where: { url.host?.contains($0.id) == true })
                   ?? webProviders.first {
                Task {
                    let calls = await provider.recordCalls(on: url)
                    Log.usage.notice("discovered: \(calls.joined(separator: "  "), privacy: .public)")
                }
            }
            self.store = store
            self.newMenuBar = MenuBarController(
                model: feed.model,
                refresh: { [weak store] id in store?.refresh(providerID: id) },
                onSettings: { [weak self] in self?.openSettings() },
                onOpen: { [weak store] in store?.refreshBecauseSomeoneIsLooking() },
                preferences: preferences)
        }

        // What each agent is doing right now, so the panel can say whether it is
        // still working without you switching to it.
        var monitors: [String: any AgentActivityMonitor] = [
            "cursor": CursorActivityMonitor(),
            "grok": GrokActivityMonitor(),
            "gemini-api": GeminiAPIActivityMonitor(),
            "kimi": KimiActivityMonitor(),
        ]
        for profile in antigravityProfiles {
            monitors[profile.id] = AntigravityActivityMonitor(profile: profile)
        }
        var claudeMonitors: [ClaudeSessionMonitor] = []
        var claudeMonitorsByProfile: [(ClaudeProfile, ClaudeSessionMonitor)] = []
        for profile in claudeProfiles {
            let monitor = ClaudeSessionMonitor(
                directory: profile.sessionsDirectory,
                projects: profile.projectsDirectory
            )
            claudeMonitors.append(monitor)
            claudeMonitorsByProfile.append((profile, monitor))
            monitors[profile.id] = monitor
        }

        // With one profile there is nothing to attribute: every session in the
        // directory is that account's, by definition. With two or more there
        // is, because the Claude desktop app files the sessions it hosts under
        // the *default* profile's directory whichever account it is signed in
        // to — so the second account's work spun the first account's ring, and
        // switching account in the app did not move it. See
        // `ClaudeSessionOwnership`.
        if claudeProfiles.count > 1 {
            let index = ClaudeDesktopSessionIndex()
            let directories = claudeProfiles.map(\.sessionsDirectory)
            var accounts: [String: String] = [:]
            var transcripts: [String: ClaudeTranscriptReader] = [:]
            for profile in claudeProfiles {
                let path = profile.sessionsDirectory.path
                if let account = profile.accountID() { accounts[path] = account }
                transcripts[path] = ClaudeTranscriptReader(projects: profile.projectsDirectory)
            }
            let profileIDs = Dictionary(uniqueKeysWithValues: claudeProfiles.map {
                ($0.sessionsDirectory.path, $0.id)
            })
            for (profile, monitor) in claudeMonitorsByProfile {
                var ownership = ClaudeSessionOwnership(
                    own: profile.sessionsDirectory,
                    directories: directories,
                    accounts: accounts,
                    transcripts: transcripts,
                    index: index
                )
                ownership.isShown = { [weak preferences] directory in
                    guard let preferences, let id = profileIDs[directory.path] else { return true }
                    return preferences.isConnected(id)
                }
                monitor.ownership = ownership
            }
            let named = accounts.count, total = claudeProfiles.count
            Log.sessions.info("claude session ownership: \(named, privacy: .public) of \(total, privacy: .public) profiles name an account")
        }
        for profile in codexProfiles {
            monitors[profile.id] = CodexActivityMonitor(profile: profile)
        }

        // The `/usage` probe is a Claude Code process too, and files a session
        // for the seconds it runs. Every Claude monitor steps over it by pid
        // and by its scratch directory, whether or not a token refresher runs
        // below. Without this the probe showed as a `busy` session, vanished,
        // and was announced as a turn that finished.
        for monitor in claudeMonitors {
            monitor.ignoredPIDs = { ClaudeUsageCLI.runningPIDs }
            monitor.ignoredWorkingDirectories = [ClaudeUsageCLI.scratchLocation().path]
        }

        // Renewing the token runs the Claude command, which registers a session
        // of its own for the second it lives. Every Claude monitor is told to
        // step over that pid, so it never reaches the panel and never counts as
        // work in progress.
        //
        // Only the default profile is renewed. The command writes whichever
        // directory `CLAUDE_CONFIG_DIR` names, so a second profile would need
        // that passed through — behaviour nobody has been able to try on a Mac
        // with two of them, and an unverified guess is worse here than a ring
        // that ages the way it already does.
        if let defaultProvider = claudeProviders.first(where: { $0.profile.slug == nil }) {
            let refresher = ClaudeTokenRefresher(
                expiry: { await defaultProvider.tokenExpiry },
                reload: { await defaultProvider.reloadTokenExpiry() }
            )
            for monitor in claudeMonitors {
                monitor.ignoredPIDs = { [weak refresher] in
                    var pids = ClaudeUsageCLI.runningPIDs
                    if let pid = refresher?.launchedPID { pids.insert(pid) }
                    return pids
                }
            }
            // The one place the failure becomes visible. The store carries the
            // fact; nothing here retries, and the warning clears itself the
            // moment a reading comes back.
            refresher.$outcome
                .receive(on: RunLoop.main)
                .sink { [weak self] outcome in
                    guard case .failed = outcome else { return }
                    self?.store?.reportRenewalFailed(providerID: defaultProvider.id)
                }
                .store(in: &cancellables)

            refresher.start()
            tokenRefresher = refresher
        }
        let activity = ActivityCoordinator(monitors: monitors) { [weak self, weak feed] id, sessions in
            guard let feed else { return }
            feed.setSessions(providerID: id, sessions: sessions)
            self?.announceCompletions(sessions: feed.sessions)
            self?.noteWorkState(providerID: id, sessions: sessions)
        }
        self.activityCoordinator = activity
        // Demo mode shows fixed sample data. A live monitor publishes on
        // subscribe, so its first emission (usually no sessions at all) would
        // overwrite the fixture sessions under the same provider id. Never
        // enabling the coordinator also keeps Pi's supplemental sessions out,
        // since it drops them for any provider that is not enabled.
        if !isDemo {
            activity.setEnabled(preferences.connectedProviders)
            preferences.$connectedProviders
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak activity] connected in
                    activity?.setEnabled(connected)
                }
                .store(in: &cancellables)
        }

        let piResponseMonitor = PiResponseMonitor(
            onResponse: { [weak self] providerID in
                _ = self?.store?.refresh(providerID: providerID)
            },
            onActivity: { [weak activity] providerID, snapshots in
                let sessions = snapshots.map {
                    AgentSession(
                        id: $0.id,
                        name: $0.model,
                        detail: L10n.t("Working"),
                        state: .busy,
                        waitingFor: nil,
                        since: $0.since
                    )
                }
                activity?.setSupplementalSessions(
                    providerID: providerID,
                    source: "pi",
                    sessions: sessions
                )
            }
        )
        piResponseMonitor.start()
        self.piResponseMonitor = piResponseMonitor

        store?.isBusy = { [weak self, weak activity] in
            (activity?.isBusy ?? false) || (self?.lmstudioMetrics?.isBusy ?? false)
                || (self?.omlxMetrics?.isBusy ?? false)
        }
        // Read on every look rather than carried in by a sink, for the reason
        // `isBusy` is: a stored copy answers with whatever the preference was
        // when it was last delivered, and this one is a switch somebody flips to
        // compare two numbers on screen right now.
        store?.asksProviderOnLook = { [weak self] in
            self?.preferences?.asksProviderOnLook ?? false
        }

        MacNotifications.requestAuthorizationIfNeeded()

        let model = feed.model
        model.resetTimeFormat = preferences.resetTimeFormat
        model.accentColor = preferences.accentColor
        model.watchLimit = preferences.watchLimit
        model.criticalLimit = preferences.criticalLimit
        model.colorTransitionStyle = preferences.colorTransitionStyle
        model.weeklyRing = preferences.weeklyRing
        model.weeklyRingDashed = preferences.weeklyRingDashed
        model.deepSeekPricingEnabled = preferences.deepSeekPricingEnabled
        model.deepSeekPricingSchedule = preferences.deepSeekPricingSchedule
    }

    /// Make a noise, and post a notification, when an agent has just
    /// finished or stopped to ask something.
    ///
    /// The watcher is fed on every publication whether or not anything is
    /// switched on, because it is a difference engine: skipping a reading would
    /// leave it comparing against a state two changes old.
    @MainActor
    private func announceCompletions(sessions: [String: [AgentSession]]) {
        let events = completions.absorb(sessions)
        guard let event = events.first, let preferences else { return }
        Log.usage.info("session \(event.session.name, privacy: .public) \(String(describing: event.reason), privacy: .public)")

        if preferences.sessionEndSound {
            SessionChime.play(event.reason == .blocked
                              ? preferences.sessionBlockedSoundName
                              : preferences.sessionEndSoundName)
        }
        guard preferences.announceSessionEnd else { return }
        MacNotifications.sessionEnded(name: event.session.name, blocked: event.reason == .blocked)
    }

    /// Takes one reading on the falling edge of a provider's work.
    ///
    /// Work that has just started has not spent anything yet; the falling edge
    /// is where the figure somebody came to look at — what that run cost — is
    /// worth a fetch. See `UsageStore.refreshBecauseWorkFinished`.
    @MainActor
    private func noteWorkState(providerID: String, sessions: [AgentSession]) {
        let isBusy = sessions.contains { $0.state == .busy }
        if busyProviderIDs.contains(providerID), !isBusy {
            store?.refreshBecauseWorkFinished(providerID: providerID)
        }
        if isBusy {
            busyProviderIDs.insert(providerID)
        } else {
            busyProviderIDs.remove(providerID)
        }
    }

    @MainActor
    private func sendTestNotification() {
        MacNotifications.test()
    }

    @MainActor
    private func announceUsageReset(event: UsageResetEvent) {
        guard let preferences else { return }
        Log.usage.info("usage reset for \(event.providerName, privacy: .public) (\(event.windowLabel, privacy: .public))")
        if preferences.usageResetSound {
            SessionChime.play(preferences.usageResetSoundName)
        }
        guard preferences.announceUsageReset else { return }
        UsageAlertNotifications.deliver(event)
    }

    @MainActor
    private func announceUsageLimit(event: UsageAlertEvent) {
        guard let preferences else { return }
        let isAnnounceEnabled: Bool
        switch event.kind {
        case .sessionLimitReached: isAnnounceEnabled = preferences.announceSessionLimitReached
        case .weeklyLimitReached:  isAnnounceEnabled = preferences.announceWeeklyLimitReached
        case .reset:               isAnnounceEnabled = preferences.announceUsageReset
        }
        guard isAnnounceEnabled else { return }
        Log.usage.info("usage limit reached for \(event.providerName, privacy: .public) (\(event.windowLabel, privacy: .public))")
        if preferences.limitReachedSound {
            SessionChime.play(preferences.limitReachedSoundName)
        }
        UsageAlertNotifications.deliver(event)
    }

    /// Closing the settings window must not take the app with it.
    ///
    /// Otherwise shutting the settings would quit the menu bar item with them.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Launching the app again while it is already running lands here, so
    /// opening it from Applications or Spotlight reopens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return true
    }

    @MainActor func openSettings() { settings?.show() }

    func applicationWillTerminate(_ notification: Notification) {
        ollamaRelay?.configure(enabled: false, endpoint: OllamaEndpoint.defaultAddress)
        lmstudioMetrics?.stop()
        omlxMetrics?.stop()
        tokenRefresher?.stop()
        piResponseMonitor?.stop()
        store?.stop()
        activityCoordinator?.stop()
        // A language server this app started, if any. Left running it would
        // outlive the reason it exists and keep answering on loopback to
        // nothing.
        AntigravityBridge.owned.stop()
    }
}
