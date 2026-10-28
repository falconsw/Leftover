import SwiftUI

private struct TooltipHeader<Mark: View>: View {
    let title: String
    /// The account's named tier, when the provider publishes one.
    var subtitle: String?
    /// Sits on the header's own line, so saying when a reading was taken costs
    /// the card no extra height.
    var note: String?
    /// A control belonging to the surface rather than to the provider, put at
    /// the end of the header line. The notch has none — its card is a tooltip,
    /// and nothing in it is clickable — so this is nil there and the header is
    /// exactly what it always was.
    var accessory: AnyView?
    @ViewBuilder let mark: Mark
    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    var body: some View {
        HStack(alignment: .center, spacing: NotchLayout.headerGap) {
            mark
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(title)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        // The title names the model; a long note yields before it does.
                        .layoutPriority(1)
                    if let note {
                        Spacer(minLength: Design.px(20))
                        Text(note)
                            .font(Typography.cardBody)
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)
                    }
                    // On the title's own line rather than centred on the
                    // whole block, so a provider that names a tier under its
                    // title puts the accessory exactly where one that does
                    // not puts it.
                    if let accessory {
                        Spacer(minLength: Design.px(20))
                        accessory
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.cardBody)
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A label on the left and a quieter value on the right — the row shape the
/// design frame uses throughout.
struct SplitRow<Accessory: View>: View {
    let leading: String
    let trailing: String
    var leadingColor: Color = Palette.textPrimary
    var trailingColor: Color? = nil
    /// Sits immediately before the trailing text, inside the same group, so it
    /// travels with the word instead of drifting to the middle of the row.
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    var body: some View {
        HStack(spacing: NotchLayout.splitRowGap) {
            Text(leading).foregroundStyle(leadingColor)
            Spacer(minLength: 0)
            HStack(spacing: NotchLayout.statusDotGap) {
                accessory()
                Text(trailing).foregroundStyle(trailingColor ?? secondaryInk)
            }
        }
        .font(Typography.cardBody)
        .lineLimit(1)
    }
}

extension SplitRow where Accessory == EmptyView {
    init(leading: String,
         trailing: String,
         leadingColor: Color = Palette.textPrimary,
         trailingColor: Color? = nil) {
        self.init(leading: leading, trailing: trailing,
                  leadingColor: leadingColor, trailingColor: trailingColor,
                  accessory: { EmptyView() })
    }
}

/// The ring beside a session's status.
///
/// Turning while the agent is working, still when it is not — so the row says
/// what is happening before the word is read.
private struct StatusRing: View {
    let state: AgentSession.State
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One turn, in seconds. Slow enough to read as deliberate rather than as
    /// something struggling.
    private static let period: Double = 1.4

    var body: some View {
        Group {
            switch state {
            case .busy:
                if reduceMotion {
                    // Still, but still three-quarters: the gap alone says
                    // "in progress" without anything moving.
                    ring(trim: 0.75)
                } else {
                    // A timeline rather than `repeatForever`. An endless
                    // animation has to be cancelled to stop, and setting the
                    // value it is already heading towards does not cancel it —
                    // which is exactly how the refresh ring here once span for
                    // ever. Derived from the clock, it simply stops being drawn.
                    TimelineView(.animation) { context in
                        ring(trim: 0.75)
                            .rotationEffect(.degrees(angle(at: context.date)))
                    }
                }
            case .waiting, .success:
                // Half a ring, held still: blocked, not progressing. (Or a full ring for success).
                // Wait, if we want success to be a full ring, we can use 1.0 trim for success.
                ring(trim: state == .success ? 1.0 : 0.5)
            case .idle:
                ring(trim: 1)
            }
        }
        .frame(width: NotchLayout.statusDot, height: NotchLayout.statusDot)
    }

    private func ring(trim: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(color,
                    style: StrokeStyle(lineWidth: NotchLayout.statusDotStroke, lineCap: .round))
            // Start the gap at the top, where the eye lands first.
            .rotationEffect(.degrees(-90))
    }

    private func angle(at date: Date) -> Double {
        let turns = date.timeIntervalSinceReferenceDate / Self.period
        return turns.truncatingRemainder(dividingBy: 1) * 360
    }
}

// MARK: - Providers

/// The tick's leading edge for a 0...1 position along a track, kept on the
/// track: at either end the tick stops against the edge instead of hanging
/// halfway off it. Internal so the tests can pin the ends.
func paceMarkerX(position: Double, trackWidth: CGFloat, markerWidth: CGFloat) -> CGFloat {
    min(max(CGFloat(position) * trackWidth - markerWidth / 2, 0),
        max(trackWidth - markerWidth, 0))
}

/// The tick on a window's bar marking the share of the cycle elapsed — where
/// the fill *should* be, so a glance says whether the burn is ahead of the
/// clock or behind it. Slightly taller than the bar, so its ends land on the
/// card's own background where the contrast holds whatever the fill colour is.
/// Hidden from VoiceOver: the pace line below the bar already says it in words.
private struct PaceMarker: View {
    /// 0...1 from the leading edge, on the bar's own terms — see
    /// `LimitWindow.paceMarkerFraction`.
    let position: Double
    let trackWidth: CGFloat
    private var width: CGFloat { Design.px(2) }

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2, style: .continuous)
            .fill(Palette.textPrimary)
            // Whole points, so it overhangs the bar evenly above and below.
            .frame(width: width, height: (NotchLayout.barHeight + Design.px(6)).rounded())
            .offset(x: paceMarkerX(position: position, trackWidth: trackWidth, markerWidth: width))
            .accessibilityHidden(true)
    }
}

