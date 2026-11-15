import Foundation
import Darwin

public enum TriagePaths {
    public static let bundleID = "io.github.dkeg.triage"
    /// Set when the user removes the hooks on purpose, so the app doesn't offer to reconnect them.
    public static let hooksDeclinedKey = "hooksReconnectDeclined"

    public static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Triage", isDirectory: true)
    }
    public static var socketPath: String { supportDir.appendingPathComponent("triage.sock").path }
    public static var helperURL: URL { supportDir.appendingPathComponent("bin/triage-hook") }
}

/// Length-prefixed framing (4-byte big-endian length + payload) over a stream socket.
public enum Wire {
    static let maxFrame = 8 * 1024 * 1024

    public static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var offset = 0
        return data.withUnsafeBytes { raw -> Bool in
            while offset < data.count {
                let n = write(fd, raw.baseAddress! + offset, data.count - offset)
                if n < 0 { if errno == EINTR { continue }; return false }
                offset += n
            }
            return true
        }
    }

    static func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var buf = Data(count: count)
        var got = 0
        while got < count {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, count - got) }
            if n == 0 { return nil }
            if n < 0 { if errno == EINTR { continue }; return nil }
            got += n
        }
        return buf
    }

    public static func writeFrame(_ fd: Int32, _ payload: Data) -> Bool {
        var len = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &len, count: 4)
        framed.append(payload)
        return writeAll(fd, framed)
    }

    public static func readFrame(_ fd: Int32) -> Data? {
        guard let head = readExactly(fd, 4) else { return nil }
        let len = Int(head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
        guard len <= maxFrame else { return nil }
        if len == 0 { return Data() }
        return readExactly(fd, len)
    }

    /// Calls `body` with a filled sockaddr_un for `path`, or returns nil if the path is too long.
    static func withSockAddr<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < cap else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8) + [0])
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, len) }
        }
    }

    static func noSigpipe(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }
}
