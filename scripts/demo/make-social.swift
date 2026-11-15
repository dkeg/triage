// Composes the social preview image (1200x630):
//   swiftc -o /tmp/make-social scripts/demo/make-social.swift && /tmp/make-social card.png packaging/AppIcon.icns out.png
// `card.png` is a still of the open approval card (scripts/demo/record.sh extracts one from the approval clip).
import SwiftUI
import AppKit

struct Social: View {
    let card: NSImage
    let icon: NSImage
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.055)
            RadialGradient(colors: [Color(red: 0.17, green: 0.20, blue: 0.30).opacity(0.95), .clear],
                           center: UnitPoint(x: 0.78, y: 0.34), startRadius: 0, endRadius: 560)
            HStack(alignment: .center, spacing: 36) {
                VStack(alignment: .leading, spacing: 22) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 84, height: 84)
                    Text("triage")
                        .font(.system(size: 76, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Text("Dynamic Island status and approvals for AI coding agents")
                        .font(.system(size: 29, weight: .regular)).foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text("brew install --cask dkeg/triage/triage")
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.09)))
                }
                .frame(width: 480, alignment: .leading)
                .padding(.vertical, 62)

                Image(nsImage: card).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: 560)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
            }
            .padding(.horizontal, 52)
        }
        .frame(width: 1200, height: 630)
    }
}

let args = CommandLine.arguments
guard args.count == 4, let card = NSImage(contentsOfFile: args[1]), let icon = NSImage(contentsOfFile: args[2]) else {
    print("usage: make-social card.png icon.icns out.png"); exit(2)
}
MainActor.assumeIsolated {
    let r = ImageRenderer(content: Social(card: card, icon: icon))
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("render failed"); exit(1) }
    try! png.write(to: URL(fileURLWithPath: args[3]))
    print("wrote \(args[3])")
}
