import AppKit
import XCTest
@testable import Leftover

/// The layout is a scaled copy of `docs/design/frame-124-hover-tooltip.png`.
/// These pin the ratios the frame fixes, so a change to `Design.scale` resizes
/// everything without silently reshaping it.
final class NotchLayoutTests: XCTestCase {
    func testRingIsTheSpecAnchor() {
        XCTAssertEqual(NotchLayout.ringDiameter, 44, accuracy: 0.001)
    }









    /// Thinner than the headline arc: same kind of fact, lesser claim on the eye.
    func testTheWeeklyRingIsThinnerThanTheHeadline() {
        XCTAssertLessThan(NotchLayout.weeklyRingStroke, NotchLayout.progressStroke)
    }

    /// A tiny real fraction still has to draw as an arc, not collapse into a
    /// dot that reads as a status light. `nil` (no reading) keeps the full ring.
    func testASmallContextStillReadsAsAnArc() {
        XCTAssertEqual(ProviderRing.localSweep(for: 0.01), NotchLayout.localArcMinimumSweep, accuracy: 0.0001)
        XCTAssertEqual(ProviderRing.localSweep(for: 0), NotchLayout.localArcMinimumSweep, accuracy: 0.0001)
        XCTAssertEqual(ProviderRing.localSweep(for: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ProviderRing.localSweep(for: 1.7), 1, accuracy: 0.0001)
        XCTAssertEqual(ProviderRing.localSweep(for: nil), 1, accuracy: 0.0001, "no reading still draws the whole ring")
    }

    /// The floor has to actually clear the two round caps drawn at the ends of
    /// the arc, or the "minimum arc" is still just a dot; and it has to stay
    /// small enough that it never reads as a genuine reading.
    func testTheMinimumArcIsLongerThanItsCaps() {
        let arcBody = NotchLayout.localArcMinimumSweep * .pi
            * (NotchLayout.ringDiameter - NotchLayout.progressStroke)
        XCTAssertGreaterThan(arcBody, 2 * NotchLayout.progressStroke)
        XCTAssertLessThan(NotchLayout.localArcMinimumSweep, 0.1)
    }


    /// A solid bar has its top and bottom snapped to the pixel grid one by
    /// one, so a fractional height drew two bars of one height a pixel apart
    /// depending on where each sat. Whole points snap the same everywhere.
    func testBarsAreWholePointsSoEveryOneDrawsTheSameThickness() {
        for height in [NotchLayout.barHeight, NotchLayout.moneyBarHeight] {
            XCTAssertEqual(height, height.rounded(), "\(height)pt lands on a different number of pixels by position")
        }
    }
}

/// The panel has to be sized for the provider list that caused the change, not
/// the one the model still holds.
///
/// `@Published` notifies subscribers in `willSet`, so a sink that reacts to
/// `snapshots` changing and then reads `model.snapshots` back sees the *previous*
/// array. That is how the panel ended up sized for zero cells while one was on
/// screen — and a panel too short for its shape clips the bottom flare, which is
/// visible as the notch looking cut off instead of curving into the bezel.
@MainActor
final class PanelSizingTests: XCTestCase {


}

/// The notch folds away to a pill so it stops being in the way, and unfolds on
/// contact. These pin the geometry that makes that bearable to live with.
@MainActor
final class FoldedNotchTests: XCTestCase {




}

/// Motion is a vocabulary, not a pile of magic numbers.
final class NotchMotionTests: XCTestCase {


    /// The stagger is capped, so a long provider list never feels sluggish.
}

/// The shape has to stay a notch at every size it is drawn at — including the
/// pill, which is narrower than the flare radius it was designed around.
final class SideNotchShapeTests: XCTestCase {



}

/// The tooltip resizes when you move between providers, because they do not all
/// report the same number of windows. Its height is computed rather than left to
/// SwiftUI so the hover region matches — and these pin that it really does vary.
final class TooltipResizeTests: XCTestCase {


}

/// The tooltip is one object: a card with a tail welded to its side. What breaks
/// that illusion is the two halves moving on different schedules.
@MainActor
final class TooltipCohesionTests: XCTestCase {
    private func snapshot(windows: Int) -> ProviderSnapshot {
        ProviderSnapshot(
            id: "p", displayName: "P", glyph: .claude, fidelity: .official, status: .ok,
            windows: (0..<windows).map {
                LimitWindow(id: "w\($0)", label: "W", usedFraction: 0.5, resetsAt: Date())
            }
        )
    }



}

/// The rings are buttons — clicking one refetches that provider — so the cursor
/// should say so, and only there.
@MainActor
final class PointerStateTests: XCTestCase {


}

/// The settings orb sits in the corner the notch's bottom flare makes, and its
/// resting arc follows that curve rather than merely sitting near it.
@MainActor
final class SettingsOrbTests: XCTestCase {








}

/// Hiding a provider is stored as the hidden set, so one added in a later
/// version shows up by default rather than silently staying dark.
@MainActor
final class PreferencesTests: XCTestCase {
    private func preferences() -> Preferences {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults)
    }

