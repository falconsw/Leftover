# Leftover

A macOS menu bar app that shows how much of your AI coding tools' usage limits
is left.

Leftover sits in the menu bar. Click it for a panel with a ring for every
connected account: Claude Code, Codex, Cursor, Antigravity, GitHub Copilot,
Grok, OpenCode, Kiro, Gemini, GLM, Kimi, MiniMax, DeepSeek and more, plus local
model servers such as Ollama, LM Studio and oMLX.

- **Your limits at a glance.** Each ring shows how much of a limit is used and
  when it resets. Hover a ring for its details, click it to read it again.
- **No passwords.** Every reading comes from the sign-in already on your Mac
  (the CLI's or app's own credentials); Leftover never asks for one and never
  writes them.
- **Notifications** when a limit runs out or resets, and when an agent session
  finishes or is waiting on you.

## Credits

Leftover is a fork of [**codenotch**](https://github.com/vinzdg/codenotch) by
Vinz, which pins the same usage readings to a screen edge. Nearly all of the
provider integrations, session monitors and cost tracking come from codenotch.
Leftover replaces the notch with a menu bar panel and trims what that no longer
needs. Thank you, Vinz.

## Requirements

macOS 15 or later.

## Install

Homebrew: coming soon.

To build from source you need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`):

```sh
make run
```

`make run` generates the Xcode project, builds a Debug copy and launches it.
Builds are ad-hoc signed, so they run on your own Mac.

### Signing with a Developer ID

Leftover reads Claude Code's token from the login keychain, and the keychain
remembers which signed binary you allowed. An ad-hoc build gets a new identity
every time, so macOS asks again after each rebuild. To avoid that, sign with
your own Developer ID:

```sh
cp Local.xcconfig.example Local.xcconfig   # then set DEVELOPMENT_TEAM
```

`make release` builds a signed, notarized DMG in `dist/` (it also needs a
`notarytool` keychain profile; see `Scripts/release.sh`).

### Demo mode

`LEFTOVER_DEMO=1` fills the panel with sample data, which is handy for
screenshots:

```sh
LEFTOVER_DEMO=1 build/DerivedData/Build/Products/Debug/Leftover.app/Contents/MacOS/Leftover
```

## License

[MIT](LICENSE).

Bundled third-party components keep their own licenses:

- [Zstandard](https://github.com/facebook/zstd) decoder, BSD, `Sources/Vendor/zstd/LICENSE`
- [holiday-cn](https://github.com/NateScarlet/holiday-cn) data, MIT, `Sources/Resources/holiday-cn-LICENSE.txt`
- [Lobe Icons](https://github.com/lobehub/lobe-icons), MIT, `Sources/Resources/LobeIcons-LICENSE.txt`

Product names and logos belong to their owners and are used only to identify
the services Leftover reads. Leftover is not affiliated with or endorsed by any
of them.
