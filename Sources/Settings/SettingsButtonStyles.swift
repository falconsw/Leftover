import SwiftUI

/// Buttons in Settings, drawn to match the panel rather than as stock macOS
/// push buttons, and every one of them answering the pointer: brighter on
/// hover, a touch smaller and darker while pressed, dimmed when it can't be
/// used. Set once over each pane (see `SettingsView.pane(for:)`), so a button
/// added later gets it without anyone having to remember to.
struct SettingsButtonStyle: ButtonStyle {
    enum Kind {
        /// A soft dark pill.
        case standard
        /// White with dark text: the one action a pane leads with.
        case prominent
    }

    var kind: Kind = .standard
    /// Smaller type and padding, for a button beside small text.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        SettingsButtonBody(configuration: configuration, kind: kind, compact: compact)
    }
}

private struct SettingsButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: SettingsButtonStyle.Kind
    let compact: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private static let destructiveRed = Color(red: 1, green: 0.42, blue: 0.4)

    /// The button's own ground, in the appearance the page is in.
    ///
    /// `Color.primary` is the label colour, which is white in a dark window
    /// and black in a light one — so a pill drawn out of it reads as a
    /// highlight in either, and the panel does not have to know which one it
    /// is looking at.
    private var fill: Color {
        let pressed = configuration.isPressed
        switch kind {
        case .standard:
            return Color.primary.opacity(pressed ? 0.18 : isHovered ? 0.12 : 0.07)
        case .prominent:
            return Color.primary.opacity(pressed ? 0.78 : isHovered ? 1 : 0.92)
        }
    }

    private var foreground: Color {
        if configuration.role == .destructive { return Self.destructiveRed }
        switch kind {
        case .standard:  return .primary
        case .prominent: return Color(nsColor: .windowBackgroundColor)
        }
    }

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: compact ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 3 : 5)
            .background(Capsule().fill(fill))
            .overlay {
                if kind == .standard {
                    Capsule().strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.10), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering && isEnabled }
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A bare symbol that gains a soft circle under the pointer: the play,
/// bell and remove buttons that sit inside a row.
struct SettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsIconButtonBody(configuration: configuration)
    }
}

private struct SettingsIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive
                             ? Color(red: 1, green: 0.42, blue: 0.4)
                             : Color.primary.opacity(isHovered ? 0.95 : 0.6))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.09 : 0)))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering && isEnabled }
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Text that reads as a link: the accent colour, underlined while the
/// pointer is on it.
struct SettingsLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsLinkButtonBody(configuration: configuration)
    }
}

private struct SettingsLinkButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.tint)
            .underline(isHovered)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
