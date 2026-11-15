import XCTest
import TriageCore
@testable import Triage

@MainActor
final class TerminalSessionsTests: XCTestCase {
    private func info(shell: Int32, tty: String, host: Int32 = 100, argv: [String]? = ["npm", "run", "dev"],
                      start: TimeInterval = 1000, cwd: String = "/Users/x/api") -> TerminalInfo {
        TerminalInfo(shellPID: shell, hostPID: host, tty: tty, cwd: cwd,
                     foreground: argv.map { TerminalForeground(pid: shell + 1, name: $0[0], argv: $0, start: Date(timeIntervalSince1970: start)) },
                     ancestry: [shell, shell - 1, host])
    }

    func testRunningTerminalBecomesARow() {
        var ids: [Int32: UUID] = [:]
        let rows = TerminalSessions.rows(from: [info(shell: 102, tty: "/dev/ttys001")], agents: [],
                                         hostBundles: [100: "com.mitchellh.ghostty"], ids: &ids, options: .init())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "api")
        XCTAssertEqual(rows[0].detail, "npm run dev")
        XCTAssertEqual(rows[0].state, .running)
        XCTAssertEqual(rows[0].source, .terminal)
        XCTAssertEqual(rows[0].hostBundleID, "com.mitchellh.ghostty")
        XCTAssertEqual(rows[0].meta?.tty, "/dev/ttys001")
        XCTAssertNotNil(rows[0].turnStartedAt)
    }

    func testIdleTerminalsAreHiddenUnlessAsked() {
        var ids: [Int32: UUID] = [:]
        let idle = info(shell: 110, tty: "/dev/ttys002", argv: nil)
        XCTAssertTrue(TerminalSessions.rows(from: [idle], agents: [], hostBundles: [:], ids: &ids, options: .init()).isEmpty)
        var o = TerminalSessions.Options(); o.showIdle = true
        let rows = TerminalSessions.rows(from: [idle], agents: [], hostBundles: [:], ids: &ids, options: o)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].detail, "At prompt")
        XCTAssertEqual(rows[0].state, .idle)
    }

    func testTerminalsRunningAnAgentAreNotListedTwice() {
        var ids: [Int32: UUID] = [:]
        // The agent's hook chain passes through shell 102 (and the shared app 100).
        let agent = Session(name: "triage", source: .claudeCode, state: .running, detail: "",
                            meta: TriageMeta(chain: [ProcRef(pid: 500, name: "claude"), ProcRef(pid: 102, name: "zsh"),
                                                     ProcRef(pid: 101, name: "login"), ProcRef(pid: 100, name: "ghostty")]))
        let sameTab = info(shell: 102, tty: "/dev/ttys001", argv: ["claude"])
        let otherTab = info(shell: 202, tty: "/dev/ttys005")            // shares only the app (100)
        let rows = TerminalSessions.rows(from: [sameTab, otherTab], agents: [agent], hostBundles: [:], ids: &ids, options: .init())
        XCTAssertEqual(rows.map { $0.meta?.tty }, ["/dev/ttys005"])
    }

    func testClaudeInTheForegroundIsExcludedEvenWithoutAHookSession() {
        var ids: [Int32: UUID] = [:]
        let rows = TerminalSessions.rows(from: [info(shell: 302, tty: "/dev/ttys007", argv: ["/Users/x/.local/bin/claude", "-r", "abc"])],
                                         agents: [], hostBundles: [:], ids: &ids, options: .init())
        XCTAssertTrue(rows.isEmpty)
    }

    func testIdsAreStableAcrossScansAndForgottenWhenTabsClose() {
        var ids: [Int32: UUID] = [:]
        let a = TerminalSessions.rows(from: [info(shell: 102, tty: "/dev/ttys001")], agents: [], hostBundles: [:], ids: &ids, options: .init())
        let b = TerminalSessions.rows(from: [info(shell: 102, tty: "/dev/ttys001")], agents: [], hostBundles: [:], ids: &ids, options: .init())
        XCTAssertEqual(a[0].id, b[0].id)
        _ = TerminalSessions.rows(from: [], agents: [], hostBundles: [:], ids: &ids, options: .init())
        XCTAssertTrue(ids.isEmpty)
    }

    func testSecretsInCommandsAreMaskedAndArgumentsCanBeHidden() {
        var ids: [Int32: UUID] = [:]
        let leaky = info(shell: 102, tty: "/dev/ttys001", argv: ["curl", "--token", "abc123", "https://x.io"])
        XCTAssertEqual(TerminalSessions.rows(from: [leaky], agents: [], hostBundles: [:], ids: &ids, options: .init())[0].detail,
                       "curl --token ••• https://x.io")
        var o = TerminalSessions.Options(); o.fullArguments = false
        XCTAssertEqual(TerminalSessions.rows(from: [leaky], agents: [], hostBundles: [:], ids: &ids, options: o)[0].detail, "curl")
    }

    func testHomeFolderIsShownAsTilde() {
        var ids: [Int32: UUID] = [:]
        let rows = TerminalSessions.rows(from: [info(shell: 102, tty: "/dev/ttys001", cwd: NSHomeDirectory())],
                                         agents: [], hostBundles: [:], ids: &ids, options: .init())
        XCTAssertEqual(rows[0].name, "~")
    }
}

