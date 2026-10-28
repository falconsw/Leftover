import SwiftUI

/// Carries readings, sessions and display settings into the model the menu
/// bar panel draws from.
@MainActor
final class PanelFeed {
    let model = PanelModel()

    /// What the agent monitors last reported, per provider.
    private(set) var sessions: [String: [AgentSession]] = [:]
    var thinkingModels: [String: Date] { model.thinkingModels }

    private var localActivities: [String: [String: LocalModelActivity]] = [:]


    func setSnapshots(_ snapshots: [ProviderSnapshot]) {
        // A pure reorder glides; value changes ride unanimated, so a poll that
        // moves a number does not also move every ring.
        let oldIDs = model.snapshots.map(\.id)
        let newIDs = snapshots.map(\.id)
        let isReorder = oldIDs.count == newIDs.count
            && !oldIDs.isEmpty && Set(oldIDs) == Set(newIDs) && oldIDs != newIDs
        if isReorder {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                model.updateSnapshots(snapshots)
            }
        } else {
            model.updateSnapshots(snapshots)
        }
        model.now = Date()
    }

    func setSessions(providerID id: String, sessions live: [AgentSession]) {
        sessions[id] = live
        model.sessions[id] = live
        model.now = Date()
    }

    func setRefreshing(_ ids: Set<String>) {
        model.refreshing = ids
    }

    func setLocalMetricsEnabled(_ enabled: Bool) {
        model.setLocalMetricsEnabled(enabled)
    }

    func setThinkingModels(_ thinking: [String: Date]) {
        model.thinkingModels = thinking
    }

    func setPerformances(_ measurements: [String: LocalModelPerformance],
                         source: String = PanelModel.ollamaSource) {
        model.updatePerformances(measurements, source: source)
    }

    /// Cell ids carry their provider's prefix, so a plain union never lets one
    /// runtime's model shadow another's.
    func setLocalActivities(_ activities: [String: LocalModelActivity],
                            source: String = LMStudioMetrics.providerID) {
        localActivities[source] = activities
        model.localActivities = localActivities.values.reduce(into: [:]) { merged, activities in
            merged.merge(activities) { current, _ in current }
        }
    }

    func setLedger(_ ledger: LocalTokenLedger, source: String = LMStudioMetrics.providerID) {
        model.updateLedger(ledger, source: source)
    }
}
