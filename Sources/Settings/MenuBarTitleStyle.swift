import Foundation

/// What the menu bar item prints beside the logo.
enum MenuBarTitleStyle: String, CaseIterable, Identifiable {
    case logoOnly
    case percent
    case namePercent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logoOnly:    return L10n.t("Logo only")
        case .percent:     return L10n.t("Logo and percentage")
        case .namePercent: return L10n.t("Logo, name and percentage")
        }
    }
}
