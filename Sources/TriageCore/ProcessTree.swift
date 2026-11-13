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

    public static func name(of pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            return URL(fileURLWithPath: String(cString: buf)).lastPathComponent
        }
        return ""
    }

    public static func parent(of pid: Int32) -> Int32? { info(pid).map { $0.kp_eproc.e_ppid } }

    /// Controlling terminal device path (e.g. /dev/ttys003), if the process has one.
    public static func tty(of pid: Int32) -> String? {
        guard let kp = info(pid) else { return nil }
        let dev = kp.kp_eproc.e_tdev
        guard dev != -1, let cname = devname(dev_t(dev), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: cname)
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
