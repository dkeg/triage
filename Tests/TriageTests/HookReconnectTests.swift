import XCTest
@testable import Triage

final class HookReconnectTests: XCTestCase {
    private func offer(app: Bool = true, offered: Bool = true, declined: Bool = false,
                       helper: Bool = true, installed: Bool = false) -> Bool {
        HookReconnect.shouldOffer(isApp: app, setupOffered: offered, declined: declined,
                                  helperExists: helper, hooksInstalled: installed)
    }

    func testOffersWhenAConnectedUserLosesTheirHooks() { XCTAssertTrue(offer()) }
    func testNeverOffersWhenHooksArePresent() { XCTAssertFalse(offer(installed: true)) }
    func testNeverOffersToSomeoneWhoNeverConnected() {
        XCTAssertFalse(offer(helper: false))                 // no helper copy: they never connected
        XCTAssertFalse(offer(offered: false))                // first-run offer not shown yet: that flow handles it
    }
    func testRespectsAnExplicitRemoval() { XCTAssertFalse(offer(declined: true)) }
    func testNeverOffersOutsideTheAppBundle() { XCTAssertFalse(offer(app: false)) }
}
