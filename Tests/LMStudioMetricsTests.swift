import XCTest
import Combine
@testable import Leftover

/// A socket that answers from a script, so the monitor's folding of polls and
/// log lines can be driven without LM Studio.
@MainActor
final class LMStudioLinkStub: LMStudioCalling {
    var loaded: [[String: Any]] = []
    var states: [String: [String: Any]] = [:]
    var failure: Error?
    var calls: [String] = []
    var closed = 0

    func load(_ identifier: String, reference: String = "ref", type: String = "llm") {
        loaded.append(["type": type, "identifier": identifier, "instanceReference": reference, "modelKey": identifier])
    }

    func call(_ endpoint: String, parameter: Any?) async throws -> Any {
        calls.append(endpoint)
        if let failure { throw failure }
        switch endpoint {
        case "listLoaded":
            return loaded
        case "getInstanceProcessingState":
            let reference = ((parameter as? [String: Any])?["specifier"] as? [String: Any])?["instanceReference"] as? String ?? ""
            return states[reference] ?? ["status": "idle", "queued": 0]
        default:
            throw LMStudioLinkError.remote("Received rpcCall for unknown endpoint, endpoint = \(endpoint)")
        }
    }

    func close() async { closed += 1 }
}

@MainActor
final class LMStudioMetricsTests: XCTestCase {
    private var logs: URL!
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        logs = FileManager.default.temporaryDirectory.appendingPathComponent("LMStudioMetricsTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logs.appendingPathComponent("2026-09"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: logs)
    }

    private func metrics(link: LMStudioLinkStub, now: @escaping () -> Date = Date.init) -> LMStudioMetrics {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = LMStudioLogFixtures.zone
        return LMStudioMetrics(makeLink: { _ in link }, logsDirectory: logs,
                               pollInterval: 0.03, inventoryInterval: 0.1, logInterval: 0.03,
                               now: now, calendar: calendar)
    }

    private func wait<T: Equatable>(for publisher: Published<T>.Publisher, _ description: String,
                                    until condition: @escaping (T) -> Bool) async {
        let expectation = expectation(description: description)
        var done = false
        publisher.sink { value in
            guard !done, condition(value) else { return }
            done = true
            expectation.fulfill()
        }.store(in: &cancellables)
        await fulfillment(of: [expectation], timeout: 3)
    }





    func testABadAddressNeverOpensASocket() {
        let link = LMStudioLinkStub()
        let metrics = metrics(link: link)
        metrics.configure(enabled: true, endpoint: "http://10.0.0.5:1234")
        XCTAssertTrue(metrics.status.contains("HTTP address on this Mac"))
        XCTAssertTrue(link.calls.isEmpty)
        metrics.stop()
        XCTAssertEqual(metrics.status, "Off")
    }

    func testLiveLMStudioWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODENOTCH_LMSTUDIO_LIVE"] == "1" else {
            throw XCTSkip("Opt-in live LM Studio check")
        }
        // The whole history of this Mac's server log, timed: half a gigabyte
        // on the machine this was written on, and it must not take minutes.
        let started = Date()
        let tail = LMStudioLogTail(directory: LMStudioEndpoint.serverLogsDirectory())
        let history = tail.loadHistory()
        let elapsed = Date().timeIntervalSince(started)
        let logged = history.filter { if case .prediction = $0 { return true } else { return false } }.count
        print("LM Studio history: \(logged) responses in \(history.count) events, \(String(format: "%.1f", elapsed))s")
        XCTAssertLessThan(elapsed, 60)
        let endpoint = try LMStudioEndpoint.parse(LMStudioEndpoint.configuredAddress() ?? LMStudioEndpoint.defaultAddress)
        let provider = LMStudioLocalProvider(endpoint: endpoint)
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertTrue(snapshot.hasReading)
        let link = LMStudioLink(endpoint: endpoint, token: { LMStudioCredentials.load() })
        let loaded = LMStudioLoadedInstance.parse(try await link.call("listLoaded", parameter: nil))
        XCTAssertEqual(Set(loaded.filter(\.isLanguageModel).map(\.identifier)),
                       Set(snapshot.localRuntime?.models.map(\.name) ?? []),
                       "the socket and the REST listing name the same instances")
        for instance in loaded where instance.isLanguageModel {
            let state = LMStudioProcessingState(try await link.call("getInstanceProcessingState",
                parameter: LMStudioWire.processingStateParameter(instanceReference: instance.instanceReference)))
            XCTAssertNotNil(state, instance.identifier)
        }
        await link.close()
    }
}