    /// The defaults themselves, for the cases that need two `Preferences` over
    /// the same store to stand in for a relaunch.
    private func scratchDefaults() -> UserDefaults {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testTheFirstLaunchIsAnnouncedExactlyOnce() {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        XCTAssertTrue(Preferences(defaults: defaults).isFirstLaunch)
        XCTAssertFalse(Preferences(defaults: defaults).isFirstLaunch,
                       "a returning user would be introduced to the app again")
    }

    func testEverythingIsConnectedByDefault() {
        let p = preferences()
        XCTAssertTrue(p.isConnected("claude"))
        XCTAssertTrue(p.isConnected("codex"))
        XCTAssertFalse(p.isConnected("a-provider-that-does-not-exist-yet"))
    }

    func testConnectingAndDisconnectingRoundTrips() {
        let p = preferences()
        p.setConnected(false, for: "cursor")
        XCTAssertFalse(p.isConnected("cursor"))
        XCTAssertTrue(p.isConnected("claude"))
        p.setConnected(true, for: "cursor")
        XCTAssertTrue(p.isConnected("cursor"))
    }

    func testChoicesSurviveARestart() {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        Preferences(defaults: defaults).setConnected(false, for: "codex")
        XCTAssertFalse(Preferences(defaults: defaults).isConnected("codex"))
    }








    /// The key is deliberately unchanged across the rename, so choices made
    /// before it survive.
    func testItReadsChoicesStoredUnderTheOldName() {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(["cursor"], forKey: "hiddenProviders")

        XCTAssertFalse(Preferences(defaults: defaults).isConnected("cursor"))
    }

    // MARK: - Order

    func testNoStoredOrderMeansNeverChosen() {
        XCTAssertTrue(Preferences(defaults: scratchDefaults()).providerOrder.isEmpty)
    }

    func testTheOrderSurvivesARelaunch() {
        let defaults = scratchDefaults()

        Preferences(defaults: defaults).setProviderOrder(["codex", "claude", "cursor"])

        XCTAssertEqual(Preferences(defaults: defaults).providerOrder,
                       ["codex", "claude", "cursor"])
    }

    func testAnAbsentProfileKeepsItsPlaceAcrossAMove() {
        let preferences = Preferences(defaults: scratchDefaults())
        preferences.setProviderOrder(["claude", "claude-work", "cursor"])

        // Settings can only show what was discovered at launch, and
        // `~/.claude-work` is not on this Mac today.
        preferences.setProviderOrder(["cursor", "claude"])

        XCTAssertEqual(preferences.providerOrder, ["cursor", "claude", "claude-work"])
    }

    /// No ceiling is the honest default: an API key is billed per token and
    /// publishes no limit, so the ring stays unfilled until the user names one.
    func testTheGeminiTokenBudgetStartsUnset() {
        XCTAssertNil(preferences().geminiAPIMonthlyTokenBudget)
    }

    func testTheGeminiTokenBudgetSurvivesARestart() {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        Preferences(defaults: defaults).geminiAPIMonthlyTokenBudget = 2_000_000

        XCTAssertEqual(Preferences(defaults: defaults).geminiAPIMonthlyTokenBudget, 2_000_000)
        // The provider is an actor and reads the store directly, off the main
        // actor — so that path has to see the same value.
        XCTAssertEqual(Preferences.storedGeminiAPIMonthlyTokenBudget(defaults: defaults),
                       2_000_000)
    }

    /// Clearing the field has to remove the key, not leave the old ceiling
    /// behind for the next launch to read back.
    func testClearingTheGeminiTokenBudgetForgetsIt() {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let p = Preferences(defaults: defaults)
        p.geminiAPIMonthlyTokenBudget = 2_000_000
        p.geminiAPIMonthlyTokenBudget = nil

        XCTAssertNil(defaults.object(forKey: "geminiAPIMonthlyTokenBudget"))
        XCTAssertNil(Preferences(defaults: defaults).geminiAPIMonthlyTokenBudget)
    }

    /// A budget of zero would divide the ring by nothing, so it reads as no
    /// budget at all rather than as a ceiling already blown.
    func testAZeroGeminiTokenBudgetReadsAsNone() {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        Preferences(defaults: defaults).geminiAPIMonthlyTokenBudget = 0

        XCTAssertNil(Preferences(defaults: defaults).geminiAPIMonthlyTokenBudget)
        XCTAssertNil(Preferences.storedGeminiAPIMonthlyTokenBudget(defaults: defaults))
    }
}

/// The glass styles differ in the `Glass` variant they ask for (`.regular`
/// for `glass`, `.clear` for `darkGlass`) and the wash drawn beneath it
/// (`glassDim`: nil for `glass`, `Palette.darkGlassDim` for `darkGlass`).
/// Both are pinned on the enum so the views cannot drift apart. `dock` follows
/// `darkGlass` everywhere but its slab, and is Dark glass on the top edge.
final class NotchSurfaceStyleTests: XCTestCase {








}

/// Settings shows whose account each reading comes from. Not decoration: the app
/// borrows credentials it does not own, so the account it reads can quietly be a
/// different one from the account you are using — which is exactly what happened
/// with Cursor during development.
final class ProviderAccountTests: XCTestCase {
    func testSummaryReadsAsASentence() {
        let account = ProviderAccount(
            label: "someone@example.com", plan: "free", source: "Cursor", manageURL: nil
        )
        XCTAssertEqual(account.summary, "someone@example.com · Free · via Cursor")
    }

