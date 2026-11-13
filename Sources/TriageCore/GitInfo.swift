import Foundation

public enum GitInfo {
    /// Current branch of the repository containing `directory` (nil outside a repo or when
    /// detached). Reads .git/HEAD directly, including worktrees where .git is a file.
    public static func branch(forDirectory directory: String?) -> String? {
        guard var dir = directory.map({ URL(fileURLWithPath: $0) }) else { return nil }
        let fm = FileManager.default
        for _ in 0..<12 {
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                var gitDir = dotGit
                if !isDir.boolValue, let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
                   pointer.hasPrefix("gitdir:") {
                    let p = pointer.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
                    gitDir = p.hasPrefix("/") ? URL(fileURLWithPath: p) : dir.appendingPathComponent(p)
                }
                guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
                let t = head.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "ref: refs/heads/"
                return t.hasPrefix(prefix) ? String(t.dropFirst(prefix.count)) : nil
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
        return nil
    }
}
