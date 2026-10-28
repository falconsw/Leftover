import SwiftUI

/// A small stand-in for the menu bar panel, so the transparency slider shows
/// its effect without opening the real panel.
///
/// It has no backdrop of its own: it reports its frame through
/// `SettingsClearRegionKey` and the settings page leaves that region
/// unpainted, so whatever is behind the window shows through — the same thing
/// the real panel floats over. The wallpaper cannot stand in for that:
/// `desktopImageURL` reports a stale picture for dynamic and system wallpapers.
struct PanelTransparencyPreview: View {
    let transparency: Double

    static let cornerRadius: CGFloat = 10

    private static let samples: [(name: String, used: Double)] = [
        ("Claude", 0.24), ("Codex", 0.58), ("Cursor", 0.86),
    ]

    var body: some View {
        panel
            .frame(height: 132)
            .frame(maxWidth: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(SettingsPalette.hairline, lineWidth: 1)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: SettingsClearRegionKey.self,
                                           value: proxy.frame(in: .named(SettingsClearRegionKey.space)))
                }
            }
            .accessibilityHidden(true)
    }

    private var panel: some View {
        HStack(spacing: 10) {
            ForEach(Self.samples, id: \.name) { sample in
                VStack(spacing: 4) {
                    ZStack {
                        Circle().stroke(.quaternary, lineWidth: 3.5)
                        Circle()
                            .trim(from: 0, to: sample.used)
                            .stroke(UsageBand.band(for: sample.used).color(),
                                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(verbatim: "\(Int((sample.used * 100).rounded()))")
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    }
                    .frame(width: 38, height: 38)
                    Text(verbatim: sample.name)
                        .font(.system(size: 9.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.menuCardSurface.opacity(1 - transparency))
        }
    }
}

/// The region of the settings page left unpainted, in `space` coordinates.
struct SettingsClearRegionKey: PreferenceKey {
    static let space = "settingsRoot"
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

/// The scroll view's visible frame, so the unpainted region stops where the
/// page is clipped instead of showing through the header.
struct SettingsViewportKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
