import Combine
import Foundation
import ServiceManagement
import os

/// What the user has chosen, kept in `UserDefaults`.
@MainActor
final class Preferences: ObservableObject {
    static let showUsagePaceKey = "showUsagePace"
    /// Beside `showUsagePaceKey` rather than inside `Keys`: the tooltip card
    /// reads it straight from the store, and `Keys` is private.
    static let showsRemainingInNotchKey = "showsRemainingInNotch"

    /// Provider IDs that currently have a ring. Stored as the ones that are
    /// on, so a provider added later stays off until someone switches it on —
    /// Claude and Codex excepted, which still default on as a family.
    @Published var connectedProviders: Set<String> {
        didSet { defaults.set(Array(connectedProviders), forKey: Keys.connected) }
    }

    /// Every provider id this copy has already decided on, so a later version's
    /// new provider is recognised as new rather than as "never chosen".
    @Published private(set) var seenProviders: Set<String> {
        didSet { defaults.set(Array(seenProviders), forKey: Keys.seen) }
    }

    /// Loaded-model cells hide without stopping the shared runtime. Stored as
    /// the ones that are off: a model Ollama or LM Studio loads later stays
    /// visible until someone hides it. Providers cannot share this list —
    /// their on-list treats absence as off.
    @Published private(set) var disabledModels: Set<String> {
        didSet { defaults.set(Array(disabledModels), forKey: Keys.disabledModels) }
    }

    /// The old hidden-providers list, kept only until `reconcile` can invert it
    /// against the ids actually on this Mac.
    private var pendingHidden: Set<String>?

    @Published var ollamaMetricsEnabled: Bool {
        didSet { defaults.set(ollamaMetricsEnabled, forKey: Keys.ollamaMetricsEnabled) }
    }

    @Published var ollamaEndpoint: String {
        didSet { defaults.set(ollamaEndpoint, forKey: Keys.ollamaEndpoint) }
    }

    /// Where LM Studio's server answers. Defaults to the port LM Studio's own
    /// settings name, so a server moved off 1234 is found without typing.
    @Published var lmstudioEndpoint: String {
        didSet { defaults.set(lmstudioEndpoint, forKey: Keys.lmstudioEndpoint) }
    }

    @Published var omlxEndpoint: String {
        didSet { defaults.set(omlxEndpoint, forKey: Keys.omlxEndpoint) }
    }

    /// Providers whose threshold alerts are muted. Stored as the muted set so
    /// a provider added later alerts by default. Connection is stored the
    /// other way: the ones that are on.
    @Published var mutedAlertProviders: Set<String> {
        didSet { defaults.set(Array(mutedAlertProviders), forKey: Keys.mutedAlerts) }
    }

    /// Names given to accounts in Settings, by provider id. Only the ones
    /// set: an account with no entry keeps the name its provider gives.
    @Published var accountNicknames: [String: String] {
        didSet { defaults.set(accountNicknames, forKey: Keys.accountNicknames) }
    }

    /// The order the user has dragged the rings into, as provider ids.
    ///
    /// Stored as the ids actually placed rather than as every id known at the
    /// time: providers are discovered at launch — Claude Code contributes one
    /// per `~/.claude-<slug>` — so an exhaustive list written today is wrong
    /// the moment a profile appears. `ProviderOrder` reconciles the two,
    /// forgivingly in both directions.
    ///
    /// Empty means never chosen, which is not the same as having chosen the
    /// order the app ships with: keeping them distinct is what lets a later
    /// version change the built-in order for everyone who never had an opinion.
    @Published var providerOrder: [String] {
        didSet { defaults.set(providerOrder, forKey: Keys.order) }
    }

    /// The preferred limit window to show for Antigravity provider (automatic, 5h, or weekly).
    @Published var antigravityHeadlineLimit: AntigravityHeadlineLimit {
        didSet { defaults.set(antigravityHeadlineLimit.rawValue, forKey: Keys.antigravityHeadlineLimit) }
    }

    /// The preferred model group to show for Antigravity provider (Gemini or Claude and GPT models).
    @Published var antigravityHeadlineModel: AntigravityHeadlineModel {
        didSet { defaults.set(antigravityHeadlineModel.rawValue, forKey: Keys.antigravityHeadlineModel) }
    }

    @Published var resetTimeFormat: ResetTimeFormat {
        didSet { defaults.set(resetTimeFormat.rawValue, forKey: Keys.resetTimeFormat) }
    }

    @Published var showUsagePace: Bool {
        didSet { defaults.set(showUsagePace, forKey: Self.showUsagePaceKey) }
    }

