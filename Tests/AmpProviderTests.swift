import XCTest
@testable import Leftover

@MainActor
final class AmpProviderTests: XCTestCase {
    private var directory: URL!
    private var secretsURL: URL!
    private var archive: UsageArchive!
    private var session: URLSession!
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("amp-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        secretsURL = directory.appendingPathComponent("secrets.json")
        try #"{"apiKey@https://ampcode.com/":"sgamp_fixture"}"#.write(to: secretsURL, atomically: true, encoding: .utf8)
        let suite = "AmpProviderTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        archive = UsageArchive(defaults: defaults)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AmpEndpoint.self]
        session = URLSession(configuration: config)
        AmpEndpoint.reset([])
    }

    override func tearDownWithError() throws {
        session.invalidateAndCancel()
        try FileManager.default.removeItem(at: directory)
        AmpEndpoint.reset([])
    }

    private func provider(at now: Date? = nil) -> AmpProvider {
        let value = now ?? date
        return AmpProvider(session: session, archive: archive, secretsURL: secretsURL, now: { value })
    }








    func testRateLimitHonorsTheServerHintAcrossRelaunchAndClearsAfterSuccess() async throws {
        AmpEndpoint.reset([.http(429, Data(), ["Retry-After": "120"]), .http(200, AmpFixture.subscription)])
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
        } catch UsageProviderError.rateLimited { }
        XCTAssertEqual(AmpEndpoint.requests.count, 1)
        XCTAssertEqual(archive.loadBackoffUntil(providerID: "amp"), date.addingTimeInterval(120))
        _ = try await provider(at: date.addingTimeInterval(121)).fetchSnapshot()
        XCTAssertEqual(AmpEndpoint.requests.count, 2)
        XCTAssertNil(archive.loadBackoffUntil(providerID: "amp"))
    }

    func testRateLimitHasAMinimumAndAcceptsHTTPDates() async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        for (header, expected) in [("0", 60.0), ("invalid", 60.0), ("NaN", 60.0),
                                   (formatter.string(from: date.addingTimeInterval(300)), 300.0)] {
            archive.saveBackoffUntil(nil, providerID: "amp")
            AmpEndpoint.reset([.http(429, Data(), ["Retry-After": header])])
            do {
                _ = try await provider().fetchSnapshot()
                XCTFail("expected rateLimited")
            } catch UsageProviderError.rateLimited(let delay) {
                XCTAssertEqual(delay, expected, accuracy: 0.1)
            }
        }
    }

}

private final class AmpEndpoint: URLProtocol, @unchecked Sendable {
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
        var copy = request
        if let stream = copy.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            copy.httpBody = data
        }
        let reply = Self.lock.withLock { () -> Reply? in
            Self.recorded.append(copy)
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
            XCTFail("unexpected Amp request")
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        }
    }
    override func stopLoading() {}
}
