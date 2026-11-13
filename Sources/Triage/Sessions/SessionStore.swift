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
        if let i = sessions.firstIndex(where: { $0.externalID == ext }) {
            if let t = e.sessionTitle, !t.isEmpty { sessions[i].name = t }
            if let c = e.cwd { sessions[i].cwd = c }
            if let m = e.triage { sessions[i].meta = m }
            return i
        }
        let name = e.sessionTitle ?? e.folderName ?? "Claude Code"
        sessions.append(Session(externalID: ext, name: name, source: .claudeCode, state: .idle, detail: "",
                                cwd: e.cwd, meta: e.triage))
        return sessions.count - 1
    }

    /// Applies a non-blocking lifecycle event.
    func apply(_ e: HookEvent) {
        if e.eventName == "SessionEnd" {
            if let ext = e.sessionID, let i = sessions.firstIndex(where: { $0.externalID == ext }) {
                pending.removeAll { $0.sessionID == sessions[i].id }
                sessions.remove(at: i)
            }
            return
        }
        guard let i = upsertSession(for: e) else { return }
        sessions[i].lastActivity = Date()
        switch e.eventName {
        case "SessionStart":
            sessions[i].state = .idle
            sessions[i].detail = e.source == "resume" ? "Resumed" : "Started"
        case "UserPromptSubmit":
            sessions[i].state = .running
            sessions[i].detail = snippet(e.prompt)
        case "PreToolUse":
            // Don't clobber a pending approval for this session.
            if !pending.contains(where: { $0.sessionID == sessions[i].id }) { sessions[i].state = .running }
            sessions[i].detail = [e.toolName, snippet(e.toolSummary, 70)].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: ": ")
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
            sessions[i].detail = snippet(e.lastAssistantMessage).isEmpty ? "Finished" : snippet(e.lastAssistantMessage)
        default:
            break
        }
    }

    /// Registers a blocking permission request. Returns its id so it can be cancelled.
    @discardableResult
    func addPermission(_ e: HookEvent, canHandBack: Bool = false, release: @escaping () -> Void = {},
                       decide: @escaping (Bool) -> Void) -> UUID? {
        guard let i = upsertSession(for: e) else { return nil }
        let session = sessions[i]
        sessions[i].state = .needsInput
        sessions[i].detail = "Wants to use \(e.toolName ?? "a tool")"
        sessions[i].lastActivity = Date()
        let req = AttentionRequest(id: UUID(), sessionID: session.id,
                                   title: e.toolSummary ?? e.toolName ?? "Permission request",
                                   detail: "\(session.name) wants to use \(e.toolName ?? "a tool")",
                                   decide: decide, canHandBack: canHandBack, release: release)
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
            if let pid = s.agentPID { return !isAlive(pid) }
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