    /// Whether pointing at a ring, or opening the menu bar's menu, refuses every
    /// reading a provider is holding and asks the provider itself.
    ///
    /// Off by default, and it has to be: it is not strictly better. A look
    /// already asks for a live reading, which is served from a cache only while
    /// that cache is newer than a couple of minutes. This spends a request even
    /// when the cache was written seconds ago — and on a provider that rate
    /// limits, one request too many is answered with a back-off that then holds
    /// a number older than the cache would have been. Worth having for somebody
    /// comparing Leftover against a vendor's own dashboard figure by figure;
    /// not worth making everybody pay for.
    @Published var asksProviderOnLook: Bool {
        didSet { defaults.set(asksProviderOnLook, forKey: Keys.asksProviderOnLook) }
    }

    /// Whether Leftover stays out of the Dock and the app switcher, living in
    /// the menu bar alone.
    @Published var hidesDockIcon: Bool {
        didSet { defaults.set(hidesDockIcon, forKey: Keys.hidesDockIcon) }
    }

    /// Whether Claude's big ring shows the day's share of the weekly limit
    /// instead of the session. See `DailyPace`.
    @Published var claudeDailyPaceRing: Bool {
        didSet { defaults.set(claudeDailyPaceRing, forKey: Keys.claudeDailyPaceRing) }
    }

    /// Whether the big ring shows the weekly limit instead of the shorter
    /// window, for every provider that has both. See `WeeklyHeadline`.
    @Published var weeklyHeadline: Bool {
        didSet { defaults.set(weeklyHeadline, forKey: Keys.weeklyHeadline) }
    }

    /// Whether DeepSeek's current peak/off-peak billing phase is shown in its
    /// usage card. Enabled by default because the card's pricing rows are
    /// useful only when the rule is visible and understood.
    @Published var deepSeekPricingEnabled: Bool {
        didSet { defaults.set(deepSeekPricingEnabled, forKey: Keys.deepSeekPricingEnabled) }
    }

    /// The locally maintained DeepSeek billing rule. It is stored as one
    /// Codable value so adding another rule field does not scatter more keys
    /// through the preferences store.
    @Published var deepSeekPricingSchedule: DeepSeekPricing.Schedule {
        didSet {
            let normalized = deepSeekPricingSchedule.normalized
            if normalized != deepSeekPricingSchedule {
                deepSeekPricingSchedule = normalized
                return
            }
            guard let data = try? JSONEncoder().encode(deepSeekPricingSchedule) else { return }
            defaults.set(data, forKey: Keys.deepSeekPricingSchedule)
        }
    }

    /// Whether a spent window shuts the rings beside it. A spent 5-hour with
    /// a healthy week, or the reverse, leaves rings that read usable and are
    /// not: with this on, both rings say shut instead — dark grey where the
    /// panel reads what is left, the red 100% earns where it reads spent.
    ///
    /// On by default: a spent window pretending its rings are usable is the
    /// worse surprise.
    @Published var shutRingsWhenSpent: Bool {
        didSet { defaults.set(shutRingsWhenSpent, forKey: Keys.shutRingsWhenSpent) }
    }

    /// In what order the panel draws its rings: the manual arrangement
    /// dragging built, most remaining first, or quota expiring soonest
    /// first. See `RingOrder` for why it is one choice rather than two
    /// switches.
    ///
    /// Manual by default: the manual arrangement is what dragging built,
    /// and re-sorting unasked would strand it.
    @Published var ringOrder: RingOrder {
        didSet { defaults.set(ringOrder.rawValue, forKey: Keys.ringOrder) }
    }

    /// Whether accounts with nothing left to spend leave the panel: the
    /// headline window or the weekly allowance at 0% remaining. Stale
    /// readings stay — an old number is not proof the account is empty.
    ///
    /// Off by default: rings disappearing unasked would strand the manual
    /// arrangement, and an empty ring is still information about the account.
    @Published var hideDepletedAccounts: Bool {
        didSet { defaults.set(hideDepletedAccounts, forKey: Keys.hideDepletedAccounts) }
    }

    @Published var weeklyRingDashed: Bool {
        didSet { defaults.set(weeklyRingDashed, forKey: Keys.weeklyRingDashed) }
    }

    @Published var weeklyRing: WeeklyRing {
        didSet { defaults.set(weeklyRing.rawValue, forKey: Keys.weeklyRing) }
    }


    /// The colour used for positive usage and active-work indicators.
    @Published var accentColor: AccentColorChoice {
        didSet { defaults.set(accentColor.rawValue, forKey: Keys.accentColor) }
    }

    /// Which look the app wears: the Mac's own, or one this app insists on.
    @Published var appTheme: AppTheme {
        didSet { defaults.set(appTheme.rawValue, forKey: Keys.appTheme) }
    }