/// One metered window: label and reset copy on a line, a track bar, then the
/// percentage burned — or what is left, when the notch is set that way.
private struct LimitWindowRow: View {
    let window: LimitWindow
    var inset: CGFloat = 0
    let fidelity: Fidelity
    let now: Date
    let resetTimeFormat: ResetTimeFormat
    let showsUsagePace: Bool
    /// Whether the reset says when it lands as well as how long there is.
    /// Decided for the whole card — see `ProviderLimitsContent`.
    var showsResetStamp: Bool = false
    var showsRemaining: Bool = false
    @Environment(\.leftoverAccentColor) private var accentColor
    @Environment(\.usageWatchLimit) private var watchLimit
    @Environment(\.usageCriticalLimit) private var criticalLimit
    @Environment(\.colorTransitionStyle) private var colorTransitionStyle
    @Environment(\.tooltipSecondaryInk) private var secondaryInk
    @Environment(\.providerDetailWidth) private var detailWidth

    private var band: UsageBand {
        if let override = window.bandOverride { return override }
        return UsageBand.band(for: window.usedFraction ?? 0, watchLimit: watchLimit, criticalLimit: criticalLimit)
    }
    /// Continuous when that style is chosen; a `bandOverride` is a deliberate discrete choice
    /// from the caller regardless of style, so it stays exactly as `band.color(accent:)` renders it.
    private var barColor: Color {
        guard window.bandOverride == nil, colorTransitionStyle == .ramp else {
            return band.color(accent: accentColor)
        }
        return UsageBand.rampColor(for: window.usedFraction ?? 0, watchLimit: watchLimit, accent: accentColor)
    }
    private var trackWidth: CGFloat { detailWidth - inset }
    private var fillWidth: CGFloat {
        let fraction = CGFloat(min(max(Percent.metered(window.usedFraction ?? 0,
                                                       showingRemaining: showsRemaining), 0), 1))
        return max(NotchLayout.barHeight, trackWidth * fraction)
    }

    private var paceText: Text {
        guard showsUsagePace, let pace = window.usagePace(now: now) else {
            return Text("")
        }
        return Text(" · \(pace.summary)")
            .foregroundColor(pace.isDeficit ? .orange : secondaryInk)
    }

    /// Blank rather than invented: some providers never say when the window rolls.
    private var resetText: String {
        window.resetsAt.map {
            ResetCopy.text(for: $0, now: now, format: resetTimeFormat,
                           withAbsoluteStamp: showsResetStamp)
        } ?? ""
    }

    /// A count-only row (no fraction, no reset) — like Ollama's per-model request
    /// counts — renders as a single table line: name left, count right.
    private var isCountRow: Bool {
        window.usedFraction == nil && (window.used != nil || window.detail != nil)
    }

    var body: some View {
        if let money = window.money {
            MoneyBreakdownView(title: window.label, money: money, fidelity: fidelity,
                               resetText: window.resetsAt == nil ? nil : resetText,
                               projection: window.usageProjection(now: now),
                               showsRemaining: showsRemaining)
        } else if isCountRow {
            SplitRow(leading: window.label, trailing: window.detail ?? window.usedText ?? "\(window.used ?? 0)")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SplitRow(leading: window.label, trailing: resetText)

                // No bar without a denominator — an empty track would read as "none
                // used", which is not what "we do not know the limit" means.
                if window.usedFraction != nil {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.barTrack)
                        Capsule().fill(barColor).frame(width: fillWidth)
                        if showsUsagePace,
                           let marker = window.paceMarkerFraction(now: now, showingRemaining: showsRemaining) {
                            PaceMarker(position: marker, trackWidth: trackWidth)
                        }
                    }
                    .frame(width: trackWidth, height: NotchLayout.barHeight)
                    .padding(.top, NotchLayout.labelToBar)
                }

