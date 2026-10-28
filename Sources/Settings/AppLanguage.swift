import Foundation

/// Which language Leftover's own copy uses.
///
/// Follow System is the default. A forced choice exists because the Mac's
/// language is not always the one the person wants this app in — bilingual
/// machines, or a Mac in a language we do not ship.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    /// The languages Leftover ships, and the only ones in the string catalog.
    static let shipped = ["en", "tr"]

    /// `nil` means follow the Mac.
    ///
    /// Plain `en`, not `en_US`: these identifiers are looked up against the
    /// string catalog, whose English is filed under `en`. A region-qualified
    /// identifier misses it and falls through to whatever localization the
    /// bundle offers next — which made choosing English serve Chinese.
    var locale: Locale? {
        switch self {
        case .system:  return nil
        case .turkish: return Locale(identifier: "tr")
        case .english: return Locale(identifier: "en")
        }
    }

    /// Following the Mac means Turkish on a Mac that prefers it and English
    /// on every other one, never a third language half-translated.
    static var systemLocale: Locale {
        let match = Bundle.preferredLocalizations(from: shipped,
                                                  forPreferences: Locale.preferredLanguages).first
        return Locale(identifier: match ?? "en")
    }

    /// Türkçe and English stay in their own language so the row is
    /// recognizable when the rest of Settings is in the other one.
    var title: String {
        switch self {
        case .system:  return L10n.t("Follow System")
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    var explanation: String {
        switch self {
        case .system:
            return L10n.t("Turkish if the Mac uses Turkish, otherwise English.")
        case .turkish, .english:
            return L10n.t("Leftover uses this language even if the Mac does not.")
        }
    }
}
