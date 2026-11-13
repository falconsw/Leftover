import Foundation

/// The Z.ai key behind a GLM Coding Plan, borrowed from whichever tool holds
/// it.
///
/// Z.ai does not ship a desktop app for the plan, so there is no single
/// session to borrow the way Claude Code's or Cursor's is borrowed. What it
/// has is an API key that several coding tools will hold on the user's behalf,
/// and a notch that wants to read one of them rather than ask for a key of its
/// own. The sources, in the order they are tried:
///
/// 1. **Claude Code** — `~/.claude/settings.json`, the documented way to point
///    Claude Code at the plan. Only claimed when the base URL alongside the
///    token is a Z.ai one: `ANTHROPIC_AUTH_TOKEN` aimed at api.anthropic.com
///    is somebody's Anthropic key, and claiming it would read the wrong
///    account and report it under GLM's name.
/// 2. **ZCode** — `~/.zcode/v2/credentials.json`. Older builds also read a
///    plan key pasted into `~/.zcode/v2/config.json` — an enabled
///    `builtin:*-coding-plan` entry whose `baseURL` says which console — and
///    that file is still honoured where it exists, but recent ZCode no longer
///    writes it: everything lives in the credentials file instead, one entry
///    per account as `account-provider:…:api-key` plus the sign-in tokens
///    `oauth:zai:access_token` and `oauth:bigmodel:access_token`. Every value
///    is encrypted at rest behind an `enc:v1:` marker, and decrypted with
///    `ZCodeCredentialCipher` — ZCode's own construction, mirrored rather
///    than asked for. A value that does not decrypt is skipped rather than
///    guessed at: a wrong guess would read as a signed-out plan.
/// 3. **OpenCode** — `~/.local/share/opencode/auth.json`, keyed under a
///    handful of provider names for the global (`z.ai`) and China
///    (`bigmodel.cn`) consoles.
/// 4. **cprov** — `~/.config/cprov/profiles/*.json`, for a Claude Code that is
///    switched between providers per terminal. cprov keeps the key out of
///    `settings.json` on purpose — `cprov glm` hands it to that one session —
///    so the first source finds nothing unless GLM happens to be the default.
///    The profile says which key is a Z.ai one; the key itself is in the
///    login keychain under service `cprov`, account = profile name. That makes
///    this the one source whose read can prompt, which is why it is tried
///    last and held in a `CredentialCache` (see `CprovKeys`).
enum GLMCredentials {
    struct Credential {
        let token: String
        /// The console this key belongs to — it decides the monitor host the
        /// usage is read from. A China-console key asked of api.z.ai answers
        /// as an auth failure, which would read as a signed-out plan that is
        /// merely pointed at the other country.
        let baseURL: URL
        /// The tool the key was found under, for the settings row.
        let source: String
    }

