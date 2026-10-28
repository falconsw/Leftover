import AppKit
import SwiftUI

/// Which look the app wears: the Mac's own, or one this app insists on.
///
/// The notch is a separate matter. It is painted by the notch surface style —
/// the Mac's glass or a solid dark panel — and it keeps its own look whatever
/// the app's windows are doing.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.t("Automatic")
        case .light:  return L10n.t("Light")
        case .dark:   return L10n.t("Dark")
        }
    }

    /// The appearance the app's windows take, or nil to follow the Mac.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}