    /// Claude's credential carries no address, so the row still has to say
    /// something useful rather than collapsing to an empty line.
    func testSummarySurvivesAMissingLabel() {
        let account = ProviderAccount(label: nil, plan: "pro", source: "Claude Code", manageURL: nil)
        XCTAssertEqual(account.summary, "Pro · via Claude Code")
    }

    func testSummarySurvivesAMissingPlan() {
        let account = ProviderAccount(label: "a@b.c", plan: nil, source: "Codex", manageURL: nil)
        XCTAssertEqual(account.summary, "a@b.c · via Codex")
    }

    /// The identity lives in the id token's claims. Decoding is base64url with
    /// the padding stripped, which plain base64 refuses.
    func testCodexClaimsDecodeFromABase64URLPayload() throws {
        let payload = #"{"email":"a@b.c","x":"-_"}"#
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let claims = try XCTUnwrap(CodexCredentials.claims(inJWT: "header.\(encoded).signature"))
        XCTAssertEqual(claims["email"] as? String, "a@b.c")
    }

    func testMalformedTokensAreRefusedRatherThanCrashing() {
        XCTAssertNil(CodexCredentials.claims(inJWT: "nonsense"))
        XCTAssertNil(CodexCredentials.claims(inJWT: "only.two"))
        XCTAssertNil(CodexCredentials.claims(inJWT: "a.!!!!.c"))
    }

    func testAMissingAuthFileIsNotAnAccount() {
        let missing = URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString).json")
        XCTAssertNil(CodexCredentials.account(from: missing))
    }
}

/// `account()` is a protocol *requirement*, not just an extension default.
///
/// A method that exists only in a protocol extension is dispatched statically,
/// so calling it through `any UsageProvider` lands on the default and never on
/// the implementation. It fails silently — every account simply reports as
/// absent — which is what shipped for one build.
final class ProviderAccountDispatchTests: XCTestCase {
    private struct Silent: UsageProvider {
        let id = "silent"
        let displayName = "Silent"
        let glyph = ProviderGlyph.claude
        func fetchSnapshot() async throws -> ProviderSnapshot {
            throw UsageProviderError.needsAuth
        }
    }

    private struct Speaking: UsageProvider {
        let id = "speaking"
        let displayName = "Speaking"
        let glyph = ProviderGlyph.claude
        func fetchSnapshot() async throws -> ProviderSnapshot {
            throw UsageProviderError.needsAuth
        }
        func account() -> ProviderAccount? {
            ProviderAccount(label: "a@b.c", plan: "pro", source: "Test", manageURL: nil)
        }
    }

