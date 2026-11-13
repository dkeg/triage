import AppKit
import TriageCore

/// Brings the terminal/app that hosts a session to the front, as precisely as the host allows.
@MainActor
final class SessionFocuser {
    private var topicCache: (date: Date, topics: [TopicRef])?

    func focus(_ session: Session) {
        Task { @MainActor in
            let host = hostApp(for: session.meta)
            var topics: [TopicRef] = []
            if host?.bundleIdentifier == FocusPlanner.subspaceBundleID { topics = await loadTopics() }
            let plan = FocusPlanner.plan(hostBundleID: host?.bundleIdentifier, meta: session.meta,
                                         cwd: session.cwd, topics: topics)
            await run(plan, host: host)
        }
    }

    /// The GUI app that contains the agent: nearest ancestor that is a regular app,
    /// falling back to the bundle id the terminal exported into the environment.
    func hostApp(for meta: TriageMeta?) -> NSRunningApplication? {
        let me = ProcessInfo.processInfo.processIdentifier
        for p in meta?.chain ?? [] where Int32(p.pid) != me {
            if let app = NSRunningApplication(processIdentifier: Int32(p.pid)), app.activationPolicy == .regular {
                return app
            }
        }
        if let id = meta?.env?["__CFBundleIdentifier"] {
            return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
        }
        return nil
    }

    private func run(_ plan: FocusTarget, host: NSRunningApplication?) async {
        switch plan {
        case .subspaceTopic(let id, _):
            _ = await shell("\(NSHomeDirectory())/.subspace/bin/subspace", ["workspaces", "activate", id])
            activate(host)
        case .terminalTab(let tty):
            if !runAppleScript(Self.terminalScript(tty: tty)) { activate(host) }
        case .itermSession(let guid):
            if !runAppleScript(Self.itermScript(guid: guid)) { activate(host) }
        case .app, .unknown:
            activate(host)
        }
    }

    private func activate(_ app: NSRunningApplication?) {
        app?.activate(options: [.activateAllWindows])
    }

    // MARK: Helpers

    private func loadTopics() async -> [TopicRef] {
        if let c = topicCache, Date().timeIntervalSince(c.date) < 30 { return c.topics }
        let out = await shell("\(NSHomeDirectory())/.subspace/bin/subspace", ["workspaces", "list", "--json"])
        let topics = FocusPlanner.parseTopics(out)
        if !topics.isEmpty { topicCache = (Date(), topics) }
        return topics
    }

    @discardableResult
    private func shell(_ path: String, _ args: [String]) async -> Data {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do { try p.run() } catch { cont.resume(returning: Data()); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: data)
            }
        }
    }

    private func runAppleScript(_ source: String) -> Bool {
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { NSLog("Triage: AppleScript failed: \(err)") }
        return err == nil
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(escape(tty))" then
                set selected tab of w to t
                set index of w to 1
                activate
                return
              end if
            end repeat
          end repeat
          error "tty not found"
        end tell
        """
    }

    static func itermScript(guid: String) -> String {
        """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if unique id of s is "\(escape(guid))" then
                  select w
                  select t
                  select s
                  activate
                  return
                end if
              end repeat
            end repeat
          end repeat
          error "session not found"
        end tell
        """
    }
}