                Text("\(window.usedFraction == nil ? "" : fidelity.qualifier)\(window.detail ?? window.summary(showingRemaining: showsRemaining))\(paceText)")
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, NotchLayout.barToUsed)
            }
        }
    }
}

private struct MoneyBreakdownView: View {
    let title: String
    let money: UsageMoneyBreakdown
    let fidelity: Fidelity
    /// Nil for a balance with no period, which gets no line for it.
    var resetText: String? = nil
    var projection: UsageProjection? = nil
    var showsRemaining: Bool = false
    @Environment(\.leftoverAccentColor) private var accentColor
    @Environment(\.usageWatchLimit) private var watchLimit
    @Environment(\.usageCriticalLimit) private var criticalLimit
    @Environment(\.providerDetailWidth) private var detailWidth
    @Environment(\.colorTransitionStyle) private var colorTransitionStyle
    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    private var barColor: Color {
        // Amber while the balance is still low but the pace says it will not
        // last the month — the point at which slowing down still helps.
        if projection?.runsOut == true,
           UsageBand.band(for: money.spentFraction, watchLimit: watchLimit, criticalLimit: criticalLimit) == .ample {
            return UsageBand.watch.color(accent: accentColor)
        }
        guard colorTransitionStyle == .ramp else {
            return UsageBand.band(for: money.spentFraction, watchLimit: watchLimit, criticalLimit: criticalLimit)
                .color(accent: accentColor)
        }
        return UsageBand.rampColor(for: money.spentFraction, watchLimit: watchLimit, accent: accentColor)
    }

    private var symbol: String {
        switch money.currency.uppercased() {
        case "CNY", "RMB", "JPY": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        default: return "\(money.currency) "
        }
    }

    private func amount(_ value: Double) -> String {
        "\(symbol)\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SplitRow(leading: title,
                     trailing: "\(fidelity.qualifier)\(money.headlineText(showingRemaining: showsRemaining))")
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(barColor)
                        .frame(width: proxy.size.width * CGFloat(Percent.metered(money.spentFraction,
                                                                                 showingRemaining: showsRemaining)))
                    Rectangle().fill(Palette.barTrack)
                }
            }
            .frame(width: detailWidth, height: NotchLayout.moneyBarHeight)
            .clipShape(Capsule())
            .padding(.top, NotchLayout.labelToBar)

            HStack(spacing: NotchLayout.blockSpacing) {
                MoneyStat(label: L10n.t("Spent"), value: amount(money.spent), color: accentColor)
                MoneyStat(label: L10n.t("Remaining"), value: amount(money.remaining))
                MoneyStat(label: L10n.t("Funded"), value: amount(money.funded), color: Palette.textPrimary)
            }
            .frame(width: detailWidth)
            .padding(.top, NotchLayout.moneyBarToStats)

            // A line each rather than one shared: in German the countdown alone
            // takes most of the card's width.
            if let resetText {
                moneyLine(resetText, color: secondaryInk)
            }
            if let projection {
                moneyLine(projectionText(projection),
                          color: projection.runsOut ? .orange : secondaryInk)
            }
        }
    }

    private func moneyLine(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Typography.cardBody)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: NotchLayout.cardTextWidth, alignment: .leading)
            .padding(.top, NotchLayout.moneyStatGap)
    }

    private func projectionText(_ projection: UsageProjection) -> String {
        if let reachedAt = projection.limitReachedAt {
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return L10n.t("On pace to run out \(formatter.string(from: reachedAt))")
        }
        return L10n.t("On pace for \(amount(money.funded * projection.fractionAtReset))")
    }
}

private struct MoneyStat: View {
    let label: String
    let value: String
    var color: Color? = nil
    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLayout.moneyStatGap) {
            Text(label).foregroundStyle(secondaryInk).lineLimit(1)
            Text(value).foregroundStyle(color ?? secondaryInk).monospacedDigit().lineLimit(1)
        }
        .font(Typography.cardBody)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What a provider's limits say: its mark and name, the tier it is on, a line
