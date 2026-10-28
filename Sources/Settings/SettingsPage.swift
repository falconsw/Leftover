import AppKit
import SwiftUI

/// The settings page's own colours, following the Mac's Appearance.
///
/// The settings window is a window of its own, not the notch, so it has no
/// business insisting on the dark look the notch uses. A person whose Mac is
/// in Light mode finds the settings in Light mode too — which is why none of
/// these are fixed greys.
enum SettingsPalette {
    /// The window's own ground, the colour the rounded panel is cut from.
    static let window = Color(dark: NSColor(hex: 0x131316), light: NSColor(hex: 0xF5F5F7))
    /// A card on that ground: one account's own surface.
    static let card = Color(dark: NSColor(hex: 0x1B1B1F), light: NSColor.white)
    /// The line between one group of settings and the next.
    static let hairline = Color(dark: NSColor.white.withAlphaComponent(0.10),
                                light: NSColor.black.withAlphaComponent(0.10))
    /// The line around a card under the pointer.
    static let hairlineStrong = Color(dark: NSColor.white.withAlphaComponent(0.20),
                                      light: NSColor.black.withAlphaComponent(0.18))
    /// The line around the whole panel.
    static let edge = Color(dark: NSColor.white.withAlphaComponent(0.14),
                            light: NSColor.black.withAlphaComponent(0.16))
}

/// A block on the settings page: a heading, and what belongs under it.
///
/// Nothing here is boxed. The page is one column of type on the window's own
/// ground, and the only things that divide it are the space between the
/// blocks and a hairline between the groups inside one.
struct SettingsBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 12)

            content
        }
    }
}

/// The name of a group of settings inside a block.
struct SettingsGroupLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
    }
}

/// A hairline between two groups of settings.
struct SettingsHairline: View {
    var body: some View {
        Rectangle()
            .fill(SettingsPalette.hairline)
            .frame(height: 1)
            .padding(.vertical, 14)
    }
}

/// One setting: its name and what it does on the left, the control on the
/// right.
///
/// The explanation sits under the name rather than under the control, so a
/// row reads as one thing — a sentence and the thing that changes it — and
/// the control column stays a straight line down the page.
struct SettingsItem<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 430, alignment: .leading)

            Spacer(minLength: 8)

            content
        }
        .padding(.vertical, 7)
    }
}

/// A paragraph under a group — the app's own words about what the group
/// does, rather than about one control.
struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }
}

/// A group of settings in a card, the way System Settings draws them: the
/// group's name above it, its rows inside.
///
/// The Notifications and System tabs are drawn this way, as a copy of the
/// Mac's own settings; Accounts keeps the page's flatter look, where the
/// accounts are cards of their own.
struct SettingsGroupCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            VStack(spacing: 0) {
                content
            }
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsPalette.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SettingsPalette.hairline, lineWidth: 1)
            }
        }
    }
}

/// One row inside such a card: the setting's name on the left, the control
/// on the right.
struct SettingsCardRow<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

/// The line between two rows of a card.
struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsPalette.hairline)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}
