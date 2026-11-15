import XCTest
@testable import TriageCore

final class TerminalScannerTests: XCTestCase {
    private func rec(_ pid: Int32, _ ppid: Int32, _ name: String, pgid: Int32? = nil, tpgid: Int32 = 0,
                     tty: String? = nil, start: TimeInterval? = nil) -> ProcRecord {
        ProcRecord(pid: pid, ppid: ppid, pgid: pgid ?? pid, tpgid: tpgid, tty: tty, name: name,
                   start: start.map { Date(timeIntervalSince1970: $0) })
    }

    /// ghostty(100) -> login(101) -> zsh(102) on ttys001, idle (foreground group is the shell's own)
    func testIdleShellIsFoundButMarkedIdle() {
        let table = [rec(100, 1, "ghostty"), rec(101, 100, "login", tty: "/dev/ttys001"),
                     rec(102, 101, "zsh", pgid: 102, tpgid: 102, tty: "/dev/ttys001")]
        let t = TerminalScanner.scan(table: table, hostPIDs: [100], cwd: { _ in "/Users/x/api" })
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].shellPID, 102)
        XCTAssertEqual(t[0].hostPID, 100)
        XCTAssertTrue(t[0].isIdle)
        XCTAssertEqual(t[0].cwd, "/Users/x/api")
        XCTAssertEqual(t[0].ancestry, [102, 101, 100])
    }

    func testForegroundJobIsReportedWithItsCommand() {
        let table = [rec(100, 1, "ghostty"), rec(102, 100, "zsh", pgid: 102, tpgid: 300, tty: "/dev/ttys001"),
                     rec(300, 102, "node", pgid: 300, tpgid: 300, tty: "/dev/ttys001", start: 1000),
                     rec(301, 300, "node", pgid: 300, tpgid: 300, tty: "/dev/ttys001")]
        let t = TerminalScanner.scan(table: table, hostPIDs: [100],
                                     argv: { $0 == 300 ? ["node", "server.js"] : nil }, cwd: { _ in "/p" })
        XCTAssertFalse(t[0].isIdle)
        XCTAssertEqual(t[0].foreground?.pid, 300)
        XCTAssertEqual(t[0].foreground?.argv, ["node", "server.js"])
    }

    func testNestedShellIsOneTerminalAndIdleWhenItsPromptIsShowing() {
        // zsh(102) -> bash(103) on the same tty; bash is at its prompt, so the tty's foreground group is bash's.
        let table = [rec(100, 1, "kaku-gui"), rec(102, 100, "zsh", pgid: 102, tpgid: 103, tty: "/dev/ttys002"),
                     rec(103, 102, "bash", pgid: 103, tpgid: 103, tty: "/dev/ttys002")]
        let t = TerminalScanner.scan(table: table, hostPIDs: [100])
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].shellPID, 102)               // the outermost shell
        XCTAssertTrue(t[0].isIdle)
    }

    func testShellsOutsideTerminalAppsAreIgnored() {
        let table = [rec(1, 0, "launchd"), rec(50, 1, "sshd"), rec(51, 50, "zsh", tty: "/dev/ttys009"),
                     rec(100, 1, "ghostty"), rec(102, 100, "zsh", tty: "/dev/ttys001")]
        let t = TerminalScanner.scan(table: table, hostPIDs: [100])
        XCTAssertEqual(t.map(\.shellPID), [102])
    }

    func testLoginShellNamesAndOrdering() {
        let table = [rec(100, 1, "Terminal"),
                     rec(110, 100, "-zsh", pgid: 110, tpgid: 110, tty: "/dev/ttys004"),                    // idle
                     rec(120, 100, "-zsh", pgid: 120, tpgid: 321, tty: "/dev/ttys005"),
                     rec(321, 120, "cargo", pgid: 321, tpgid: 321, tty: "/dev/ttys005", start: 2000),
                     rec(130, 100, "-zsh", pgid: 130, tpgid: 322, tty: "/dev/ttys006"),
                     rec(322, 130, "make", pgid: 322, tpgid: 322, tty: "/dev/ttys006", start: 1000)]
        let t = TerminalScanner.scan(table: table, hostPIDs: [100])
        XCTAssertEqual(t.map(\.shellPID), [130, 120, 110])   // longest-running first, idle last
    }

    func testLiveTableHasProcessesAndSelf() {
        let table = ProcessTable.snapshot()
        XCTAssertGreaterThan(table.count, 20)
        XCTAssertTrue(table.contains { $0.pid == getpid() })
        XCTAssertNotNil(table.first { $0.pid == getpid() }?.start)
    }
}

final class CommandRedactorTests: XCTestCase {
    func testPlainCommandsStayReadable() {
        XCTAssertEqual(CommandRedactor.display(argv: ["/usr/local/bin/npm", "run", "dev"]), "npm run dev")
        XCTAssertEqual(CommandRedactor.display(argv: ["-zsh"]), "zsh")
        XCTAssertEqual(CommandRedactor.display(argv: ["ssh", "prod-server"]), "ssh prod-server")
    }

    func testProgramOnlyMode() {
        XCTAssertEqual(CommandRedactor.display(argv: ["ssh", "-i", "key.pem", "prod"], fullArguments: false), "ssh")
    }

    func testSecretFlagsAndAssignmentsAreMasked() {
        XCTAssertEqual(CommandRedactor.display(argv: ["curl", "--token", "abc123", "https://x.io"]), "curl --token ••• https://x.io")
        XCTAssertEqual(CommandRedactor.display(argv: ["tool", "--api-key=abc123"]), "tool --api-key=•••")
        XCTAssertEqual(CommandRedactor.display(argv: ["env", "GITHUB_TOKEN=ghp_abc", "run"]), "env GITHUB_TOKEN=••• run")
        XCTAssertEqual(CommandRedactor.display(argv: ["mysql", "-p", "x"]), "mysql -p x")   // -p alone is ambiguous: not guessed
    }

    func testUrlCredentialsAndOpaqueTokensAreMasked() {
        XCTAssertEqual(CommandRedactor.display(argv: ["git", "clone", "https://user:pw@github.com/a/b.git"]),
                       "git clone https://•••@github.com/a/b.git")
        XCTAssertTrue(CommandRedactor.display(argv: ["x", "sk-abcdefghijklmnop"]).contains("•••"))
        XCTAssertTrue(CommandRedactor.display(argv: ["x", "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5"]).contains("•••"))
        XCTAssertFalse(CommandRedactor.display(argv: ["cd", "my-long-but-ordinary-directory-name-here"]).contains("•••"))
    }

    func testLongCommandsAreTruncated() {
        let long = CommandRedactor.display(argv: ["echo"] + Array(repeating: "word", count: 40), maxLength: 30)
        XCTAssertEqual(long.count, 30)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}
