import AppKit
import Foundation

/// Selects the exact tab a session is running in, where the terminal offers
/// a way to name it.
///
/// There is no general mechanism — every terminal is its own answer, and each
/// costs a one-time Automation consent for AppleScript:
///
/// * **cmux** matches a terminal panel by its *working directory* — the
///   session process's own cwd. Its socket CLI would be nicer (it names tabs
///   by tty), but the server refuses any client that is not itself inside a
///   cmux terminal session (manaflow-ai/cmux#3089) — and Leftover never is.
/// * **Terminal.app** and **iTerm2** match a tab by tty.
/// * **Ghostty** (1.3+) scripts its terminals with an id, a title and a
///   *working directory* but no tty, so it is matched by the session's cwd
///   like cmux; `focus` selects the tab and raises its window in one go.
/// * Everything else publishes nothing (Warp), and the caller falls back to
///   raising the app — the honest answer rather than a silent no-op.
enum TerminalTabFocus {

    // MARK: - cmux

    /// A process's full argument/environment block as NUL-separated strings.
    /// Same-user reads only — which is all a session's own tree ever needs.
    static func environment(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size
        else { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        var strings: [String] = []
        buffer.withUnsafeBytes { raw in
            var offset = MemoryLayout<Int32>.size   // past argc
            while offset < raw.count {
                guard let nul = raw[offset...].firstIndex(of: 0) else { break }
                // Empty runs separate the blocks (path, argv, env) — skip
                // them rather than stop at the first one.
                if nul == offset {
                    offset += 1
                    continue
                }
                if let string = String(bytes: raw[offset..<nul], encoding: .utf8) {
                    strings.append(string)
                }
                offset = nul + 1
            }
        }
        return strings
    }

    // MARK: - Running the tools

}
