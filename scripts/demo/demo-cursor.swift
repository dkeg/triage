// Drives the real pointer for the recorded demo (compiled and run by scripts/demo/record.sh).
//
//   demo-cursor <approveX> <approveY> <pillX> <pillY> <restX> <restY>      (global points, origin top-left)
//
// Waits for the demo app to write /tmp/triage-demo-t0, then plays the pointer part of the story.
import CoreGraphics
import Foundation

// `demo-cursor park x y` just moves the pointer out of the way (used by the strip scenes).
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "park",
   let x = Double(CommandLine.arguments[2]), let y = Double(CommandLine.arguments[3]) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?
        .post(tap: .cghidEventTap)
    exit(0)
}
let a = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard a.count == 6 else { print("usage: demo-cursor approveX approveY pillX pillY restX restY"); exit(2) }
let approve = CGPoint(x: a[0], y: a[1]), pill = CGPoint(x: a[2], y: a[3]), rest = CGPoint(x: a[4], y: a[5])

func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func glide(from: CGPoint, to: CGPoint, seconds: Double) {
    let steps = Int(seconds * 120)
    for i in 1...max(steps, 1) {
        let t = Double(i) / Double(steps)
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2          // ease in-out
        post(.mouseMoved, CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e))
        usleep(UInt32(1_000_000 / 120))
    }
}
func click(_ p: CGPoint) {
    post(.leftMouseDown, p); usleep(90_000); post(.leftMouseUp, p)
}

post(.mouseMoved, rest)
var t0: Double?
for _ in 0..<600 {                                                                // up to 30s
    if let s = try? String(contentsOfFile: "/tmp/triage-demo-t0", encoding: .utf8), let v = Double(s) { t0 = v; break }
    usleep(50_000)
}
guard let start = t0 else { print("demo never started"); exit(1) }
func wait(until t: Double) {
    let d = start + t - Date().timeIntervalSince1970
    if d > 0 { usleep(UInt32(d * 1_000_000)) }
}

wait(until: 4.2);  glide(from: rest, to: approve, seconds: 0.8)
wait(until: 5.4);  click(approve)
wait(until: 5.7);  glide(from: approve, to: rest, seconds: 0.8)
wait(until: 7.0);  glide(from: rest, to: pill, seconds: 0.7)
wait(until: 9.8);  glide(from: pill, to: rest, seconds: 0.8)
print("pointer story done")
