import AppKit
import SwiftUI
import XCTest
@testable import Leftover

final class BusyWaveTests: XCTestCase {

    func testMonochromeBrandsFallBackToTextPrimary() {
        XCTAssertEqual(ProviderGlyph.cursor.brandColor, Palette.textPrimary)
    }

    func testClaudeIsTerracotta() throws {
        let rgb = try XCTUnwrap(NSColor(ProviderGlyph.claude.brandColor).usingColorSpace(.sRGB))
        XCTAssertEqual(rgb.redComponent, CGFloat(0xD9) / 255, accuracy: 0.01)
        XCTAssertEqual(rgb.greenComponent, CGFloat(0x77) / 255, accuracy: 0.01)
        XCTAssertEqual(rgb.blueComponent, CGFloat(0x57) / 255, accuracy: 0.01)
    }
}
