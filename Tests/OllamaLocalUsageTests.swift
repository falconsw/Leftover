import XCTest
@testable import Leftover

final class OllamaMemoryTests: XCTestCase {

    func testUnloadTimeDoesNotInventAnExpirationOrReset() throws {
        let reading = try OllamaLocalUsage.parse(Data(#"{"models":[{"name":"unknown","size":0}]}"#.utf8))
        XCTAssertEqual(reading.models[0].unloadText(now: Date()), "Unavailable")
        XCTAssertEqual(reading.models[0].memoryLabel, "Memory")
        XCTAssertEqual(reading.models[0].memoryText, "0 B")
        let date = try XCTUnwrap(OllamaLocalUsage.parseISO8601("2026-09-08T19:00:00Z"))
        let model = LocalRuntimeReading.Model(name: "cpu", memoryBytes: nil, contextLength: nil,
                                              quantizationLevel: nil, expiresAt: date)
        XCTAssertEqual(model.unloadText(now: date), "Pending")
        XCTAssertFalse(model.unloadText(now: date.addingTimeInterval(-60)).isEmpty)
        XCTAssertNotNil(OllamaLocalUsage.parseISO8601("2026-09-08T18:06:07.541672-04:00"))
        XCTAssertNil(OllamaLocalUsage.parseISO8601("not-a-date"))
    }
}
