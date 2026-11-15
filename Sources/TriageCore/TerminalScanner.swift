import Foundation

public struct TerminalForeground: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    public var argv: [String]
    public var start: Date?

    public init(pid: Int32, name: String, argv: [String], start: Date? = nil) {
        self.pid = pid; self.name = name; self.argv = argv; self.start = start
    }
}

/// A terminal tab or window: a shell on its own tty, hosted by a terminal app.
public struct TerminalInfo: Equatable, Sendable {
    public var shellPID: Int32
    public var hostPID: Int32
    public var tty: String
    public var cwd: String?
    /// What is running in the foreground, or nil when the shell is sitting at its prompt.
    public var foreground: TerminalForeground?
    /// Every process id from the shell up to the host app (for matching against agent sessions).
    public var ancestry: [Int32]

    public var isIdle: Bool { foreground == nil }

    public init(shellPID: Int32, hostPID: Int32, tty: String, cwd: String?,
                foreground: TerminalForeground?, ancestry: [Int32]) {
        self.shellPID = shellPID; self.hostPID = hostPID; self.tty = tty; self.cwd = cwd
        self.foreground = foreground; self.ancestry = ancestry
    }
}

public enum TerminalScanner {
    public static let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh", "nu", "xonsh", "elvish"]

    /// Finds the terminals running under `hostPIDs` (the terminal apps' own processes).
    ///
    /// - Parameters:
    ///   - argv: argv of a process; only asked for foreground jobs.
    ///   - cwd: working directory of a process.
    public static func scan(table: [ProcRecord], hostPIDs: Set<Int32>,
                            argv: (Int32) -> [String]? = { _ in nil },
                            cwd: (Int32) -> String? = { _ in nil }) -> [TerminalInfo] {
        let byPID = Dictionary(table.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        func isShell(_ name: String) -> Bool {
            shellNames.contains(name.hasPrefix("-") ? String(name.dropFirst()) : name)
        }
        /// Walks up to a host app; returns it and the chain from the shell to it.
        func hostChain(of rec: ProcRecord) -> (host: Int32, chain: [Int32])? {
            var chain = [rec.pid], cur = rec
            for _ in 0..<12 {
                guard let parent = byPID[cur.ppid], parent.pid > 1 else { return nil }
                chain.append(parent.pid)
                if hostPIDs.contains(parent.pid) { return (parent.pid, chain) }
                cur = parent
            }
            return nil
        }

        // One terminal per tty: the outermost shell on it (a nested shell shares the tty).
        var byTTY: [String: (rec: ProcRecord, host: Int32, chain: [Int32])] = [:]
        for rec in table where rec.tty != nil && isShell(rec.name) {
            guard let tty = rec.tty, let found = hostChain(of: rec) else { continue }
            if let existing = byTTY[tty], existing.rec.pid < rec.pid { continue }
            byTTY[tty] = (rec, found.host, found.chain)
        }

        var out: [TerminalInfo] = []
        for (tty, entry) in byTTY {
            let shell = entry.rec
            var foreground: TerminalForeground?
            if shell.tpgid > 0, shell.tpgid != shell.pgid {
                let leader = byPID[shell.tpgid]
                    ?? table.filter { $0.pgid == shell.tpgid && $0.tty == tty }.min { $0.pid < $1.pid }
                if let leader, !isShell(leader.name) {            // a nested shell at its prompt is still idle
                    foreground = TerminalForeground(pid: leader.pid, name: leader.name,
                                                    argv: argv(leader.pid) ?? [leader.name], start: leader.start)
                }
            }
            out.append(TerminalInfo(shellPID: shell.pid, hostPID: entry.host, tty: tty,
                                    cwd: cwd(foreground?.pid ?? shell.pid) ?? cwd(shell.pid),
                                    foreground: foreground, ancestry: entry.chain))
        }
        // Running first (longest-running at the top), then idle by tty for a stable order.
        return out.sorted {
            switch ($0.foreground, $1.foreground) {
            case let (a?, b?): return (a.start ?? .distantFuture) < (b.start ?? .distantFuture)
            case (.some, .none): return true
            case (.none, .some): return false
            default: return $0.tty < $1.tty
            }
        }
    }
}
