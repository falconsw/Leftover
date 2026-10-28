import Foundation

/// What one release changed, in the app's own words.
struct ReleaseNote: Equatable {
    /// Matched against `CFBundleShortVersionString`, so it has to be exactly
    /// the string `MARKETING_VERSION` is set to.
    let version: String
    /// One line under the title. What this release is *about*.
    let headline: String
    let changes: [Change]

    /// A title carries the change; the detail is optional, so a small fix can
    /// be a single line rather than a line padded out to match its neighbours.
    struct Change: Equatable {
        let title: String
        let detail: String

        init(title: String, detail: String = "") {
            self.title = title
            self.detail = detail
        }
    }
}

/// The release history the app ships with.
///
/// Written here rather than fetched: it has to be there on a
/// first launch with no network, and it belongs to the build it describes.
/// Add an entry here whenever `MARKETING_VERSION` is bumped.
enum ReleaseNotes {
    static var all: [ReleaseNote] {
        [
            ReleaseNote(
                version: "1.0.0",
                headline: L10n.t("The first release."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("Your limits in the menu bar"),
                        detail: L10n.t("Click the menu bar item for a panel with a ring for every connected account.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Read from the tools already signed in"),
                        detail: L10n.t("Claude Code, Codex, Cursor, Antigravity, Copilot, Grok, OpenCode and more, each read from the sign-in already on this Mac. Leftover never asks for a password.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Details when you want them"),
                        detail: L10n.t("Hover a ring for its limits and when they reset, open More for the full card and the sessions running, and click a ring to read it again.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Told when a limit resets or runs out"),
                        detail: L10n.t("Notifications in Settings chooses which you want.")
                    ),
                ]
            ),
        ]
    }

    /// The note worth showing on this launch, if there is one.
    ///
    /// `notes` is a parameter so the rule can be tested against a fixed history
    /// rather than against whatever the app happens to ship this week.
    static func unseen(in version: String,
                       lastSeen: String?,
                       notes: [ReleaseNote] = ReleaseNotes.all) -> ReleaseNote? {
        guard lastSeen != version else { return nil }
        return notes.first { $0.version == version }
    }
}
