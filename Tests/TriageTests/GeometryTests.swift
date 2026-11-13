import XCTest
@testable import Triage

final class GeometryTests: XCTestCase {
    func testPanelCentersOnCutout() {
        let g = IslandGeometry(cutout: CGRect(x: 838.5, y: 1093, width: 59, height: 40),
                               screenFrame: CGRect(x: 0, y: 0, width: 1736, height: 1133),
                               isPhysical: true)
        XCTAssertEqual(g.panelFrame.midX, g.cutout.midX, accuracy: 0.001)
        XCTAssertEqual(g.panelFrame.maxY, 1133, accuracy: 0.001) // flush with the top screen edge
    }

    @MainActor func testSizesGrowWithMode() {
        let m = IslandModel()
        m.geometry = IslandGeometry(cutout: CGRect(x: 838.5, y: 1093, width: 59, height: 40),
                                    screenFrame: CGRect(x: 0, y: 0, width: 1736, height: 1133), isPhysical: true)
        XCTAssertEqual(m.size, .zero) // hidden until there is a session
        m.sessions = IslandModel.mockSessions()
        let collapsed = m.size
        m.mode = .expanded
        XCTAssertEqual(collapsed.height, 33) // matches the hardware island band
        XCTAssertGreaterThan(m.size.width, collapsed.width)
        XCTAssertGreaterThan(m.size.height, collapsed.height)
    }
}
