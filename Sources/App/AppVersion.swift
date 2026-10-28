import Foundation

enum AppVersion {
    /// The marketing version, as shown in Settings and keyed by What's New.
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