/// when something is blocked or cannot be read, and one row per metered window
/// — label, reset, bar, and the percentage spelled out at both ends.
///
/// The piece both surfaces start from. The menu bar's menu draws this and
/// stops here, because a menu is a glance; the notch's tooltip draws it and
/// then adds what is *happening* — see `ProviderDetailContent`.
struct ProviderLimitsContent: View {
    /// What a local model is doing right now, for the header's note.
    var activityNote: String?
    let snapshot: ProviderSnapshot
    let now: Date
    var resetTimeFormat: ResetTimeFormat = .automatic
    var showUsagePace: Bool = false
    var showsRemaining: Bool = false
    /// Drawn at the end of the header line — see `TooltipHeader.accessory`.
    var headerAccessory: AnyView?
    @Environment(\.tooltipSecondaryInk) private var secondaryInk
    @Environment(\.providerDetailWidth) private var detailWidth

    /// Only worth saying when the numbers are not current. A remembered reading
    /// has to be dated, or it quietly passes itself off as live.
    private var readingAge: String? {
        guard snapshot.hasReading, let since = snapshot.status.staleSince,
              since != .distantPast
        else { return nil }
        return ElapsedCopy.ago(since: since, now: now)
    }

    /// Whether every reset on this card has room to say when it lands.
    ///
    /// All of them or none. "(20:30)" on one row and nothing on the row under
    /// it reads as a value that went missing rather than as a column that ran
    /// out — so the widest row decides for the card, and a card that cannot
    /// hold the brackets keeps the plain countdown it has always had. The
    /// notch's column is 200pt and rarely can; the menu's is half as wide
    /// again and always does.
    private var showsResetStamps: Bool {
        let rows = snapshot.windows.compactMap { window -> (String, String, CGFloat)? in
            guard let resetsAt = window.resetsAt else { return nil }
            let inset = window.group == nil ? 0 : 2 * Design.px(16)
            return (window.label,
                    ResetCopy.text(for: resetsAt, now: now, format: resetTimeFormat,
                                   withAbsoluteStamp: true),
                    detailWidth - inset)
        }
        guard !rows.isEmpty else { return false }
        return rows.allSatisfy { NotchLayout.splitRowFits(leading: $0.0, trailing: $0.1, width: $0.2) }
    }

    private var runtimeSummary: String? {
        guard snapshot.kind == .localRuntime, snapshot.localModel == nil else { return nil }
        return snapshot.localRuntime?.summary
    }

    private struct WindowGroup: Identifiable {
        let id: String
        let title: String?
        var windows: [LimitWindow]
    }

    private var groupedWindows: [WindowGroup] {
        var result: [WindowGroup] = []
        for window in snapshot.windows {
            if let last = result.last, last.title == window.group {
                result[result.count - 1].windows.append(window)
            } else {
                result.append(WindowGroup(id: window.group ?? window.id, title: window.group, windows: [window]))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TooltipHeader(title: snapshot.kind == .localRuntime
                          ? L10n.t("\(snapshot.localModel?.brand?.displayName ?? snapshot.displayName) · Local")
                          : L10n.t("\(snapshot.displayName) Usage"),
                          // A runtime with nothing loaded has no window to
                          // draw, so its own summary — "2 models loaded",
                          // "Server reachable · No models loaded" — stands in
                          // for the tier line. The notch never reaches this:
                          // it makes a cell per model and none at all for a
                          // runtime that has none.
                          subtitle: snapshot.plan ?? runtimeSummary,
                          note: activityNote ?? (snapshot.localModel?.brand != nil ? snapshot.displayName : readingAge),
                          accessory: headerAccessory) {
                ProviderGlyphView(glyph: snapshot.glyph)
                    .foregroundStyle(Palette.textPrimary)
            }

            if let block = snapshot.block {
                BlockedRow(text: block.summary(now: now))
                    .padding(.top, NotchLayout.headerToBlock)
            }

            if let message = snapshot.statusMessage {
                Text(message)
                    .font(Typography.cardBody)
                    .foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, NotchLayout.headerToBlock)
            } else if let localModel = snapshot.localModel {
                RuntimeModelDetails(model: localModel, performance: snapshot.localPerformance,
                                    showsPerformance: snapshot.showsLocalPerformance,
                                    ledger: snapshot.localLedger, now: now)
            } else {
                let stamps = showsResetStamps
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groupedWindows.enumerated()), id: \.element.id) { groupIndex, group in
                        if let title = group.title {
                            VStack(alignment: .leading, spacing: Design.px(12)) {
                                Text(title)
                                    .font(Typography.cardBody)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Palette.textPrimary)
                                    .padding(.leading, Design.px(4))

                                VStack(alignment: .leading, spacing: NotchLayout.blockSpacing) {
                                    ForEach(Array(group.windows.enumerated()), id: \.element.id) { windowIndex, window in
                                        LimitWindowRow(window: window, inset: 2 * Design.px(16), fidelity: snapshot.fidelity, now: now, resetTimeFormat: resetTimeFormat, showsUsagePace: showUsagePace, showsResetStamp: stamps, showsRemaining: showsRemaining)
                                            .padding(.top, windowIndex == 0 ? 0 : NotchLayout.blockSpacing)
                                    }
                                }
                                .padding(Design.px(16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.px(20))
                                        .stroke(Color.white.opacity(0.25), lineWidth: Design.px(1.5))
                                )
                            }
                            .padding(.top, groupIndex == 0 ? NotchLayout.headerToBlock : Design.px(28))
                        } else {
                            ForEach(Array(group.windows.enumerated()), id: \.element.id) { windowIndex, window in
                                LimitWindowRow(window: window, fidelity: snapshot.fidelity, now: now, resetTimeFormat: resetTimeFormat, showsUsagePace: showUsagePace, showsResetStamp: stamps, showsRemaining: showsRemaining)
                                    .padding(.top, (groupIndex == 0 && windowIndex == 0) ? NotchLayout.headerToBlock : NotchLayout.blockSpacing)
                            }
                        }
                    }
                }
                .padding(.bottom, groupedWindows.contains(where: { $0.title != nil }) ? Design.px(8) : 0)
            }
        }
    }
}

