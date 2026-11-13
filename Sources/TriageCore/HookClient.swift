import Foundation
import Darwin

public enum HookClient {
    /// Sends one request and blocks for the reply. Returns nil if the app isn't listening
    /// (callers should then do nothing, so Claude falls back to its normal behavior).
    /// An empty reply means "no decision".
    public static func send(_ payload: Data, socketPath: String = TriagePaths.socketPath) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        Wire.noSigpipe(fd)
        let ok = Wire.withSockAddr(socketPath) { connect(fd, $0, $1) == 0 } ?? false
        guard ok, Wire.writeFrame(fd, payload) else { return nil }
        return Wire.readFrame(fd) ?? Data()
    }

    /// Adds `_triage` context (parent pid, terminal env) to a raw hook payload.
    public static func enrich(_ raw: Data, ppid: Int32 = getppid(),
                              environment: [String: String] = ProcessInfo.processInfo.environment,
                              chain: [ProcRef]? = nil, tty: String? = nil) -> Data {
        guard var obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { return raw }
        let keys = ["TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID", "TMUX", "TMUX_PANE",
                    "__CFBundleIdentifier", "TTY", "SUPACODE_WORKTREE", "WARP_SESSION_ID"]
        var env: [String: String] = [:]
        for k in keys { if let v = environment[k] { env[k] = v } }
        var meta: [String: Any] = ["ppid": Int(ppid), "env": env]
        // The hook's own parent is the shell wrapper; walk up from there to find the host app.
        let procs = chain ?? ([ProcRef(pid: Int(ppid), name: ProcessTree.name(of: ppid))] + ProcessTree.ancestry(of: ppid))
        meta["chain"] = procs.map { ["pid": $0.pid, "name": $0.name] as [String: Any] }
        if let t = tty ?? ProcessTree.nearestTTY(from: ppid) { meta["tty"] = t }
        obj["_triage"] = meta
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? raw
    }
}
