import XCTest
@testable import RippleKit

final class JoinCodeTests: XCTestCase {
    func testParsesJoinRepliesAndKeepsLeadingZeros() {
        XCTAssertEqual(JoinCode.code(in: "Ripple join 583921"), "583921")
        XCTAssertEqual(JoinCode.code(in: "RIPPLE JOIN 001234"), "001234")
        XCTAssertEqual(JoinCode.code(in: "Yes, Ripple-join: 583921!"), "583921")
    }

    func testRejectsMissingAndWrongLengthCodes() {
        for text in ["Ripple join", "Ripple join 4821", "Ripple join 12345", "Ripple join 1234567", "join 583921"] {
            XCTAssertNil(JoinCode.code(in: text), text)
        }
    }

    func testJoinAndAlarmRepliesDoNotOverlap() {
        XCTAssertNil(JoinCode.code(in: "Ripple accept 4821"))
        XCTAssertNil(ReplyCode.acceptCode(in: "Ripple join 583921"))
    }

    func testPendingJoinRequestCanBeSavedWithoutTheMessageBody() throws {
        let request = JoinTemporaryRequest(runId: "run-1", code: "001234", from: "+14165550199")
        let data = try RippleJSON.encoder.encode(request)
        XCTAssertEqual(try RippleJSON.decoder.decode(JoinTemporaryRequest.self, from: data), request)
        let saved = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(saved.contains("Ripple join"))
    }
}