private struct RuntimeModelDetails: View {
    let model: LocalRuntimeReading.Model
    let performance: LocalModelPerformance?
    let showsPerformance: Bool
    /// Present for a runtime that logs its requests; five more rows, counted
    /// in `ProviderSnapshot.localLedgerRowCount`.
    let ledger: LocalTokenLedger.Summary?
    let now: Date
    @Environment(\.providerDetailWidth) private var detailWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.name)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(height: NotchLayout.modelNameHeight(model.name, width: detailWidth), alignment: .topLeading)
                .padding(.top, NotchLayout.headerToBlock)
                .accessibilityLabel(model.name)
            VStack(spacing: NotchLayout.sessionRowGap) {
                if showsPerformance {
                    SplitRow(leading: "Last speed (derived)", trailing: performance?.speedText ?? "Not measured",
                             trailingColor: performance?.band.color)
                    SplitRow(leading: "Speed band", trailing: performance?.band.label ?? "—")
                }
                SplitRow(leading: model.memoryLabel, trailing: model.displayedMemoryBytes == nil ? "Unavailable" : model.memoryText)
                SplitRow(leading: "Context limit", trailing: model.contextText)
                SplitRow(leading: "Quantization", trailing: model.quantizationText)
                SplitRow(leading: "Unloads", trailing: model.unloadText(now: now))
                if showsPerformance {
                    SplitRow(leading: "Measured", trailing: performance.map { ElapsedCopy.ago(since: $0.measuredAt, now: now) } ?? "—")
                }
                if let ledger {
                    SplitRow(leading: "Context used", trailing: ledger.contextText(contextLength: model.contextLength))
                    SplitRow(leading: "Tokens today", trailing: ledger.tokensTodayText)
                    SplitRow(leading: "Requests today", trailing: ledger.requestsTodayText)
                    SplitRow(leading: "Reasoning share", trailing: ledger.reasoningShareText)
                    SplitRow(leading: "Draft accepted", trailing: ledger.draftAcceptanceText)
                }
            }
            .padding(.top, NotchLayout.blockSpacing)
        }
        .font(Typography.cardBody)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum UsageFormat {
    static func tokens(_ value: Int?) -> String {
        guard let value else { return "—" }
        switch value {
        case 1_000_000_000...:
            return String(format: "%.2fB", locale: Locale(identifier: "en_US_POSIX"),
                          Double(value) / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", locale: Locale(identifier: "en_US_POSIX"),
                          Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", locale: Locale(identifier: "en_US_POSIX"),
                          Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }

    static func duration(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        return "\(minutes)m"
    }

    static func days(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)d"
    }
}

private struct CodexMetric: Identifiable {
    let id: String
    let value: String
    let label: String
}

private struct CodexMetricList: View {
    let metrics: [CodexMetric]
    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLayout.codexMetricRowGap) {
            ForEach(metrics) { metric in
                HStack(alignment: .firstTextBaseline, spacing: Design.px(20)) {
                    Text(metric.label)
                        .font(Typography.cardBody)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(metric.value)
                        .font(Typography.cardBody)
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .frame(height: NotchLayout.codexMetricRowHeight)
            }
        }
        .frame(height: NotchLayout.codexMetricHeight)
    }
}

