import AppKit
import Combine
import SwiftUI

/// The menu bar item: at rest, a one-line summary of a provider; clicked, the panel.
@MainActor
final class MenuBarController {
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let model: PanelModel
    private let onOpen: () -> Void
    private let preferences: Preferences
    private var cancellables: Set<AnyCancellable> = []

    init(model: PanelModel, refresh: @escaping (String) -> Task<Void, Never>?,
         onSettings: @escaping () -> Void, onOpen: @escaping () -> Void = {},
         preferences: Preferences) {
        self.model = model
        self.onOpen = onOpen
        self.preferences = preferences
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
        popover.animates = true
        let panel = MenuBarPanel(refresh: refresh, onSettings: { [weak popover] in
            popover?.performClose(nil)
            onSettings()
        }, preferences: preferences)
        let hosting = NSHostingController(rootView: AnyView(panel.environmentObject(model)))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        if let button = item.button {
            let logo = NSImage(named: "MenuBarIcon")
            logo?.size = NSSize(width: 18, height: 18)
            logo?.isTemplate = true
            logo?.accessibilityDescription = "Leftover"
            button.image = logo
            button.imagePosition = .imageLeading
            button.action = #selector(toggle)
            button.target = self
        }

        updateTitle()
        model.objectWillChange
            .merge(with: preferences.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateTitle() }
            .store(in: &cancellables)
    }

    /// The chosen provider's percentage, or the most used one's, in the style set in Settings.
    private func updateTitle() {
        let usage = model.snapshots.filter { $0.kind == .usage && $0.usedFraction != nil }
        let chosen = preferences.menuBarProviderID.flatMap { id in usage.first { $0.id == id } }
        guard preferences.menuBarTitleStyle != .logoOnly,
              let snapshot = chosen ?? usage.max(by: { $0.usedFraction! < $1.usedFraction! }),
              let used = snapshot.usedFraction
        else {
            item.button?.title = ""
            return
        }
        let shown = preferences.menuBarShowsRemaining ? 1 - used : used
        let percent = Int((min(max(shown, 0), 1) * 100).rounded())
        let text = preferences.menuBarTitleStyle == .namePercent
            ? L10n.t("\(snapshot.displayName) \(percent)%")
            : L10n.t("\(percent)%")
        item.button?.title = " " + text
    }

    /// Hides the material AppKit puts behind a popover, so the panel's own
    /// surface shows and its opacity setting means something: with the
    /// material left in, a dark backdrop showed however transparent the panel was.
    private func hidePopoverMaterial() {
        guard let content = popover.contentViewController?.view.window?.contentView else { return }
        for sub in content.subviews {
            if let effect = sub as? NSVisualEffectView { effect.isHidden = true }
        }
        popover.contentViewController?.view.wantsLayer = true
        popover.contentViewController?.view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
            onOpen()
        }
    }

    func open() {
        guard !popover.isShown else { return }
        show()
        onOpen()
    }

    private func show() {
        guard let button = item.button else { return }
        // Left alone the popover takes the menu bar's look, which follows
        // the wallpaper rather than the theme chosen in Settings.
        popover.appearance = NSAppearance(
            named: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        hidePopoverMaterial()
    }
}