    /// Through the existential — the way the store actually calls it.
    func testAnImplementationIsFoundThroughTheProtocol() {
        let providers: [any UsageProvider] = [Silent(), Speaking()]
        XCTAssertNil(providers[0].account())
        XCTAssertEqual(providers[1].account()?.label, "a@b.c",
                       "the concrete implementation was skipped — static dispatch")
    }

    func testTheDefaultStillAppliesToProvidersWithoutOne() {
        XCTAssertNil((Silent() as any UsageProvider).account())
    }
}

/// Antigravity's mark is flattened from its own SVG, so what is asserted is
/// that it survived flattening: one closed loop, inside the unit box, filling
/// it. The Gemini spark it replaced was generated, and its geometry could be
/// checked exactly; this one comes from artwork and can only be checked for
/// sanity.
final class ProviderGlyphTests: XCTestCase {
    private var loop: [CGPoint] { GlyphOutline.antigravity[0] }

    func testItIsOneClosedLoopInTheUnitBox() {
        XCTAssertEqual(GlyphOutline.antigravity.count, 1)
        XCTAssertGreaterThan(loop.count, 50, "the curves were not flattened into enough points")
        for p in loop {
            XCTAssertTrue((0...1).contains(p.x), "x outside the unit box: \(p.x)")
            XCTAssertTrue((0...1).contains(p.y), "y outside the unit box: \(p.y)")
        }
    }

    /// Normalisation should fill the box on its longer axis, or the mark would
    /// render smaller than every other glyph for no reason.
    func testItFillsTheBox() {
        let xs = loop.map(\.x), ys = loop.map(\.y)
        let span = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        XCTAssertEqual(span, 1, accuracy: 0.01)
    }

    func testEveryGlyphResolvesAnOutline() {
        for glyph in [ProviderGlyph.claude, .openai, .third, .cursor, .antigravity] {
            XCTAssertFalse(glyph.outline.isEmpty, "\(glyph) draws nothing")
        }
    }

    /// The raw value is what archived readings were written under.
    func testTheRawValueSurvivesTheRename() {
        XCTAssertEqual(ProviderGlyph.antigravity.rawValue, "gemini")
    }

    /// `gemini` was taken by the arch before the sparkle needed a name, and it
    /// is an archive key, so the sparkle got a second one rather than the two
    /// marks trading meanings under stored readings.
    func testTheSparkHasItsOwnRawValue() {
        XCTAssertEqual(ProviderGlyph.geminiSpark.rawValue, "gemini-spark")
    }

    /// The dispatch is one line and pointing it at the arch would be silent —
    /// both marks fill the box and both are one closed loop. What separates
    /// them is where the ink reaches the edge: the spark has a point at each of
    /// the four edge midpoints, while the arch touches the top at its apex and
    /// is open along the bottom.
    func testTheSparkResolvesToTheSparkleAndNotTheArch() throws {
        let spark = ProviderGlyph.geminiSpark.outline
        XCTAssertEqual(spark.count, 1)
        let points = try XCTUnwrap(spark.first)

        let left = try XCTUnwrap(points.min { $0.x < $1.x })
        XCTAssertEqual(left.x, 0, accuracy: 0.01)
        XCTAssertEqual(left.y, 0.5, accuracy: 0.01)

        let right = try XCTUnwrap(points.max { $0.x < $1.x })
        XCTAssertEqual(right.x, 1, accuracy: 0.01)
        XCTAssertEqual(right.y, 0.5, accuracy: 0.01)

        let top = try XCTUnwrap(points.min { $0.y < $1.y })
        XCTAssertEqual(top.y, 0, accuracy: 0.01)
        XCTAssertEqual(top.x, 0.5, accuracy: 0.01)

        let bottom = try XCTUnwrap(points.max { $0.y < $1.y })
        XCTAssertEqual(bottom.y, 1, accuracy: 0.01)
        XCTAssertEqual(bottom.x, 0.5, accuracy: 0.01)
    }
}


/// The notch's own visibility. Its default matters more than the other two
/// settings here: get it wrong and a fresh install shows nothing at all, which
/// is indistinguishable from the app failing to start.
final class NotchVisibilityTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "NotchVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }





}

/// Which displays get a notch. Its default matters: get it wrong and a fresh
/// install with two displays either shows a notch where none was expected or
/// hides the one that was always there.
final class NotchScreenScopeTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "NotchScreenScopeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }




}

/// The fleet's add/remove maths, without any displays: which controllers to
/// retire and which to create when the screen list changes.
final class NotchFleetReconcileTests: XCTestCase {
    private func key(_ n: Int) -> NSNumber { NSNumber(value: n) }





}

