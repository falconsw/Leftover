import AppKit

/// Every measurement is quoted in design-frame pixels so it can be checked
/// against `docs/design/frame-124-hover-tooltip.png` directly.
enum NotchLayout {


    // A provider cell
    static let ringDiameter  = Design.px(117)   // 44pt, the design spec's anchor










    static let trackStroke   = Design.px(15.5)
    static let progressStroke = Design.px(8)
    /// A fraction of the circle, not a pixel length. Below it the arc's two
    /// round caps (each `progressStroke / 2`) overlap and the context reading
    /// collapses into a dot that looks like a status light. At 0.06 the arc
    /// path (radius `(ringDiameter - progressStroke) / 2`) draws roughly 20px
    /// of body plus caps — clearly an arc. It only floors a known reading;
    /// `nil` still draws the full ring.
    static let localArcMinimumSweep: CGFloat = 0.06

    // The activity indicator. Not in the design frame — sized to sit in the gap
    // between the glyph (46px across) and the inside edge of the track (86px),
    // so it never crowds either.
    static let activityDiameter = Design.px(72)
    static let activityStroke   = Design.px(5.5)

    // The weekly ring. Not in the design frame — the frame draws one ring per
    // provider — so these are placed against what is already there rather than
    // quoted from it, and the tests state the clearances rather than the
    // numbers.
    //
    // Thinner than the headline arc on purpose: same kind of fact, lesser
    // claim on the eye. Two arcs of equal weight in a 44pt circle read as one
    // confused reading rather than as two limits.
    static let weeklyRingStroke = Design.px(5)
    /// Inside: centred in the gap between the glyph and the working
    /// indicator's own arc, which is the only clear band left in there.
    static let weeklyInsideRadius = Design.px(28)
    /// Outside: past the track, into the margin the notch keeps between a ring
    /// and its bezel. Far enough out not to crowd the track, far enough in that
    /// the bezel is never touched.
    static let weeklyOutsideRadius = Design.px(65)

    // The hover tooltip
    static let cardWidth     = Design.px(600)
    static let cardPadding   = Design.px(32)
    /// Whole points, unlike the distances around it. A usage bar is a solid
    /// edge-to-edge fill, so the compositor snaps its top and its bottom to the
    /// pixel grid separately: at the frame's 3.95pt, a bar that happened to sit
    /// half a pixel lower came out a whole pixel thinner than the one beside
    /// it. Four points is four pixels at 1x and eight at 2x wherever it lands.
    static let barHeight     = Design.px(10.5).rounded()
    static let headerGap     = Design.px(17)    // glyph -> title
    static let headerToBlock = Design.px(21)
    static let labelToBar    = Design.px(16.8)
    static let barToUsed     = Design.px(17.8)
    static let blockSpacing  = Design.px(20)
    /// Whole points for the reason `barHeight` is.
    static let moneyBarHeight = Design.px(12).rounded()
    static let moneyBarToStats = Design.px(14)
    static let moneyStatGap = Design.px(4)
    static let usageDetailIdentityGap = Design.px(4)
    static let usageDetailLabelToBar = Design.px(12)
    static let usageDetailChartHeight = Design.px(96)
    static let usageDetailChartGap = Design.px(18)
    static let usageDetailBarGap = Design.px(5)
    static let sessionRowGap = Design.px(10)   // the two lines of one session
    /// The spinner beside a session's status. Sized against the body text's cap
    /// (18px) rather than picked by eye, so it reads as part of the word rather
    /// than a bullet pinned near it.
    static let statusDot       = Design.px(17)
    static let statusDotStroke = Design.px(3.4)
    static let statusDotGap    = Design.px(11)
    static let hairline      = Design.px(2.5)  // rule above the session list

