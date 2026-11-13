import XCTest
@testable import TriageCore

final class DecisionTests: XCTestCase {
    func testAlwaysAllowPassesSuggestionsThroughVerbatim() throws {
        let sugg: [JSONValue] = [.object(["type": .string("addRules"), "behavior": .string("allow"),
                                          "rules": .array([.object(["toolName": .string("Bash"), "ruleContent": .string("swift build:*")])])])]
        let data = HookDecision.permissionResponse(allow: true, updatedPermissions: sugg)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let d = (obj["hookSpecificOutput"] as! [String: Any])["decision"] as! [String: Any]
        XCTAssertEqual(d["behavior"] as? String, "allow")
        let up = d["updatedPermissions"] as! [[String: Any]]
        XCTAssertEqual(up.count, 1)
        XCTAssertEqual(up[0]["type"] as? String, "addRules")
        XCTAssertEqual(((up[0]["rules"] as! [[String: Any]])[0])["ruleContent"] as? String, "swift build:*")
    }

    func testPlainAllowHasNoUpdatedPermissions() throws {
        let obj = try JSONSerialization.jsonObject(with: HookDecision.permissionResponse(allow: true)) as! [String: Any]
        let d = (obj["hookSpecificOutput"] as! [String: Any])["decision"] as! [String: Any]
        XCTAssertNil(d["updatedPermissions"])
    }

    func testGitBranchFromHead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feature/x\n".write(to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        let sub = root.appendingPathComponent("a/b"); try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        XCTAssertEqual(GitInfo.branch(forDirectory: sub.path), "feature/x")
        XCTAssertNil(GitInfo.branch(forDirectory: FileManager.default.temporaryDirectory.path))
    }

    func testGitWorktreeFilePointer() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("wt-\(UUID().uuidString)")
        let gitdir = base.appendingPathComponent("real/.git/worktrees/w"); let wt = base.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: gitdir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wt, withIntermediateDirectories: true)
        try "ref: refs/heads/topic\n".write(to: gitdir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        try "gitdir: \(gitdir.path)\n".write(to: wt.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GitInfo.branch(forDirectory: wt.path), "topic")
    }
}
