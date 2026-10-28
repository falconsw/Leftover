import SwiftUI

/// The motion vocabulary, in one place so the whole surface moves like one thing.
///
/// Springs rather than eased curves throughout: macOS motion reads as physical
/// because things overshoot slightly and settle, and a panel that scales without
/// any of that feels like a slideshow. The numbers are chosen to be *just* under
/// bouncy — `dampingFraction` in the high 0.7s gives a single soft settle rather
/// than a wobble.
enum NotchMotion {

    /// A percentage changing under you. Slower on purpose: a ring that snaps to a
    /// new value reads as a glitch, one that sweeps reads as a measurement.
    static let reading = Animation.spring(response: 0.9, dampingFraction: 0.9)

}
