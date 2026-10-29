import SwiftUI
import XCTest
@testable import Leftover

@MainActor
final class ApifyProviderTests: XCTestCase {
    private var directory: URL!
    private var authURL: URL!
    private var archive: UsageArchive!
    private var session: URLSession!
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    /// The CLI's file with the token still in it, which is the one shape a
    /// test can stand up without a keychain.
    private let fileLogin = #"{"token":"apify_api_fixture","id":"abc123","username":"fixture","email":"fixture@example.invalid","plan":{"id":"SCALE"},"secretsBackend":"file"}"#

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("apify-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        authURL = directory.appendingPathComponent("auth.json")
        try fileLogin.write(to: authURL, atomically: true, encoding: .utf8)
        let suite = "ApifyProviderTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        archive = UsageArchive(defaults: defaults)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ApifyEndpoint.self]
        session = URLSession(configuration: config)
        ApifyEndpoint.reset([])
    }

    override func tearDownWithError() throws {
        session.invalidateAndCancel()
        try FileManager.default.removeItem(at: directory)
        ApifyEndpoint.reset([])
    }

    /// Nothing of this Mac's: no environment token, nothing pasted, no CLI
    /// keychain item — only the file the test wrote.
    private func sources(settings: String? = nil,
                         cliKeychain: @escaping () throws -> String = { throw UsageProviderError.needsAuth },
                         cliKeychainPresent: Bool = false,
                         deleteSettingsToken: @escaping () -> Void = {},
                         forgetCached: @escaping () -> Void = {}) -> ApifyCredentialSources {
        ApifyCredentialSources(
            environment: [:],
            settingsToken: { settings },
            settingsPresent: { settings != nil },
            deleteSettingsToken: deleteSettingsToken,
            authURL: authURL,
            cliKeychain: cliKeychain,
            cliKeychainPresent: { cliKeychainPresent },
            forgetCached: forgetCached
        )
    }

    private func provider(at now: Date? = nil, sources: ApifyCredentialSources? = nil) -> ApifyProvider {
        let value = now ?? date
        return ApifyProvider(session: session, archive: archive, sources: sources ?? self.sources(), now: { value })
    }





    func testAnUnauthorizedAnswerDropsTheCachedTokenSoTheNextReadAsksAgain() async throws {
        // A 401 is the one signal the copy in hand is wrong despite the item
        // not having moved — which is what a re-login to another account
        // looks like from here.
        var forgotten = 0
        ApifyEndpoint.reset([.http(401, Data())])
        do {
            _ = try await provider(sources: sources(forgetCached: { forgotten += 1 })).fetchSnapshot()
            XCTFail("expected needsAuth")
        } catch UsageProviderError.needsAuth {}
        XCTAssertEqual(forgotten, 1)
    }




    func testRateLimitHonorsTheServerHintAcrossRelaunchAndClearsAfterSuccess() async throws {
        ApifyEndpoint.reset([.http(429, Data(), ["Retry-After": "120"]), .http(200, Data(ApifyFixture.limits.utf8))])
        let current = provider()
        for _ in 0..<2 {
            do {
                _ = try await current.fetchSnapshot()
                XCTFail("expected rateLimited")
            } catch UsageProviderError.rateLimited(let delay) {
                XCTAssertEqual(delay, 120)
            }
        }
        // Construct after the first response, like an actual relaunch.
        do {
            _ = try await provider().fetchSnapshot()
            XCTFail("expected persisted backoff")
        } catch UsageProviderError.rateLimited {}
        XCTAssertEqual(ApifyEndpoint.requests.count, 1, "a penalty is waited out, not spent on another attempt")
        XCTAssertEqual(archive.loadBackoffUntil(providerID: "apify"), date.addingTimeInterval(120))
        _ = try await provider(at: date.addingTimeInterval(121)).fetchSnapshot()
        XCTAssertEqual(ApifyEndpoint.requests.count, 2)
        XCTAssertNil(archive.loadBackoffUntil(providerID: "apify"))
    }

    func testRateLimitHasAMinimumAndAcceptsHTTPDates() async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        for (header, expected) in [("0", 60.0), ("invalid", 60.0), ("NaN", 60.0),
                                   (formatter.string(from: date.addingTimeInterval(300)), 300.0)] {
            archive.saveBackoffUntil(nil, providerID: "apify")
            ApifyEndpoint.reset([.http(429, Data(), ["Retry-After": header])])
            do {
                _ = try await provider().fetchSnapshot()
                XCTFail("expected rateLimited")
            } catch UsageProviderError.rateLimited(let delay) {
                XCTAssertEqual(delay, expected, accuracy: 0.1)
            }
        }
    }

    func testRefreshFollowsARotatedCLIToken() async throws {
        ApifyEndpoint.reset([.http(200, Data(ApifyFixture.limits.utf8)), .http(200, Data(ApifyFixture.limits.utf8))])
        let current = provider()
        _ = try await current.fetchSnapshot()
        try fileLogin.replacingOccurrences(of: "apify_api_fixture", with: "apify_api_rotated")
            .write(to: authURL, atomically: true, encoding: .utf8)
        _ = try await current.fetchSnapshot()
        XCTAssertEqual(ApifyEndpoint.requests.map { $0.value(forHTTPHeaderField: "Authorization") },
                       ["Bearer apify_api_fixture", "Bearer apify_api_rotated"],
                       "the file is re-read on every fetch, so a new login needs no relaunch")
    }

    func testSwitchingOffForgetsOnlyTheTokenCodenotchHolds() async throws {
        var deleted = 0
        let provider = provider(sources: sources(settings: "pasted", deleteSettingsToken: { deleted += 1 }))
        await provider.signOut()
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(try String(contentsOf: authURL, encoding: .utf8), fileLogin,
                       "the CLI's login is the CLI's to end")
    }

    func testForgettingTheCachedCredentialReachesTheCaches() {
        var forgotten = 0
        provider(sources: sources(forgetCached: { forgotten += 1 })).forgetCachedCredential()
        XCTAssertEqual(forgotten, 1)
    }


    func testTheGlyphAssetRendersAsAMarkNotASquare() throws {
        XCTAssertEqual(ProviderGlyph.apify.rawValue, "apify")
        XCTAssertEqual(ProviderGlyph.apify.assetName, "glyph-apify")
        let asset = try XCTUnwrap(NSImage(named: ProviderGlyph.apify.assetName))
        XCTAssertGreaterThan(asset.size.width, 0)
        let renderer = ImageRenderer(content: ProviderGlyphView(glyph: .apify, size: 32).foregroundStyle(.white))
        let data = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        var ink = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { ink += 1 }
        }
        let coverage = Double(ink) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
        XCTAssertGreaterThan(coverage, 0.05)
        XCTAssertLessThan(coverage, 0.85)
    }
}

private final class ApifyEndpoint: URLProtocol {
    enum Reply {
        case http(Int, Data, [String: String] = [:])
        case failure(URLError.Code)
    }
    private static let lock = NSLock()
    private static var replies: [Reply] = []
    private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] { lock.withLock { recorded } }

    static func reset(_ values: [Reply]) {
        lock.withLock { replies = values; recorded = [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.lock.withLock { () -> Reply? in
            Self.recorded.append(request)
            return Self.replies.isEmpty ? nil : Self.replies.removeFirst()
        }
        switch reply {
        case .http(let status, let data, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case nil:
            XCTFail("unexpected Apify request")
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        }
    }
    override func stopLoading() {}
}