/// The fleet against the real screen list: main-only keeps a single notch,
/// all-displays one per screen. On a one-display Mac both are one — the point
/// is the count follows the scope, not a fixed number.
@MainActor
final class NotchFleetScopeTests: XCTestCase {


}

@MainActor
private final class SyntheticNSScreen: NSScreen {
    private let number: Int

    init(number: Int) {
        self.number = number
        super.init()
    }

    override var frame: CGRect {
        CGRect(x: CGFloat(number) * 1600, y: 0, width: 1440, height: 900)
    }

    override var visibleFrame: CGRect { frame }

    override var deviceDescription: [NSDeviceDescriptionKey: Any] {
        [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: number)]
    }
}

@MainActor
final class NotchFleetRebindingTests: XCTestCase {
    private func screen(_ number: Int) -> SyntheticNSScreen {
        SyntheticNSScreen(number: number)
    }


}

/// Renaming the app renames its defaults domain, so every setting moves to a
/// new empty one unless it is carried across.
final class RenameMigrationTests: XCTestCase {
    private func suite() -> (UserDefaults, String) {
        let name = "RenameMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    /// A source domain of our own, so the tests never read the real one — the
    /// first version of this did exactly that, and copied live settings into a
    /// scratch suite.
    private func oldDomain(_ contents: [String: Any]) -> String {
        let name = "RenameMigrationTests.old.\(UUID().uuidString)"
        UserDefaults.standard.setPersistentDomain(contents, forName: name)
        return name
    }



}

/// The card's height is budgeted, not measured, and the panel reaches inward by
/// the budget. A card taller than that is not scrolled or grown — it is
/// clipped, and the clipping takes the *title* off the top. Six sessions did
/// exactly that.
final class TooltipOverflowTests: XCTestCase {

}

/// Hiding sessions behind "and N more" is a cost, not a feature: the point of
/// the readout is that nothing needs opening. So the cap is solved for the
/// display rather than fixed — a laptop that cannot hold ten rows summarises,
/// a desk display that can does not.
final class SessionCapTests: XCTestCase {








}

/// A tooltip is centred on the cell it belongs to, so the first and last
/// providers throw half a card past the end of the stack. Both orientations
/// need room for it — a side edge was assumed exempt because the card sits
/// beside the stack, but it sits beside it *horizontally* while being centred
/// on it *vertically*, and the title was clipped off the top.
final class TooltipEndroomTests: XCTestCase {

}

/// A card with no readings shows a status message instead, and the budget used
/// to reserve one line for it whatever it said. The longest of them takes
/// three, so the card came up short and clipped the part that says what to do —
/// on the one ring a user is looking at because something is wrong.
final class StatusMessageHeightTests: XCTestCase {
    /// Every message the app can actually produce, against the budget the card
    /// is built to.
    private var everyStatusCard: [(name: String, snapshot: ProviderSnapshot)] {
        let states: [(String, ProviderStatus)] = [
            ("needsAuth", .needsAuth),
            ("accessDenied", .accessDenied),
            ("unsupported", .unsupported("The free plan has nothing for Cursor to meter yet")),
            ("error", .error("HTTP 500")),
            ("stale", .stale(since: .distantPast)),
            ("ok", .ok)
        ]
        return [("claude", "Claude"), ("claude-work", "Claude (work)"), ("cursor", "Cursor"),
                ("codex", "Codex"), ("gemini", "Antigravity")].flatMap { id, name in
            states.map { state in
                ("\(id)/\(state.0)",
                 ProviderSnapshot(id: id, displayName: name, glyph: .claude,
                                  fidelity: .official, status: state.1, windows: []))
            }
        }
    }



    /// Whole lines, so the last one never straddles the clip.
    func testHeightIsAWholeNumberOfLines() {
        for text in ["", "short", String(repeating: "a long message ", count: 12)] {
            let height = NotchLayout.bodyTextHeight(text)
            let lines = height / NotchLayout.cardBodyLineHeight
            XCTAssertEqual(lines, lines.rounded(), accuracy: 0.0001, "\(text.prefix(20))")
        }
    }

}

/// Choosing a size multiplies the whole surface. What matters is that it is a
/// multiplication and nothing more: the design frame stays the thing every
/// constant is quoted from, and `medium` stays that frame untouched.
@MainActor
final class NotchSizeTests: XCTestCase {






}
