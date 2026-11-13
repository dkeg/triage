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