    // Codex account activity
    static let codexUsageTop   = Design.px(20)
    static let codexMetricTop  = Design.px(14)
    static let codexMetricRowGap = Design.px(8)
    static let codexMetricRowHeight = Design.px(40)
    static let codexMetricHeight = 5 * codexMetricRowHeight + 4 * codexMetricRowGap
    static let codexMetricBottom = Design.px(14)
    static let codexUsageRowGap = Design.px(12)
    static let codexChartTop   = Design.px(15)
    static let codexChartHeight = Design.px(115)
    /// Title, count, and expiry. The third line is reserved so a missing
    /// expiry cannot shrink the hover region under the card.
    static var codexResetCreditsHeight: CGFloat {
        blockSpacing + 3 * cardBodyLineHeight + 2 * codexUsageRowGap
    }

    /// The card's body face. Held rather than rebuilt at each use: the line
    /// height below and the wrap measurement in `bodyTextHeight` have to be
    /// measuring the same font, or the budget and the text disagree.
    static let cardBodyFont = NSFont.systemFont(
        ofSize: Design.fontSize(capPixels: 18), weight: .regular
    )
    static let cardBodyLineHeight: CGFloat = lineHeight(cardBodyFont)

    /// How wide a line of body text is inside the card.
    static var cardTextWidth: CGFloat { cardWidth - 2 * cardPadding }

    /// How tall a run of body text is once it has wrapped to that column.
    ///
    /// Measured, because a status message is the one piece of card text whose
    /// length is not known here. The budget assumed a single line, and the
    /// longest of them — "Leftover was refused access to …'s saved login.
    /// Click this ring to ask again, and choose Always Allow." — takes three:
    /// 33pt against 12pt reserved. The card came up 21pt short and clipped the
    /// two lines that said what to do about it, on the one ring a user looks at
    /// precisely because something is wrong.
    ///
    /// Rounded up to whole lines: the card's height is a stack of line boxes,
    /// and half a line of budget leaves the last one straddling the clip.
    ///
    /// `width` is the column the text actually wraps to. The notch's card is
    /// the default and the only one the panel geometry is solved against; the
    /// Detail panel passes its own, so a name that fits one line there is not
    /// given two lines of room.
    static func bodyTextHeight(_ text: String, width: CGFloat = cardTextWidth) -> CGFloat {
        guard !text.isEmpty else { return cardBodyLineHeight }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: cardBodyFont]
        )
        let lines = max(1, Int((bounds.height / cardBodyLineHeight).rounded(.up)))
        return CGFloat(lines) * cardBodyLineHeight
    }

    /// Whether a label and the value opposite it both fit on one row of
    /// `width`, with the gap `SplitRow` keeps between them and a little room
    /// to spare.
    ///
    /// Measured in the card's own body face, because this decides whether a
    /// row may carry a longer string at all — a row that cannot is given the
    /// short one rather than left to truncate.
    ///
    /// The slack is not padding for its own sake. `NSString`'s metrics come in
    /// a point or two under what SwiftUI's `Text` asks for the same string in
    /// the same face, so a row measured to fit exactly was still truncated on
    /// screen — and a row that fits to the last point reads as crowded even
    /// when it does not truncate. Both are answered by refusing the last few
    /// points.
    static func splitRowFits(leading: String, trailing: String, width: CGFloat) -> Bool {
        let attributes: [NSAttributedString.Key: Any] = [.font: cardBodyFont]
        let leadingWidth = (leading as NSString).size(withAttributes: attributes).width
        let trailingWidth = (trailing as NSString).size(withAttributes: attributes).width
        return leadingWidth + splitRowGap + trailingWidth + splitRowSlack <= width
    }

    /// The least `SplitRow` leaves between a label and its value.
    static let splitRowGap = Design.px(20)
    /// What `splitRowFits` keeps back — see its note.
    static let splitRowSlack = Design.px(24)

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    static func modelNameHeight(_ name: String, width: CGFloat = cardTextWidth) -> CGFloat {
        min(2 * cardBodyLineHeight, bodyTextHeight(name, width: width))
    }


    /// What to assume before the panel knows which screen it is on. The figure
    /// that shipped, so nothing about the default placement moves.
    static let defaultSessionCap = 4

}