private struct CodexDailyUsageChart: View {
    let buckets: [CodexTokenUsage.DailyBucket]
    let maximum: Int
    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Palette.ringTrack)
                    .frame(height: NotchLayout.hairline)

                HStack(alignment: .bottom, spacing: Design.px(4)) {
                    ForEach(buckets) { bucket in
                        RoundedRectangle(cornerRadius: Design.px(3), style: .continuous)
                            .fill(secondaryInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: proxy.size.height
                                   * CGFloat(bucket.tokens) / CGFloat(maximum))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: NotchLayout.codexChartHeight)
        .clipped()
    }
}

/// Unused rate-limit resets on this account.
private struct UsageResetCreditsSection: View {
    let credits: UsageResetCredits
    let now: Date
    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    private var countText: String {
        switch credits.availableCount {
        case 0: return L10n.t("No unused resets")
        case 1: return L10n.t("1 unused reset")
        case let n: return L10n.t("\(n) unused resets")
        }
    }

    private var observedCountText: String {
        guard let checkedAt = credits.checkedAt else { return countText }
        return L10n.t("\(countText) · \(ElapsedCopy.ago(since: checkedAt, now: now))")
    }

    private var expiryText: String? {
        guard credits.availableCount > 0, let date = credits.nextExpiry, date > now else {
            return nil
        }
        let stamp = Self.stamp(for: date, now: now)
        return credits.availableCount > 1
            ? L10n.t("Next expires \(stamp)")
            : L10n.t("Expires \(stamp)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Palette.ringTrack)
                .frame(height: NotchLayout.hairline)
                .padding(.top, NotchLayout.codexUsageTop)

            VStack(alignment: .leading, spacing: 0) {
                Text(credits.checkedAt == nil
                     ? L10n.t("Unused resets") : L10n.t("Unused resets (cached)"))
                    .font(Typography.cardBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, NotchLayout.blockSpacing)

                Text(observedCountText)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, NotchLayout.codexUsageRowGap)

                if let expiryText {
                    Text(expiryText)
                        .font(Typography.cardBody)
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                        .padding(.top, NotchLayout.codexUsageRowGap)
                }
            }
            .frame(height: NotchLayout.codexResetCreditsHeight, alignment: .top)
        }
    }

    /// Same date templates `ResetCopy` uses past the hour, so this line and
    /// the quota rows agree on what "soon" looks like.
    private static func stamp(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let template = ResetCopy.daysApart(from: now, to: date, calendar: calendar) >= 7
            ? "MMM d" : "E j:mm"
        return ResetCopy.formatter(template: template, calendar: calendar,
                                   locale: L10n.locale).string(from: date)
    }
}

/// Account-wide Codex activity. Unlike the quota rows above, this is sourced
/// from the Codex profile usage endpoint and is not a local estimate.
private struct CodexUsageSection: View {
    let usage: CodexTokenUsage
    let now: Date

    private var buckets: [CodexTokenUsage.DailyBucket] {
        usage.last30Days(now: now)
    }

    private var maximum: Int {
        max(1, buckets.map(\.tokens).max() ?? 0)
    }

    private var todayText: String {
        usage.usageToday(now: now).map { UsageFormat.tokens($0) } ?? L10n.t("Pending")
    }

    private var metrics: [CodexMetric] {
        let summary = usage.summary
        return [
            CodexMetric(id: "lifetime", value: UsageFormat.tokens(summary?.lifetimeTokens),
                        label: L10n.t("Lifetime tokens")),
            CodexMetric(id: "peak", value: UsageFormat.tokens(summary?.peakDailyTokens),
                        label: L10n.t("Peak tokens")),
            CodexMetric(id: "longest", value: UsageFormat.duration(
                seconds: summary?.longestRunningTurnSeconds), label: L10n.t("Longest chat")),
            CodexMetric(id: "current-streak", value: UsageFormat.days(
                summary?.currentStreakDays), label: L10n.t("Current streak")),
            CodexMetric(id: "longest-streak", value: UsageFormat.days(
                summary?.longestStreakDays), label: L10n.t("Longest streak"))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Palette.ringTrack)
                .frame(height: NotchLayout.hairline)
                .padding(.top, NotchLayout.codexUsageTop)

            CodexMetricList(metrics: metrics)
                .padding(.top, NotchLayout.codexMetricTop)
                .padding(.bottom, NotchLayout.codexMetricBottom)

            Rectangle()
                .fill(Palette.ringTrack)
                .frame(height: NotchLayout.hairline)

            SplitRow(leading: L10n.t("Today"), trailing: todayText)
                .padding(.top, NotchLayout.blockSpacing)
            SplitRow(leading: L10n.t("30-day tokens"),
                     trailing: UsageFormat.tokens(usage.usageInLast30Days(now: now)))
                .padding(.top, NotchLayout.codexUsageRowGap)
            CodexDailyUsageChart(buckets: buckets, maximum: maximum)
                .padding(.top, NotchLayout.codexChartTop)
        }
    }
}

