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

    func testApprovalGateOnlyBypassesTerminalsThatShowNativePrompt() {
        let t = "com.apple.Terminal"
        XCTAssertTrue(ApprovalGate.shouldBypass(enabled: true, hostBundleID: t, frontmostBundleID: t))
        XCTAssertFalse(ApprovalGate.shouldBypass(enabled: true, hostBundleID: t, frontmostBundleID: "x"))
        XCTAssertFalse(ApprovalGate.shouldBypass(enabled: false, hostBundleID: t, frontmostBundleID: t))
        // Subspace-hosted sessions must never get an empty answer (it can act as a denial).
        XCTAssertFalse(ApprovalGate.shouldBypass(enabled: true, hostBundleID: "com.subspace.app",
                                                 frontmostBundleID: "com.subspace.app"))
        XCTAssertFalse(ApprovalGate.shouldBypass(enabled: true, hostBundleID: nil, frontmostBundleID: nil))
        XCTAssertTrue(ApprovalGate.canHandBack(hostBundleID: "com.googlecode.iterm2"))
        XCTAssertFalse(ApprovalGate.canHandBack(hostBundleID: "com.subspace.app"))
    }

    func testExpandedIsWiderThanCollapsed() {
        let m = IslandModel()
        m.geometry = IslandGeometry(cutout: CGRect(x: 838.5, y: 1093, width: 59, height: 40),
                                    screenFrame: CGRect(x: 0, y: 0, width: 1736, height: 1133), isPhysical: true)
        m.sessions = IslandModel.mockSessions()
        m.mode = .expanded
        XCTAssertEqual(m.size.width, IslandModel.expandedWidth)
        XCTAssertLessThanOrEqual(IslandModel.expandedWidth, IslandGeometry.canvas.width)
    }

    func testPermissionNotificationDoesNotLeaveStaleWaiting() {
        let m = IslandModel()
        m.apply(event("Notification", #","notification_type":"permission_prompt","message":"needs permission""#))
        XCTAssertNotEqual(m.sessions[0].state, .needsInput)
    }

    func testElicitationMarksWaitingAndToolCompletionClearsIt() {
        let m = IslandModel()
        m.apply(event("Notification", #","notification_type":"elicitation_dialog","message":"Pick one""#))
        XCTAssertEqual(m.sessions[0].state, .needsInput)
        m.apply(event("PostToolUse", #","tool_name":"AskUserQuestion""#))
        XCTAssertEqual(m.sessions[0].state, .running)
    }

    func testReleaseOnlyWhenHandBackIsSafe() {
        let m = IslandModel()
        var released = false
        let unsafe = m.addPermission(event("PermissionRequest", session: "u", #","tool_name":"Bash""#),
                                     canHandBack: false, release: { released = true }) { _ in }!
        m.release(id: unsafe)
        XCTAssertFalse(released); XCTAssertEqual(m.pending.count, 1)   // stays until answered
        let safe = m.addPermission(event("PermissionRequest", session: "s", #","tool_name":"Bash""#),
                                   canHandBack: true, release: { released = true }) { _ in }!
        m.release(id: safe)
        XCTAssertTrue(released); XCTAssertEqual(m.pending.count, 1)
    }

    func testPruneDeadSessions() {
        let m = IslandModel()
        let live = HookEvent.decode(Data(#"{"hook_event_name":"SessionStart","session_id":"live","cwd":"/a","_triage":{"chain":[{"pid":10,"name":"sh"},{"pid":111,"name":"claude"}]}}"#.utf8))!
        let dead = HookEvent.decode(Data(#"{"hook_event_name":"SessionStart","session_id":"dead","cwd":"/b","_triage":{"chain":[{"pid":10,"name":"sh"},{"pid":222,"name":"claude"}]}}"#.utf8))!
        m.apply(live); m.apply(dead)
        m.addPermission(dead) { _ in }
        m.pruneDead(isAlive: { $0 == 111 })
        XCTAssertEqual(m.sessions.map(\.externalID), ["live"])
        XCTAssertTrue(m.pending.isEmpty)
    }

    func testDiscoveredSessionIsAdoptedByFirstHookEvent() {
        let m = IslandModel()
        m.discover(agents: [(pid: 4242, cwd: "/Users/x/triage", chain: [ProcRef(pid: 4242, name: "claude")], tty: nil)])
        XCTAssertEqual(m.sessions.count, 1)
        XCTAssertEqual(m.sessions[0].name, "triage")
        XCTAssertNil(m.sessions[0].externalID)
        let e = HookEvent.decode(Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"real","cwd":"/Users/x/triage","prompt":"hi","_triage":{"chain":[{"pid":9,"name":"sh"},{"pid":4242,"name":"claude"}]}}"#.utf8))!
        m.apply(e)
        XCTAssertEqual(m.sessions.count, 1)               // adopted, not duplicated
        XCTAssertEqual(m.sessions[0].externalID, "real")
        XCTAssertEqual(m.sessions[0].state, .running)
    }

    func testDiscoverIsIdempotent() {
        let m = IslandModel()
        let a = [(pid: 1, cwd: "/a" as String?, chain: [ProcRef(pid: 1, name: "claude")], tty: nil as String?)]
        m.discover(agents: a); m.discover(agents: a)
        XCTAssertEqual(m.sessions.count, 1)
    }

    func testDemoSessionDisappearsWhenAnswered() {
        let m = IslandModel()
        m.simulateAttention()
        XCTAssertEqual(m.sessions.count, 1)
        m.resolve(approve: true)
        XCTAssertTrue(m.sessions.isEmpty)
    }
}
