import AppKit
import SwiftUI

/// The dark values are sampled from `docs/design/frame-124-hover-tooltip.png`,
/// not invented, and they differ slightly from the hexes written in the design
/// spec — the frame is the source of truth, so the sampled values win.
///
/// The light values are not sampled from anything, because there is no light
/// frame: they exist only because the glass surface (`NotchSurfaceStyle.glass`)
/// hands light and dark to the Mac's Appearance settings, and white ink on
/// light glass is unreadable. They were picked for at least 3:1 against white.
/// `solid` pins the panel to `darkAqua`, so it keeps the frame's hexes exactly.
///
/// The two tracks are the system's quaternary label colour: translucent, so
/// they darken or lighten whatever is behind them, and the same grey macOS
/// uses for an unfilled gauge.
///
/// `notch` and `card` stay pure black: they paint the resting pill, which has
/// to read as the bezel, and the whole surface in the solid style.
enum Palette {
    static let ringTrack     = Color(nsColor: .quaternaryLabelColor)
    static let barTrack      = Color(nsColor: .quaternaryLabelColor)

    /// Named so `UsageBand.rampColor` can interpolate between them per-appearance rather
    /// than blending two already-resolved `Color`s (which would mix in whichever appearance
    /// happened to be current when the `Color` was built, not the one it draws in).
    ///
    /// Ample is the app icon's green, darkened in Light mode to stay legible on white.
    /// Watch and critical are macOS's own `systemYellow` and `systemRed`, so the ramp's
    /// ends match the solid band colours below.
    static let amplePair: (dark: UInt32, light: UInt32) = (0x5EEBB8, 0x15A67A)
    static let watchPair: (dark: UInt32, light: UInt32) = (0xFFD60A, 0xFFCC00)
    static let criticalPair: (dark: UInt32, light: UInt32) = (0xFF453A, 0xFF3B30)

    static let ample         = Color(dark: NSColor(hex: amplePair.dark), light: NSColor(hex: amplePair.light))
    static let watch         = Color(nsColor: .systemYellow)
    static let critical      = Color(nsColor: .systemRed)

    /// A continuous point between two palette anchors, each resolved for the current
    /// appearance first and interpolated in sRGB channels second — resolving after
    /// interpolating would blend whichever appearance was current when the ramp was
    /// evaluated into every later draw, not the appearance it is actually drawn in.
    static func ramp(from: (dark: UInt32, light: UInt32), to: (dark: UInt32, light: UInt32), fraction: Double) -> Color {
        let t = min(max(fraction, 0), 1)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? from.dark : from.light)
                .blendedByChannel(with: NSColor(hex: isDark ? to.dark : to.light), fraction: t)
        })
    }

    // Generation-speed bands are independent of cloud quota usage.
    static let generationFast = Color(nsColor: .systemBlue)
    static let generationSlow = Color(nsColor: .systemRed)

    static let textPrimary   = Color(dark: .white, light: .black)
    static let textSecondary = Color(dark: NSColor(hex: 0x808080), light: NSColor(hex: 0x6B6B6B))

    /// The surface of a card in the menu bar's menu: a wash over the menu's own
    /// glass rather than a slab on top of it, so the blur behind the menu still
    /// reads through.
    ///
    /// The menu's glass takes its tint from what is behind it, not from the
    /// Mac's appearance, so a Light menu can sit over a dark wallpaper and come
    /// out dark. The wash is opaque enough that the ink chosen for the
    /// appearance keeps its contrast whichever way the glass went: black on the
    /// light wash, white on the dark one, with the secondary ink above 3:1 even
    /// over glass tinted the other way.
    static let menuCardSurface = Color(dark: NSColor(white: 0.08, alpha: 0.72),
                                       light: NSColor(white: 1.0, alpha: 0.80))
    /// Secondary ink on a menu card. `textSecondary`'s #808080 is the notch's
    /// frame-accurate grey on pure black; on the menu's lighter, translucent
    /// card it fell under 3:1, so the card takes a lighter grey in dark and a
    /// slightly darker one in light.
    static let menuTextSecondary = Color(dark: NSColor(hex: 0xA8A8A8), light: NSColor(hex: 0x5E5E5E))
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Resolved against whatever appearance is current when the colour is
    /// drawn, which for the notch is the panel's: `nil` for glass (so the Mac
    /// decides) and `darkAqua` for solid.
    init(dark: NSColor, light: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green:   CGFloat((hex >> 8) & 0xFF) / 255,
            blue:    CGFloat(hex & 0xFF) / 255,
            alpha:   1
        )
    }

    /// A linear per-channel sRGB lerp — the same arithmetic the Windows ramp does in JS, kept
    /// deliberately simple rather than going through `blended(withFraction:of:)`, whose
    /// blending colour space is not something either side of a Mac/Windows parity claim
    /// should depend on.
    func blendedByChannel(with other: NSColor, fraction: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        func lerp(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * fraction }
        return NSColor(
            srgbRed: lerp(a.redComponent, b.redComponent),
            green:   lerp(a.greenComponent, b.greenComponent),
            blue:    lerp(a.blueComponent, b.blueComponent),
            alpha:   1
        )
    }
}

private struct LeftoverReduceTransparencyKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// True when macOS Accessibility "Reduce Transparency" is enabled in system settings,
    /// or explicitly overridden via `.environment(\.leftoverReduceTransparency, ...)`.
    var leftoverReduceTransparency: Bool {
        get { self[LeftoverReduceTransparencyKey.self] || self.accessibilityReduceTransparency }
        set { self[LeftoverReduceTransparencyKey.self] = newValue }
    }
}

private struct TooltipSecondaryInkKey: EnvironmentKey {
    static let defaultValue = Palette.textSecondary
}

extension EnvironmentValues {
    /// Secondary ink resolved for the current tooltip surface. This stays
    /// frame-accurate unless ordinary dark Liquid Glass needs extra contrast.
    var tooltipSecondaryInk: Color {
        get { self[TooltipSecondaryInkKey.self] }
        set { self[TooltipSecondaryInkKey.self] = newValue }
    }
}

extension EnvironmentValues {
}