/// The line that says you are stopped.
///
/// Deliberately loud where the rest of the card is quiet: it is the one thing
/// here that changes what you can do next, and it can be true while the
/// percentage beside it still reads comfortable.
private struct BlockedRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NotchLayout.statusDotGap) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: NotchLayout.statusDot))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(Typography.cardBody)
        .foregroundStyle(Palette.critical)
    }
}

// MARK: - Activity

private struct SessionRow: View {
    let session: AgentSession
    let now: Date
    /// Set when rows can be clicked to jump to the session's terminal.
    var onFocus: ((pid_t) -> Void)? = nil
    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    private var stateColor: Color {
        switch session.state {
        case .busy:    return Palette.textPrimary
        case .waiting: return Palette.watch
        case .success: return Palette.ample
        case .idle:    return secondaryInk
        }
    }

    private var stateWord: String {
        switch session.state {
        case .busy:    return L10n.t("working")
        case .waiting: return L10n.t("waiting")
        case .success: return L10n.t("complete")
        case .idle:    return L10n.t("idle")
        }
    }

    /// While blocked, what it is blocked on matters more than where it lives.
    private var detail: String {
        if session.state == .waiting, let waitingFor = session.waitingFor, !waitingFor.isEmpty {
            return waitingFor
        }
        return session.detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SplitRow(leading: session.name, trailing: stateWord,
                     trailingColor: stateColor) {
                StatusRing(state: session.state, color: stateColor)
            }
            SplitRow(
                leading: detail,
                trailing: ElapsedCopy.text(since: session.since, now: now),
                leadingColor: secondaryInk
            )
            .padding(.top, NotchLayout.sessionRowGap)
        }
        // Sessions that publish a pid can be jumped to; the rest are text,
        // and a gesture on them would promise something it cannot do.
        .contentShape(Rectangle())
        .onTapGesture {
            guard let pid = session.processID else { return }
            onFocus?(pid)
        }
    }
}

/// The live sessions for this provider, under a rule that separates them from
/// the limit windows above — they answer a different question.
private struct SessionList: View {
    let summary: ActivitySummary
    let now: Date
    /// How many rows this screen has room for; the rest are counted.
    let cap: Int
    var onFocus: ((pid_t) -> Void)? = nil
    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    /// Busy sessions first, so what is hidden is what matters least.
    private var ordered: [AgentSession] {
        summary.sessions.sorted { a, b in
            let rank: (AgentSession) -> Int = {
                switch $0.state { case .waiting: 0; case .busy: 1; case .success: 2; case .idle: 3 }
            }
            return rank(a) == rank(b) ? a.since > b.since : rank(a) < rank(b)
        }
    }

    private var shown: [AgentSession] { Array(ordered.prefix(max(0, cap))) }
    private var hidden: Int { max(0, summary.sessions.count - shown.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Palette.ringTrack)
                .frame(height: NotchLayout.hairline)
                .padding(.top, NotchLayout.blockSpacing)

            // Only as many as the card's budgeted height can hold. The rest
            // are counted rather than drawn: the card is clipped, not scrolled,
            // so anything past the budget silently pushes the title off the top.
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, session in
                SessionRow(session: session, now: now, onFocus: onFocus)
                    .padding(.top, NotchLayout.blockSpacing)
            }

            if hidden > 0 {
                Text(L10n.t("and \(hidden) more"))
                    .font(Typography.cardBody)
                    .foregroundStyle(secondaryInk)
                    .padding(.top, NotchLayout.blockSpacing)
            }
        }
    }
}

// MARK: - Shared provider detail

