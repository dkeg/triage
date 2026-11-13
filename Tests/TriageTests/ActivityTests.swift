import XCTest
import TriageCore
@testable import Triage

@MainActor
final class ActivityTests: XCTestCase {
    func testToolWording() {
        XCTAssertEqual(Activity.describe(toolName: "Edit", summary: "/a/b/IslandView.swift"), "Editing IslandView.swift")
        XCTAssertEqual(Activity.describe(toolName: "Bash", summary: "swift build"), "Running: swift build")
        XCTAssertEqual(Activity.describe(toolName: "Grep", summary: "TODO"), "Searching: TODO")
        XCTAssertEqual(Activity.describe(toolName: "Read", summary: nil), "Reading")
        XCTAssertEqual(Activity.describe(toolName: "mcp__x__y", summary: "q"), "mcp__x__y q")
        XCTAssertEqual(Activity.describe(toolName: "Bash", summary: String(repeating: "x", count: 100)).count, "Running: ".count + 61)
    }

    func testElapsedAndAgo() {
        XCTAssertEqual(Activity.elapsed(45), "45s")
        XCTAssertEqual(Activity.elapsed(192), "3m 12s")
        XCTAssertEqual(Activity.elapsed(3900), "1h 5m")
        XCTAssertEqual(Activity.ago(10), "just now")
        XCTAssertEqual(Activity.ago(180), "3m ago")
        XCTAssertEqual(Activity.ago(7300), "2h ago")
    }

    private func event(_ json: String) -> HookEvent { HookEvent.decode(Data(json.utf8))! }

    func testTurnTimerAndActivityOnSession() {
        let m = IslandModel()
        m.apply(event(#"{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/x","prompt":"go"}"#))
        XCTAssertNotNil(m.sessions[0].turnStartedAt)
        m.apply(event(#"{"hook_event_name":"PreToolUse","session_id":"s","cwd":"/x","tool_name":"Edit","tool_input":{"file_path":"/x/A.swift"}}"#))
        XCTAssertEqual(m.sessions[0].detail, "Editing A.swift")
        m.apply(event(#"{"hook_event_name":"Stop","session_id":"s","cwd":"/x"}"#))
        XCTAssertNil(m.sessions[0].turnStartedAt)
    }

    func testRichApprovalCard() {
        let m = IslandModel()
        let e = event(#"""
        {"hook_event_name":"PermissionRequest","session_id":"s","cwd":"/Users/example/Projects/Triage","tool_name":"Edit",
         "tool_input":{"file_path":"/x/A.swift","old_string":"let a = 1\nlet b = 2","new_string":"let a = 3"},
         "permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Edit","ruleContent":"/x/**"}],"behavior":"allow","destination":"session"}]}
        """#)
        var always = false
        m.addPermission(e, allowAlways: { always = true }) { _ in }
        let r = m.attention!
        XCTAssertEqual(r.command, "/x/A.swift")
        XCTAssertEqual(r.preview.map(\.kind), [.removed, .removed, .added])
        XCTAssertEqual(r.alwaysSummary, "Edit(/x/**)")
        XCTAssertNotNil(r.location)
        XCTAssertGreaterThan(IslandModel.cardHeight(for: r), 110)
        m.resolveAlways()
        XCTAssertTrue(always); XCTAssertNil(m.attention)
    }

    func testNoSuggestionsMeansNoAlwaysButton() {
        let m = IslandModel()
        m.addPermission(event(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls","description":"List files"}}"#)) { _ in }
        XCTAssertNil(m.attention?.allowAlways)
        XCTAssertEqual(m.attention?.note, "List files")
    }

    func testLongCommandGrowsCard() {
        let short = AttentionRequest(id: UUID(), sessionID: UUID(), title: "", detail: "", decide: { _ in }, command: "ls")
        let long = AttentionRequest(id: UUID(), sessionID: UUID(), title: "", detail: "", decide: { _ in },
                                    command: String(repeating: "a long command ", count: 20))
        XCTAssertGreaterThan(IslandModel.cardHeight(for: long), IslandModel.cardHeight(for: short))
    }
}
