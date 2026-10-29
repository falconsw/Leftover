import Foundation

/// Sample readings for demo mode (`LEFTOVER_DEMO=1`): five of the accounts
/// Leftover reads, at levels that show every band, plus a local model for the
/// busy indicator. Used for screenshots, so keep it plausible.
enum Fixtures {
    static func snapshots(now: Date = Date(), calendar: Calendar = .current) -> [ProviderSnapshot] {
        let sessionReset = now.addingTimeInterval(51 * 60)
        let weekReset = calendar.startOfDay(for: now.addingTimeInterval(3 * 24 * 60 * 60))
        let monthReset = calendar.startOfDay(for: now.addingTimeInterval(12 * 24 * 60 * 60))

        return [
            ProviderSnapshot(
                id: "claude",
                displayName: "Claude",
                glyph: .claude,
                fidelity: .official,
                status: .ok,
                windows: [
                    LimitWindow(id: "claude.session", label: L10n.t("Current session"),
                                usedFraction: 0.93, resetsAt: sessionReset),
                    LimitWindow(id: "claude.all", label: L10n.t("All models"),
                                usedFraction: 0.38, resetsAt: weekReset)
                ]
            ),
            ProviderSnapshot(
                id: "codex",
                displayName: "Codex",
                glyph: .openai,
                fidelity: .official,
                status: .ok,
                windows: [
                    LimitWindow(id: "codex.session", label: L10n.t("5-hour Limit"),
                                usedFraction: 0.21, resetsAt: now.addingTimeInterval(3 * 60 * 60)),
                    LimitWindow(id: "codex.weekly", label: L10n.t("Weekly Limit"),
                                usedFraction: 0.44, resetsAt: weekReset)
                ]
            ),
            ProviderSnapshot(
                id: "cursor",
                displayName: "Cursor",
                glyph: .cursor,
                fidelity: .official,
                status: .ok,
                windows: [
                    LimitWindow(id: "cursor.monthly", label: L10n.t("Included usage"),
                                usedFraction: 0.52, resetsAt: monthReset)
                ]
            ),
            ProviderSnapshot(
                id: "grok",
                displayName: "Grok",
                glyph: .grok,
                fidelity: .official,
                status: .ok,
                windows: [
                    LimitWindow(id: "grok.weekly", label: L10n.t("Weekly limit"),
                                usedFraction: 0.64, resetsAt: weekReset)
                ]
            ),
            ProviderSnapshot(
                id: "copilot",
                displayName: "Copilot",
                glyph: .copilot,
                fidelity: .official,
                status: .ok,
                windows: [
                    LimitWindow(id: "copilot.premium", label: L10n.t("Premium requests"),
                                usedFraction: 0.12, resetsAt: monthReset)
                ]
            ),
            // A runtime snapshot, split into the `lmstudio:model:<name>` cell
            // by `panelSnapshots` on its way to the notch, as a live poll is.
            ProviderSnapshot(
                id: "lmstudio",
                displayName: "LM Studio",
                glyph: .lmstudio,
                fidelity: .official,
                status: .ok,
                windows: [],
                kind: .localRuntime,
                localRuntime: LocalRuntimeReading(models: [
                    LocalRuntimeReading.Model(name: "qwen3-coder-30b",
                                              memoryBytes: 18 * 1024 * 1024 * 1024,
                                              contextLength: 32768,
                                              quantizationLevel: "Q4_K_M",
                                              memoryKind: .modelSize)
                ])
            )
        ]
    }

    /// The demo's local model is generating with two requests queued behind
    /// it, the case the busy indicator draws differently.
    static func localActivities(now: Date = Date()) -> [String: LocalModelActivity] {
        ["lmstudio:model:qwen3-coder-30b": LocalModelActivity(phase: .generating, queued: 2,
                                                              since: now.addingTimeInterval(-12))]
    }

    /// Demo mode must show a working ring or the busy indicator cannot be
    /// eyeballed. The rest get no session so idle rings stay for comparison.
    static func sessions(now: Date = Date()) -> [String: [AgentSession]] {
        [
            "claude": [
                AgentSession(id: "demo.claude", name: "Claude Code", detail: "~/Projects/leftover",
                             state: .busy, waitingFor: nil, since: now.addingTimeInterval(-90))
            ],
            "codex": [
                AgentSession(id: "demo.codex", name: "Codex", detail: "~/Projects/site",
                             state: .busy, waitingFor: nil, since: now.addingTimeInterval(-30))
            ]
        ]
    }
}