/// Everything one provider has to say, with nothing said about where it is
/// drawn.
///
/// This is the notch tooltip's contents, lifted out of the tooltip: the
/// header, the blocked line, the grouped limit windows, a local model's
/// readings, Codex's reset credits and account activity, DeepSeek's usage
/// breakdown and the live sessions — in that order, which is the order the
/// notch has always put them in.
///
/// It is `ProviderLimitsContent` — the part the menu bar's menu also draws —
/// plus what is *happening*: Codex's unused resets and account activity,
/// DeepSeek's usage breakdown, and the live sessions. The limits are the
/// shared half, so a change to a bar, a band or a reset lands on both
/// surfaces at once.
///
/// It is deliberately free of the notch's geometry. The tooltip's own card is
/// a fixed width, a tail and a pre-solved height, because the panel behind it
/// has to be sized in AppKit before SwiftUI lays anything out. So the
/// container is the caller's business — `TooltipCard` wraps this in
/// `TooltipShell` — and the one thing the rows have to be told is how wide
/// their bars may draw, which arrives as `\.providerDetailWidth`.
struct ProviderDetailContent: View {
    let snapshot: ProviderSnapshot
    var activity: ActivitySummary?
    let now: Date
    /// How many sessions there is room to list; the rest are counted. The
    /// notch solves this from the display it is on, a scrolling panel has no
    /// such ceiling.
    var sessionCap: Int = NotchLayout.defaultSessionCap
    /// Project rows the cost section may list, as the view model solved it.
    var costRows: Int = 0
    var resetTimeFormat: ResetTimeFormat = .automatic
    var deepSeekPricingEnabled: Bool = true
    var deepSeekPricingSchedule: DeepSeekPricing.Schedule = .current
    /// A tap on a session row jumps to that session's terminal — nil leaves
    /// the rows as plain text.
    var onFocusSession: ((pid_t) -> Void)? = nil
    /// Everything, or the limits alone.
    ///
    /// False stops after `ProviderLimitsContent` — the header, a block if
    /// there is one, the status message and every limit window — and drops the
    /// sections that are *about* the provider rather than about its quota.
    ///
    /// True by default, which is the notch: its card is opened by hovering one
    /// ring and has nothing to switch. The menu gives each card a switch of
    /// its own and passes what it says.
    var showsExtendedDetail: Bool = true
    /// A control the surface owns, drawn at the end of the header line. The
    /// notch passes none; the menu passes its switch, so the switch sits
    /// beside the provider it belongs to rather than somewhere above the card.
    var headerAccessory: AnyView?
    @AppStorage(Preferences.showUsagePaceKey) private var showUsagePace = false
    @AppStorage(Preferences.showsRemainingInNotchKey) private var showsRemaining = false

    /// The phase a local model is in, and the queue behind it, for the header.
    /// Ollama's relay only knows thinking; LM Studio's poll names the phase.
    private var localActivityNote: String? {
        guard snapshot.localModel != nil, let activity, activity.state == .working else { return nil }
        return activity.note ?? activity.sessions.first?.name ?? L10n.t("Thinking")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderLimitsContent(activityNote: localActivityNote, snapshot: snapshot, now: now,
                                  resetTimeFormat: resetTimeFormat, showUsagePace: showUsagePace,
                                  showsRemaining: showsRemaining,
                                  headerAccessory: headerAccessory)
            if showsExtendedDetail {
                if let resetCredits = snapshot.availableResetCredits(at: now) {
                    UsageResetCreditsSection(credits: resetCredits, now: now)
                }
                if let tokenUsage = snapshot.tokenUsage {
                    CodexUsageSection(usage: tokenUsage, now: now)
                }
                if let usageDetail = snapshot.usageDetail, usageDetail.hasUsage {
                    DeepSeekUsageDetail(detail: usageDetail, now: now,
                                        schedule: deepSeekPricingSchedule,
                                        showsPricing: deepSeekPricingEnabled)
                }
                if let activity, snapshot.localModel == nil {
                    SessionList(summary: activity, now: now, cap: sessionCap,
                                onFocus: onFocusSession)
                }
                if costRows > 0, let model = CostModels.model(for: snapshot.id) {
                    CostSection(model: model, rows: costRows)
                }
            }
        }
    }
}

private struct ProviderDetailWidthKey: EnvironmentKey {
    static var defaultValue: CGFloat { NotchLayout.cardTextWidth }
}

extension EnvironmentValues {
    /// How wide a provider-detail row may draw its bars and charts: the text
    /// column inside whatever surface is holding it, already less its padding.
    ///
    /// The notch card's column is the default, so the tooltip keeps the
    /// frame-measured proportions it was drawn to and nothing there has to
    /// pass anything. The Detail panel, which is resizable, sets its own —
    /// the one measurement in these rows that belongs to the container rather
    /// than to the notch.
    var providerDetailWidth: CGFloat {
        get { self[ProviderDetailWidthKey.self] }
        set { self[ProviderDetailWidthKey.self] = newValue }
    }
}

// MARK: - Entry point