    static var claudeSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }
    static var zcodeConfigURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".zcode/v2/config.json")
    }
    static var zcodeCredentialsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".zcode/v2/credentials.json")
    }
    static var zcodeSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".zcode/v2/setting.json")
    }
    static var openCodeAuthURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/share/opencode/auth.json")
    }

    /// Throws only for the cprov source: a keychain read that macOS refused
    /// is not the same as no key anywhere, and must not be reported as one.
    static func load() throws -> Credential? {
        try load(claudeSettings: claudeSettingsURL,
                 zcodeConfig: zcodeConfigURL,
                 zcodeCredentials: zcodeCredentialsURL,
                 openCodeAuth: openCodeAuthURL)
            ?? cprov(CprovKeys.home, key: CprovKeys.key)
    }

    /// Who holds the key and for which console, without reading a keychain
    /// item's data — for the settings row, which is redrawn far too often to
    /// be the reason a dialogue appears.
    static func holder() -> (source: String, baseURL: URL)? {
        if let found = load(claudeSettings: claudeSettingsURL,
                            zcodeConfig: zcodeConfigURL,
                            zcodeCredentials: zcodeCredentialsURL,
                            openCodeAuth: openCodeAuthURL) {
            return (found.source, found.baseURL)
        }
        return cprovProfiles(CprovKeys.home)
            .first { CprovKeys.isPresent(account: $0.name) }
            .map { ("cprov", $0.console) }
    }

    /// Every path is a parameter so a test can point each source at its own
    /// fixture without touching a real one. A nil path simply drops that
    /// source, and a nil secret decrypts the ZCode file with this Mac's own —
    /// tests pass the one they encrypted their fixtures with.
    static func load(claudeSettings: URL?, zcodeConfig: URL?,
                     zcodeCredentials: URL?, openCodeAuth: URL?,
                     zcodeSecret: String? = nil) -> Credential? {
        claudeSettings.flatMap(claudeCode)
            ?? zcodeConfig.flatMap(zcodePlanKey)
            ?? zcodeCredentials.flatMap { zcode($0, secret: zcodeSecret) }
            ?? openCodeAuth.flatMap(openCode)
    }

    // MARK: Claude Code

    /// `~/.claude/settings.json` → `env.ANTHROPIC_AUTH_TOKEN` plus
    /// `env.ANTHROPIC_BASE_URL`.
    static func claudeCode(_ url: URL) -> Credential? {
        guard let root = dictionary(at: url), let env = root["env"] as? [String: Any],
              let token = string(env["ANTHROPIC_AUTH_TOKEN"]) ?? string(env["ANTHROPIC_API_KEY"])
        else { return nil }

        // The base URL is what makes this a GLM key. Without it, or pointed
        // somewhere else, the token is not ours to claim.
        guard let base = string(env["ANTHROPIC_BASE_URL"]),
              let url = URL(string: base),
              let host = url.host,
              isZaiHost(host)
        else { return nil }

        return Credential(token: token, baseURL: consoleBase(from: host), source: "Claude Code")
    }

    // MARK: ZCode

    /// `~/.zcode/v2/config.json` → an enabled `builtin:*-coding-plan` provider
    /// with the plan key pasted in. The `baseURL` beside it is the tool's own
    /// Anthropic endpoint — its *host* decides which console the usage is read
    /// from, the path is dropped: the monitor lives at the console root, and
    /// asking it under `/api/anthropic` answers a misleading 404.
    static func zcodePlanKey(_ url: URL) -> Credential? {
        guard let root = dictionary(at: url), let providers = root["provider"] as? [String: Any]
        else { return nil }

        for (id, value) in providers.sorted(by: { $0.key < $1.key }) {
            guard isPlanProvider(id), let provider = value as? [String: Any],
                  let options = provider["options"] as? [String: Any],
                  let key = string(options["apiKey"])
            else { continue }
            // Explicitly disabled entries are not keys being used; claiming
            // one would read an account the user switched off.
            if let enabled = provider["enabled"] as? Bool, !enabled { continue }
            let console = (string(options["baseURL"]))
                .flatMap { URL(string: $0) }
                .flatMap { $0.host }
                .map(consoleBase(from:)) ?? URL(string: "https://api.z.ai")!
            return Credential(token: key, baseURL: console, source: "ZCode")
        }
        return nil
    }

    /// ZCode uses separate provider ids for the paid Coding Plan and the
    /// account's Start Plan. Both expose the same monitor shape now; a plain
    /// `builtin:zai` entry remains pay-as-you-go and must not be claimed as a
    /// plan quota.
    static func isPlanProvider(_ id: String) -> Bool {
        id.contains("coding-plan") || id.contains("start-plan")
    }

    /// Whether ZCode has Z.ai's Start Plan switched on.
    ///
    /// Start Plan keys are handled by `zcodePlanKey`; this helper lets the row
    /// distinguish an active Start Plan from no ZCode configuration when the
    /// entry has no usable key.
    static func zcodeHasStartPlan(_ url: URL = zcodeConfigURL) -> Bool {
        guard let root = dictionary(at: url), let providers = root["provider"] as? [String: Any]
        else { return false }
        return providers.contains { id, value in
            guard id.contains("start-plan"), let provider = value as? [String: Any],
                  let options = provider["options"] as? [String: Any],
                  string(options["apiKey"]) != nil
            else { return false }
            return provider["enabled"] as? Bool ?? true
        }
    }

    /// Whether ZCode's current sign-in is the Start Plan only (#71, new layout).
    ///
    /// `config.json` is gone from recent ZCode — the plan choice moved to
    /// `setting.json`'s `providerFamilyConnectionSelections`, one `{kind}` per
    /// console (`start-plan`, `individual-coding-plan`, `team-coding-plan`).
    /// True only when there is at least one selection and every one of them
    /// is the Start Plan: a coding plan on either console is a plan with
    /// published usage, and no selection at all is not a plan of any kind.
    static func zcodeSettingsHasStartPlanOnly(_ url: URL = zcodeSettingsURL) -> Bool {
        guard let root = dictionary(at: url),
              let selections = root["providerFamilyConnectionSelections"] as? [String: Any],
              !selections.isEmpty
        else { return false }
        return selections.values.allSatisfy {
            ($0 as? [String: Any])?["kind"] as? String == "start-plan"
        }
    }

    /// `~/.zcode/v2/credentials.json` → the plan key, or the sign-in token.
    ///
    /// Recent ZCode files the plan key per account and encrypts every value
    /// at rest, so each candidate is decrypted before it is trusted — and a
    /// value that does not decrypt is skipped, not sent: it reads on the
    /// monitor as a signed-out plan. Older builds wrote the token in the
    /// clear, and those pass through untouched.
    ///
    /// The account key comes first: it is the plan's own credential, where
    /// the sign-in token is a login session that happens to be accepted too.
    /// With several accounts the keys sort, so the answer is stable rather
    /// than a directory-listing lottery.
    static func zcode(_ url: URL, secret: String? = nil) -> Credential? {
        guard let root = dictionary(at: url) else { return nil }
        let resolved = secret ?? ZCodeCredentialCipher.defaultSecret()
        func read(_ value: Any?) -> String? {
            guard let raw = string(value),
                  let plain = ZCodeCredentialCipher.decrypt(raw, secret: resolved)
            else { return nil }
            return plain.isEmpty ? nil : plain
        }

        for key in root.keys.filter(isAccountAPIKey).sorted() {
            if let token = read(root[key]) {
                return Credential(token: token,
                                  baseURL: key.lowercased().contains("bigmodel")
                                    ? URL(string: "https://open.bigmodel.cn")!
                                    : URL(string: "https://api.z.ai")!,
                                  source: "ZCode")
            }
        }
        if let token = read(root["oauth:zai:access_token"]) {
            return Credential(token: token, baseURL: URL(string: "https://api.z.ai")!, source: "ZCode")
        }
        if let token = read(root["oauth:bigmodel:access_token"]) {
            return Credential(token: token, baseURL: URL(string: "https://open.bigmodel.cn")!, source: "ZCode")
        }
        return nil
    }

    /// ZCode files the plan key per account as
    /// `account-provider:coding-plan:<provider>:account:<id>:api-key` — the
    /// shape its own store validates with `^account-provider:.+:api-key$`.
    static func isAccountAPIKey(_ key: String) -> Bool {
        key.hasPrefix("account-provider:") && key.hasSuffix(":api-key")
            && key.count > "account-provider:".count + ":api-key".count
    }

    // MARK: OpenCode

    /// The provider names OpenCode's own sign-in writes, most specific first.
    private static let openCodeProviderIDs = ["zai-coding-plan", "zai", "z-ai", "z.ai", "glm", "zhipu", "zhipuai"]

    static func openCode(_ url: URL) -> Credential? {
        guard let root = dictionary(at: url) else { return nil }
        for id in openCodeProviderIDs {
            guard let entry = root[id] else { continue }
            // The entry is either the key itself or an object carrying it —
            // both shapes have shipped.
            if let token = string(entry) {
                return Credential(token: token, baseURL: console(forProviderID: id), source: "OpenCode")
            }
            if let object = entry as? [String: Any] {
                let key = ["apiKey", "api_key", "token", "key", "accessToken", "auth_token"]
                    .compactMap { string(object[$0]) }.first
                if let key {
                    return Credential(token: key, baseURL: console(forProviderID: id), source: "OpenCode")
                }
            }
        }
        return nil
    }

    /// The provider id decides the console: the `zhipu` names sign into the
    /// China console, everything else the global one.
    static func console(forProviderID id: String) -> URL {
        id.hasPrefix("zhipu")
            ? URL(string: "https://open.bigmodel.cn")!
            : URL(string: "https://api.z.ai")!
    }

    // MARK: cprov

    /// The key-holding Z.ai profiles under a cprov home, sorted by name so
    /// that two of them give a stable answer.
    ///
    /// A built-in profile names its provider (`"provider": "zai"`) and leaves
    /// the endpoint to cprov's catalog; a custom one carries its own
    /// `baseUrl`, and is claimed on the same evidence a `settings.json` key
    /// is — the host. `"auth": "subscription"` profiles have no key to find.
    static func cprovProfiles(_ home: URL) -> [(name: String, console: URL)] {
        let directory = home.appendingPathComponent("profiles")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { file -> (name: String, console: URL)? in
                guard let profile = dictionary(at: file),
                      string(profile["auth"]) == "key"
                else { return nil }
                // cprov files the key under the file's own name; the `name`
                // field inside is a copy of it.
                let name = file.deletingPathExtension().lastPathComponent

                if let host = string(profile["baseUrl"]).flatMap({ URL(string: $0) })?.host {
                    return isZaiHost(host) ? (name, consoleBase(from: host)) : nil
                }
                return string(profile["provider"]) == "zai"
                    ? (name, URL(string: "https://api.z.ai")!)
                    : nil
            }
    }

    /// The first Z.ai profile that has a key. `key` is a parameter so a test
    /// can stand in for the keychain; a throw from it — macOS said no — is
    /// passed on rather than read as a profile without a key.
    static func cprov(_ home: URL, key: (String) throws -> String?) rethrows -> Credential? {
        for profile in cprovProfiles(home) {
            if let token = try key(profile.name), !token.isEmpty {
                return Credential(token: token, baseURL: profile.console, source: "cprov")
            }
        }
        return nil
    }

    // MARK: Shared

    static func isZaiHost(_ host: String) -> Bool {
        host == "api.z.ai" || host.hasSuffix(".z.ai")
            || host == "open.bigmodel.cn" || host.hasSuffix(".bigmodel.cn")
    }

    static func consoleBase(from host: String) -> URL {
        host.hasSuffix("bigmodel.cn")
            ? URL(string: "https://open.bigmodel.cn")!
            : URL(string: "https://api.z.ai")!
    }

    private static func dictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root
    }

    /// Non-empty strings only: an empty key is worse than a missing one, it is
    /// a request that cannot succeed being sent all the same.
    private static func string(_ value: Any?) -> String? {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
