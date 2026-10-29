import XCTest
@testable import Leftover

/// `GET /api/v1/models` as LM Studio 0.4.24 answered it on 2026-09-10, cut
/// down to the fields the parser reads plus the ones it must ignore.
enum LMStudioFixtures {
    static let listing = #"""
    {"models":[
      {"type":"llm","publisher":"unsloth","key":"qwen3.8-27b","display_name":"Qwen3.8 27B UD","architecture":"qwen35",
       "quantization":{"name":"Q8_K_XL","bits_per_weight":8},"size_bytes":31457991680,"params_string":"27B",
       "loaded_instances":[{"id":"qwen3.8-27b","config":{"context_length":32768,"eval_batch_size":2048,"parallel":1,"flash_attention":true}}],
       "max_context_length":262144,"format":"gguf","capabilities":{"vision":false,"trained_for_tool_use":true},"description":null},
      {"type":"llm","publisher":"qwen","key":"qwen/qwen3.6-35b-a3b","display_name":"Qwen3.6 35B A3B","architecture":"qwen3_5_moe",
       "quantization":{"name":"8bit","bits_per_weight":8},"size_bytes":37580963840,"params_string":"35B",
       "loaded_instances":[],"max_context_length":262144,"format":"mlx"},
      {"type":"embedding","publisher":"nomic-ai","key":"text-embedding-nomic-embed-text-v1.5",
       "quantization":{"name":"Q4_K_M","bits_per_weight":4},"size_bytes":84106624,
       "loaded_instances":[{"id":"text-embedding-nomic-embed-text-v1.5","config":{"context_length":2048}}],"max_context_length":2048,"format":"gguf"}
    ]}
    """#

    static func snapshot(_ reading: LocalRuntimeReading) -> ProviderSnapshot {
        ProviderSnapshot(id: "lmstudio", displayName: "LM Studio", glyph: .lmstudio,
                         fidelity: .official, status: .ok, windows: [],
                         kind: .localRuntime, localRuntime: reading)
    }

    static func listing(instances: [(id: String, key: String, context: Int?)]) -> Data {
        let models = instances.map { instance -> [String: Any] in
            var config: [String: Any] = [:]
            if let context = instance.context { config["context_length"] = context }
            return ["type": "llm", "key": instance.key, "size_bytes": 1_000_000,
                    "quantization": ["name": "Q4_K_M"], "max_context_length": 8192,
                    "loaded_instances": [["id": instance.id, "config": config]]]
        }
        return try! JSONSerialization.data(withJSONObject: ["models": models])
    }
}

final class LMStudioUsageTests: XCTestCase {


    func testTwoInstancesOfOneModelAreTwoCells() throws {
        let models: [[String: Any]] = [["type": "llm", "key": "qwen3.8-27b", "size_bytes": 10, "max_context_length": 4096,
            "loaded_instances": [["id": "qwen3.8-27b"], ["id": "qwen3.8-27b:2"]]]]
        let reading = try LMStudioUsage.parse(try JSONSerialization.data(withJSONObject: ["models": models]))
        XCTAssertEqual(reading.models.map(\.name), ["qwen3.8-27b", "qwen3.8-27b:2"])
        XCTAssertEqual(reading.models.map(\.contextLength), [4096, 4096])
        XCTAssertEqual(reading.models.map(\.quantizationText), ["Unavailable", "Unavailable"])
    }


    func testTheWrongServiceAndMalformedListingsAreNotEmptySuccesses() {
        // LM Studio answers an unknown path with HTTP 200 and this body, so a
        // wrong port must fail on the envelope rather than pass as "no models".
        for payload in [#"{"error":{"type":"invalid_request","code":"invalid_api_key","message":"…"}}"#,
                        "{}", #"{"models":null}"#, "not json",
                        #"{"models":[{"type":"llm","key":"a","loaded_instances":[{"id":" "}]}]}"#,
                        #"{"models":[{"type":"llm","key":"a","size_bytes":-1,"loaded_instances":[{"id":"a"}]}]}"#,
                        #"{"models":[{"type":"llm","key":"a","max_context_length":0,"loaded_instances":[{"id":"a"}]}]}"#,
                        #"{"models":[{"type":"llm","key":"a","loaded_instances":[{"id":"a"},{"id":"a"}]}]}"#] {
            XCTAssertThrowsError(try LMStudioUsage.parse(Data(payload.utf8)), payload)
        }
    }
}

final class LMStudioEndpointTests: XCTestCase {
    func testOnlyLocalHTTPOriginsAreAcceptedAndNormalised() throws {
        XCTAssertEqual(try LMStudioEndpoint.parse(" http://localhost:1234/ ").absoluteString, "http://127.0.0.1:1234")
        XCTAssertEqual(try LMStudioEndpoint.parse("http://[::1]:41343").port, 41343)
        for address in ["https://127.0.0.1:1234", "http://10.238.1.89:1234", "http://user:pass@localhost:1234",
                        "http://localhost:1234/api/v1", "ws://127.0.0.1:1234", "http://localhost:0", ""] {
            XCTAssertThrowsError(try LMStudioEndpoint.parse(address), address) { error in
                XCTAssertEqual(error as? LMStudioError, .invalidEndpoint)
            }
        }
    }

    func testTheSocketSharesTheServersPort() throws {
        let endpoint = try LMStudioEndpoint.parse("http://127.0.0.1:41343")
        XCTAssertEqual(LMStudioEndpoint.websocketURL(endpoint, namespace: "llm").absoluteString, "ws://127.0.0.1:41343/llm")
    }

    func testTheConfiguredPortIsReadFromLMStudiosOwnSettings() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("LMStudioEndpointTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertNil(LMStudioEndpoint.configuredAddress(home: home), "no LM Studio, no address")
        let internals = home.appendingPathComponent(".lmstudio/.internal")
        try FileManager.default.createDirectory(at: internals, withIntermediateDirectories: true)
        let config = internals.appendingPathComponent("http-server-config.json")
        try Data(#"{"autoStartOnLaunch":true,"port":41343,"cors":true,"networkInterface":"0.0.0.0"}"#.utf8).write(to: config)
        XCTAssertEqual(LMStudioEndpoint.configuredAddress(home: home), "http://127.0.0.1:41343")
        try Data(#"{"port":0}"#.utf8).write(to: config)
        XCTAssertNil(LMStudioEndpoint.configuredAddress(home: home))
        try Data("not json".utf8).write(to: config)
        XCTAssertNil(LMStudioEndpoint.configuredAddress(home: home))
        XCTAssertEqual(LMStudioEndpoint.serverLogsDirectory(home: home).lastPathComponent, "server-logs")
    }

    func testTokensAreSplitTheWayLMStudioReadsThem() {
        let parts = LMStudioCredentials.parts(of: " sk-lm-tL9sH4ED:MQZTWwaOsmlIEKL4EruT\n")
        XCTAssertEqual(parts, .init(clientIdentifier: "tL9sH4ED", clientPasskey: "MQZTWwaOsmlIEKL4EruT"))
        for malformed in ["sk-lm-tL9sH4ED", "sk-lm-short:MQZTWwaOsmlIEKL4EruT", "sk-lm-tL9sH4ED:tooshort",
                          "tL9sH4ED:MQZTWwaOsmlIEKL4EruT", "sk-lm-tL9sH4E!:MQZTWwaOsmlIEKL4EruT", ""] {
            XCTAssertNil(LMStudioCredentials.parts(of: malformed), malformed)
        }
    }

    func testTheEnvironmentTokenWinsAndBlankIsAbsent() {
        XCTAssertEqual(LMStudioCredentials.load(environment: ["LM_API_TOKEN": " sk-lm-x "], keychain: { "stored" }), "sk-lm-x")
        XCTAssertEqual(LMStudioCredentials.load(environment: ["LM_API_TOKEN": "  "], keychain: { "stored" }), "stored",
                       "a blank export is no token")
        XCTAssertNil(LMStudioCredentials.load(environment: [:], keychain: { nil }))
    }

    func testTheKeychainClosureIsNotCachedBetweenCalls() {
        var calls = 0
        _ = LMStudioCredentials.load(environment: [:], keychain: { calls += 1; return "stored" })
        _ = LMStudioCredentials.load(environment: [:], keychain: { calls += 1; return "stored" })
        XCTAssertEqual(calls, 2, "the injectable path must bypass the cache")
    }

}
