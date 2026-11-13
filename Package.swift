// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Triage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Triage", path: "Sources/Triage"),
        .testTarget(name: "TriageTests", dependencies: ["Triage"], path: "Tests/TriageTests"),
    ]
)
