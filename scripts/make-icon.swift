// Generates packaging/AppIcon.icns:  swiftc -o /tmp/make-icon scripts/make-icon.swift && /tmp/make-icon
//
// The icon: the Dynamic Island's capsule holding three triage tags (red, amber, green, shrinking
// with priority) on a dark squircle, with two faint list rows below hinting at the session list.
import SwiftUI
import AppKit

struct Icon: View {
    var body: some View {
        ZStack {
            // Squircle body on the standard macOS icon grid (824pt artwork on a 1024pt canvas).
            RoundedRectangle(cornerRadius: 184, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.22, blue: 0.28),
                                              Color(red: 0.05, green: 0.06, blue: 0.09)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .overlay(RoundedRectangle(cornerRadius: 184, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 5))
                .shadow(color: .black.opacity(0.35), radius: 22, y: 14)

            VStack(spacing: 64) {
                // The island.
                Capsule(style: .continuous)
                    .fill(Color.black)
                    .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 5))
                    .frame(width: 600, height: 232)
                    .overlay(
                        // Tags shrink with priority: red is the loudest, green the quietest.
                        HStack(spacing: 52) {
                            tag(Color(red: 1.00, green: 0.30, blue: 0.30), size: 156)
                            tag(Color(red: 1.00, green: 0.69, blue: 0.13), size: 118)
                            tag(Color(red: 0.20, green: 0.78, blue: 0.35), size: 84)
                        })
                // Faint session rows.
                VStack(spacing: 26) {
                    Capsule().fill(.white.opacity(0.13)).frame(width: 440, height: 40)
                    Capsule().fill(.white.opacity(0.08)).frame(width: 300, height: 40)
                }
            }
            .offset(y: -6)
        }
        .frame(width: 1024, height: 1024)
    }

    private func tag(_ c: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c.opacity(1), c.opacity(0.82)], center: .topLeading, startRadius: 4, endRadius: size))
            .frame(width: size, height: size)
            .shadow(color: c.opacity(0.65), radius: size * 0.2)
    }
}

@MainActor func render() throws {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    renderer.isOpaque = false
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try png.write(to: URL(fileURLWithPath: "/tmp/icon_1024.png"))
}
MainActor.assumeIsolated { try! render() }
print("wrote /tmp/icon_1024.png")
