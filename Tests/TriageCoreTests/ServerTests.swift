import XCTest
@testable import TriageCore

final class ServerTests: XCTestCase {
    private func tempSocket() -> String { "/tmp/triage-test-\(UUID().uuidString.prefix(8)).sock" }

    func testRoundTripReply() throws {
        let path = tempSocket()
        let server = HookServer(path: path) { data, conn in
            conn.reply(Data("echo:".utf8) + data)
        }
        try server.start(); defer { server.stop() }
        let reply = HookClient.send(Data("hi".utf8), socketPath: path)
        XCTAssertEqual(reply, Data("echo:hi".utf8))
    }

    func testNoServerReturnsNil() {
        XCTAssertNil(HookClient.send(Data("x".utf8), socketPath: tempSocket()))
    }

    func testDeferredReplyBlocksClientUntilAnswered() throws {
        let path = tempSocket()
        let held = Box<HookConnection>()
        let arrived = expectation(description: "request arrived")
        let server = HookServer(path: path) { _, conn in held.value = conn; arrived.fulfill() }
        try server.start(); defer { server.stop() }

        let done = expectation(description: "client got reply")
        var got: Data?
        DispatchQueue.global().async { got = HookClient.send(Data("ask".utf8), socketPath: path); done.fulfill() }
        wait(for: [arrived], timeout: 2)
        held.value?.reply(Data("yes".utf8))
        wait(for: [done], timeout: 2)
        XCTAssertEqual(got, Data("yes".utf8))
    }

    func testClientHangupFiresOnClose() throws {
        let path = tempSocket()
        let held = Box<HookConnection>()
        let arrived = expectation(description: "arrived")
        let server = HookServer(path: path) { _, conn in held.value = conn; arrived.fulfill() }
        try server.start(); defer { server.stop() }

        // Raw client that sends a frame then vanishes without reading the reply.
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        _ = Wire.withSockAddr(path) { connect(fd, $0, $1) }
        XCTAssertTrue(Wire.writeFrame(fd, Data("ask".utf8)))
        wait(for: [arrived], timeout: 2)

        let closed = expectation(description: "closed")
        held.value?.setOnClose { closed.fulfill() }
        close(fd)
        wait(for: [closed], timeout: 2)
    }

    func testEnrichAddsMeta() throws {
        let raw = Data(#"{"hook_event_name":"Stop","session_id":"s1"}"#.utf8)
        let out = HookClient.enrich(raw, ppid: 42, environment: ["TERM_PROGRAM": "ghostty", "SECRET": "no"])
        let e = try XCTUnwrap(HookEvent.decode(out))
        XCTAssertEqual(e.triage?.ppid, 42)
        XCTAssertEqual(e.triage?.env?["TERM_PROGRAM"], "ghostty")
        XCTAssertNil(e.triage?.env?["SECRET"])
    }

    func testPermissionResponseShape() throws {
        let allow = try JSONSerialization.jsonObject(with: HookDecision.permissionResponse(allow: true)) as! [String: Any]
        let out = allow["hookSpecificOutput"] as! [String: Any]
        XCTAssertEqual(out["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual((out["decision"] as! [String: Any])["behavior"] as? String, "allow")
        let deny = try JSONSerialization.jsonObject(with: HookDecision.permissionResponse(allow: false, message: "no")) as! [String: Any]
        let d = (deny["hookSpecificOutput"] as! [String: Any])["decision"] as! [String: Any]
        XCTAssertEqual(d["behavior"] as? String, "deny"); XCTAssertEqual(d["message"] as? String, "no")
    }
}

final class Box<T>: @unchecked Sendable { var value: T? }
