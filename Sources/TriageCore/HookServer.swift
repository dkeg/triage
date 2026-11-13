import Foundation
import Darwin

/// One client connection. Either reply once, or leave it open (pending) until the
/// client goes away, in which case `onClose` fires.
public final class HookConnection: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false
    private var watcher: DispatchSourceRead?
    private var closeHandler: (@Sendable () -> Void)?
    private var closedByPeer = false

    /// Called when the client hangs up while the request is still pending. Fires
    /// immediately if that already happened.
    public func setOnClose(_ f: @escaping @Sendable () -> Void) {
        lock.lock()
        if closedByPeer { lock.unlock(); f(); return }
        closeHandler = f
        lock.unlock()
    }

    init(fd: Int32) { self.fd = fd }

    /// Sends the reply and closes the connection. Safe to call more than once.
    public func reply(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        watcher?.cancel(); watcher = nil
        _ = Wire.writeFrame(fd, data)
        close(fd)
    }

    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return !closed }

    /// Detects the client hanging up (e.g. Claude killed the hook because the user
    /// answered in the terminal).
    func watchForClose(queue: DispatchQueue) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            var byte: UInt8 = 0
            let n = recv(self.fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) {
                self.lock.lock()
                let wasOpen = !self.closed
                var handler: (@Sendable () -> Void)?
                if wasOpen {
                    self.closed = true; self.closedByPeer = true
                    self.watcher?.cancel(); self.watcher = nil; close(self.fd)
                    handler = self.closeHandler
                }
                self.lock.unlock()
                handler?()
            } else if n > 0 {
                _ = recv(self.fd, &byte, 1, MSG_DONTWAIT)   // drain unexpected bytes
            }
        }
        watcher = src
        src.resume()
    }
}

public final class HookServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data, HookConnection) -> Void
    private let path: String
    private let handler: Handler
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "triage.hook-server")

    public init(path: String = TriagePaths.socketPath, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        signal(SIGPIPE, SIG_IGN)
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        let bound = Wire.withSockAddr(path) { bind(fd, $0, $1) == 0 } ?? false
        guard bound else { close(fd); throw posixError("bind \(path)") }
        chmod(path, 0o600)
        guard listen(fd, 32) == 0 else { close(fd); throw posixError("listen") }
        listenFD = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        acceptSource = src
        src.resume()
    }

    public func stop() {
        acceptSource?.cancel(); acceptSource = nil
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(path)
    }

    private func acceptOne() {
        let c = accept(listenFD, nil, nil)
        guard c >= 0 else { return }
        Wire.noSigpipe(c)
        DispatchQueue.global(qos: .userInitiated).async { [handler, queue] in
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            guard let data = Wire.readFrame(c) else { close(c); return }
            var none = timeval(tv_sec: 0, tv_usec: 0)
            setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
            let conn = HookConnection(fd: c)
            handler(data, conn)
            if conn.isOpen { conn.watchForClose(queue: queue) }
        }
    }

    private func posixError(_ what: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "\(what): \(String(cString: strerror(errno)))"])
    }
}
