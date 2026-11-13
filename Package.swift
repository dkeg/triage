// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Triage",
    platforms: [.macOS(.v14)],
    targets: [
        // Wire protocol, socket server/client, hook event model, settings.json installer.
        .target(name: "TriageCore", path: "Sources/TriageCore"),
        // The menubar app.
        .executableTarget(name: "Triage", dependencies: ["TriageCore"], path: "Sources/Triage"),
        // Tiny command that Claude Code runs as a hook; forwards to the app over a Unix socket.
        .executableTarget(name: "triage-hook", dependencies: ["TriageCore"], path: "Sources/TriageHook"),
        .testTarget(name: "TriageTests", dependencies: ["Triage"], path: "Tests/TriageTests"),
        .testTarget(name: "TriageCoreTests", dependencies: ["TriageCore"], path: "Tests/TriageCoreTests"),
    ]
)
