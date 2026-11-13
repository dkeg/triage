import Foundation
import TriageCore

/// Pure mapping from Claude Code hook events to session changes, kept separate from the
/// UI model so it can be unit tested.
extension IslandModel {
    private func snippet(_ s: String?, _ n: Int = 90) -> String {
        let t = (s ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return t.count > n ? String(t.prefix(n)) + "…" : t
    }

    @discardableResult
    func upsertSession(for e: HookEvent) -> Int? {
        guard let ext = e.sessionID else { return nil }
        // A session we discovered by scanning processes: attach the real session id to it.
        if !sessions.contains(where: { $0.externalID == ext }),
           case let pids = Set((e.triage?.chain ?? []).filter { $0.name == "claude" }.map(\.pid)), !pids.isEmpty,
           let d = sessions.firstIndex(where: { $0.externalID == nil && !$0.agentPIDs.isDisjoint(with: pids) }) {
            sessions[d].externalID = ext
        }
        if let i = sessions.firstIndex(where: { $0.externalID == ext }) {
            if let t = e.sessionTitle, !t.isEmpty { sessions[i].name = t }
            if let c = e.cwd { sessions[i].cwd = c }
            if let m = e.triage {
                sessions[i].meta = m
                if let h = HostApp.bundleID(for: m) { sessions[i].hostBundleID = h }
            }
            return i
        }
        let name = e.sessionTitle ?? e.folderName ?? "Claude Code"
        sessions.append(Session(externalID: ext, name: name, source: .claudeCode, state: .idle, detail: "",
                                cwd: e.cwd, meta: e.triage, hostBundleID: HostApp.bundleID(for: e.triage)))
        return sessions.count - 1
    }

    /// Adds sessions for running `claude` processes we haven't heard from yet, so the island
    /// is useful straight after launch instead of waiting for the next hook event.
    func discover(agents: [(pid: Int, cwd: String?, chain: [ProcRef], tty: String?)]) {
        for a in agents where !sessions.contains(where: { $0.agentPIDs.contains(a.pid) }) {
            let name = a.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code"
            sessions.append(Session(name: name, source: .claudeCode, state: .idle, detail: "Running",
                                    cwd: a.cwd, meta: TriageMeta(chain: a.chain, tty: a.tty),
                                    hostBundleID: HostApp.bundleID(for: TriageMeta(chain: a.chain, tty: a.tty))))
        }
    }

    /// Applies a non-blocking lifecycle event.
    func apply(_ e: HookEvent) {
        if e.eventName == "SessionEnd" {
            if let ext = e.sessionID, let i = sessions.firstIndex(where: { $0.externalID == ext }) {
                dropAnsweredRequests(for: e, sessionID: sessions[i].id)
                sessions.remove(at: i)
            }
            return
        }
        guard let i = upsertSession(for: e) else { return }
        sessions[i].lastActivity = Date()
        // Answered in the app itself (e.g. Subspace's own prompt) rather than here? Then the
        // hook was never hung up on, so spot it from what happens next.
        dropAnsweredRequests(for: e, sessionID: sessions[i].id)
        switch e.eventName {
        case "SessionStart":
            sessions[i].state = .idle
            sessions[i].detail = e.source == "resume" ? "Resumed" : "Started"
        case "UserPromptSubmit":
            sessions[i].state = .running
            sessions[i].turnStartedAt = Date()
            sessions[i].detail = snippet(e.prompt)
        case "PreToolUse":
            // Don't clobber a pending approval for this session.
            if !pending.contains(where: { $0.sessionID == sessions[i].id }) { sessions[i].state = .running }
            sessions[i].detail = Activity.describe(toolName: e.toolName, summary: e.toolSummary)
            if sessions[i].turnStartedAt == nil { sessions[i].turnStartedAt = Date() }
        case "Notification":
            switch e.notificationType {
            case "idle_prompt":
                sessions[i].state = .done
                sessions[i].detail = "Waiting for your next prompt"
            case "elicitation_dialog", "agent_needs_input":
                sessions[i].state = .needsInput
                sessions[i].detail = snippet(e.message)
            case "permission_prompt":
                // Real approvals arrive as PermissionRequest. When another app's own prompt
                // handles one, marking "waiting" here would never be cleared.
                break
            default:
                if let m = e.message, !m.isEmpty { sessions[i].detail = snippet(m) }
            }
        case "PostToolUse", "PostToolUseFailure":
            // A tool finished, so whatever it was waiting on has been answered.
            if !pending.contains(where: { $0.sessionID == sessions[i].id }) { sessions[i].state = .running }
        case "Stop":
            sessions[i].state = .done
            sessions[i].turnStartedAt = nil
            sessions[i].detail = snippet(e.lastAssistantMessage).isEmpty ? "Finished" : snippet(e.lastAssistantMessage)
        default:
            break
        }
    }

    /// Registers a blocking permission request. Returns its id so it can be cancelled.
    @discardableResult
    func addPermission(_ e: HookEvent, canHandBack: Bool = false, release: @escaping () -> Void = {},
                       allowAlways: (() -> Void)? = nil, decide: @escaping (Bool) -> Void) -> UUID? {
        guard let i = upsertSession(for: e) else { return nil }
        let session = sessions[i]
        sessions[i].state = .needsInput
        sessions[i].detail = "Wants to use \(e.toolName ?? "a tool")"
        sessions[i].lastActivity = Date()
        let req = AttentionRequest(id: UUID(), sessionID: session.id,
                                   title: e.toolSummary ?? e.toolName ?? "Permission request",
                                   detail: "\(session.name) wants to use \(e.toolName ?? "a tool")",
                                   decide: decide, canHandBack: canHandBack, hostBundleID: session.hostBundleID, release: release,
                                   command: e.fullCommand, note: e.toolNote, toolName: e.toolName ?? "", toolInput: e.toolInput,
                                   preview: e.diffPreview, location: Self.location(cwd: e.cwd ?? session.cwd),
                                   alwaysSummary: allowAlways == nil ? nil : e.suggestionSummary,
                                   allowAlways: allowAlways)
        pending.append(req)
        return req.id
    }

    /// The client went away (answered in the terminal, or Claude gave up).
    func cancelPermission(_ id: UUID) {
        guard let idx = pending.firstIndex(where: { $0.id == id }) else { return }
        let sid = pending[idx].sessionID
        pending.remove(at: idx)
        markResolved(sessionID: sid)
    }

    /// Removes pending requests that are no longer waiting on anyone: the same tool call finished,
    /// or the turn ended/restarted. Closes their hooks so nothing is left hanging.
    @discardableResult
    func dropAnsweredRequests(for e: HookEvent, sessionID: UUID) -> Int {
        var dropped: [AttentionRequest] = []
        pending.removeAll { r in
            guard r.sessionID == sessionID else { return false }
            let answered: Bool
            switch e.eventName {
            case "PostToolUse", "PostToolUseFailure":
                // Same call: identical input, or the same command/path (the completion event can carry a
                // slightly different input object than the request did).
                answered = r.toolName == (e.toolName ?? "")
                    && (r.toolInput == e.toolInput || (!r.command.isEmpty && r.command == e.fullCommand))
            case "Stop", "UserPromptSubmit", "SessionEnd":
                answered = true
            default:
                answered = false
            }
            if answered { dropped.append(r) }
            return answered
        }
        dropped.forEach { $0.release() }
        return dropped.count
    }

    /// "folder · branch" for a working directory.
    static func location(cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        guard let branch = GitInfo.branch(forDirectory: cwd) else { return folder }
        return "\(folder) · \(branch)"
    }

    /// Hands a pending request back to the app's own prompt.
    func release(id: UUID) {
        guard let idx = pending.firstIndex(where: { $0.id == id }), pending[idx].canHandBack else { return }
        let req = pending.remove(at: idx)
        req.release()
        markResolved(sessionID: req.sessionID)
    }

    /// Drops sessions whose agent process has exited (crash, kill -9: no SessionEnd), and
    /// long-silent sessions we can't check.
    func pruneDead(isAlive: (Int) -> Bool, now: Date = Date(), maxIdle: TimeInterval = 12 * 3600) {
        let dead = sessions.filter { s in
            if !s.agentPIDs.isEmpty { return !s.agentPIDs.contains(where: isAlive) }
            return now.timeIntervalSince(s.lastActivity) > maxIdle
        }
        guard !dead.isEmpty else { return }
        let ids = Set(dead.map(\.id))
        pending.removeAll { ids.contains($0.sessionID) }
        sessions.removeAll { ids.contains($0.id) }
    }

    func markResolved(sessionID: UUID) {
        if let i = sessions.firstIndex(where: { $0.id == sessionID }),
           !pending.contains(where: { $0.sessionID == sessionID }) {
            sessions[i].state = .running
        }
    }
}
