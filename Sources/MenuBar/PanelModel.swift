import SwiftUI
import Combine

/// What the menu bar panel draws: the readings, the agents at work and the
/// display choices that shape them.
@MainActor
final class PanelModel: ObservableObject {
    @Published var snapshots: [ProviderSnapshot] = []
    /// Per runtime, so Ollama's relay switching off clears its own readings
    /// and nobody else's.
    private var performances: [String: [String: LocalModelPerformance]] = [:]
    /// Per runtime for the same reason: each runtime's metrics replace their
    /// own ledger wholesale, so a single slot let the last one to report
    /// erase the others'.
    private var ledgers: [String: LocalTokenLedger] = [:]
    private var localMetricsEnabled = false

    /// The Ollama relay's own id; its readings are keyed by model name.
    static let ollamaSource = "ollama-local"

    @Published var thinkingModels: [String: Date] = [:]
    /// What each local model instance is doing, keyed by cell id. Cell ids are
    /// namespaced per provider, so runtimes never collide.
    @Published var localActivities: [String: LocalModelActivity] = [:]
    /// Live agent sessions, keyed by the provider they belong to.
    @Published var sessions: [String: [AgentSession]] = [:]
    /// Ticked on refresh so the "Resets in N min" copy stays honest.
    @Published var now: Date = Date()
    /// Providers with a fetch in flight, driven by the store.
    @Published var refreshing: Set<String> = []

    @Published var resetTimeFormat: ResetTimeFormat = .automatic
    @Published var accentColor: AccentColorChoice = .system
    @Published var weeklyRing: WeeklyRing = .off
    @Published var weeklyRingDashed: Bool = false
    @Published var watchLimit: Double = 0.50
    @Published var criticalLimit: Double = 0.70
    @Published var colorTransitionStyle: ColorTransitionStyle = .hardStep
    @Published var deepSeekPricingEnabled = true
    @Published var deepSeekPricingSchedule = DeepSeekPricing.Schedule.current

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Language change leaves snapshots untouched; tick `now` so copy
        // already on screen is redrawn against the new catalog.
        NotificationCenter.default.publisher(for: L10n.didChange)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.now = Date() }
            }
            .store(in: &cancellables)
    }

    func setLocalMetricsEnabled(_ enabled: Bool) {
        localMetricsEnabled = enabled
        if !enabled { performances[Self.ollamaSource] = nil; thinkingModels = [:] }
        snapshots = snapshots.map(decorated)
    }

    func updateSnapshots(_ providerSnapshots: [ProviderSnapshot]) {
        snapshots = ProviderOrder.cells(from: providerSnapshots, keeping: snapshots)
            .map(decorated).map(Costs.decorate)
    }

    func updatePerformances(_ measurements: [String: LocalModelPerformance],
                            source: String = PanelModel.ollamaSource) {
        performances[source] = measurements
        snapshots = snapshots.map(decorated)
    }

    /// Logged tokens per cell, read against `now` as it is drawn so "today"
    /// rolls over at midnight without a new line being written.
    func updateLedger(_ ledger: LocalTokenLedger, source: String = LMStudioMetrics.providerID) {
        ledgers[source] = ledger
        snapshots = snapshots.map(decorated)
    }

    private func decorated(_ snapshot: ProviderSnapshot) -> ProviderSnapshot {
        guard let model = snapshot.localModel else { return snapshot }
        var snapshot = snapshot
        let shows = localMetricsEnabled || snapshot.localRuntimeMeasuresSpeed
        snapshot.showsLocalPerformance = shows
        snapshot.localPerformance = shows
            ? performances[snapshot.providerID]?[Self.performanceKey(for: snapshot, model: model)] : nil
        snapshot.localLedger = ledgers[snapshot.providerID]?.summary(for: snapshot.id, now: now)
        snapshot.localContextFraction = snapshot.localLedger?.contextFraction(contextLength: model.contextLength)
        return snapshot
    }

    /// Ollama's relay knows a model by the name a client used, with Ollama's
    /// implicit `:latest`; everything else reports by cell id.
    static func performanceKey(for snapshot: ProviderSnapshot, model: LocalRuntimeReading.Model) -> String {
        snapshot.providerID == ollamaSource ? OllamaThinkingStream.modelKey(model.name) : snapshot.id
    }

    func isRefreshing(_ snapshot: ProviderSnapshot) -> Bool {
        refreshing.contains(snapshot.providerID)
    }

    /// A provider with no activity source gets none, rather than borrowing
    /// somebody else's.
    func activity(for snapshot: ProviderSnapshot) -> ActivitySummary? {
        guard let model = snapshot.localModel else { return activity(for: snapshot.providerID) }
        if let local = localActivities[snapshot.id] {
            return ActivitySummary(sessions: [AgentSession(id: snapshot.id, name: local.label,
                detail: snapshot.displayName, state: .busy, waitingFor: nil, since: local.since)],
                queued: local.queued, note: local.note)
        }
        guard let since = thinkingModels[OllamaThinkingStream.modelKey(model.name)] else { return nil }
        return ActivitySummary(sessions: [AgentSession(id: snapshot.id, name: L10n.t("Thinking"),
            detail: snapshot.displayName, state: .busy, waitingFor: nil, since: since)])
    }

    func activity(for providerID: String) -> ActivitySummary? {
        ActivitySummary(sessions: sessions[providerID] ?? [])
    }
}
