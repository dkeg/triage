import Foundation

/// Tiny file logger (~/Library/Logs/Triage/triage.log) so approval problems can be diagnosed.
enum TriageLog {
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Triage")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("triage.log")
        if let size = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int), size > 1_000_000 {
            try? FileManager.default.removeItem(at: u)
        }
        return u
    }()
    private static let queue = DispatchQueue(label: "triage.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
            else { try? data.write(to: url) }
        }
    }
}