    /// How see-through the menu bar panel is, from 0 (solid) to 0.8.
    ///
    /// The panel floats over whatever the user is doing, so it can be as
    /// present or as ghostly as they like: the desktop shows through the rest.
    /// What the menu bar item prints beside the logo.
    @Published var menuBarTitleStyle: MenuBarTitleStyle {
        didSet { defaults.set(menuBarTitleStyle.rawValue, forKey: Keys.menuBarTitleStyle) }
    }

    /// The provider the menu bar item reports, as an id. Nil follows the most
    /// used one.
    @Published var menuBarProviderID: String? {
        didSet { defaults.set(menuBarProviderID, forKey: Keys.menuBarProviderID) }
    }

    /// Whether the menu bar item prints what is left rather than what is used.
    @Published var menuBarShowsRemaining: Bool {
        didSet { defaults.set(menuBarShowsRemaining, forKey: Keys.menuBarShowsRemaining) }
    }

    @Published var panelTransparency: Double {
        didSet {
            let clamped = min(max(panelTransparency, 0), 0.8)
            if clamped != panelTransparency { panelTransparency = clamped; return }
            defaults.set(clamped, forKey: Keys.panelTransparency)
        }
    }

    @Published var watchLimit: Double {
        didSet {
            let clamped = min(max(watchLimit, 0.01), criticalLimit - 0.01)
            if clamped != watchLimit { watchLimit = clamped; return }
            defaults.set(watchLimit, forKey: Keys.watchLimit)
        }
    }

    @Published var criticalLimit: Double {
        didSet {
            let clamped = min(max(criticalLimit, watchLimit + 0.01), 1.0)
            if clamped != criticalLimit { criticalLimit = clamped; return }
            defaults.set(criticalLimit, forKey: Keys.criticalLimit)
        }
    }

    /// Hard step or continuous ramp — see `ColorTransitionStyle`.
    @Published var colorTransitionStyle: ColorTransitionStyle {
        didSet { defaults.set(colorTransitionStyle.rawValue, forKey: Keys.colorTransitionStyle) }
    }

    /// Spinning arc or breathing disc — see `BusyIndicatorStyle`.
    @Published var busyIndicatorStyle: BusyIndicatorStyle {
        didSet { defaults.set(busyIndicatorStyle.rawValue, forKey: Keys.busyIndicatorStyle) }
    }

    /// The language the app itself speaks.
    ///
    /// `.system` follows the Mac. Written through `L10n.apply` so the store
    /// and the change notification stay a single write.
    @Published var language: AppLanguage {
        didSet { L10n.apply(language) }
    }

    /// Post a notification when an agent stops working.
    ///
    /// On by default: the app already knows the moment a session ends, and a
    /// user who installed a thing that watches sessions is unlikely to want
    /// that particular fact kept from them.
    @Published var announceSessionEnd: Bool {
        didSet { defaults.set(announceSessionEnd, forKey: Keys.announceSessionEnd) }
    }

    /// Play a sound alongside the notification.
    @Published var sessionEndSound: Bool {
        didSet { defaults.set(sessionEndSound, forKey: Keys.sessionEndSound) }
    }

    /// Which sound a finished turn makes.
    @Published var sessionEndSoundName: String {
        didSet { defaults.set(sessionEndSoundName, forKey: Keys.sessionEndSoundName) }
    }

    /// And which one a session blocked on you makes.
    ///
    /// A separate choice because the two say different things — one is "that's
    /// done", the other is "you are the hold-up" — and a single sound for both
    /// makes the second one easy to ignore.
    @Published var sessionBlockedSoundName: String {
        didSet { defaults.set(sessionBlockedSoundName, forKey: Keys.sessionBlockedSoundName) }
    }

    /// Post a notification when a provider's limit resets.
    @Published var announceUsageReset: Bool {
        didSet { defaults.set(announceUsageReset, forKey: Keys.announceUsageReset) }
    }

    /// Sound an alert alongside the usage reset notification modal.
    @Published var usageResetSound: Bool {
        didSet { defaults.set(usageResetSound, forKey: Keys.usageResetSound) }
    }

    /// Which sound a usage reset notification makes.
    @Published var usageResetSoundName: String {
        didSet { defaults.set(usageResetSoundName, forKey: Keys.usageResetSoundName) }
    }

    /// Post a notification when a provider's session limit is reached.
    @Published var announceSessionLimitReached: Bool {
        didSet { defaults.set(announceSessionLimitReached, forKey: Keys.announceSessionLimitReached) }
    }

    /// Post a notification when a provider's weekly limit is reached.
    @Published var announceWeeklyLimitReached: Bool {
        didSet { defaults.set(announceWeeklyLimitReached, forKey: Keys.announceWeeklyLimitReached) }
    }

