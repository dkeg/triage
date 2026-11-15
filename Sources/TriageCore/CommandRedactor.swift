import Foundation

/// Turns a process's argv into a short one-line description for the screen, masking things that
/// look like secrets (tokens, passwords, URL credentials) so they don't end up on a shared display.
public enum CommandRedactor {
    static let secretFlag = try! NSRegularExpression(
        pattern: #"^-{1,2}(token|key|secret|password|passwd|pass|pwd|auth|authorization|bearer|api[-_]?key|access[-_]?token|client[-_]?secret)(=.*)?$"#,
        options: [.caseInsensitive])
    static let secretAssignment = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9_]*(TOKEN|KEY|SECRET|PASSWORD|PASSWD|PASS|AUTH)[A-Za-z0-9_]*=.+"#,
        options: [.caseInsensitive])
    static let knownTokenPrefixes = ["sk-", "ghp_", "gho_", "ghs_", "github_pat_", "xoxb-", "xoxp-", "AKIA", "AIza", "npm_", "glpat-"]
    static let mask = "•••"

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// An opaque, high-entropy-looking string (a bearer token, API key, ...).
    static func looksLikeToken(_ s: String) -> Bool {
        if knownTokenPrefixes.contains(where: { s.hasPrefix($0) }) && s.count >= 12 { return true }
        guard s.count >= 28, !s.contains("/"), !s.contains(" ") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard s.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        let hasDigit = s.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
        let hasLetter = s.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        return hasDigit && hasLetter
    }

    static func redactURL(_ s: String) -> String {
        guard let r = s.range(of: #"://[^/\s@]+@"#, options: .regularExpression) else { return s }
        return s.replacingCharacters(in: r, with: "://\(mask)@")
    }

    /// - Parameter fullArguments: false shows just the program name.
    public static func display(argv: [String], fullArguments: Bool = true, maxLength: Int = 64) -> String {
        guard let first = argv.first, !first.isEmpty else { return "" }
        var program = URL(fileURLWithPath: first).lastPathComponent
        if program.hasPrefix("-") { program.removeFirst() }          // login shells appear as -zsh
        guard fullArguments else { return program }

        var parts = [program]
        var redactNext = false
        for arg in argv.dropFirst() {
            if redactNext { parts.append(mask); redactNext = false; continue }
            if matches(secretFlag, arg) {
                if let eq = arg.firstIndex(of: "=") { parts.append(String(arg[..<eq]) + "=" + mask) }
                else { parts.append(arg); redactNext = true }
            } else if matches(secretAssignment, arg), let eq = arg.firstIndex(of: "=") {
                parts.append(String(arg[..<eq]) + "=" + mask)
            } else if looksLikeToken(arg) {
                parts.append(mask)
            } else {
                parts.append(redactURL(arg))
            }
        }
        let line = parts.joined(separator: " ").replacingOccurrences(of: "\n", with: " ")
        return line.count > maxLength ? String(line.prefix(maxLength - 1)) + "…" : line
    }
}
