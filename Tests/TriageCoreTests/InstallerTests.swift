import XCTest
@testable import TriageCore

final class InstallerTests: XCTestCase {
    private var dir: URL!
    private var settings: URL { dir.appendingPathComponent("settings.json") }
    private let helper = URL(fileURLWithPath: "/tmp/Triage/bin/triage-hook")

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("triage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func json() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    }

    private let existing = """
    {"theme":"dark","permissions":{"allow":["Bash(ls)"]},
     "hooks":{"PermissionRequest":[{"matcher":"*","hooks":[{"type":"command","command":"/bin/other-tool","timeout":86400}]}],
              "Notification":[{"hooks":[{"type":"command","command":"/bin/notify"}]}]}}
    """

    func testInstallPreservesExistingHooksAndSettings() throws {
        try existing.write(to: settings, atomically: true, encoding: .utf8)
        try HookInstaller.install(settings: settings, helper: helper)
        let obj = try json()
        XCTAssertEqual(obj["theme"] as? String, "dark")
        XCTAssertNotNil(obj["permissions"])
        let hooks = obj["hooks"] as! [String: Any]
        let perm = hooks["PermissionRequest"] as! [[String: Any]]
        XCTAssertEqual(perm.count, 2)
        XCTAssertTrue(String(describing: perm).contains("/bin/other-tool"))
        XCTAssertTrue(HookInstaller.isInstalled(settings: settings))
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.appendingPathExtension("triage-backup").path))
    }

    func testPermissionHookIsBlockingOthersAsync() throws {
        try HookInstaller.install(settings: settings, helper: helper)
        let hooks = try json()["hooks"] as! [String: [[String: Any]]]
        func handler(_ e: String) -> [String: Any] { (hooks[e]![0]["hooks"] as! [[String: Any]])[0] }
        XCTAssertNil(handler("PermissionRequest")["async"])
        XCTAssertEqual(handler("Stop")["async"] as? Bool, true)
    }

    func testInstallIsIdempotent() throws {
        try existing.write(to: settings, atomically: true, encoding: .utf8)
        try HookInstaller.install(settings: settings, helper: helper)
        try HookInstaller.install(settings: settings, helper: helper)
        let hooks = try json()["hooks"] as! [String: [[String: Any]]]
        XCTAssertEqual(hooks["PermissionRequest"]!.count, 2)
        XCTAssertEqual(hooks["Stop"]!.count, 1)
    }

    func testUninstallRestoresOthers() throws {
        try existing.write(to: settings, atomically: true, encoding: .utf8)
        try HookInstaller.install(settings: settings, helper: helper)
        try HookInstaller.uninstall(settings: settings)
        let hooks = try json()["hooks"] as! [String: [[String: Any]]]
        XCTAssertEqual(Set(hooks.keys), ["PermissionRequest", "Notification"])
        XCTAssertEqual(hooks["PermissionRequest"]!.count, 1)
        XCTAssertFalse(HookInstaller.isInstalled(settings: settings))
    }

    func testInstallOnMissingFile() throws {
        try HookInstaller.install(settings: settings, helper: helper)
        XCTAssertTrue(HookInstaller.isInstalled(settings: settings))
    }
}
