import AppKit
import CoreTransferable
import SwiftUI
import Combine

/// The subjects of the settings page, in the order the tab bar names them.
private enum SettingsSubject: String, CaseIterable, Identifiable, Hashable {
    case accounts, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts:      return L10n.t("Accounts")
        case .system:        return L10n.t("System")
        }
    }

    /// The subject's own mark, drawn beside its name in the tab bar.
    var icon: String {
        switch self {
        case .accounts:      return "person.crop.circle.fill"
        case .system:        return "gearshape.fill"
        }
    }
}

/// The settings window.
///
/// Two subjects, Accounts and System, with the providers that have settings
/// of their own folded into Accounts. No sidebar and no panes to switch between, so
/// everything is a scroll away from everything else.
///
/// Nothing here is boxed: the page is one column of type on the window's own
/// ground, and the only things that divide it are the space between the
/// blocks and a hairline between the groups inside one. The app's own accent
/// is the only colour, and it is on the controls.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let providers: () -> [ProviderSummary]

    /// Re-read whenever the sheet comes forward. Switching account happens in
    /// another app, so the user is always coming *back* here to see it — which
    /// makes returning focus the exact moment the old value is wrong.
    @State private var accounts: [ProviderSummary] = []
    /// Which subject the page is showing.
    @State private var subject: SettingsSubject = .accounts
    /// The provider being dragged right now.
    ///
    /// Held here rather than read off the drop, because the rows have to move
    /// *during* the drag and `dropDestination` only hands over its payload once
    /// the pointer is released. See `DragState` for why it is a reference.
    @State private var drag = DragState()
    /// Bumped on every drop, purely to make the rows' cursor rects re-evaluate.
    ///
    /// A re-render per drop, which is a discrete action and cheap — unlike the
    /// per-drag state this replaced.
    @State private var cursorRefresh = 0
    /// Where the transparency preview sits; the page is not painted there.
    @State private var clearRegion: CGRect?
    @State private var viewport: CGRect = .zero

    /// Switching off has to reach the store's archive, not just the preference
    /// — see `UsageStore.signOut(providerID:)`.
    let signOut: (String) -> Void
    /// Switching on takes the user to wherever that account is signed in.
    /// Returns false when there was nothing to open.
    let signIn: (String) -> Bool
    let switchAccount: (String) -> Bool
    /// Re-reads a provider's credential. For a declined keychain prompt that is
    /// the whole remedy: asking again is what puts the prompt back on screen.
    let retry: (String) -> Void
    var usageStore: UsageStore? = nil
    var sendTestNotification: (() -> Void)? = nil
    @Environment(\.leftoverReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            ScrollView {
                subjectContent
                    .padding(.horizontal, 26)
                    .padding(.top, 20)
                    .padding(.bottom, 26)
            }
            // The page opens at its top. Without this the scroll view keeps
            // whatever it was left at, and a window that opens halfway down
            // its own settings reads as though it opened in the wrong place.
            .defaultScrollAnchor(.top)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: SettingsViewportKey.self,
                                           value: proxy.frame(in: .named(SettingsClearRegionKey.space)))
                }
            }
            // Always on screen. The page is long, and an indicator that only
            // shows while the wheel is turning is an indicator nobody finds.
            .scrollIndicators(.visible)
            // A scroll view per subject, so that switching tabs opens the new
            // one at its top rather than halfway down.
            .id(subject)
            .transition(.opacity)
        }
        // Rebuild the whole page when the language changes.
        //
        // A segmented `Picker` draws its options through `ForEach`, which
        // identifies each row by its tag — the enum case. Switching language
        // changes only the title that row renders, not its identity, so the
        // rows compare equal, AppKit's segmented control is told nothing has
        // changed, and it keeps the segment labels it was first built with.
        // The result was a page where every plain `Text` had switched back to
        // English and every picker was still in Chinese.
        //
        // Re-identifying here rather than on each picker: there are several of
        // them across three cards, and another added later would arrive with
        // the bug and no way to notice.
        .id(preferences.language)
        .tint(preferences.accentColor.color)
        .environment(\.leftoverAccentColor, preferences.accentColor.color)
        // Every button on the page answers the pointer the same way.
        .buttonStyle(SettingsButtonStyle())
        // Fills the window rather than claiming a fixed size. Under
        // `fullSizeContentView` the content view is the whole frame — title
        // bar included — so a view sized to `SettingsView.height` left the
        // title bar's worth of transparent window above it, with the traffic
        // lights floating in the hole.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // What actually draws the panel: the window itself is transparent
        // (see `SettingsWindowController.show()`), so this colour is the whole
        // visible surface, and clipping it is what rounds all four corners
        // rather than only the two macOS rounds for a titled window.
        .coordinateSpace(name: SettingsClearRegionKey.space)
        .onPreferenceChange(SettingsClearRegionKey.self) { clearRegion = $0 }
        .onPreferenceChange(SettingsViewportKey.self) { viewport = $0 }
        .background(SettingsPalette.window.mask { ground })
        .clipShape(RoundedRectangle(cornerRadius: SettingsView.cornerRadius,
                                    style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsView.cornerRadius, style: .continuous)
                .strokeBorder(SettingsPalette.edge, lineWidth: 1)
        }
        // Without this SwiftUI insets the content by the title bar's height
        // even though the window has none to speak of, and the panel's own
        // rounded top is pushed down leaving a transparent band with the
        // traffic lights stranded in it.
        .ignoresSafeArea()
        .onAppear { refreshVisibleState() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification
        )) { _ in refreshVisibleState() }
        .onReceive((usageStore?.$panelSnapshots.eraseToAnyPublisher()
                    ?? Empty<[ProviderSnapshot], Never>().eraseToAnyPublisher())
            .receive(on: RunLoop.main)) { _ in
                // The sheet stays open while models load and unload. Update
                // those rows without re-reading cloud credentials on each poll.
                guard let usageStore else { return }
                let models = usageStore.localModelSummaries
                let updated = accounts.filter { $0.localModel == nil }.flatMap { account in
                    [account] + models.filter { $0.sourceProviderID == account.id }
                }
                accounts = ProviderOrder.arrange(updated, by: preferences.providerOrder, id: \.id)
            }
        .onReceive((usageStore?.$providerAccountRevision.eraseToAnyPublisher()
                    ?? Empty<Int, Never>().eraseToAnyPublisher())
            .receive(on: RunLoop.main)) { _ in
                // Authentication can finish in a separate WebView window while
                // this page remains alive. Re-read only the account summaries
                // for that explicit event, not on every usage poll.
                accounts = providers()
            }
    }

    /// The page's ground with the preview's region cut out, clipped to the
    /// scroll view so the hole scrolls under the tab bar rather than through it.
    private var ground: some View {
        Rectangle()
            .overlay(alignment: .topLeading) {
                if let hole = clearRegion, viewport != .zero {
                    RoundedRectangle(cornerRadius: PanelTransparencyPreview.cornerRadius, style: .continuous)
                        .frame(width: hole.width, height: hole.height)
                        .offset(x: hole.minX - viewport.minX, y: hole.minY - viewport.minY)
                        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
                        .clipped()
                        .offset(x: viewport.minX, y: viewport.minY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
    }

    /// The band across the top of the panel that the traffic lights sit in.
    ///
    /// The lights are the left of it and the app's own mark the right, so the
    /// two read as one row rather than as two things that happen to be near
    /// the top. `SettingsWindowController` positions the lights against this
    /// too.
    private var header: some View {
        HStack(spacing: 9) {
            // The room the three traffic lights take across.
            Color.clear.frame(width: SettingsView.trafficLightWidth)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
            Text(L10n.t("Leftover Settings"))
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text("Leftover \(AppVersion.current)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 26)
        .frame(height: SettingsView.headerHeight)
        .overlay(alignment: .bottom) {
            SettingsPalette.hairline.frame(height: 1)
        }
    }

    /// The subjects of the page, named across the top of it.
    ///
    /// A row of tabs rather than a column of them: the page is one column of
    /// text, and the three things it holds are named over the top of it, the
    /// way a document names its sections.
    private var tabBar: some View {
        HStack(spacing: 20) {
            ForEach(SettingsSubject.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { subject = item }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(subject == item
                                             ? preferences.accentColor.color
                                             : Color.secondary)
                        Text(item.title)
                            .font(.system(size: 12.5, weight: subject == item ? .semibold : .regular))
                            .foregroundStyle(subject == item ? Color.primary : Color.secondary)
                    }
                    // The open tab has a container of its own, the way a
                    // modern toolbar tab bar draws it: a soft rounded plate
                    // behind the mark and the name, rather than a rule
                    // under them.
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if subject == item {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.10))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(subject == item ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            SettingsPalette.hairline.frame(height: 1)
        }
    }

    /// The subject on show.
    @ViewBuilder
    private var subjectContent: some View {
        switch subject {
        case .accounts:      accountsBlock
        case .system:        systemBlock
        }
    }

    /// The accounts themselves: who Leftover reads, in what order their rings
    /// are drawn, and the providers that have settings of their own.
    /// The accounts themselves: who Leftover reads, in what order their rings
    /// are drawn, and the providers that have settings of their own.
    private var accountsBlock: some View {
        SettingsBlock(title: L10n.t("Accounts")) {
            VStack(alignment: .leading, spacing: 12) {
                if needsSetup { setupNote }

                SettingsItem(title: L10n.t("Ring order"),
                            detail: preferences.ringOrder.explanation) {
                    Picker("", selection: $preferences.ringOrder) {
                        ForEach(RingOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    // The control names itself: what the mode it is set to
                    // actually does, said where the pointer is.
                    .help(preferences.ringOrder.explanation)
                }
                SettingsNote(text: listOrderFooter)

                SettingsHairline()

                SettingsGroupLabel(title: L10n.t("Connected"))
                ForEach(connected) { account in
                    AccountRow(provider: account, preferences: preferences,
                               signOut: signOut, signIn: signIn,
                               switchAccount: switchAccount, retry: retry,
                               refresh: { usageStore?.reevaluate(providerID: $0) },
                               isOrderable: true,
                               drag: drag,
                               cursorRefresh: cursorRefresh,
                               onDrop: { cursorRefresh += 1 },
                               takePlaceOf: { move($0, onto: account.id) },
                               didConnect: { connect(account.id) })
                }
                if connected.isEmpty {
                    SettingsNote(text: L10n.t("Nothing is connected yet, so the panel is empty."))
                }
                // Beside the switches it explains, not stranded at the end of
                // the block.
                SettingsNote(text: L10n.t("Most accounts are read from a tool already signed in on this Mac. DeepSeek and MiniMax sign in through a Leftover window instead, and signing out here clears only that session."))

                // Absent rather than empty when everything is on: a titled,
                // empty group reads as something having failed to load.
                if !notConnected.isEmpty {
                    SettingsHairline()
                    SettingsGroupLabel(title: L10n.t("Not connected"))

                    // A tile each, three to a row. Stacked, eighteen tools
                    // that Leftover does not read were eighteen rows of the
                    // same sentence, and the page was twice as long as the
                    // accounts it is about.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                              spacing: 8) {
                        ForEach(notConnected) { account in
                            CompactAccountRow(provider: account, preferences: preferences,
                                              signOut: signOut, signIn: signIn,
                                              didConnect: { connect(account.id) })
                        }
                    }

                    // Says what switching one back on will do, which is the
                    // only question this group raises.
                    SettingsNote(text: L10n.t("Switch one on and it joins the end of the list above."))
                }

            }
        }
        // A row switched off jumps from one group to the other. Scoped to
        // that one value so nothing else on the page inherits an animation.
        .animation(.snappy(duration: 0.25), value: preferences.connectedProviders)
        .animation(.snappy(duration: 0.25), value: preferences.disabledModels)
    }

    /// The app's own settings: how it looks, what language it speaks, and what
    /// it does when the Mac starts.
    private var systemBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                PanelTransparencyPreview(transparency: preferences.panelTransparency)
                SettingsGroupCard(title: L10n.t("Appearance")) {
                    SettingsCardRow(title: L10n.t("Theme")) {
                        Picker("", selection: $preferences.appTheme) {
                            ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 230)
                    }
                    SettingsCardDivider()
                    SettingsCardRow(title: L10n.t("Panel transparency")) {
                        // A slider, because the panel's own ground is the one
                        // thing about it that has no other place to live.
                        HStack(spacing: 10) {
                            Slider(value: $preferences.panelTransparency, in: 0...0.8)
                                .frame(width: 170)
                            Text("\(Int((preferences.panelTransparency * 100).rounded()))%")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                    SettingsCardDivider()
                    SettingsCardRow(title: L10n.t("Language")) {
                        Picker("", selection: $preferences.language) {
                            ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }
                }
            }
            SettingsNote(text: preferences.language.explanation)

            SettingsGroupCard(title: L10n.t("Menu bar")) {
                SettingsCardRow(title: L10n.t("Shows")) {
                    Picker("", selection: $preferences.menuBarTitleStyle) {
                        ForEach(MenuBarTitleStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
                if preferences.menuBarTitleStyle != .logoOnly {
                    SettingsCardDivider()
                    SettingsCardRow(title: L10n.t("Provider")) {
                        Picker("", selection: menuBarProviderBinding) {
                            Text(L10n.t("Most used")).tag("")
                            ForEach(menuBarProviders, id: \.id) { Text($0.displayName).tag($0.id) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                    SettingsCardDivider()
                    SettingsCardRow(title: L10n.t("Show what is left")) {
                        Toggle("", isOn: $preferences.menuBarShowsRemaining)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }
            SettingsNote(text: L10n.t("Most used follows whichever limit is closest to running out."))

            SettingsGroupCard(title: L10n.t("Notifications")) {
                SettingsCardRow(title: L10n.t("When an agent finishes")) {
                    Toggle("", isOn: $preferences.announceSessionEnd)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsCardDivider()
                SettingsCardRow(title: L10n.t("When a limit runs out")) {
                    Toggle("", isOn: limitReachedBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsCardDivider()
                SettingsCardRow(title: L10n.t("When a limit resets")) {
                    Toggle("", isOn: $preferences.announceUsageReset)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsCardDivider()
                SettingsCardRow(title: L10n.t("Play sounds")) {
                    Toggle("", isOn: soundsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if let sendTestNotification {
                    SettingsCardDivider()
                    SettingsCardRow(title: L10n.t("Test notification")) {
                        Button(L10n.t("Send a test")) { sendTestNotification() }
                            .buttonStyle(SettingsButtonStyle(kind: .standard))
                    }
                }
            }
            SettingsNote(text: L10n.t("Alerts arrive as Mac notifications. A warning at 80% and 100% of a limit always comes; mute a provider with the bell on its row in Accounts."))

            SettingsGroupCard(title: L10n.t("Startup")) {
                SettingsCardRow(title: L10n.t("Open Leftover at login")) {
                    Toggle("", isOn: $preferences.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            if let problem = preferences.launchAtLoginProblem {
                SettingsNote(text: problem)
            }

            SettingsGroupCard(title: L10n.t("Readings")) {
                SettingsCardRow(title: L10n.t("Skip the cache when the panel opens")) {
                    Toggle("", isOn: $preferences.asksProviderOnLook)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            SettingsNote(text: L10n.t("Opening the panel asks for a new reading. With this on, it skips what apps on this Mac have cached and asks the provider directly, which costs a request each time. Leave it off unless you are checking a figure against the provider's own page."))

            SettingsGroupCard(title: L10n.t("Dock")) {
                SettingsCardRow(title: L10n.t("Hide from Dock")) {
                    Toggle("", isOn: $preferences.hidesDockIcon)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            SettingsNote(text: L10n.t("Leftover lives in the menu bar. Switch this off to see it in the Dock and the app switcher too."))
        }
    }
    /// The providers the menu bar item can report: those with a reading.
    private var menuBarProviders: [ProviderSnapshot] {
        (usageStore?.panelSnapshots ?? []).filter { $0.kind == .usage }
    }

    /// "Most used" is the empty tag; a provider that has gone away reads as it.
    private var menuBarProviderBinding: Binding<String> {
        Binding(
            get: {
                guard let id = preferences.menuBarProviderID,
                      menuBarProviders.contains(where: { $0.id == id }) else { return "" }
                return id
            },
            set: { preferences.menuBarProviderID = $0.isEmpty ? nil : $0 }
        )
    }

    /// Session and weekly limits as one switch.
    private var limitReachedBinding: Binding<Bool> {
        Binding(
            get: { preferences.announceSessionLimitReached || preferences.announceWeeklyLimitReached },
            set: {
                preferences.announceSessionLimitReached = $0
                preferences.announceWeeklyLimitReached = $0
            }
        )
    }

    /// One switch for every alert's sound.
    private var soundsBinding: Binding<Bool> {
        Binding(
            get: { preferences.sessionEndSound || preferences.limitReachedSound || preferences.usageResetSound },
            set: {
                preferences.sessionEndSound = $0
                preferences.limitReachedSound = $0
                preferences.usageResetSound = $0
            }
        )
    }

    private func refreshVisibleState() {
        accounts = providers()
    }

    /// The band across the top of the panel that the traffic lights sit in.
    ///
    /// The lights are the left of it and the app's own mark the right, so the
    /// two read as one row rather than as two things that happen to be near
    /// the top. `SettingsWindowController` positions the lights against this
    /// too.
    static let headerHeight: CGFloat = 52

    /// How much room the three lights take across, for the one layout that
    /// has to start to the right of them: the header. The last light's centre
    /// is 22.5 further along again and the light itself is 12 wide, so
    /// anything drawn after this has to start past 66 + something.
    static let trafficLightWidth: CGFloat = 88

    /// The panel's corner rounding. All four corners, not the two macOS gives
    /// a titled window — the window is transparent and the content draws the
    /// shape.
    static let cornerRadius: CGFloat = 20

    /// One column of settings, wide enough for a row's name and its
    /// explanation beside the control without crowding.
    static let width: CGFloat = 780
    /// The page scrolls, so this is only how much of it is on screen at once.
    static let height: CGFloat = 660

    /// The rows the panel actually draws, in the order it draws them.
    ///
    /// Model switches control visibility; their shared runtime has its own
    /// connection row and must remain enabled for its models to appear.
    private var ringAccounts: [ProviderSummary] {
        accounts.filter {
            $0.kind == .usage || ($0.localModel != nil && preferences.isConnected($0.sourceProviderID ?? $0.id))
        }
    }

    private var connected: [ProviderSummary] {
        ringAccounts.filter { preferences.isConnected($0.id) }
    }

    private var notConnected: [ProviderSummary] {
        ringAccounts.filter { !preferences.isConnected($0.id) }
    }

    /// Nothing to read from anywhere. On a first launch that is the normal
    /// state, and it is the only moment the sheet has something to explain.
    private var needsSetup: Bool {
        guard !connected.contains(where: { $0.localModel != nil }) else { return false }
        let usageAccounts = accounts.filter { $0.kind == .usage }
        return !usageAccounts.isEmpty && usageAccounts.allSatisfy { $0.account == nil }
    }

    /// What the list footer says about ordering: the picker above names the
    /// sort, so this only says what dragging still does under it.
    private var listOrderFooter: String {
        switch preferences.ringOrder {
        case .manual:
            return L10n.t("Drag an account by its handle to move it.")
        case .remaining, .deficit:
            return L10n.t("Sorted automatically. Dragging only decides between accounts that tie.")
        }
    }

    /// Names the tools rather than saying "tools already signed in on this
    /// Mac". Someone who uses Claude in a browser reads that sentence, installs
    /// this, sees four blank rings and concludes it is broken — and the
    /// distinction that catches them out is Claude *Code*, not the Claude app.
    static var setupCopy: String {
        L10n.t("Leftover reads usage from tools already signed in on this Mac — it never asks for your password. Install and sign in to any of Claude Code (the terminal tool, not the Claude app), Cursor (the editor or cursor-agent), Codex, Antigravity, GLM, Grok, OpenCode, Command Code, GitHub Copilot, Kimi Code, Kiro, Amp, Apify, the Kilo CLI, Muse, Higgsfield or a Gemini API key (via Gemini CLI, OpenCode or Hermes), and its ring appears in the panel.")
    }

    /// Said before it happens rather than after. A system dialogue asking to
    /// read a *credential*, from an app installed a minute ago, looks alarming
    /// unless it was expected — and choosing Allow instead of Always Allow made
    /// it return on every read, which is what "it asks every time" turns out to
    /// be.
    static var keychainCopy: String {
        L10n.t("macOS may ask before Leftover reads Claude Code's, Antigravity's, cursor-agent's or Muse's saved login. Background refreshes never show that question; it appears only when you click Allow access…, and Deny stops Leftover reading that login until you ask again.")
    }

    /// A provider has just been switched on: put it after the ones already
    /// connected.
    ///
    /// Done here rather than in `Preferences` because the full list of
    /// providers lives here — `providerOrder` is empty until someone drags
    /// something, and "the end of the connected ones" cannot be expressed
    /// against an order that does not exist yet.
    private func connect(_ providerID: String) {
        let ids = ProviderOrder.joiningConnected(providerID,
                                                 in: accounts.map(\.id),
                                                 isConnected: preferences.isConnected)
        accounts = ProviderOrder.arrange(accounts, by: ids, id: \.id)
        preferences.setProviderOrder(ids)
    }

    /// Put the dragged provider where the one under the pointer sits, while the
    /// drag is still in the air.
    ///
    /// Written through the preference on every crossing rather than batched
    /// until the drop: a drag released outside the window fires no drop at all,
    /// and a list left visibly reordered but unsaved would disagree with the
    /// panel until the window was next opened.
    ///
    /// Returns whether both ids are ours — anything dragged in from another app
    /// is a string too.
    @discardableResult
    private func move(_ movedID: String, onto targetID: String) -> Bool {
        guard let from = accounts.firstIndex(where: { $0.id == movedID }),
              let to = accounts.firstIndex(where: { $0.id == targetID })
        else { return false }
        guard from != to else { return true }

        var reordered = accounts
        reordered.insert(reordered.remove(at: from), at: to)
        accounts = reordered
        // Every row, connected or not — the order is a fact about the list, and
        // a provider switched off today still has a place to come back to.
        preferences.setProviderOrder(accounts.map(\.id))
        return true
    }

    private var setupNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("Connect an assistant to get started"))
                    .font(.callout.weight(.medium))
                Text(SettingsView.setupCopy)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(SettingsView.keychainCopy)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            reduceTransparency ? .orange.opacity(0.18) : .orange.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.orange.opacity(0.4), lineWidth: 1)
            }
        }
    }


}

/// A grab cursor AppKit can be forced to re-evaluate on the spot.
///
/// `.pointerStyle` rides the pointer-tracking system, which AppKit consults only
/// on a mouse move — so a drag ending with the pointer held still leaves an
/// arrow on the grip. `invalidateCursorRects(for:)` is the escape hatch the
/// pointer system lacks, and owning a cursor rect is what puts it within reach.
private struct GrabCursor: NSViewRepresentable {
    /// Bumped by the parent on each drop. Its only purpose is to make
    /// `updateNSView` run, which is where the rects are invalidated — the value
    /// itself is never read.
    let refreshToken: Int

    func makeNSView(context: Context) -> CursorRectView { CursorRectView() }

    func updateNSView(_ view: CursorRectView, context: Context) {
        // The pointer is sitting on a grip whose cursor AppKit reset to an arrow
        // when the drag ended, and it will not ask again on its own. This asks.
        view.window?.invalidateCursorRects(for: view)
    }

    /// A transparent view whose whole job is to declare "an open hand belongs
    /// here", so `resetCursorRects` — which AppKit calls on its own and on every
    /// `invalidateCursorRects` — has something to re-establish.
    final class CursorRectView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

/// What is being dragged, shared by every row without any of them observing it.
///
/// A class on purpose. As `@State`/`@Binding` this was SwiftUI state, so setting
/// it re-rendered every row twice per drag — once to start, once to finish — and
/// the second rebuild arrived after the drop and reset the pointer. A plain
/// reference is read the same way and changes nothing on screen.
@MainActor
final class DragState {
    var id: String?
}

/// One provider: whether Leftover reads it, whose account that is, and where
/// to go if there is nothing to read.
/// A tool Leftover knows about but does not read: its name, its mark, and
/// the switch that starts reading it.
///
/// A tile rather than a row. Eighteen of these stacked were eighteen rows
/// saying the same thing — signed out, nothing read — and the page was twice
/// as long as the accounts it was about.
private struct CompactAccountRow: View {
    let provider: ProviderSummary
    @ObservedObject var preferences: Preferences
    let signOut: (String) -> Void
    let signIn: (String) -> Bool
    let didConnect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProviderGlyphView(glyph: provider.glyph, size: 14)
                .accessibilityHidden(true)
            Text(provider.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Toggle("", isOn: connectionBinding(for: provider, preferences: preferences,
                                               signIn: signIn, signOut: signOut,
                                               didConnect: didConnect))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(provider.localModel != nil
                      ? L10n.t("Show or hide this model in the panel.")
                      : L10n.t("Switch on to sign in and read \(provider.name) again."))
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsPalette.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SettingsPalette.hairline, lineWidth: 1)
        }
    }
}

/// The switch that starts reading a provider, or lets it go.
///
/// One control for both directions: on signs in, off signs out.
///
/// Switching on does more than set a flag — if there is no credential to
/// read it opens the sign-in there and then, which is the point of managing
/// this from one place. Switching off is a real sign-out: it forgets the
/// readings as well as stopping the next one.
private func connectionBinding(for provider: ProviderSummary,
                               preferences: Preferences,
                               signIn: @escaping (String) -> Bool,
                               signOut: @escaping (String) -> Void,
                               didConnect: @escaping () -> Void) -> Binding<Bool> {
    Binding(
        get: { preferences.isConnected(provider.id) },
        set: { wantsOn in
            if wantsOn {
                preferences.setConnected(true, for: provider.id)
                // After the switch, not before: where it belongs depends on
                // which providers are connected, and this one has only just
                // become one of them.
                didConnect()
                // Nothing to open for Claude Code — but then there is no
                // account either, so `detail` is already showing what to do.
                if provider.localModel == nil { _ = signIn(provider.id) }
            } else {
                if provider.localModel == nil { signOut(provider.id) }
                preferences.setConnected(false, for: provider.id)
            }
        }
    )
}

private struct AccountRow: View {
    let provider: ProviderSummary
    @ObservedObject var preferences: Preferences
    let signOut: (String) -> Void
    let signIn: (String) -> Bool
    let switchAccount: (String) -> Bool
    let retry: (String) -> Void
    let refresh: (String) -> Void
    /// Whether this row has a place in the panel to argue about. A provider
    /// switched off draws no ring, so there is nothing for a drag to arrange.
    let isOrderable: Bool
    /// The provider in flight, shared with every other row: this one has to
    /// know what is being dragged the moment the pointer arrives, not once it
    /// is released.
    let drag: DragState
    /// Changes on every drop; handed straight to `GrabCursor`, which uses the
    /// change itself rather than the value.
    let cursorRefresh: Int
    /// Tells the list a drop landed, so the cursor rects get re-evaluated while
    /// the pointer is still standing on the grip.
    let onDrop: () -> Void
    /// Move the dragged provider into this row's place. False when the id is
    /// not one of ours.
    let takePlaceOf: (String) -> Bool
    /// Called after this row is switched on, so the list can decide where it
    /// now belongs. The row itself cannot: it can see only itself.
    let didConnect: () -> Void

    @Environment(\.leftoverReduceTransparency) private var reduceTransparency

    /// The handle only appears under the pointer, so a row at rest stays as
    /// quiet as it was before there was anything to drag.
    @State private var isHovering = false

    private var isConnected: Bool { preferences.isConnected(provider.id) }
    private var isMuted: Bool { preferences.isMutedAlerts(for: provider.id) }

    /// The name the owner gave the account, where there is one; the row, the
    /// panel and the notifications all use the same word.
    private var displayName: String { preferences.nickname(for: provider.id) ?? provider.name }
    @State private var isRenaming = false
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Centred, not baseline-aligned. A glyph is a `Shape` and has no
            // text baseline, so `.firstTextBaseline` lines its *bottom edge* up
            // with the text's baseline and lifts every icon above its own name.
            // Everything on this row is a single line, so centring is what makes
            // the mark, the name, the button and the switch sit on one axis.
            HStack(alignment: .center, spacing: 10) {
                // Grip, mark and name are one grab area: a 12pt square is a
                // blank to hit, and none of the three do anything else. The
                // buttons and the switch stay out — a drag would compete.
                HStack(spacing: 10) {
                    if isOrderable { handle }

                    ProviderGlyphView(glyph: provider.glyph, size: 16)
                        .foregroundStyle(isConnected ? .primary : .tertiary)

                    Text(displayName)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isConnected ? .primary : .secondary)
                }
                // Without this only the drawn pixels are grabbable, and the
                // gaps between the three of them are not.
                .contentShape(Rectangle())
                // `onDrag` rather than `draggable`, for its one advantage: it
                // runs a closure when the drag *starts*. Every other row needs
                // to know what is coming before it can make room for it, and
                // `dropDestination` does not hand over its payload until the
                // drop.
                .onDrag {
                    // A row with no ring has nothing to place. Handing back an
                    // empty provider is how `onDrag` declines a drag.
                    guard isOrderable else { return NSItemProvider() }
                    drag.id = provider.id
                    return NSItemProvider(object: provider.id as NSString)
                } preview: {
                    // The name alone, not the row: dragging the switch, the
                    // buttons and two lines of explanation across the window is
                    // a lot of translucent furniture to move a ring one place
                    // up.
                    HStack(spacing: 6) {
                        ProviderGlyphView(glyph: provider.glyph, size: 12)
                        Text(displayName)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .help(isOrderable
                      ? L10n.t("Drag to reorder. The panel shows the rings in this order.")
                      : L10n.t("Switch this on to give it a ring in the panel."))
                // Two mechanisms, neither of which covers both halves.
                // `pointerStyle` draws the hand on an ordinary hover but cannot
                // re-evaluate under a pointer that has not moved, which is the
                // state a finished drag leaves behind; the cursor rect exists
                // only so `invalidateCursorRects` can force that.
                //
                // It must sit *over* the content — behind it, SwiftUI's own
                // pointer regions win and the rect is never consulted at all —
                // and it must not take hits, or it swallows the drag.
                .pointerStyle(isOrderable ? .grabIdle : nil)
                .overlay {
                    if isOrderable {
                        GrabCursor(refreshToken: cursorRefresh)
                            .allowsHitTesting(false)
                    }
                }

                Spacer(minLength: 8)

                // A name of the owner's choosing. Two logins on one provider
                // are told apart by their directory names ("Claude (work)"),
                // which is the machine's word for them, not the person's; and
                // the same name has to hold in the panel, the menu bar and
                // every notification, so it is kept in Preferences and applied
                // by the store rather than typed over here.
                if isConnected, provider.kind == .usage {
                    Button {
                        draftName = preferences.nickname(for: provider.id) ?? ""
                        isRenaming.toggle()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(SettingsIconButtonStyle())
                    .help(L10n.t("Name this account"))
                    .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(L10n.t("Name"), text: $draftName, prompt: Text(provider.name))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { isRenaming = false }
                                .onChange(of: draftName) { _, name in
                                    preferences.setNickname(name, for: provider.id)
                                }
                            Text(L10n.t("What the panel and notifications call this account. Empty goes back to \(provider.name)."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(width: 280)
                    }
                }

                // Per-provider threshold alerts, muted here rather than in a
                // separate notifications pane — the thing being muted is this
                // row's reading, so the control belongs on the row.
                if isConnected, provider.kind == .usage {
                    Button {
                        preferences.setAlertsMuted(!isMuted, for: provider.id)
                    } label: {
                        Image(systemName: isMuted ? "bell.slash" : "bell")
                            .font(.system(size: 11))
                            .foregroundStyle(isMuted ? .tertiary : .secondary)
                    }
                    .buttonStyle(SettingsIconButtonStyle())
                    .help(isMuted
                          ? L10n.t("Alerts for \(displayName) are muted. Click to unmute.")
                          : L10n.t("Alert when \(displayName) crosses 80% and 100% of a limit."))
                }

                // Prefers the app that owns the account, and falls back to the
                // web page only when there is no app to open.
                //
                // The reading is borrowed from an app on this Mac, so that app
                // is where the account actually lives — and the website is a
                // different session entirely, which will bounce you to a login
                // if the browser is not signed in. Sending someone to a login
                // screen from a row that says "connected" is the wrong answer
                // whenever the real thing is one launch away.
                // The way back from a declined keychain prompt, and the only
                // one: declining is easy to do by reflex, and nothing else on
                // screen will ask macOS again.
                //
                // Shown only while macOS is actually refusing. It used to be
                // permanent for any keychain-backed provider, which meant it sat
                // there next to a working account offering to fix nothing — and
                // when it *was* needed there was no way to tell the two apart.
                if isConnected, provider.wasRefusedAccess {
                    Button(L10n.t("Allow access…")) { retry(provider.id) }
                        .controlSize(.small)
                        // Not "it will stop asking": for Claude it will not.
                        // Claude Code recreates its login when the token
                        // rotates, and a recreated item forgets the grant.
                        .help(L10n.t("Asks macOS for \(provider.name)'s saved login again. Deny stops Leftover reading it until you ask again."))
                }

                if isConnected, let destination {
                    Button(destination.title) { open(destination) }
                        .controlSize(.small)
                        .help(destination.help)
                }

                Toggle(provider.name, isOn: binding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help(provider.localModel != nil
                          ? L10n.t("Show or hide this model in the panel. It stays loaded in \(provider.runtimeName ?? "Ollama").")
                          : isConnected
                          ? L10n.t("Switch off to stop reading \(provider.name) and forget its readings. \(provider.signIn.signOutCaveat)")
                          : L10n.t("Switch on to sign in and read \(provider.name) again."))
            }

            // 48 = the handle, the glyph and the two gaps before the name, so
            // the detail still starts under the first letter of the name.
            detail
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 48)

            // Outside `detail` on purpose. That chain shows the account summary
            // whenever there is an account, and an aged-out token still has
            // one — the credential is there, it is simply too old to use. Put
            // inside, this warning would be swallowed by the very row that
            // makes everything look fine.
            if isConnected, provider.needsSignInRenewal {
                Text(L10n.t("\(provider.name) usage needs its sign-in renewed — run `claude` once in a terminal."))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 48)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // One account in a card of its own. A list of accounts is a list of
        // things, and a line around each one says which thing is which long
        // before the eye reaches the name — the detail under it can be as
        // long as it likes without blurring into the account below.
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsPalette.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isHovering ? SettingsPalette.hairlineStrong : SettingsPalette.hairline,
                              lineWidth: 1)
        }
        // The whole row is the drop target, handle or not: a 12pt strip is a
        // hard thing to hit, and there is no ambiguity about which row the
        // pointer is over.
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .dropDestination(for: String.self) { ids, _ in
            defer { drag.id = nil }
            guard isOrderable else { return false }
            // AppKit resets the cursor when a drag session ends and will not ask
            // what belongs here again until the mouse next moves — so releasing
            // the button and holding still left an arrow on a grip that was
            // perfectly grabbable. Setting a cursor by hand loses that race
            // whatever the timing, because the reset lands last; asking AppKit
            // to re-evaluate the rects does not race it at all.
            onDrop()
            // The list already settled on the way in. This only answers whether
            // what was released was ever ours.
            guard let moved = ids.first else { return false }
            return takePlaceOf(moved)
        } isTargeted: { entered in
            // The rearrangement happens here, not on the drop: the pointer
            // crossing into this row is the whole gesture, and the rows sliding
            // out of the way is what says where the ring will land.
            guard isOrderable, entered, let moved = drag.id, moved != provider.id
            else { return }
            withAnimation(.snappy(duration: 0.22)) { _ = takePlaceOf(moved) }
        }
    }

    /// The affordance only. The drag itself is on the whole group around it,
    /// because this is far too small a thing to have to hit.
    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            // Always drawn, only dimmer at rest. It used to be invisible until
            // hovered, and hover is exactly the state a drag leaves stale: the
            // reorder moves the row out from under a pointer that has not
            // itself moved, so no further hover event arrives and the grip
            // stayed gone until the pointer left the row and came back. Dimming
            // cannot fail that way — the worst a stale `isHovering` costs now
            // is a little emphasis.
            .opacity(isHovering ? 1 : (reduceTransparency ? 0.7 : 0.4))
            // Tall enough to be part of a real target rather than a 13pt strip
            // floating in the middle of the row.
            .frame(width: 12, height: 22)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            accountDetail
            
            // Antigravity limit dropdown
            if isConnected, provider.id == AntigravityProfile.defaultID {
                // The two pickers side by side: stacked, they were the
                // tallest thing in the row and said almost nothing.
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Ring shows"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Picker(L10n.t("Ring shows"), selection: $preferences.antigravityHeadlineLimit) {
                            ForEach(AntigravityHeadlineLimit.allCases) { limit in
                                Text(limit.title).tag(limit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Model data"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Picker(L10n.t("Model data"), selection: $preferences.antigravityHeadlineModel) {
                            ForEach(AntigravityHeadlineModel.allCases) { model in
                                Text(model.explanation).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                }
                .padding(.top, 2)
                .help(L10n.t("Choose which of Antigravity's limits its ring shows."))
                .onChange(of: preferences.antigravityHeadlineLimit) { _ in
                    refresh(provider.id)
                }
                .onChange(of: preferences.antigravityHeadlineModel) { _ in
                    refresh(provider.id)
                }
            }

            // Google publishes no limit for a bare API key, so the ring has
            // nothing to fill against until the user names a ceiling itself.
            if isConnected, provider.id == "gemini-api" {
                // The field's own title would be drawn as a leading label
                // inside a `Form` row, which puts the caption hard against
                // the box and leaves the unit stranded past it. Hidden, so
                // the caption above can own the naming and the row can
                // breathe.
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("Monthly budget"))
                    HStack(spacing: 8) {
                        TextField(L10n.t("None"), value: $preferences.geminiAPIMonthlyTokenBudget,
                                  format: .number)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 130)
                        Text(L10n.t("tokens"))
                    }
                }
                .padding(.top, 2)
                .foregroundStyle(.secondary)
                .help(L10n.t("Fills the ring against a ceiling you choose; Google publishes none for an API key."))
            }
            // Ollama owns its credential: the user enters an API key here, stored
            // in the keychain. The env var OLLAMA_API_KEY is checked first, so a
            // shell that exports one needs no entry here.
            if provider.id == "ollama" {
                ollamaKeyEntry
            }

            // MiniMax is signed into in Leftover, or by a Coding Plan key
            // pasted here. The region is which console that key belongs to.
            // Stored in the keychain on Save, the same way Ollama's is.
            if provider.id == "qoder" {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Region"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Picker(selection: $preferences.qoderRegion) {
                        Text(L10n.t("International")).tag(Sites.QoderRegion.global)
                        Text(L10n.t("China mainland")).tag(Sites.QoderRegion.china)
                    } label: { EmptyView() }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                    Text(L10n.t("Sign in to Qoder in Leftover. Each region has a separate account and session. Website verification may be required."))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if provider.id == "minimax" {
                minimaxEntry
            }

            // Apify borrows the CLI's login when there is one; the token
            // pasted here is for a Mac without it. Stored in the keychain on
            // Save, the same way Ollama's is.
            if provider.id == "apify" {
                apifyTokenEntry
            }
            if provider.id == "higgsfield" {
                higgsfieldKeyEntry
            }
        }
    }

    /// The API key input for Ollama. Stored in the keychain on Save, then a
    /// refresh is triggered so the ring picks up the new credential without a
    /// relaunch.
    @State private var ollamaKey = ""
    @State private var ollamaKeySaved = false

    private var ollamaKeyEntry: some View {
        // Laid out like the Gemini budget above it, and for the same reason:
        // a field's own title becomes a leading label in a `Form` row, which
        // crowds the box and pins it to the caption. The caption goes on its
        // own line instead, and `.small` comes off the controls — it bought
        // nothing but a cramped row.
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Ollama API key"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(L10n.t("Paste your key"), text: $ollamaKey)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                Button(L10n.t("Save")) {
                    guard !ollamaKey.isEmpty else { return }
                    OllamaCredentials.store(ollamaKey)
                    ollamaKey = ""
                    ollamaKeySaved = true
                    _ = signIn(provider.id)
                }
                .disabled(ollamaKey.isEmpty)
                if ollamaKeySaved {
                    Text(L10n.t("Saved"))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.top, 2)
    }

    /// The API token input for Apify. Stored in the keychain on Save, then a
    /// refresh is triggered so the ring picks up the new credential without a
    /// relaunch — the same shape as Ollama's key above, and for the same
    /// reason the caption sits on its own line.
    @State private var apifyToken = ""
    @State private var apifyTokenSaved = false

    private var apifyTokenEntry: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Apify API token"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(L10n.t("Paste your key"), text: $apifyToken)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                Button(L10n.t("Save")) {
                    guard !apifyToken.isEmpty else { return }
                    ApifyCredentials.storeSettingsToken(apifyToken)
                    apifyToken = ""
                    apifyTokenSaved = true
                    _ = signIn(provider.id)
                }
                .disabled(apifyToken.isEmpty)
                if apifyTokenSaved {
                    Text(L10n.t("Saved"))
                        .foregroundStyle(.green)
                }
            }
            Text(L10n.t("Paste a token from Apify Console › Settings › API & Integrations. Not needed after apify login, or with APIFY_TOKEN exported. Stored in your login keychain."))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    /// The API key input for Higgsfield. Stored in the keychain on Save, then a
    /// refresh is triggered so the ring picks up the new credential without a relaunch.
    @State private var higgsfieldKey = ""
    @State private var higgsfieldKeySaved = false

    private var higgsfieldKeyEntry: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Higgsfield API key"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(L10n.t("Paste your key"), text: $higgsfieldKey)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                Button(L10n.t("Save")) {
                    guard !higgsfieldKey.isEmpty else { return }
                    HiggsfieldCredentials.store(higgsfieldKey)
                    higgsfieldKey = ""
                    higgsfieldKeySaved = true
                    _ = signIn(provider.id)
                }
                .disabled(higgsfieldKey.isEmpty)
                if higgsfieldKeySaved {
                    Text(L10n.t("Saved"))
                        .foregroundStyle(.green)
                }
            }
            Text(L10n.t("Paste an API key or token from Higgsfield Console. Not needed after hf auth login, or with HIGGSFIELD_API_KEY exported. Stored in your login keychain."))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    /// Region and Coding Plan key for MiniMax.
    ///
    /// Laid out like the Ollama key above it, and for the same reason: a
    /// field's own title becomes a leading label in a `Form` row. Captions
    /// sit on their own line. Changing the region only stores the choice —
    /// opening Sign in here would throw a sheet over a preference picker.
    @State private var minimaxKey = ""
    @State private var minimaxKeySaved = false
    @State private var minimaxCookie = ""
    @State private var minimaxCookieSaved = false

    private var minimaxEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Region and the two keys side by side. Stacked, they were three
            // rows of their own in the middle of an account row, and the
            // account row is the thing the eye is looking for.
            HStack(alignment: .top, spacing: 16) {
                minimaxRegionEntry
                    .frame(width: 140, alignment: .leading)
                minimaxKeyEntry
                    .frame(maxWidth: .infinity, alignment: .leading)
                minimaxCookieEntry
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(L10n.t("Sign in to MiniMax in Leftover, or paste a Coding Plan key. A Cookie header is optional. Leftover never reads a browser's cookies."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private var minimaxRegionEntry: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Region"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Picker(selection: $preferences.minimaxRegion) {
                Text(L10n.t("International")).tag(MiniMaxRegion.international)
                Text(L10n.t("China mainland")).tag(MiniMaxRegion.china)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var minimaxKeyEntry: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("MiniMax Coding Plan key"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(L10n.t("Paste your key"), text: $minimaxKey)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 170)
                Button(L10n.t("Save")) {
                    guard !minimaxKey.isEmpty else { return }
                    MiniMaxCredentials.storeAPIKey(minimaxKey)
                    minimaxKey = ""
                    minimaxKeySaved = true
                    _ = signIn(provider.id)
                }
                .buttonStyle(SettingsButtonStyle(kind: .standard, compact: true))
                .disabled(minimaxKey.isEmpty)
                if minimaxKeySaved {
                    Text(L10n.t("Saved"))
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var minimaxCookieEntry: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Cookie header (optional)"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(L10n.t("Cookie: …"), text: $minimaxCookie)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 170)
                Button(L10n.t("Save")) {
                    guard !minimaxCookie.isEmpty else { return }
                    MiniMaxCredentials.storeCookieHeader(minimaxCookie)
                    minimaxCookie = ""
                    minimaxCookieSaved = true
                    _ = signIn(provider.id)
                }
                .buttonStyle(SettingsButtonStyle(kind: .standard, compact: true))
                .disabled(minimaxCookie.isEmpty)
                if minimaxCookieSaved {
                    Text(L10n.t("Saved"))
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
            }
        }
    }

    @ViewBuilder
    private var accountDetail: some View {
        if let model = provider.localModel {
            Text(isConnected ? L10n.t("\(model.memoryText) \(model.memoryLabel) · via \(provider.runtimeName ?? "Ollama")")
                 : L10n.t("Hidden from the panel · Loaded in \(provider.runtimeName ?? "Ollama")"))
                .foregroundStyle(.secondary)
        } else if !isConnected {
            Text(L10n.t("Signed out — nothing is read, and no readings are kept."))
                .foregroundStyle(.tertiary)
        } else if let account = provider.account {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(account.summary)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if canOpenSignIn {
                        Button(L10n.t("Switch…")) { _ = switchAccount(provider.id) }
                            .buttonStyle(SettingsLinkButtonStyle())
                            .help(provider.signIn.switchHint)
                    }
                }
                // Says where the account actually lives, which is the whole
                // answer to "how do I change it" — not here.
                Text(provider.signIn.switchHint)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if provider.wasRefusedAccess {
            // Not a sign-in problem, so do not send them off to sign in. The
            // credential is right there and macOS is the one saying no — the
            // remedy is the button on this same row.
            Text(L10n.t("Leftover is not reading \(provider.name)'s saved login. Choose Allow access… above and answer Allow."))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                Text(provider.signIn.explanation)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if let title = provider.signIn.actionTitle, canOpenSignIn {
                    Button(title) { _ = signIn(provider.id) }
                        .controlSize(.small)
                }

            }
        }
    }

    /// Where this row's "Open" button goes.
    enum Destination {
        case app(URL, name: String)
        case website(URL, host: String)

        var title: String {
            switch self {
            case .app(_, let name):     return L10n.t("Open \(name)")
            case .website(_, let host): return L10n.t("Open \(host)")
            }
        }

        var help: String {
            switch self {
            case .app(_, let name):
                return L10n.t("Opens \(name), which is where this account is signed in.")
            case .website(_, let host):
                return L10n.t("Opens \(host) in your browser. That site has its own sign-in, separate from the credential read here.")
            }
        }
    }

    /// The owning app when it is installed, the vendor's page otherwise.
    private var destination: Destination? {
        if case .openApp(let bundleID, let name) = provider.signIn,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return .app(app, name: name)
        }
        // Claude Code is a command with no app to open, so its row is always a
        // link — and claude.ai is genuinely where its usage can be checked.
        if let url = provider.account?.manageURL, let host = url.host {
            return .website(url, host: host)
        }
        return nil
    }

    private func open(_ destination: Destination) {
        switch destination {
        case .app(let url, _):
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .website(let url, _):
            NSWorkspace.shared.open(url)
        }
    }

    /// Offering to open an app that isn't installed gives a button that does
    /// nothing — worse than no button.
    private var canOpenSignIn: Bool {
        switch provider.signIn {
        case .modal:
            return true
        case .openApp(let bundleID, _):
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        case .guidance:
            return false
        case .command:
            // Installed or not, the button does something: it runs the login
            // or opens the install page.
            return true
        }
    }

    /// The switch that connects this provider, or lets it go.
    private var binding: Binding<Bool> {
        connectionBinding(for: provider, preferences: preferences,
                          signIn: signIn, signOut: signOut,
                          didConnect: didConnect)
    }

}

