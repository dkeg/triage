import Foundation
import Darwin

/// One row of the process table, with just what terminal detection needs.
public struct ProcRecord: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    /// Process group, and the foreground process group of the controlling terminal.
    public var pgid: Int32
    public var tpgid: Int32
    public var tty: String?
    public var name: String
    public var start: Date?

    public init(pid: Int32, ppid: Int32, pgid: Int32, tpgid: Int32, tty: String?, name: String, start: Date? = nil) {
        self.pid = pid; self.ppid = ppid; self.pgid = pgid; self.tpgid = tpgid
        self.tty = tty; self.name = name; self.start = start
    }
}

public enum ProcessTable {
    /// Every process id. Note `proc_listallpids` returns a *count* of ids, not a byte size, and
    /// fills only as many as fit, so grow the buffer until it comes back with room to spare.
    public static func allPIDs() -> [pid_t] {
        var capacity = 2048
        while capacity <= 1 << 20 {
            var buf = [pid_t](repeating: 0, count: capacity)
            let got = Int(proc_listallpids(&buf, Int32(capacity * MemoryLayout<pid_t>.size)))
            if got <= 0 { return [] }
            if got < capacity { return buf.prefix(got).filter { $0 > 0 } }
            capacity *= 2
        }
        return []
    }

    /// A snapshot of every process the current user can see.
    public static func snapshot() -> [ProcRecord] {
        var out: [ProcRecord] = []
        for pid in allPIDs() {
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            var kp = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { continue }
            var tty: String?
            let dev = kp.kp_eproc.e_tdev
            if dev != -1, let cname = devname(dev_t(dev), S_IFCHR) { tty = "/dev/" + String(cString: cname) }
            let name = withUnsafeBytes(of: kp.kp_proc.p_comm) { raw -> String in
                let bytes = raw.prefix { $0 != 0 }
                return String(decoding: bytes, as: UTF8.self)
            }
            let t = kp.kp_proc.p_un.__p_starttime
            out.append(ProcRecord(pid: pid, ppid: kp.kp_eproc.e_ppid, pgid: kp.kp_eproc.e_pgid,
                                  tpgid: kp.kp_eproc.e_tpgid, tty: tty, name: name,
                                  start: t.tv_sec > 0 ? Date(timeIntervalSince1970: TimeInterval(t.tv_sec)) : nil))
        }
        return out
    }
}
