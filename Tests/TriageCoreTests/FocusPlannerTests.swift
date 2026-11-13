import XCTest
@testable import TriageCore

final class FocusPlannerTests: XCTestCase {
    let topics = [TopicRef(id: "root", path: "/Users/x/Projects/Triage"),
                  TopicRef(id: "wt", path: "/Users/x/Projects/Triage/.worktrees/feature"),
                  TopicRef(id: "other", path: "/Users/x/Projects/TriageExtra")]

    func testLongestPrefixWins() {
        XCTAssertEqual(FocusPlanner.topic(for: "/Users/x/Projects/Triage/.worktrees/feature/src", in: topics)?.id, "wt")
        XCTAssertEqual(FocusPlanner.topic(for: "/Users/x/Projects/Triage/Sources", in: topics)?.id, "root")
    }

    func testPrefixRequiresPathBoundary() {
        XCTAssertEqual(FocusPlanner.topic(for: "/Users/x/Projects/TriageExtra/a", in: topics)?.id, "other")
        XCTAssertNil(FocusPlanner.topic(for: "/Users/x/Projects/Tri", in: topics))
    }

    func testSubspacePlans() {
        XCTAssertEqual(FocusPlanner.plan(hostBundleID: "com.subspace.app", meta: nil,
                                         cwd: "/Users/x/Projects/Triage", topics: topics),
                       .subspaceTopic(id: "root", bundleID: "com.subspace.app"))
        XCTAssertEqual(FocusPlanner.plan(hostBundleID: "com.subspace.app", meta: nil, cwd: "/elsewhere", topics: topics),
                       .app(bundleID: "com.subspace.app"))
    }

    func testTerminalAndITerm() {
        XCTAssertEqual(FocusPlanner.plan(hostBundleID: "com.apple.Terminal", meta: TriageMeta(tty: "/dev/ttys004"),
                                         cwd: nil, topics: []), .terminalTab(tty: "/dev/ttys004"))
        let meta = TriageMeta(env: ["ITERM_SESSION_ID": "w0t1p0:ABC-123"])
        XCTAssertEqual(FocusPlanner.plan(hostBundleID: "com.googlecode.iterm2", meta: meta, cwd: nil, topics: []),
                       .itermSession(guid: "ABC-123"))
    }

    func testOtherAppsJustActivate() {
        XCTAssertEqual(FocusPlanner.plan(hostBundleID: "com.mitchellh.ghostty", meta: nil, cwd: nil, topics: []),
                       .app(bundleID: "com.mitchellh.ghostty"))
        XCTAssertEqual(FocusPlanner.plan(hostBundleID: nil, meta: nil, cwd: nil, topics: []), .unknown)
    }

    func testParseTopicsSkipsLogLineAndArchived() {
        let out = Data("""
        [database] Using override: /x
        [{"id":"a","path":"/p/a","isArchived":false},{"id":"b","path":"/p/b","isArchived":true}]
        """.utf8)
        XCTAssertEqual(FocusPlanner.parseTopics(out), [TopicRef(id: "a", path: "/p/a")])
    }

    func testEnrichCapturesRealProcessChain() throws {
        let raw = Data(#"{"hook_event_name":"Stop"}"#.utf8)
        let out = HookClient.enrich(raw)
        let e = try XCTUnwrap(HookEvent.decode(out))
        XCTAssertFalse((e.triage?.chain ?? []).isEmpty)
        XCTAssertEqual(e.triage?.chain?.first?.pid, Int(getppid()))
    }
}