@MainActor
final class SectionLayoutTests: XCTestCase {
    private func model(agents: Int, terminals: Int) -> IslandModel {
        let m = IslandModel()
        m.geometry = IslandGeometry(cutout: CGRect(x: 838.5, y: 1093, width: 59, height: 40),
                                    screenFrame: CGRect(x: 0, y: 0, width: 1736, height: 1133), isPhysical: true)
        m.sessions = (0..<agents).map { Session(name: "a\($0)", source: .claudeCode, state: .running, detail: "") }
        m.terminals = (0..<terminals).map { Session(name: "t\($0)", source: .terminal, state: .running, detail: "") }
        m.mode = .expanded
        return m
    }

    func testTwoColumnsOnlyWhenBothKindsExist() {
        XCTAssertFalse(model(agents: 2, terminals: 0).twoColumns)
        XCTAssertFalse(model(agents: 0, terminals: 3).twoColumns)
        XCTAssertTrue(model(agents: 2, terminals: 3).twoColumns)
    }

    func testTwoColumnsAreWiderButNoTallerThanTheLongerColumn() {
        let both = model(agents: 3, terminals: 3)
        let agentsOnly = model(agents: 3, terminals: 0)
        XCTAssertGreaterThan(both.size.width, agentsOnly.size.width)
        XCTAssertEqual(both.size.height, agentsOnly.size.height)          // side by side, not stacked
        XCTAssertLessThanOrEqual(both.size.width, IslandGeometry.canvas.width)
    }

    func testSectionsAreLimitedWithAMoreLine() {
        let m = model(agents: 9, terminals: 2)
        m.rowsPerSection = 4
        XCTAssertEqual(m.visible(m.sessions).count, 4)
        XCTAssertEqual(m.overflow(m.sessions), 5)
        XCTAssertEqual(m.overflow(m.terminals), 0)
        let tall = m.size.height
        m.rowsPerSection = 2
        XCTAssertLessThan(m.size.height, tall)                              // fewer rows, shorter card
        XCTAssertLessThanOrEqual(m.size.height, IslandGeometry.canvas.height)
    }

    func testEmptyStateStillHasHeight() {
        XCTAssertGreaterThan(model(agents: 0, terminals: 0).size.height, 40)
    }

    func testSingleColumnStacksTheSectionsAndKeepsTheNarrowWidth() {
        let m = model(agents: 3, terminals: 2)
        let side = m.size
        m.cardLayout = .single
        XCTAssertFalse(m.twoColumns)
        XCTAssertEqual(m.size.width, IslandModel.expandedWidth)
        XCTAssertLessThan(m.size.width, side.width)
        // Stacked: both sections' heights add up, so it is taller than side by side.
        XCTAssertEqual(m.size.height - side.height, m.sectionHeight(m.terminals), accuracy: 0.5)
        XCTAssertLessThanOrEqual(m.size.height, IslandGeometry.canvas.height)
    }

    func testLayoutChoiceDoesNotAffectSingleKindCards() {
        let a = model(agents: 3, terminals: 0)
        let before = a.size
        a.cardLayout = .single
        XCTAssertEqual(a.size, before)
        let t = model(agents: 0, terminals: 3)
        let tBefore = t.size
        t.cardLayout = .single
        XCTAssertEqual(t.size, tBefore)
    }

    func testTheCardNeverOutgrowsItsPanel() {
        for layout in CardLayout.allCases {
            let m = model(agents: 12, terminals: 12)
            m.cardLayout = layout
            m.rowsPerSection = 8
            XCTAssertLessThanOrEqual(m.size.height, IslandGeometry.canvas.height, "\(layout)")
            // ...even with a tall approval request on top.
            m.addPermission(HookEvent.decode(Data(#"{"hook_event_name":"PermissionRequest","session_id":"p","tool_name":"Bash","tool_input":{"command":"\#(String(repeating: "echo hello ", count: 40))"}}"#.utf8))!) { _ in }
            XCTAssertLessThanOrEqual(m.size.height, IslandGeometry.canvas.height, "\(layout) with a request")
        }
    }

    func testRowsShrinkWhenTheyWouldNotFitAndTheMoreLineCoversTheRest() {
        let m = model(agents: 12, terminals: 12)
        m.cardLayout = .single
        m.rowsPerSection = 8
        XCTAssertLessThan(m.effectiveRows, 8)
        XCTAssertEqual(m.visible(m.sessions).count + m.overflow(m.sessions), 12)
        let roomy = model(agents: 3, terminals: 2)
        roomy.rowsPerSection = 4
        XCTAssertEqual(roomy.effectiveRows, 4)                          // plenty of room: setting honoured
    }
}

