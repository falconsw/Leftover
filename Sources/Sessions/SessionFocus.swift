import AppKit
import Darwin
import Foundation

/// Brings the window an agent is running in to the front.
///
/// A session knows its own pid and nothing else — Claude Code publishes no
/// window, tab or tty. What it does have is a parent: the shell that launched
/// it, whose parent is the terminal application. So the app is found by walking
/// up the process tree until something turns up that macOS considers an
/// application, and that is what gets raised.
///
/// Raising the app is the answer every terminal gets. Selecting the *tab*
/// inside it needs the terminal's own scripting interface and there is no
/// general one — cmux answers through its socket CLI, Terminal.app and iTerm2
/// by tty over AppleScript, Warp and Ghostty publish nothing. `focus` tries
/// the tab and settles for the app; `activateApp` is the app-only route.
enum SessionFocus {

    /// The process's controlling terminal, named the way ps prints it
    /// (`ttys014`). Nil when it has none — agents with no terminal to go back
    /// to, which is most desktop-hosted sessions.
    static func tty(of pid: pid_t) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0
        else { return nil }
        // NODEV (-1) is "no controlling terminal"; devname would read it as a
        // real device number and answer garbage.
        guard info.kp_eproc.e_tdev != -1,
              let name = devname(info.kp_eproc.e_tdev, S_IFCHR)
        else { return nil }
        return String(cString: name)
    }

    /// The process's working directory — how a terminal that publishes no tty
    /// (cmux's AppleScript interface) can still name the tab it lives in.
    static func currentDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let read = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info,
                                Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard read == Int32(MemoryLayout<proc_vnodepathinfo>.size) else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    /// The nearest ancestor process that macOS knows as a running application.
    static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        for candidate in ancestry(of: pid) {
            if let app = NSRunningApplication(processIdentifier: candidate),
               app.bundleIdentifier != nil {
                return app
            }
        }
        return nil
    }

    /// The process and its parents, nearest first.
    ///
    /// Bounded rather than looped until pid 1: a corrupted `kinfo_proc` that
    /// reports itself as its own parent would otherwise spin forever, and no
    /// real chain from an agent to its terminal is more than a handful deep.
    static func ancestry(of pid: pid_t, limit: Int = 8) -> [pid_t] {
        var chain: [pid_t] = []
        var current = pid
        while chain.count < limit, current > 1 {
            chain.append(current)
            guard let parent = parent(of: current), parent != current else { break }
            current = parent
        }
        return chain
    }

    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0
        else { return nil }
        return info.kp_eproc.e_ppid
    }
}
