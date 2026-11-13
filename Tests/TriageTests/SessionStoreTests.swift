import XCTest
import TriageCore
@testable import Triage

@MainActor
final class SessionStoreTests: XCTestCase {
    private func event(_ name: String, session: String = "s1", _ extra: String = "") -> HookEvent {
        HookEvent.decode(Data(#"{"hook_event_name":"\#(name)","session_id":"\#(session)","cwd":"/Users/x/triage"\#(extra)}"#.utf8))!
    }

    func testLifecycle() {
        let m = IslandModel()
        m.apply(event("SessionStart", #","source":"startup""#))
        XCTAssertEqual(m.sessions.count, 1)
        XCTAssertEqual(m.sessions[0].name, "triage")
        m.apply(event("UserPromptSubmit", #","prompt":"fix the bug""#))
        XCTAssertEqual(m.sessions[0].state, .running)
        XCTAssertEqual(m.sessions[0].detail, "fix the bug")
        m.apply(event("PreToolUse", #","tool_name":"Bash","tool_input":{"command":"swift build"}"#))
        XCTAssertEqual(m.sessions[0].detail, "Bash: swift build")
        m.apply(event("Stop", #","last_assistant_message":"All done""#))
        XCTAssertEqual(m.sessions[0].state, .done)
        m.apply(event("SessionEnd"))
        XCTAssertTrue(m.sessions.isEmpty)
    }

    func testUnknownSessionIsAdoptedMidFlight() {
        let m = IslandModel()
        m.apply(event("Stop", session: "late"))
        XCTAssertEqual(m.sessions.count, 1)
    }

    func testPermissionApproveDecidesAndClears() {
        let m = IslandModel()
        var answer: Bool?
        m.addPermission(event("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"rm -rf x"}"#)) { answer = $0 }
        XCTAssertEqual(m.sessions[0].state, .needsInput)
        XCTAssertEqual(m.attention?.title, "rm -rf x")
        m.resolve(approve: true)
        XCTAssertEqual(answer, true)
        XCTAssertNil(m.attention)
        XCTAssertEqual(m.sessions[0].state, .running)
    }

    func testPreToolUseDoesNotClobberPendingApproval() {
        let m = IslandModel()
        m.addPermission(event("PermissionRequest", #","tool_name":"Bash""#)) { _ in }
        m.apply(event("PreToolUse", #","tool_name":"Read""#))
        XCTAssertEqual(m.sessions[0].state, .needsInput)
    }

    func testCancelledPermissionDoesNotInvokeDecision() {
        let m = IslandModel()
        var called = false
        let id = m.addPermission(event("PermissionRequest", #","tool_name":"Bash""#)) { _ in called = true }!
        m.cancelPermission(id)
        XCTAssertFalse(called)
        XCTAssertNil(m.attention)
        XCTAssertEqual(m.sessions[0].state, .running)
    }

    func testQueueResolvesOldestFirst() {
        let m = IslandModel()
        var order: [String] = []
        m.addPermission(event("PermissionRequest", session: "a", #","tool_name":"Bash""#)) { _ in order.append("a") }
        m.addPermission(event("PermissionRequest", session: "b", #","tool_name":"Bash""#)) { _ in order.append("b") }
        m.resolve(approve: true); m.resolve(approve: false)
        XCTAssertEqual(order, ["a", "b"])
    }

    func testSessionEndDropsItsPendingRequests() {
        let m = IslandModel()
        m.addPermission(event("PermissionRequest", #","tool_name":"Bash""#)) { _ in }
        m.apply(event("SessionEnd"))
        XCTAssertTrue(m.pending.isEmpty)
    }
}
