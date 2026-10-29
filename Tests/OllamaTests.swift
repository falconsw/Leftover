import XCTest
import SwiftUI
@testable import Leftover

/// Memory sizes and token counts are printed through `Foundation`'s
/// locale-aware formatting, so a machine set to Indonesian prints "4,5 GB"
/// where a US one prints "4.5 GB". Building the expectation the same way is
/// the only version of these assertions that is true on both.
func expectedGigabytes(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(0...1)))) GB"
}

func expectedTokens(_ value: Int) -> String {
    "\(value.formatted()) tokens"
}

final class OllamaLocalUsageTests: XCTestCase {



    func testMalformedListingsAreNotEmptySuccesses() {
        for payload in ["{}", "{\"models\":null}", "not json",
                        #"{"models":[{"name":" "}]}"#,
                        #"{"models":[{"name":"a","size":-1}]}"#,
                        #"{"models":[{"name":"a","size_vram":-1}]}"#,
                        #"{"models":[{"name":"a","context_length":0}]}"#,
                        #"{"models":[{"name":"a"},{"name":"a"}]}"#] {
            XCTAssertThrowsError(try OllamaLocalUsage.parse(Data(payload.utf8)), payload)
        }
    }

    func testTheEnvironmentKeyWinsAndBlankIsAbsent() {
        XCTAssertEqual(OllamaCredentials.load(environment: ["OLLAMA_API_KEY": " k "], keychain: { "stored" }), "k")
        XCTAssertEqual(OllamaCredentials.load(environment: ["OLLAMA_API_KEY": "  "], keychain: { "stored" }), "stored",
                       "a blank export is no key")
        XCTAssertNil(OllamaCredentials.load(environment: [:], keychain: { nil }))
    }

    func testTheKeychainClosureIsNotCachedBetweenCalls() {
        var calls = 0
        _ = OllamaCredentials.load(environment: [:], keychain: { calls += 1; return "stored" })
        _ = OllamaCredentials.load(environment: [:], keychain: { calls += 1; return "stored" })
        XCTAssertEqual(calls, 2, "the injectable path must bypass the cache")
    }

    func testOnlyLocalHTTPOriginsAreAccepted() throws {
        XCTAssertEqual(try OllamaEndpoint.parse(" http://localhost:11434/ ").absoluteString,
                       "http://127.0.0.1:11434")
        XCTAssertEqual(try OllamaEndpoint.parse("http://[::1]:11434").port, 11434)
        for address in ["https://127.0.0.1:11434", "http://192.168.1.2:11434",
                        "http://127.0.0.1.example.com", "http://user:pass@localhost:11434",
                        "http://localhost:11434/api", "http://localhost:11434?x=y",
                        "http://localhost:11434#x", "http://localhost:0", "file:///tmp/a"] {
            XCTAssertThrowsError(try OllamaEndpoint.parse(address), address)
        }
    }
}

@MainActor
final class OllamaModelCellTests: XCTestCase {







}

@MainActor
final class LocalModelBrandTests: XCTestCase {
    func testDetectsBrandsAcrossVersionsTagsAndNamespaces() {
        let cases: [(String, LocalModelBrand)] = [
            ("qwen3:0.6b", .qwen), ("Qwen/Qwen2.5-Coder-7B-Instruct:Q4_K_M", .qwen),
            ("qwq:32b", .qwen), ("gemma3:270m", .gemma),
            ("google/gemma-3-1b-it-GGUF", .gemma), ("embeddinggemma:latest", .gemma),
            ("llama3.2:1b", .llama), ("meta-llama/Llama-3.1-8B-Instruct", .llama),
            ("hf.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF:Q4_K_M", .llama),
            ("deepseek-r1:1.5b", .deepseek),
            ("hf.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF:Q4_K_M", .deepseek),
            ("DeepSeek-R1-Distill-Llama-8B", .deepseek),
            ("mistral:7b", .mistral), ("ministral-3:3b", .mistral),
            ("mistralai/Ministral-3-3B-Instruct-2512", .mistral),
            ("mixtral:8x7b", .mistral), ("devstral-small:24b", .mistral)
        ]
        for (name, expected) in cases {
            XCTAssertEqual(LocalModelBrand.detect(modelName: name), expected, name)
        }
    }



