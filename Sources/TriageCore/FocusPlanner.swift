import Foundation

public struct TopicRef: Equatable, Sendable {
    public var id: String
    public var path: String
    public init(id: String, path: String) { self.id = id; self.path = path }
}

public enum FocusTarget: Equatable, Sendable {
    /// Subspace: activate this topic, then bring the app forward.
    case subspaceTopic(id: String, bundleID: String)
    /// Terminal.app tab with this tty.
    case terminalTab(tty: String)
    /// iTerm2 session with this unique id (the GUID half of ITERM_SESSION_ID).
    case itermSession(guid: String)
    /// Just bring the host app forward.
    case app(bundleID: String)
    case unknown
}

public enum FocusPlanner {
    public static let subspaceBundleID = "com.subspace.app"
    public static let terminalBundleID = "com.apple.Terminal"
    public static let itermBundleID = "com.googlecode.iterm2"

    /// Longest-prefix match of a working directory against known topics.
    public static func topic(for cwd: String?, in topics: [TopicRef]) -> TopicRef? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return topics
            .filter { cwd == $0.path || cwd.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }

    public static func plan(hostBundleID: String?, meta: TriageMeta?, cwd: String?,
                            topics: [TopicRef]) -> FocusTarget {
        guard let host = hostBundleID else { return .unknown }
        switch host {
        case subspaceBundleID:
            if let t = topic(for: cwd, in: topics) { return .subspaceTopic(id: t.id, bundleID: host) }
            return .app(bundleID: host)
        case terminalBundleID:
            if let tty = meta?.tty { return .terminalTab(tty: tty) }
            return .app(bundleID: host)
        case itermBundleID:
            if let raw = meta?.env?["ITERM_SESSION_ID"], let guid = raw.split(separator: ":").last {
                return .itermSession(guid: String(guid))
            }
            return .app(bundleID: host)
        default:
            return .app(bundleID: host)
        }
    }

    /// Parses `subspace workspaces list --json`, which may be preceded by log lines.
    public static func parseTopics(_ output: Data) -> [TopicRef] {
        guard let text = String(data: output, encoding: .utf8) else { return [] }
        // Skip log prefixes like "[database] ..." by starting at the JSON array itself.
        guard let start = ["[{", "[]"].compactMap({ text.range(of: $0)?.lowerBound }).min(),
              let data = String(text[start...]).data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let id = d["id"] as? String, let path = d["path"] as? String,
                  (d["isArchived"] as? Bool) != true else { return nil }
            return TopicRef(id: id, path: path)
        }
    }
}
