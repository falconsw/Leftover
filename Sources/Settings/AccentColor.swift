import AppKit
import SwiftUI

/// The user-selected colour for positive usage and active work indicators.
///
/// Raw values are persistence keys, not display copy. Keeping them stable lets
/// labels and ordering change without losing an existing choice.
enum AccentColorChoice: String, CaseIterable, Identifiable {
    case system
    case pink = "ff33e1"
    case red = "eb4236"
    case orange = "eb8436"
    case yellow = "ffd400"
    case green = "00ff88"
    case teal = "00e5cc"
    case blue = "36a8eb"
    case indigo = "6c5ce7"
    case purple = "b026ff"
    case offWhite = "f7f6f5"
    /// The green of the app's own mark, so the interface and the icon are
    /// the same colour.
    case logo = "5eebb8"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .system:   return Color(nsColor: .controlAccentColor)
        case .pink:     return Color(hex: 0xFF33E1)
        case .red:      return Color(hex: 0xEB4236)
        case .orange:   return Color(hex: 0xEB8436)
        case .yellow:   return Color(hex: 0xFFD400)
        case .green:    return Palette.ample
        case .teal:     return Color(hex: 0x00E5CC)
        case .blue:     return Color(hex: 0x36A8EB)
        case .indigo:   return Color(hex: 0x6C5CE7)
        case .purple:   return Color(hex: 0xB026FF)
        case .offWhite: return Color(hex: 0xF7F6F5)
        case .logo:     return Palette.ample
        }
    }
}

private struct LeftoverAccentColorKey: EnvironmentKey {
    static let defaultValue = Palette.ample
}

extension EnvironmentValues {
    var leftoverAccentColor: Color {
        get { self[LeftoverAccentColorKey.self] }
        set { self[LeftoverAccentColorKey.self] = newValue }
    }
}
