import SwiftUI

/// The panel opened from the menu bar: a ring per provider along the top and,
/// below, the card of the one last hovered. "More" extends the card in place.
struct MenuBarPanel: View {
    /// Clicking a ring refreshes that provider right away.
    let refresh: (String) -> Task<Void, Never>?
    let onSettings: () -> Void
    @ObservedObject var preferences: Preferences
    @EnvironmentObject private var model: PanelModel
    /// Sticky: stays on the last hovered provider until another one is hovered.
    @State private var selectedID: String?
    @State private var expanded = false
    /// The provider clicked and waiting on its refresh; its arc spins meanwhile.
    @State private var awaitingID: String?

    private var providers: [ProviderSnapshot] {
        model.snapshots.filter { $0.kind == .usage }
    }

    private var mostCritical: ProviderSnapshot? {
        providers.max { ($0.usedFraction ?? -1) < ($1.usedFraction ?? -1) }
    }

    private var selected: ProviderSnapshot? {
        if let selectedID, let match = providers.first(where: { $0.id == selectedID }) { return match }
        return mostCritical
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if providers.isEmpty {
                Text(L10n.t("Reading…")).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                // One row: more providers widen the panel rather than wrap.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(providers) { snapshot in
                        ProviderChip(snapshot: snapshot,
                                     selected: selected?.id == snapshot.id,
                                     working: model.activity(for: snapshot)?.state == .working,
                                     refreshing: model.isRefreshing(snapshot) || awaitingID == snapshot.id)
                            .onHover { if $0 { selectedID = snapshot.id } }
                            .onTapGesture {
                                selectedID = snapshot.id
                                let id = snapshot.id
                                let task = refresh(id)
                                awaitingID = id
                                Task {
                                    await task?.value
                                    if awaitingID == id { awaitingID = nil }
                                }
                            }
                    }
                }
                if let snapshot = selected {
                    Divider()
                    ProviderDetail(snapshot: snapshot, activity: model.activity(for: snapshot),
                                   now: model.now, expanded: $expanded)
                }

                Divider()
                HStack(spacing: 4) {
                    Spacer()
                    PanelFooterButton(title: L10n.t("Settings"), systemImage: "gearshape") { onSettings() }
                    PanelFooterButton(title: L10n.t("Quit"), systemImage: "power") { NSApp.terminate(nil) }
                }
                .padding(.top, -4)
            }
        }
        .padding(16)
        .frame(minWidth: 340, alignment: .leading)
        // With the popover's material hidden, this opacity is the panel's.
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.menuCardSurface.opacity(1 - preferences.panelTransparency))
        }
    }
}

/// One ring in the top row: percentage inside, name below, coloured by usage band.
private struct ProviderChip: View {
    let snapshot: ProviderSnapshot
    let selected: Bool
    var working: Bool = false
    var refreshing: Bool = false

    private var fraction: Double { min(max(snapshot.usedFraction ?? 0, 0), 1) }
    private var color: Color { UsageBand.band(for: fraction).color() }
    private var hasReading: Bool { snapshot.usedFraction != nil }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 4)
                if hasReading {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(verbatim: "\(Int((fraction * 100).rounded()))")
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                } else {
                    Text(verbatim: "–").foregroundStyle(.secondary)
                }
                if working || refreshing {
                    SpinnerArc(color: working ? color : .secondary)
                        .frame(width: 30, height: 30)
                }
            }
            .frame(width: 46, height: 46)
            Text(snapshot.displayName)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 64)
        }
        .padding(6)
        .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .pointerStyle(.link)
    }
}

/// A provider's card: title and limit windows; "More" adds running sessions,
/// reset credits, Codex tokens and the DeepSeek breakdown.
private struct ProviderDetail: View {
    let snapshot: ProviderSnapshot
    let activity: ActivitySummary?
    let now: Date
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderDetailContent(snapshot: snapshot, activity: activity, now: now,
                                  showsExtendedDetail: expanded)
                .environment(\.providerDetailWidth, 330)
                .environment(\.tooltipSecondaryInk, Palette.menuTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasMore {
                HStack {
                    Spacer()
                    Button {
                        expanded.toggle()
                    } label: {
                        Label(expanded ? L10n.t("Less") : L10n.t("More"),
                              systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .pointerStyle(.link)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether "More" would add anything.
    private var hasMore: Bool {
        activity != nil
            || snapshot.hasAvailableResetCredits
            || snapshot.tokenUsage != nil
            || (snapshot.usageDetail?.hasUsage ?? false)
    }
}

/// The Settings / Quit buttons in the footer, highlighted on hover.
private struct PanelFooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.10 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The thin arc spinning inside a ring while its provider is busy or refreshing.
private struct SpinnerArc: View {
    let color: Color
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.22)
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

