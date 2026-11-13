import Foundation
import Darwin

public struct ProcRef: Codable, Equatable, Sendable {
    public var pid: Int
    public var name: String
    public init(pid: Int, name: String) { self.pid = pid; self.name = name }
}

public enum ProcessTree {
    private static func info(_ pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var kp = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
        return kp
    }

    /// Display name of a process. Claude Code runs from a versioned binary
    /// (~/.local/share/claude/versions/2.1.x, reached via a `claude` symlink), so the resolved
    /// path alone says "2.1.x"; normalize those to "claude".
    public static func name(of pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return "" }
        let path = String(cString: buf)
        let base = URL(fileURLWithPath: path).lastPathComponent
        if base == "claude" || path.contains("/claude/versions/") { return "claude" }
        // Interpreter installs (node ... claude): the launch name is in argv[0].
        if ["node", "bun", "deno"].contains(base), let a0 = argv0(of: pid),
           URL(fileURLWithPath: a0).lastPathComponent == "claude" { return "claude" }
        return base
    }

    /// argv[0] of a process, via KERN_PROCARGS2 (nil when not readable).
    public static func argv0(of pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 8 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        // Layout: Int32 argc, exec path (NUL-terminated), NUL padding, then argv strings.
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }          // skip exec path
        while i < size, buf[i] == 0 { i += 1 }          // skip padding
        let start = i
        while i < size, buf[i] != 0 { i += 1 }
        return start < i ? String(decoding: buf[start..<i], as: UTF8.self) : nil
    }

    public static func parent(of pid: Int32) -> Int32? { info(pid).map { $0.kp_eproc.e_ppid } }

    /// Controlling terminal device path (e.g. /dev/ttys003), if the process has one.
    public static func tty(of pid: Int32) -> String? {
        guard let kp = info(pid) else { return nil }
        let dev = kp.kp_eproc.e_tdev
        guard dev != -1, let cname = devname(dev_t(dev), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: cname)
    }

    /// Working directory of a process.
    public static func cwd(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard size > 0 else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) {
            String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : path
    }

    /// Pids of all processes whose executable is named `name`.
    public static func pids(named name: String) -> [Int32] {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return [] }
        var buf = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 64)
        let got = proc_listallpids(&buf, Int32(buf.count * MemoryLayout<pid_t>.size))
        guard got > 0 else { return [] }
        return buf.prefix(Int(got) / MemoryLayout<pid_t>.size).filter { $0 > 0 && Self.name(of: $0) == name }
    }

    /// Ancestors of `pid`, nearest first (not including `pid` itself), stopping before launchd.
    public static func ancestry(of pid: Int32, limit: Int = 16) -> [ProcRef] {
        var out: [ProcRef] = []
        var cur = pid
        while out.count < limit, let p = parent(of: cur), p > 1 {
            out.append(ProcRef(pid: Int(p), name: name(of: p)))
            cur = p
        }
        return out
    }

    /// First controlling tty found walking up from `pid` (including itself).
    public static func nearestTTY(from pid: Int32, limit: Int = 16) -> String? {
        var cur = pid
        for _ in 0..<limit {
            if let t = tty(of: cur) { return t }
            guard let p = parent(of: cur), p > 1 else { return nil }
            cur = p
        }
        return nil
    }
}
