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
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> Data {
        guard var obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { return raw }
        let keys = ["TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID", "TMUX", "TMUX_PANE",
                    "__CFBundleIdentifier", "TTY", "SUPACODE_WORKTREE", "WARP_SESSION_ID"]
        var env: [String: String] = [:]
        for k in keys { if let v = environment[k] { env[k] = v } }
        obj["_triage"] = ["ppid": Int(ppid), "env": env] as [String: Any]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? raw
    }
}