    /// Sound an alert alongside the limit reached notification modal.
    @Published var limitReachedSound: Bool {
        didSet { defaults.set(limitReachedSound, forKey: Keys.limitReachedSound) }
    }

    /// Which sound a limit reached notification makes.
    @Published var limitReachedSoundName: String {
        didSet { defaults.set(limitReachedSoundName, forKey: Keys.limitReachedSoundName) }
    }

    /// The ceiling the Gemini API ring fills against, counted in tokens.
    ///
    /// In tokens rather than money because a bare `GEMINI_API_KEY` publishes no
    /// limit of any kind — there is nothing to read, so the ceiling has to come
    /// from the user — and because prices change under the app while a token
    /// stays a token. `nil` means no ceiling, which is the honest default: the
    /// key is billed per token with no cap.
    @Published var geminiAPIMonthlyTokenBudget: Int? {
        didSet {
            if let budget = geminiAPIMonthlyTokenBudget, budget > 0 {
                defaults.set(budget, forKey: Keys.geminiAPIMonthlyTokenBudget)
            } else {
                defaults.removeObject(forKey: Keys.geminiAPIMonthlyTokenBudget)
            }
        }
    }

    @Published var qoderRegion: Sites.QoderRegion {
        didSet { defaults.set(qoderRegion.rawValue, forKey: Keys.qoderRegion) }
    }

    /// Which MiniMax console the Coding Plan is read from.
    ///
    /// International and China mainland are different hosts, and a key issued
    /// on one is refused by the other. Absent means never chosen, which is
    /// international.
    @Published var minimaxRegion: MiniMaxRegion {
        didSet { defaults.set(minimaxRegion.rawValue, forKey: Keys.minimaxRegion) }
    }

    /// The version whose changes have already been shown.
    ///
    /// Written when the What's New dialogue is dismissed rather than when it
    /// opens, so a crash in between cannot swallow the one launch it was going
    /// to appear on.
    @Published var lastSeenVersion: String? {
        didSet { defaults.set(lastSeenVersion, forKey: Keys.lastSeenVersion) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != Self.isRegisteredForLogin else { return }
            applyLaunchAtLogin()
        }
    }

    /// Set when the login-item request was refused, so the UI can say so rather
    /// than quietly flipping the switch back.
    @Published private(set) var launchAtLoginProblem: String?

    private let defaults: UserDefaults
    private enum Keys {
        /// The old off-list. Kept so a 1.9 install can invert it once.
        static let disconnected = "hiddenProviders"
        static let connected = "connectedProviders"
        static let seen = "seenProviders"
        static let disabledModels = "disabledModels"
        static let ollamaEndpoint = "ollamaEndpoint"

        static let lmstudioEndpoint = "lmstudioEndpoint"
        static let omlxEndpoint = "omlxEndpoint"
        static let introducedOllama = "introducedOllama"
        static let ollamaMetricsEnabled = "ollamaMetricsEnabled"
        static let mutedAlerts = "mutedAlertProviders"
        static let accountNicknames = "accountNicknames"
        static let hasLaunched = "hasLaunchedBefore"
        static let resetTimeFormat = "resetTimeFormat"
        static let asksProviderOnLook = "asksProviderOnLook"
        static let hidesDockIcon = "hidesDockIcon"
        static let accentColor = "accentColor"
        static let appTheme = "appTheme"
        static let panelTransparency = "panelTransparency"
        static let menuBarTitleStyle = "menuBarTitleStyle"
        static let menuBarProviderID = "menuBarProviderID"
        static let menuBarShowsRemaining = "menuBarShowsRemaining"
        static let weeklyRing = "weeklyRing"
        static let weeklyRingDashed = "weeklyRingDashed"
        static let shutRingsWhenSpent = "shutRingsWhenSpent"
        static let ringOrder = "ringOrder"
        static let hideDepletedAccounts = "hideDepletedAccounts"
        static let claudeDailyPaceRing = "claudeDailyPaceRing"
        static let weeklyHeadline = "weeklyHeadline"
        static let watchLimit = "watchLimit"
        static let criticalLimit = "criticalLimit"
        static let colorTransitionStyle = "colorTransitionStyle"
        static let busyIndicatorStyle = "busyIndicatorStyle"
        static let lastSeenVersion = "lastSeenVersion"
        static let order = "providerOrder"
        static let announceSessionEnd = "announceSessionEnd"
        static let sessionEndSound = "sessionEndSound"
        static let sessionEndSoundName = "sessionEndSoundName"
        static let sessionBlockedSoundName = "sessionBlockedSoundName"
        static let announceUsageReset = "announceUsageReset"
        static let usageResetSound = "usageResetSound"
        static let usageResetSoundName = "usageResetSoundName"
        static let announceSessionLimitReached = "announceSessionLimitReached"
        static let announceWeeklyLimitReached = "announceWeeklyLimitReached"
        static let limitReachedSound = "limitReachedSound"
        static let limitReachedSoundName = "limitReachedSoundName"
        static let geminiAPIMonthlyTokenBudget = "geminiAPIMonthlyTokenBudget"
        static let minimaxRegion = "minimaxRegion"
        static let qoderRegion = "qoderRegion"
        static let antigravityHeadlineLimit = "antigravityHeadlineLimit"
        static let antigravityHeadlineModel = "antigravityHeadlineModel"
        static let deepSeekPricingEnabled = "deepSeekPricingEnabled"
        static let deepSeekPricingSchedule = "deepSeekPricingSchedule"
    }

