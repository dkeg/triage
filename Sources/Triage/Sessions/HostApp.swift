import AppKit
import TriageCore

/// Which GUI app hosts a session (Subspace, Ghostty, Kaku, ...), and its icon.
enum HostApp {
    /// Nearest ancestor that is a regular app; falls back to the bundle id the terminal exports.
    static func bundleID(for meta: TriageMeta?) -> String? {
        let me = ProcessInfo.processInfo.processIdentifier
        for p in meta?.chain ?? [] where Int32(p.pid) != me {
            if let app = NSRunningApplication(processIdentifier: Int32(p.pid)), app.activationPolicy == .regular,
               let id = app.bundleIdentifier { return id }
        }
        return meta?.env?["__CFBundleIdentifier"]
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = img
        return img
    }
}
