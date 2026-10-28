import AppKit
import SwiftUI

/// The settings window, as a panel that does not activate the app.
///
/// A menubar app that activates itself puts its own menus in the screen's
/// menu bar — the app name, and View, Window and Help after it — and a
/// menubar app that owns the top of the screen is a different thing from one
/// that shows a window when asked. A non-activating panel is the way out: it
/// comes to the front and takes the keyboard without the app ever becoming
/// the active application, so the menu bar stays where it was.
///
/// `canBecomeKey` has to be said out loud: a panel says no by default, and a
/// panel that cannot be key cannot hold the focus of a text field.
final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    /// Never the main window — the app has no main window to speak of, and a
    /// main window would put the app's menus in the menu bar.
    override var canBecomeMain: Bool { false }
}

/// Hosts the settings sheet in its own window.
///
/// A real window rather than something attached to the panel: settings are a
/// place you go, not something you glance at.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: SettingsPanel?
    /// Ends text editing when a click lands anywhere but a text field.
    private var clickAwayMonitor: Any?
    private let preferences: Preferences
    /// A closure, not a snapshot. Read once at launch, the account shown here
    /// went stale the moment someone switched account in Cursor — and stayed
    /// stale until the app was restarted.
    private let providers: () -> [ProviderSummary]
    private let signOut: (String) -> Void
    private let signIn: (String) -> Bool
    private let switchAccount: (String) -> Bool
    private let retry: (String) -> Void
    private let usageStore: UsageStore?
    private let sendTestNotification: (() -> Void)?

    init(preferences: Preferences,
         providers: @escaping () -> [ProviderSummary],
         signOut: @escaping (String) -> Void,
         signIn: @escaping (String) -> Bool,
         switchAccount: @escaping (String) -> Bool,
         retry: @escaping (String) -> Void,
         sendTestNotification: (() -> Void)? = nil,
         usageStore: UsageStore? = nil) {
        self.usageStore = usageStore
        self.sendTestNotification = sendTestNotification
        self.switchAccount = switchAccount
        self.retry = retry
        self.preferences = preferences
        self.providers = providers
        self.signOut = signOut
        self.signIn = signIn
    }

    /// Bring the window to the front.
    ///
    /// The app stays an accessory, and it is never activated: no Dock icon,
    /// and — the part that matters here — no menu bar of its own appearing at
    /// the top of the screen while the settings are open. It used to promote
    /// itself to a regular app for as long as the window was open, and that
    /// promotion is what put Leftover's own menus up there. A menubar app
    /// that owns the whole top of the screen is a different thing from one
    /// that shows a window when asked.
    ///
    /// The panel is a non-activating one, which is how it comes to the front
    /// and takes the keyboard without the app becoming active.
    private func surface(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        Self.startUnfocused(window)
    }

    /// Put the window in the middle of the screen the pointer is on.
    ///
    /// `NSWindow.center()` centres on whichever screen AppKit thinks the
    /// window belongs to, which for a window that has never been on screen is
    /// not necessarily the one the user is looking at. On a machine with more
    /// than one display that put the settings window on a second screen,
    /// off to the side of the one the pointer was on — a window that looks as
    /// though it never opened at all.
    private static func centerOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                      y: visible.midY - size.height / 2))
    }

    /// Opened with nothing being typed in. AppKit hands a window that becomes
    /// key to the first control in its key-view loop — here, whichever text
    /// field the open pane happens to start with — so Settings opened with a
    /// caret blinking in an API key field, and AutoFill offering passwords for
    /// it. Cleared now and once more after SwiftUI's first layout, which is
    /// when a freshly built pane's fields join the loop. Tab still reaches them.
    static func startUnfocused(_ window: NSWindow) {
        window.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak window] in
            guard let window, window.firstResponder is NSText else { return }
            window.makeFirstResponder(nil)
        }
    }

    /// A text field in Settings stayed active — caret blinking, AutoFill's
    /// "Passwords…" bubble hanging under it — until another field took focus,
    /// because AppKit only moves focus between controls that accept it, and
    /// most of this panel (rows, labels, the background) does not. A click
    /// anywhere else in the window now ends the editing. The value is not
    /// lost: the fields bind on every keystroke, and the click still goes
    /// through to whatever it landed on, a Save button included.
    ///
    /// Decided after the click, from where focus actually went, not from what
    /// the click hit: a SwiftUI text field sits inside wrapper views, and
    /// judging by the hit view read a click into another field as a click
    /// away — the new field took focus and was dropped a moment later.
    private func watchForClicksAway(in window: NSWindow) {
        guard clickAwayMonitor == nil else { return }
        clickAwayMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak window] event in
            guard let window, event.window === window,
                  let edited = Self.editedField(in: window)
            else { return event }
            let fieldFrame = edited.convert(edited.bounds, to: nil)
            guard !Self.isInside(event.locationInWindow, fieldFrame: fieldFrame) else { return event }
            // After the click is delivered, so a button it landed on still sees
            // the edited value, and a field it landed on has taken focus.
            DispatchQueue.main.async { [weak window, weak edited] in
                guard let window, let edited,
                      Self.editedField(in: window) === edited
                else { return }   // focus already moved on, to another field or nowhere
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    /// The text field being typed in: AppKit edits it through the window's
    /// shared field editor, whose delegate is the field.
    private static func editedField(in window: NSWindow) -> NSTextField? {
        guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return nil }
        return editor.delegate as? NSTextField
    }

    /// Whether a click belongs to the field being edited, allowing a few points
    /// round it for the focus ring and the bezel the eye counts as the field.
    static func isInside(_ point: NSPoint, fieldFrame: NSRect) -> Bool {
        fieldFrame.insetBy(dx: -4, dy: -4).contains(point)
    }

    /// Sit the traffic lights in the middle of the panel's header band.
    ///
    /// Their default place is a title bar's worth from the top, which on a
    /// `fullSizeContentView` window leaves them crowded into the corner of
    /// the sidebar card rather than centred in the row the card's toggle and
    /// the pane's title share. AppKit puts them back on some window events,
    /// so this runs again whenever the window comes forward rather than only
    /// at creation.
    private func layoutTrafficLights(in window: NSWindow) {
        let buttons = [NSWindow.ButtonType.closeButton,
                       .miniaturizeButton,
                       .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let container = buttons.first?.superview else { return }

        for (index, button) in buttons.enumerated() {
            var frame = button.frame
            frame.origin.x = Self.firstLightCentreX
                + CGFloat(index) * Self.lightSpacing - frame.width / 2
            // Flipped: AppKit measures a window's content from the bottom.
            frame.origin.y = container.bounds.height
                - SettingsView.headerHeight / 2 - frame.height / 2
            button.frame = frame
        }
    }

    /// Centre of the close button, in from the window's left edge, and the
    /// centre-to-centre step to the next one — both measured off the design
    /// this panel is matching.
    private static let firstLightCentreX: CGFloat = 26
    private static let lightSpacing: CGFloat = 22.5

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        layoutTrafficLights(in: window)
    }

    func show() {
        if let window {
            // Re-centered every time, not only at creation: a window is
            // positioned once and then just re-surfaced from here on, so if
            // it ever ended up off any connected screen — a display that was
            // reconfigured or disconnected since — every later click would
            // silently bring forward a window that isn't anywhere visible.
            if !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
                Self.centerOnActiveScreen(window)
            }
            surface(window)
            return
        }

        let window = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0,
                                width: SettingsView.width, height: SettingsView.height),
            // `fullSizeContentView` runs the content flush up under the traffic
            // lights, with no separate title strip above it, and
            // `nonactivatingPanel` is what keeps the app's own menus out of
            // the screen's menu bar while these are open.
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // A floating panel sits above the other applications' windows, which
        // is where a window you opened from the menu bar belongs.
        window.isFloatingPanel = true
        window.level = .floating
        // Kept for Mission Control and for anything that asks the window what
        // it is; the bar itself says the same thing.
        window.title = L10n.t("Leftover Settings")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // A floating rounded panel rather than a square window. The rounded
        // shape is drawn by the content (see `SettingsView.body`), so the
        // window has to stop painting its own square one behind it — hence
        // the clear background, which also lets the corners cut through
        // instead of showing black wedges outside the curve.
        window.isOpaque = false
        window.backgroundColor = .clear
        // The panel follows the Mac's Appearance rather than insisting on the
        // dark look the notch uses: AppKit's own controls inside it — pickers,
        // switches, menus — follow the window, and the window follows the
        // system.
        window.hasShadow = true
        window.delegate = self
        watchForClicksAway(in: window)
        // The window itself answers first, not the first text field in it.
        window.initialFirstResponder = nil
        window.contentView = NSHostingView(
            rootView: SettingsView(preferences: preferences,
                                   providers: providers,
                                   signOut: signOut,
                                   signIn: signIn,
                                   switchAccount: switchAccount,
                                   retry: retry,
                                   usageStore: usageStore,
                                   sendTestNotification: sendTestNotification)
        )
        Self.centerOnActiveScreen(window)
        window.isReleasedWhenClosed = false
        self.window = window
        layoutTrafficLights(in: window)
        surface(window)
    }
}
