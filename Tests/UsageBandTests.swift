import AppKit
import SwiftUI
import XCTest
@testable import Leftover

final class UsageBandTests: XCTestCase {
    func testBandsMatchTheDesignFrame() {
        // The three levels the mockup renders, and the colour it renders them in.
        XCTAssertEqual(UsageBand.band(for: 0.21), .ample)
        XCTAssertEqual(UsageBand.band(for: 0.52), .watch)
        XCTAssertEqual(UsageBand.band(for: 0.73), .critical)
    }

    func testBoundaries() {
        XCTAssertEqual(UsageBand.band(for: 0.0), .ample)
        XCTAssertEqual(UsageBand.band(for: 0.4999), .ample)
        XCTAssertEqual(UsageBand.band(for: 0.50), .watch)
        XCTAssertEqual(UsageBand.band(for: 0.6999), .watch)
        XCTAssertEqual(UsageBand.band(for: 0.70), .critical)
        XCTAssertEqual(UsageBand.band(for: 0.9999), .critical)
        XCTAssertEqual(UsageBand.band(for: 1.0), .exhausted)
        XCTAssertEqual(UsageBand.band(for: 1.4), .exhausted)
    }

    /// Only the ample state takes the user's accent choice. The warning bands
    /// exist to interrupt whatever else is on screen, and a customisable
    /// warning colour could be chosen into invisibility — so they stay fixed
    /// regardless of what accent is passed in.
    func testOnlyAmpleFollowsTheChosenAccent() {
        let accent = Color.pink
        XCTAssertEqual(UsageBand.ample.color(accent: accent), accent)
        XCTAssertEqual(UsageBand.watch.color(accent: accent), Palette.watch)
        XCTAssertEqual(UsageBand.critical.color(accent: accent), Palette.critical)
        XCTAssertEqual(UsageBand.exhausted.color(accent: accent), Palette.critical)
    }

    // MARK: - rampColor

    /// Same appearance-resolution trick `PaletteAppearanceTests.resolve` uses below: a
    /// dynamic `Color` only picks its real value once something asks for it inside a
    /// specific `NSAppearance`.
    private func resolveRamp(
        _ fraction: Double,
        watchLimit: Double = 0.50,
        appearance: NSAppearance.Name = .darkAqua
    ) -> NSColor? {
        var resolved: NSColor?
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            let color = UsageBand.rampColor(for: fraction, watchLimit: watchLimit)
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        return resolved
    }

    private func assertRampHex(
        _ fraction: Double,
        is hex: UInt32,
        watchLimit: Double = 0.50,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let resolved = resolveRamp(fraction, watchLimit: watchLimit) else {
            XCTFail("ramp did not resolve", file: file, line: line)
            return
        }
        let tolerance = 1.0 / 255
        XCTAssertEqual(resolved.redComponent, Double((hex >> 16) & 0xFF) / 255, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(resolved.greenComponent, Double((hex >> 8) & 0xFF) / 255, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(resolved.blueComponent, Double(hex & 0xFF) / 255, accuracy: tolerance, file: file, line: line)
    }

}

/// The palette went dynamic when the notch gained a glass surface, so the
/// frame's hexes are no longer visible in the source — they are one branch of
/// a colour that only resolves against an appearance. These tests keep that
/// branch honest: `darkAqua` must still be pixel-for-pixel the frame, and the
/// light branch must actually be different ink rather than a silent fallback.
final class PaletteAppearanceTests: XCTestCase {






    // MARK: -

    /// The `NSColor` has to be built *inside* the drawing appearance: a dynamic
    /// colour created outside it resolves against whatever the test host's
    /// appearance happens to be.
    private func resolve(
        _ color: Color,
        _ appearance: NSAppearance.Name,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> NSColor? {
        var resolved: NSColor?
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        XCTAssertNotNil(resolved, "\(appearance.rawValue) did not resolve", file: file, line: line)
        return resolved
    }

    private func assertOpaque(
        _ color: Color,
        _ appearance: NSAppearance.Name,
        is hex: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let resolved = resolve(color, appearance, file: file, line: line) else { return }
        let tolerance = 1.0 / 255
        XCTAssertEqual(resolved.redComponent, Double((hex >> 16) & 0xFF) / 255, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(resolved.greenComponent, Double((hex >> 8) & 0xFF) / 255, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(resolved.blueComponent, Double(hex & 0xFF) / 255, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(resolved.alphaComponent, 1, accuracy: tolerance, file: file, line: line)
    }

    private func assertTrack(
        _ color: Color,
        _ appearance: NSAppearance.Name,
        white: Double,
        alpha: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let resolved = resolve(color, appearance, file: file, line: line) else { return }
        let tolerance = 1.0 / 255
        XCTAssertEqual(resolved.redComponent, white, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(resolved.greenComponent, white, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(resolved.blueComponent, white, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(resolved.alphaComponent, alpha, accuracy: 0.005, file: file, line: line)
    }
}
