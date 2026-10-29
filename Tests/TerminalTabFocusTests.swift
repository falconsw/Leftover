import XCTest
@testable import Leftover

/// Path normalisation and AppleScript escaping behind exact-tab focus.
final class TerminalTabFocusTests: XCTestCase {






    /// The runner's own environment block is readable and NUL-parsed.
    func testReadsAProcessEnvironment() {
        let entries = TerminalTabFocus.environment(of: getpid())
        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.contains { $0.hasPrefix("PATH=") })
    }

    /// The test runner's own tty and cwd, when they exist, read like ps
    /// prints them.
    func testReadsTheControllingTerminalName() {
        if let tty = SessionFocus.tty(of: getpid()) {
            XCTAssertTrue(tty.hasPrefix("ttys"), "unexpected tty name \(tty)")
        }
    }

    func testReadsAProcessWorkingDirectory() {
        let cwd = SessionFocus.currentDirectory(of: getpid())
        XCTAssertEqual(cwd?.hasPrefix("/"), true)
    }
}