    /// The budget read straight from disk, off the main actor.
    ///
    /// The Gemini API provider is an actor and asks for this on every fetch, and
    /// `@Published` state is main-actor-isolated where `UserDefaults` is
    /// thread-safe — so the provider reads the store, not the object.
    nonisolated static func storedGeminiAPIMonthlyTokenBudget(
        defaults: UserDefaults = .standard
    ) -> Int? {
        guard let budget = defaults.object(forKey: Keys.geminiAPIMonthlyTokenBudget) as? Int,
              budget > 0
        else { return nil }
        return budget
    }
    
    nonisolated static func storedAntigravityHeadlineLimit(
        defaults: UserDefaults = .standard
    ) -> AntigravityHeadlineLimit {
        guard let value = defaults.string(forKey: Keys.antigravityHeadlineLimit),
              let limit = AntigravityHeadlineLimit(rawValue: value)
        else { return .automatic }
        return limit
    }

    nonisolated static func storedAntigravityHeadlineModel(
        defaults: UserDefaults = .standard
    ) -> AntigravityHeadlineModel {
        guard let value = defaults.string(forKey: Keys.antigravityHeadlineModel),
              let model = AntigravityHeadlineModel(rawValue: value)
        else { return .gemini }
        return model
    }

    /// The MiniMax region read straight from disk, off the main actor.
    ///
    /// The provider is an actor and asks for this on every fetch, and
    /// `@Published` state is main-actor-isolated where `UserDefaults` is
    /// thread-safe — so the provider reads the store, not the object.
    nonisolated static func storedMinimaxRegion(
        defaults: UserDefaults = .standard
    ) -> MiniMaxRegion {
        guard let value = defaults.string(forKey: Keys.minimaxRegion),
              let region = MiniMaxRegion(rawValue: value)
        else { return .international }
        return region
    }

