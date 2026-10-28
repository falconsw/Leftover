import SwiftUI

/// How a provider's ring shows that one of its agents is working right now.
///
/// Raw values are persistence keys, not display copy. The default is `.arc` for the same reason
/// `ColorTransitionStyle` defaults to `.hardStep`: a visual change to every existing user's notch
/// must be something they opt into, not something that reaches them unannounced the next time the
/// app updates.
///
/// One switch covers the disc's brand colour, its faster breath while requests are queued and its
/// staying bright over a stale reading. Those are what make the disc readable at a glance; offered
/// as separate settings they would only produce combinations nobody asked for.
enum BusyIndicatorStyle: String, CaseIterable, Identifiable {
    /// The original behaviour: a thin white quarter-arc turning inside the ring, which becomes a
    /// ring of dots while requests are queued.
    case arc
    /// `BusyWave` — a disc in the provider's brand colour breathing under its glyph, faster while
    /// requests are queued, and not dimmed with a stale reading.
    case breath

    var id: String { rawValue }

}

private struct BusyIndicatorStyleKey: EnvironmentKey {
    static let defaultValue = BusyIndicatorStyle.arc
}

extension EnvironmentValues {
    var busyIndicatorStyle: BusyIndicatorStyle {
        get { self[BusyIndicatorStyleKey.self] }
        set { self[BusyIndicatorStyleKey.self] = newValue }
    }
}