    func testEverySupportedBrandHasABundledVectorAsset() throws {
        for brand in LocalModelBrand.allCases {
            let asset = try XCTUnwrap(NSImage(named: brand.glyph.assetName), brand.rawValue)
            XCTAssertGreaterThan(asset.size.width, 0)
            XCTAssertGreaterThan(asset.size.height, 0)
            // Unsupported SVG root attributes can resolve an asset but render
            // a solid placeholder square. Check the native template's alpha.
            let renderer = ImageRenderer(content: ProviderGlyphView(glyph: brand.glyph, size: 32)
                .foregroundStyle(.white))
            let data = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            var inkPixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { inkPixels += 1 }
                }
            }
            let coverage = Double(inkPixels) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
            XCTAssertGreaterThan(coverage, 0.05, brand.rawValue)
            XCTAssertLessThan(coverage, 0.85, brand.rawValue)
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "LobeIcons-LICENSE", withExtension: "txt"))
    }
}

@MainActor
final class OllamaLocalProviderTests: XCTestCase {
    func testTransportUsesOnlyTheReadOnlyListing() async throws {
        let requested = expectation(description: "listing")
        let provider = makeProvider { request in
            XCTAssertEqual(request.url?.path, "/api/ps")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(request.timeoutInterval, 3)
            requested.fulfill()
            return (200, Data(#"{"models":[]}"#.utf8))
        }
        let snapshot = try await provider.fetchSnapshot()
        await fulfillment(of: [requested], timeout: 1)
        XCTAssertEqual(snapshot.kind, .localRuntime)
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertTrue(snapshot.hasReading)
        XCTAssertNil(provider.account())
    }

    func testTransportAndHTTPFailuresStayVisible() async {
        for status in [301, 401, 404, 500] {
            let provider = makeProvider { _ in (status, Data()) }
            do {
                _ = try await provider.fetchSnapshot()
                XCTFail("HTTP \(status) succeeded")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("HTTP \(status)"))
            }
        }
        let provider = makeProvider { _ in throw URLError(.timedOut) }
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Timeout succeeded")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("unavailable"))
        }
    }

    func testCancelledRequestStaysCancellation() async {
        let provider = makeProvider { _ in throw URLError(.cancelled) }
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Cancelled request succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Cancellation became \(error)")
        }
    }

    func testSessionDoesNotStoreCredentialsOrFollowRedirects() {
        let session = OllamaLocalProvider.makeSession()
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertNil(session.configuration.urlCredentialStorage)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
        let url = URL(string: "http://127.0.0.1:11434/api/ps")!
        let task = session.dataTask(with: url)
        OllamaRedirectPolicy().urlSession(session, task: task,
            willPerformHTTPRedirection: HTTPURLResponse(url: url, statusCode: 302,
                httpVersion: nil, headerFields: nil)!,
            newRequest: URLRequest(url: URL(string: "https://example.com")!)) { request in
                XCTAssertNil(request)
            }
    }

    private func makeProvider(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> OllamaLocalProvider {
        OllamaStubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OllamaStubProtocol.self]
        return OllamaLocalProvider(endpoint: URL(string: OllamaEndpoint.defaultAddress)!,
                              session: URLSession(configuration: configuration))
    }
}

