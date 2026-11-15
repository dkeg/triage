import XCTest
@testable import TriageCore

final class ProcessTests: XCTestCase {
    func testCwdOfSelf() {
        let cwd = ProcessTree.cwd(of: getpid())
        XCTAssertEqual(cwd.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                       URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path)
    }

    func testPidsNamedFindsSelf() {
        let me = ProcessTree.name(of: getpid())
        XCTAssertFalse(me.isEmpty)
        XCTAssertTrue(ProcessTree.pids(named: me).contains(getpid()))
    }
}

final class AgentNameTests: XCTestCase {
    func testLiveClaudeBinaryIsRecognised() {
        // Any running Claude Code process on this machine must resolve to "claude".
        for pid in ProcessTree.pids(named: "claude") { XCTAssertEqual(ProcessTree.name(of: pid), "claude") }
    }

    func testArgv0OfSelfIsReadable() {
        XCTAssertNotNil(ProcessTree.argv0(of: getpid()))
    }
}

final class ProcessListingTests: XCTestCase {
    /// Regression: proc_listallpids returns a count, not bytes; treating it as bytes dropped every
    /// process beyond the first ~25% of the table (new processes have the highest pids).
    func testNewlySpawnedProcessIsFoundInTheSnapshotAndByName() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        defer { p.terminate() }
        let pid = p.processIdentifier
        XCTAssertTrue(ProcessTable.allPIDs().contains(pid))
        XCTAssertTrue(ProcessTable.snapshot().contains { $0.pid == pid })
        XCTAssertTrue(ProcessTree.pids(named: "sleep").contains(pid))
    }

    func testListingIsNotTruncated() {
        // Every process we can query individually must also be in the list.
        let all = Set(ProcessTable.allPIDs())
        XCTAssertTrue(all.contains(getpid()))
        XCTAssertTrue(all.contains(getppid()) || getppid() <= 1)
        XCTAssertGreaterThan(all.count, 100)
    }
}

