import XCTest
import CoreGraphics
import ImageIO
@testable import Triage

@MainActor
final class IslandMeasureTests: XCTestCase {
    private func fixture(_ name: String) throws -> CGImage {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    /// Real capture of the system island while Music is playing (about 136pt wide).
    func testMeasuresRealMusicActivity() throws {
        let w = try XCTUnwrap(SystemIslandMeasure.width(in: try fixture("island_music.png"), scale: 2))
        XCTAssertEqual(w, 136, accuracy: 10)
    }

    /// Synthetic: a black rounded pill of known width on a bright background.
    private func pillImage(widthPt: CGFloat, background: CGFloat, scale: CGFloat = 2) -> CGImage {
        let wPx = Int(600 * scale), hPx = Int(48 * scale)
        let ctx = CGContext(data: nil, width: wPx, height: hPx, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: background, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: wPx, height: hPx))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        // CG origin is bottom-left; the island spans 4...42pt from the top.
        let rect = CGRect(x: (600 - widthPt) / 2 * scale, y: (48 - 42) * scale, width: widthPt * scale, height: 38 * scale)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 19 * scale, cornerHeight: 19 * scale, transform: nil))
        ctx.fillPath()
        return ctx.makeImage()!
    }

    func testMeasuresSyntheticPillsAcrossWidths() throws {
        for width in [59.0, 136, 220] as [CGFloat] {
            let w = try XCTUnwrap(SystemIslandMeasure.width(in: pillImage(widthPt: width, background: 0.7), scale: 2))
            XCTAssertEqual(w, width, accuracy: 8, "width \(width)")
        }
    }

    func testDarkBackgroundYieldsNilNotGarbage() {
        XCTAssertNil(SystemIslandMeasure.width(in: pillImage(widthPt: 136, background: 0.02), scale: 2))
    }

    func testCenterReserveByMode() {
        let m = IslandModel()
        m.geometry = IslandGeometry(cutout: CGRect(x: 838.5, y: 1093, width: 59, height: 40),
                                    screenFrame: CGRect(x: 0, y: 0, width: 1736, height: 1133), isPhysical: true)
        m.pillWidthMode = .compact
        XCTAssertEqual(m.centerReserve, 69)
        m.pillWidthMode = .wide
        XCTAssertEqual(m.centerReserve, 150)
        m.pillWidthMode = .auto
        XCTAssertEqual(m.centerReserve, 150)            // no reading yet -> safe fallback
        m.measuredIslandWidth = 59
        XCTAssertEqual(m.centerReserve, 75)             // idle island: hugs it
        m.measuredIslandWidth = 136
        XCTAssertEqual(m.centerReserve, 152)            // Live Activity: widens
    }

    func testYieldHidesPill() {
        let m = IslandModel()
        m.geometry = IslandGeometry(cutout: CGRect(x: 838.5, y: 1093, width: 59, height: 40),
                                    screenFrame: CGRect(x: 0, y: 0, width: 1736, height: 1133), isPhysical: true)
        m.sessions = IslandModel.mockSessions()
        XCTAssertNotEqual(m.size, .zero)
        m.yielding = true
        XCTAssertEqual(m.size, .zero)
    }

    func testHardwareIslandDoesNotTriggerHover() {
        let m = IslandModel()
        m.geometry = IslandGeometry(cutout: CGRect(x: 838.5, y: 1093, width: 59, height: 40),
                                    screenFrame: CGRect(x: 0, y: 0, width: 1736, height: 1133), isPhysical: true)
        m.sessions = IslandModel.mockSessions()
        m.pillWidthMode = .wide
        let w = m.size.width
        let rect = CGRect(x: 868 - w / 2, y: 1133 - 4 - m.size.height, width: w, height: m.size.height)
        let y = rect.midY
        XCTAssertFalse(m.hoverHit(CGPoint(x: 868, y: y), in: rect))          // over the hardware island
        XCTAssertFalse(m.hoverHit(CGPoint(x: 868 + 60, y: y), in: rect))     // still inside the reserved middle
        XCTAssertTrue(m.hoverHit(CGPoint(x: 868 + 120, y: y), in: rect))     // Triage's right wing
        XCTAssertTrue(m.hoverHit(CGPoint(x: 868 - 120, y: y), in: rect))     // Triage's left wing
        m.mode = .expanded                                                    // once open, the whole card counts
        XCTAssertTrue(m.hoverHit(CGPoint(x: 868, y: y), in: rect))
    }
}