private final class OllamaStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!,
                statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class OllamaLifecycleTests: XCTestCase {



    func testInventoryDefaultsOnAndPreservesOtherChoices() {
        let defaults = isolatedDefaults()
        defaults.set(["cursor"], forKey: "hiddenProviders")
        let first = Preferences(defaults: defaults)
        XCTAssertTrue(first.isConnected("ollama-local"))
        XCTAssertFalse(first.isConnected("cursor"))
        XCTAssertTrue(first.isConnected("codex"))
        first.setConnected(false, for: "ollama-local")
        XCTAssertFalse(Preferences(defaults: defaults).isConnected("ollama-local"))
    }





    func testClickedModelCanAwaitTheExistingInventoryPoll() async throws {
        let provider = RuntimeStub()
        provider.suspended = true
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: isolatedDefaults()))
        store.refreshLocalRuntimes()
        await started(provider)
        let pending = try XCTUnwrap(store.refresh(providerID: "ollama-local"))
        var completed = false
        let waiting = Task { await pending.value; completed = true }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(completed, "Joining a poll must await its actual completion")
        XCTAssertEqual(provider.calls, 1)
        provider.finish()
        await waiting.value
        XCTAssertTrue(completed)
        XCTAssertFalse(store.refreshing.contains("ollama-local"))
    }



    func testLocalTicksDoNotFetchOrStarveCloudProviders() async throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let local = RuntimeStub()
        let cloud = QuotaStub()
        let store = UsageStore(providers: [cloud, local], refreshInterval: 0.02,
                               idleRefreshInterval: 0.05, archive: UsageArchive(defaults: isolatedDefaults()),
                               pollingNow: { now })
        store.refreshLocalRuntimes()
        await started(local)
        XCTAssertEqual(cloud.calls, 0)
        store.start()
        defer { store.stop() }
        for _ in 0..<20 {
            now.addTimeInterval(0.01)
            store.refreshLocalRuntimes()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThanOrEqual(cloud.calls, 2)
        XCTAssertEqual(store.snapshots.map(\.id), ["cloud", "ollama-local"])
    }


    func testChangingEndpointClearsOldReadingAndDoesNotEnableMonitoring() async throws {
        let provider = OllamaLocalProvider(endpoint: try OllamaEndpoint.parse(OllamaEndpoint.defaultAddress))
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: isolatedDefaults()),
                               disconnected: ["ollama-local"])
        let updated = try OllamaEndpoint.parse("http://127.0.0.1:11435")
        store.updateOllamaEndpoint(updated)
        XCTAssertEqual(provider.endpoint, updated)
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.refreshing.isEmpty)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "OllamaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func started(_ provider: RuntimeStub) async {
        for _ in 0..<100 {
            if provider.calls > 0 { return }
            await Task.yield()
        }
        XCTFail("Provider did not start")
    }
}

@MainActor
private final class RuntimeStub: UsageProvider {
    nonisolated let id: String
    nonisolated let displayName = "Ollama"
    nonisolated let glyph = ProviderGlyph.ollamaLocal
    nonisolated let kind: ProviderKind
    var calls = 0
    var fails = false
    var suspended = false
    var models: [LocalRuntimeReading.Model] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []
    init(id: String = "ollama-local", kind: ProviderKind = .localRuntime) {
        self.id = id
        self.kind = kind
    }
    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        if suspended { await withCheckedContinuation { continuations.append($0) } }
        if fails { throw OllamaError.unavailable }
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                fidelity: .official, status: .ok, windows: [],
                                kind: kind, localRuntime: LocalRuntimeReading(models: models))
    }
    func finish() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

@MainActor
private final class QuotaStub: UsageProvider {
    nonisolated let id = "cloud"
    nonisolated let displayName = "Cloud"
    nonisolated let glyph = ProviderGlyph.claude
    var calls = 0
    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.4)])
    }
}

private func ollamaSnapshot(_ reading: LocalRuntimeReading) -> ProviderSnapshot {
    ProviderSnapshot(id: "ollama-local", displayName: "Ollama", glyph: .ollamaLocal,
                     fidelity: .official, status: .ok, windows: [],
                     kind: .localRuntime, localRuntime: reading)
}

@MainActor
final class OllamaRenderTests: XCTestCase {






    private func save(_ image: NSImage, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["OLLAMA_RENDER_DIRECTORY"] else { return }
        let data = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
