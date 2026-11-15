import AppKit
import TriageCore

/// Turns scanned terminals into session rows, leaving out the ones an agent session already covers.
enum TerminalSessions {
    struct Options {
        var showIdle = false
        var fullArguments = true
    }

    static func rows(from infos: [TerminalInfo], agents: [Session], hostBundles: [Int32: String],
                     ids: inout [Int32: UUID], options: Options) -> [Session] {
        // Anything between a shell and its terminal app that an agent session also passes through
        // (the app itself is shared by every tab, so it doesn't count).
        let agentPIDs = Set(agents.flatMap { ($0.meta?.chain ?? []).map { Int32($0.pid) } })
        let agentTTYs = Set(agents.compactMap { $0.meta?.tty })

        var seen = Set<Int32>()
        var out: [Session] = []
        for info in infos {
            if agentTTYs.contains(info.tty) { continue }
            if info.ancestry.dropLast().contains(where: agentPIDs.contains) { continue }
            if let argv0 = info.foreground?.argv.first, URL(fileURLWithPath: argv0).lastPathComponent == "claude" { continue }
            if info.isIdle && !options.showIdle { continue }

            seen.insert(info.shellPID)
            let id = ids[info.shellPID] ?? UUID()
            ids[info.shellPID] = id

            let name: String
            if let cwd = info.cwd, !cwd.isEmpty {
                name = cwd == NSHomeDirectory() ? "~" : URL(fileURLWithPath: cwd).lastPathComponent
            } else { name = "Terminal" }

            var session = Session(
                id: id, name: name, source: .terminal,
                state: info.isIdle ? .idle : .running,
                detail: info.foreground.map { CommandRedactor.display(argv: $0.argv, fullArguments: options.fullArguments) } ?? "At prompt",
                lastActivity: info.foreground?.start ?? .distantPast,
                cwd: info.cwd,
                meta: TriageMeta(chain: info.ancestry.map { ProcRef(pid: Int($0), name: "") }, tty: info.tty),
                hostBundleID: hostBundles[info.hostPID])
            session.turnStartedAt = info.foreground?.start
            out.append(session)
        }
        ids = ids.filter { seen.contains($0.key) }          // forget tabs that are gone
        return out
    }
}

/// Polls the process table for running terminals. The scan happens off the main thread.
@MainActor
final class TerminalMonitor {
    private unowned let model: IslandModel
    private var timer: Timer?
    private var ids: [Int32: UUID] = [:]
    private var scanning = false

    init(model: IslandModel) { self.model = model }

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    func scan() {
        guard !DemoStory.isEnabled else { return }              // the recorded demo must never show real terminals
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Pref.showTerminals) as? Bool ?? true else {
            if !model.terminals.isEmpty { model.terminals = [] }
            return
        }
        guard !scanning else { return }
        scanning = true
        var hosts: [Int32: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, ApprovalGate.nativePromptHosts.contains(id) { hosts[app.processIdentifier] = id }
        }
        let agents = model.sessions
        let options = TerminalSessions.Options(
            showIdle: defaults.bool(forKey: Pref.showIdleTerminals),
            fullArguments: defaults.object(forKey: Pref.showCommandArguments) as? Bool ?? true)
        Task.detached(priority: .utility) { [weak self] in
            let infos = TerminalScanner.scan(table: ProcessTable.snapshot(), hostPIDs: Set(hosts.keys),
                                             argv: { ProcessTree.argv(of: $0) }, cwd: { ProcessTree.cwd(of: $0) })
            await self?.apply(infos, hosts: hosts, agents: agents, options: options)
        }
    }

    private func apply(_ infos: [TerminalInfo], hosts: [Int32: String], agents: [Session], options: TerminalSessions.Options) {
        let rows = TerminalSessions.rows(from: infos, agents: agents, hostBundles: hosts, ids: &ids, options: options)
        if rows != model.terminals { model.terminals = rows }
        scanning = false
    }
}
