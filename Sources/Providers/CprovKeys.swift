import Foundation
import Security

/// Where cprov keeps the keys behind its profiles.
///
/// cprov switches Claude Code between providers, and its whole point is that
/// the key is *not* in `settings.json`: `cprov glm` puts it in that one
/// session's environment and nowhere on disk. What it documents for other
/// tools instead is the login keychain — service `cprov`, account = profile
/// name — which is what this reads. On a machine where cprov was told to use
/// its file backend (`CPROV_SECRET_BACKEND=file`) the keys sit in
/// `secrets.json` beside the profiles, and that is honoured first because
/// reading it cannot prompt.
///
/// The keychain item was filed by `/usr/bin/security`, so its ACL does not
/// list Leftover and the first data read prompts. Held until the item moves,
/// for the reason spelled out in `CredentialCache`; a refusal counts as a
/// verdict on that version of the item and is not put to macOS again until
/// "Allow access…" forgets it or cprov writes a new key.
enum CprovKeys {
    static let service = "cprov"

    /// cprov's own rule (`src/paths.js`): `CPROV_HOME`, else
    /// `$XDG_CONFIG_HOME/cprov`, else `~/.config/cprov`. An app launched from
    /// the Dock sees neither variable, which is the common case and lands on
    /// the default.
    static var home: URL {
        home(environment: ProcessInfo.processInfo.environment)
    }

    static func home(environment: [String: String]) -> URL {
        if let custom = environment["CPROV_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        let config = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config")
        return config.appendingPathComponent("cprov")
    }

    /// A key and the version of the item it was read from. The stamp is what
    /// lets the cache notice `cprov add` replacing the key: a stored key never
    /// expires on its own, so "expired" here means "the item has moved".
    private struct Held {
        let key: String
        let stamp: Date?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var caches: [String: CredentialCache<Held>] = [:]

    private static func cache(for account: String) -> CredentialCache<Held> {
        lock.lock(); defer { lock.unlock() }
        if let cache = caches[account] { return cache }
        let cache = CredentialCache<Held>(isPermanentFailure: { error in
            if case UsageProviderError.accessDenied = error { return true }
            return false
        }) { $0.stamp != KeychainItem.modifiedAt(service: service, account: account) }
        caches[account] = cache
        return cache
    }

    /// Whether cprov holds a key for this profile. Attributes are free to ask
    /// about; only the data can prompt.
    static func isPresent(account: String) -> Bool {
        fileKey(account: account, home: home) != nil
            || KeychainItem.modifiedAt(service: service, account: account) != nil
    }

    /// The profile's key, or nil when cprov has none for it. Throws when the
    /// item is there and could not be read — `accessDenied` for a declined
    /// prompt, which is not the same as having no key.
    static func key(account: String) throws -> String? {
        if let key = fileKey(account: account, home: home) { return key }
        guard KeychainItem.modifiedAt(service: service, account: account) != nil else { return nil }
        return try cache(for: account).value(
            itemModifiedAt: { KeychainItem.modifiedAt(service: service, account: account) },
            reload: { try read(account: account) }
        ).key
    }

    static func forgetCached() {
        lock.lock()
        let all = Array(caches.values)
        lock.unlock()
        all.forEach { $0.forget() }
    }

    /// `secrets.json` → `{ "<profile>": "<key>" }`, cprov's file backend.
    static func fileKey(account: String, home: URL) -> String? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("secrets.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = (root[account] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return key
    }

    /// Newest item under this service and account, then a targeted data read.
    /// Same two-step as Claude Code's and the Apify CLI's: attributes are
    /// free, the secret is not.
    private static func read(account: String) throws -> Held {
        guard let winner = KeychainItem.newest(service: service, account: account) else {
            throw UsageProviderError.needsAuth
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: winner.persistentRef,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            Log.usage.error("cprov keychain read failed: OSStatus \(status)")
            if ClaudeCredentials.wasTransient(status) { throw UsageProviderError.credentialExpired }
            throw ClaudeCredentials.wasRefused(status)
                ? UsageProviderError.accessDenied
                : UsageProviderError.needsAuth
        }
        guard let key = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { throw UsageProviderError.needsAuth }
        return Held(key: key, stamp: winner.modifiedAt)
    }
}