    /// True the very first time this copy runs, and never again.
    ///
    /// Deliberately *not* inferred from "there are no readings yet" — that is
    /// also true of someone who switched every provider off, and re-introducing
    /// them to the app every launch would be worse than never introducing them
    /// at all.
    let isFirstLaunch: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isFirstLaunch = !defaults.bool(forKey: Keys.hasLaunched)
        defaults.set(true, forKey: Keys.hasLaunched)
        let storedConnected = defaults.stringArray(forKey: Keys.connected)
        let storedSeen = Set(defaults.stringArray(forKey: Keys.seen) ?? [])
        let connected: Set<String>
        let seen: Set<String>
        let hidden: Set<String>?
        if let storedConnected {
            connected = Set(storedConnected)
            seen = storedSeen.isEmpty ? connected : storedSeen
            hidden = nil
        } else if defaults.object(forKey: Keys.disconnected) != nil {
            // An empty off-list is still a choice: everyone was on.
            hidden = Set(defaults.stringArray(forKey: Keys.disconnected) ?? [])
            connected = []
            seen = storedSeen
        } else if !self.isFirstLaunch || defaults.bool(forKey: Keys.introducedOllama) {
            // Launched before this key existed, and never hid anyone.
            hidden = []
            connected = []
            seen = storedSeen
        } else {
            hidden = nil
            connected = []
            seen = storedSeen
        }
        self.connectedProviders = connected.filter { !Self.isModelCell($0) }
        self.seenProviders = seen.filter { !Self.isModelCell($0) }
        self.pendingHidden = hidden
        let models: Set<String>
        if let storedDisabled = defaults.stringArray(forKey: Keys.disabledModels) {
            models = Set(storedDisabled)
        } else {
            // Model cells that lived on the old off-list stay off. Read the
            // leftover even after `connectedProviders` exists: an earlier
            // invert left those ids in `hiddenProviders` and then ignored them.
            let leftover = hidden ?? Set(defaults.stringArray(forKey: Keys.disconnected) ?? [])
            models = leftover.filter(Self.isModelCell)
        }
        self.disabledModels = models
        defaults.set(Array(models), forKey: Keys.disabledModels)
        let ollamaOn: Bool
        if storedConnected != nil {
            ollamaOn = connected.contains("ollama-local")
        } else if let hidden {
            ollamaOn = !hidden.contains("ollama-local")
        } else {
            ollamaOn = false
        }
        self.ollamaMetricsEnabled = defaults.object(forKey: Keys.ollamaMetricsEnabled) as? Bool
            ?? (defaults.bool(forKey: Keys.introducedOllama) && ollamaOn)
        self.ollamaEndpoint = (try? OllamaEndpoint.parse(
            defaults.string(forKey: Keys.ollamaEndpoint) ?? OllamaEndpoint.defaultAddress
        ).absoluteString) ?? OllamaEndpoint.defaultAddress
        // A stored choice wins; otherwise LM Studio's own configuration file
        // says where it listens, and 1234 is what it ships with.
        self.lmstudioEndpoint = (try? LMStudioEndpoint.parse(
            defaults.string(forKey: Keys.lmstudioEndpoint)
                ?? LMStudioEndpoint.configuredAddress() ?? LMStudioEndpoint.defaultAddress
        ).absoluteString) ?? LMStudioEndpoint.defaultAddress
        self.omlxEndpoint = (try? OMLXEndpoint.parse(
            defaults.string(forKey: Keys.omlxEndpoint)
                ?? OMLXEndpoint.configuredAddress() ?? OMLXEndpoint.defaultAddress
        ).absoluteString) ?? OMLXEndpoint.defaultAddress
        self.mutedAlertProviders = Set(defaults.stringArray(forKey: Keys.mutedAlerts) ?? [])
        self.accountNicknames = defaults.dictionary(forKey: Keys.accountNicknames) as? [String: String] ?? [:]
        self.resetTimeFormat = defaults.string(forKey: Keys.resetTimeFormat)
            .flatMap(ResetTimeFormat.init(rawValue:)) ?? .automatic
        self.showUsagePace = defaults.bool(forKey: Self.showUsagePaceKey)
        // Off by default: see the property. A request spent on every look is a
        // choice, and on a rate-limited provider it can cost freshness rather
        // than buy it.
        self.asksProviderOnLook = defaults.bool(forKey: Keys.asksProviderOnLook)
        self.hidesDockIcon = defaults.object(forKey: Keys.hidesDockIcon) as? Bool ?? true
        // Off by default: it swaps what Claude's ring means, and that is a
        // choice for whoever budgets their week that way.
        self.claudeDailyPaceRing = defaults.bool(forKey: Keys.claudeDailyPaceRing)
        // Off by default for the same reason: it changes what every ring means.
        self.weeklyHeadline = defaults.bool(forKey: Keys.weeklyHeadline)
        self.deepSeekPricingEnabled = defaults.object(forKey: Keys.deepSeekPricingEnabled) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.deepSeekPricingSchedule),
           let schedule = try? JSONDecoder().decode(DeepSeekPricing.Schedule.self, from: data) {
            self.deepSeekPricingSchedule = schedule.normalized
        } else {
            self.deepSeekPricingSchedule = .current
        }
        self.antigravityHeadlineLimit = defaults.string(forKey: Keys.antigravityHeadlineLimit)
            .flatMap(AntigravityHeadlineLimit.init(rawValue:)) ?? .automatic
        self.antigravityHeadlineModel = defaults.string(forKey: Keys.antigravityHeadlineModel)
            .flatMap(AntigravityHeadlineModel.init(rawValue:)) ?? .gemini
        // Off by default: an extra arc in a 44pt circle is a change to how
        // every reading looks, and nobody asked for it on their behalf.
        self.weeklyRingDashed = defaults.object(forKey: Keys.weeklyRingDashed) as? Bool ?? false
        // Off by default: it swaps what every meter means, and that is a
        // choice for whoever budgets from the other end.
        self.shutRingsWhenSpent = defaults.object(forKey: Keys.shutRingsWhenSpent) as? Bool ?? true
        self.ringOrder = defaults.string(forKey: Keys.ringOrder).flatMap(RingOrder.init(rawValue:))
            ?? .manual
        self.hideDepletedAccounts = defaults.bool(forKey: Keys.hideDepletedAccounts)

        self.weeklyRing = defaults.string(forKey: Keys.weeklyRing)
            .flatMap(WeeklyRing.init(rawValue:)) ?? .off
        // The app's own green, so the interface and the mark are the same
        // colour. No longer a choice; a stored pick from before is ignored.
        self.accentColor = .logo
        // The Mac's own look until asked otherwise: the app has always
        // followed it, and a setting nobody has touched should not change
        // what anyone sees.
        self.appTheme = defaults.string(forKey: Keys.appTheme)
            .flatMap(AppTheme.init(rawValue:)) ?? .system
        // Solid until asked otherwise: a panel that suddenly lets the desktop
        // through is a change nobody asked for.
        self.panelTransparency = defaults.object(forKey: Keys.panelTransparency) as? Double ?? 0
        self.menuBarTitleStyle = defaults.string(forKey: Keys.menuBarTitleStyle)
            .flatMap(MenuBarTitleStyle.init(rawValue:)) ?? .namePercent
        self.menuBarProviderID = defaults.string(forKey: Keys.menuBarProviderID)
        self.menuBarShowsRemaining = defaults.bool(forKey: Keys.menuBarShowsRemaining)
        let storedWatchLimit = defaults.object(forKey: Keys.watchLimit) as? Double ?? 0.50
        let storedCriticalLimit = defaults.object(forKey: Keys.criticalLimit) as? Double ?? 0.70
        // `didSet` does the clamping, and it does not run for these assignments,
        // so a stored pair that crossed over is repaired here instead.
        let critical = min(max(storedCriticalLimit, 0.02), 1.0)
        self.criticalLimit = critical
        self.watchLimit = min(max(storedWatchLimit, 0.01), critical - 0.01)
        self.colorTransitionStyle = defaults.string(forKey: Keys.colorTransitionStyle)
            .flatMap(ColorTransitionStyle.init(rawValue:)) ?? .hardStep
        self.busyIndicatorStyle = defaults.string(forKey: Keys.busyIndicatorStyle)
            .flatMap(BusyIndicatorStyle.init(rawValue:)) ?? .arc
        // Absent means never chosen, which is follow-the-Mac.
        self.language = defaults.string(forKey: L10n.languageDefaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        // Absent means nothing has been shown yet, which is true of a fresh
        // install — so the current release reads as new to it.
        self.lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion)
        // Absent means never chosen, so the rings keep the order the app ships
        // with until someone drags one.
        self.providerOrder = defaults.stringArray(forKey: Keys.order) ?? []
        // Both default to on, so `bool(forKey:)` — which answers false for a
        // key that was never written — cannot stand in for the default.
        self.announceSessionEnd = defaults.object(forKey: Keys.announceSessionEnd) as? Bool ?? true
        self.sessionEndSound = defaults.object(forKey: Keys.sessionEndSound) as? Bool ?? true
        self.sessionEndSoundName = defaults.string(forKey: Keys.sessionEndSoundName)
            ?? SessionChime.defaultFinished
        self.sessionBlockedSoundName = defaults.string(forKey: Keys.sessionBlockedSoundName)
            ?? SessionChime.defaultBlocked
        self.announceUsageReset = defaults.object(forKey: Keys.announceUsageReset) as? Bool ?? true
        self.usageResetSound = defaults.object(forKey: Keys.usageResetSound) as? Bool ?? true
        self.usageResetSoundName = defaults.string(forKey: Keys.usageResetSoundName)
            ?? SessionChime.defaultFinished
        self.announceSessionLimitReached = defaults.object(forKey: Keys.announceSessionLimitReached) as? Bool ?? true
        self.announceWeeklyLimitReached = defaults.object(forKey: Keys.announceWeeklyLimitReached) as? Bool ?? true
        self.limitReachedSound = defaults.object(forKey: Keys.limitReachedSound) as? Bool ?? true
        self.limitReachedSoundName = defaults.string(forKey: Keys.limitReachedSoundName)
            ?? SessionChime.defaultBlocked
        self.geminiAPIMonthlyTokenBudget = Self.storedGeminiAPIMonthlyTokenBudget(defaults: defaults)
        self.minimaxRegion = Self.storedMinimaxRegion(defaults: defaults)
        self.qoderRegion = Sites.QoderRegion(rawValue: defaults.string(forKey: Keys.qoderRegion) ?? "") ?? .global
        // Read from the system rather than from our own store: the user can turn
        // this off in System Settings, and a remembered `true` would then be a lie.
        self.launchAtLogin = Self.isRegisteredForLogin
    }

    // MARK: Account names

    func nickname(for providerID: String) -> String? {
        accountNicknames[providerID]
    }

    /// Blank, or only spaces, goes back to the provider's own name.
    func setNickname(_ name: String, for providerID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            accountNicknames.removeValue(forKey: providerID)
        } else {
            accountNicknames[providerID] = trimmed
        }
    }

    // MARK: Threshold alerts

    func isMutedAlerts(for providerID: String) -> Bool {
        mutedAlertProviders.contains(providerID)
    }

    func setAlertsMuted(_ muted: Bool, for providerID: String) {
        if muted {
            mutedAlertProviders.insert(providerID)
        } else {
            mutedAlertProviders.remove(providerID)
        }
    }

    // MARK: Menu bar

    /// Claude and Codex stay on for a first install and for a newly discovered
    /// profile. Everyone else starts off.
    nonisolated static func isDefaultOnFamily(_ providerID: String) -> Bool {
        ClaudeProfile.isClaude(providerID: providerID)
            || CodexProfile.isCodex(providerID: providerID)
    }

    /// Model cells are `providerID:model:…`. A new loaded model is not a new
    /// provider, and absence on the provider on-list cannot mean on for these.
    static func isModelCell(_ id: String) -> Bool {
        id.contains(":model:")
    }

    func isConnected(_ providerID: String) -> Bool {
        if Self.isModelCell(providerID) {
            return !disabledModels.contains(providerID)
        }
        if defaults.object(forKey: Keys.connected) != nil {
            return connectedProviders.contains(providerID)
        }
        if let hidden = pendingHidden {
            // Absence from the old off-list means on — for providers that
            // off-list could have named. MiniMax did not exist then, so
            // missing from it is not a choice to show it.
            if providerID == "minimax" { return false }
            return !hidden.contains(providerID)
        }
        return Self.isDefaultOnFamily(providerID)
    }

    func setConnected(_ connected: Bool, for providerID: String) {
        if Self.isModelCell(providerID) {
            if connected {
                disabledModels.remove(providerID)
            } else {
                disabledModels.insert(providerID)
            }
            return
        }
        if defaults.object(forKey: Keys.connected) == nil, let hidden = pendingHidden {
            let next = connected ? hidden.subtracting([providerID]) : hidden.union([providerID])
            pendingHidden = next
            defaults.set(Array(next), forKey: Keys.disconnected)
            seenProviders.insert(providerID)
            return
        }
        if defaults.object(forKey: Keys.connected) == nil {
            // First install: persist Claude and Codex as on, then apply this toggle.
            connectedProviders = ["claude", "codex"]
        }
        if connected {
            connectedProviders.insert(providerID)
        } else {
            connectedProviders.remove(providerID)
        }
        seenProviders.insert(providerID)
    }

    /// Fold this Mac's current provider ids into the stored on-list.
    ///
    /// First launch writes Claude and Codex. An upgrade from `hiddenProviders`
    /// inverts that off-list against `discoveredIDs`. After that, only a
    /// never-seen Claude or Codex id is added automatically. Model cells stay
    /// on `disabledModels` and are not inverted.
    func reconcile(discoveredIDs: [String]) {
        let discovered = Set(discoveredIDs.filter { !Self.isModelCell($0) })
        if defaults.object(forKey: Keys.connected) != nil {
            connectedProviders.subtract(connectedProviders.filter(Self.isModelCell))
            seenProviders.subtract(seenProviders.filter(Self.isModelCell))
            let novel = discovered.subtracting(seenProviders)
            for id in novel where Self.isDefaultOnFamily(id) {
                connectedProviders.insert(id)
            }
            seenProviders.formUnion(discovered)
            return
        }
        if let hidden = pendingHidden {
            // Invert the old off-list, then drop MiniMax: it did not exist
            // when that list was written, so absence from it is not "on".
            connectedProviders = discovered
                .subtracting(hidden.filter { !Self.isModelCell($0) })
                .subtracting(["minimax"])
            seenProviders = discovered
            pendingHidden = nil
            return
        }
        connectedProviders = Set(discovered.filter(Self.isDefaultOnFamily))
        seenProviders = discovered
    }

    /// What `UsageStore` still treats as the off-list, among ids it knows.
    func disconnectedIDs(among discovered: [String]) -> Set<String> {
        Set(discovered.filter { !isConnected($0) })
    }

    /// Record a new order, keeping the ids that are not on this Mac today.
    ///
    /// Settings can only show what was discovered at launch, so writing its
    /// list verbatim would quietly forget where a Claude profile sat the moment
    /// its directory was moved away — and put it back at the end when it
    /// returned, for something the user never did.
    func setProviderOrder(_ ids: [String]) {
        providerOrder = ProviderOrder.remember(ids, keeping: providerOrder)
    }

    // MARK: - Login item

    static var isRegisteredForLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginProblem = nil
        } catch {
            // Commonly refused for an app running from a build directory rather
            // than /Applications, which is worth saying plainly.
            Log.usage.error("launch at login failed: \(error.localizedDescription, privacy: .public)")
            launchAtLoginProblem = L10n.t("macOS refused this — try moving Leftover to /Applications.")
            launchAtLogin = Self.isRegisteredForLogin
        }
    }
}
