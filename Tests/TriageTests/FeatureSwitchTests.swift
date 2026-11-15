import XCTest
@testable import Triage

final class FeatureSwitchTests: XCTestCase {
    /// "Always allow" saves whatever wildcard rule Claude Code suggests; keep it off until the card shows that rule.
    func testAlwaysAllowIsOffByDefault() {
        XCTAssertFalse(Features.alwaysAllow)
    }

    @MainActor func testDemoRequestHasNoAlwaysAllowWhileItIsOff() {
        let m = IslandModel()
        m.simulateAttention()
        XCTAssertNil(m.attention?.allowAlways)
        XCTAssertNil(m.attention?.alwaysSummary)
    }
}
