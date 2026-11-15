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
        XCTAssertEqual(m.sessions[0].detail, "Running: swift build")
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

    func testHostAppFromTerminalEnvironment() {
        let e = HookEvent.decode(Data(#"{"hook_event_name":"SessionStart","session_id":"k","cwd":"/a","_triage":{"chain":[],"env":{"__CFBundleIdentifier":"fun.tw93.kaku"}}}"#.utf8))!
        let m = IslandModel()
        m.apply(e)
        XCTAssertEqual(m.sessions[0].hostBundleID, "fun.tw93.kaku")
        var released = false
        let id = m.addPermission(HookEvent.decode(Data(#"{"hook_event_name":"PermissionRequest","session_id":"k","tool_name":"Bash"}"#.utf8))!,
                                 canHandBack: true, release: { released = true }) { _ in }!
        XCTAssertEqual(m.pending.first?.hostBundleID, "fun.tw93.kaku")
        XCTAssertTrue(ApprovalGate.canHandBack(hostBundleID: "fun.tw93.kaku"))
        m.release(id: id); XCTAssertTrue(released)
    }

    func testNestedClaudeProcessesDoNotDuplicateASession() {
        let m = IslandModel()
        // Process scan finds the outer claude (100); the hook sees the nearer wrapper (101) then the outer.
        m.discover(agents: [(pid: 100, cwd: "/p/triage", chain: [ProcRef(pid: 100, name: "claude")], tty: nil)])
        let e = HookEvent.decode(Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"real","cwd":"/p/triage","prompt":"x","_triage":{"chain":[{"pid":9,"name":"sh"},{"pid":101,"name":"claude"},{"pid":100,"name":"claude"}]}}"#.utf8))!
        m.apply(e)
        XCTAssertEqual(m.sessions.count, 1)
        XCTAssertEqual(m.sessions[0].externalID, "real")
        // Re-scanning must not add it back.
        m.discover(agents: [(pid: 100, cwd: "/p/triage", chain: [ProcRef(pid: 100, name: "claude")], tty: nil)])
        XCTAssertEqual(m.sessions.count, 1)
        // The wrapper exiting alone does not prune the session while the outer one lives.
        m.pruneDead(isAlive: { $0 == 100 })
        XCTAssertEqual(m.sessions.count, 1)
    }

    func testApprovingInTheAppClearsTheStuckRequestWhenTheToolFinishes() {
        let m = IslandModel()
        var closed = false
        m.addPermission(event("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"ls"}"#), release: { closed = true }) { _ in }
        XCTAssertEqual(m.pending.count, 1)
        m.apply(event("PostToolUse", #","tool_name":"Bash","tool_input":{"command":"ls"}"#))
        XCTAssertTrue(m.pending.isEmpty)
        XCTAssertTrue(closed)                       // the hook is released, not left hanging
        XCTAssertEqual(m.sessions[0].state, .running)
    }

    func testAnotherToolFinishingDoesNotClearAnUnansweredRequest() {
        let m = IslandModel()
        m.addPermission(event("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"rm x"}"#)) { _ in }
        m.apply(event("PostToolUse", #","tool_name":"Read","tool_input":{"file_path":"/a"}"#))          // parallel tool
        m.apply(event("PostToolUse", #","tool_name":"Bash","tool_input":{"command":"ls"}"#))            // different command
        XCTAssertEqual(m.pending.count, 1)
    }

    func testTurnEndingOrRestartingClearsPendingRequests() {
        for endEvent in ["Stop", "UserPromptSubmit", "SessionEnd"] {
            let m = IslandModel()
            var closed = false
            m.addPermission(event("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"ls"}"#), release: { closed = true }) { _ in }
            m.apply(event(endEvent))
            XCTAssertTrue(m.pending.isEmpty, endEvent)
            XCTAssertTrue(closed, endEvent)
        }
    }

    func testCompletionWithSlightlyDifferentInputStillClearsTheRequest() {
        let m = IslandModel()
        m.addPermission(event("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"swift build","description":"Build it","timeout":120000}"#)) { _ in }
        m.apply(event("PostToolUse", #","tool_name":"Bash","tool_input":{"command":"swift build"}"#))
        XCTAssertTrue(m.pending.isEmpty)
    }

    func testOnlyApprovalsAndQuestionsCountAsWaiting() {
        let m = IslandModel()
        m.apply(event("Stop", session: "done", #","last_assistant_message":"finished""#))          // finished, awaiting a prompt
        XCTAssertEqual(m.waitingCount, 0)
        m.addPermission(event("PermissionRequest", session: "ask", #","tool_name":"Bash""#)) { _ in }
        XCTAssertEqual(m.waitingCount, 1)                                                           // approval
        m.apply(event("Notification", session: "q", #","notification_type":"elicitation_dialog","message":"Pick one""#))
        XCTAssertEqual(m.waitingCount, 2)                                                           // question
        m.apply(event("Notification", session: "idle", #","notification_type":"idle_prompt""#))
        XCTAssertEqual(m.waitingCount, 2)                                                           // idle prompt does not count
    }

    func testPillShowsEvenWithNoSessions() {
        let m = IslandModel()
        m.geometry = IslandGeometry(cutout: CGRect(x: 838.5, y: 1093, width: 59, height: 40),
                                    screenFrame: CGRect(x: 0, y: 0, width: 1736, height: 1133), isPhysical: true)
        XCTAssertTrue(m.sessions.isEmpty)
        XCTAssertNotEqual(m.size, .zero)
        m.mode = .expanded
        XCTAssertGreaterThan(m.size.height, 0)
    }

    func testWideningIsAppliedImmediatelyNarrowingNeedsConfirmation() {
        let m = IslandModel()
        m.ingestIslandReading(58)
        XCTAssertEqual(m.measuredIslandWidth, 58)             // first reading accepted
        m.ingestIslandReading(150)                            // e.g. the charging island opens
        XCTAssertEqual(m.measuredIslandWidth, 150)            // pill moves at once
        m.ingestIslandReading(100)                            // closing, caught mid-animation
        XCTAssertEqual(m.measuredIslandWidth, 150)            // not applied yet
        m.ingestIslandReading(58)
        XCTAssertEqual(m.measuredIslandWidth, 150)            // still not: 100 and 58 disagree
        m.ingestIslandReading(58)
        XCTAssertEqual(m.measuredIslandWidth, 58)             // two agreeing readings
    }

    func testUnreadableFramesKeepTheLastGoodValue() {
        let m = IslandModel()
        m.ingestIslandReading(137)
        m.ingestIslandReading(nil); m.ingestIslandReading(nil)
        XCTAssertEqual(m.measuredIslandWidth, 137)
    }

    func testHugeReadingsNeedConfirmationBeforeHidingThePill() {
        let m = IslandModel()
        m.ingestIslandReading(58)
        m.ingestIslandReading(500)                            // could be a glitch
        XCTAssertFalse(m.yielding)
        m.ingestIslandReading(502)                            // Spotlight really is open
        XCTAssertTrue(m.yielding)
        m.ingestIslandReading(58); m.ingestIslandReading(58)
        XCTAssertFalse(m.yielding)
    }
}
