import XCTest
@testable import Mebius

/// The arithmetic behind reopening a route that stopped delivering.
///
/// Route selection ran once, in `play(streamId:view:)`. Whatever produced a frame
/// served the rest of the session, and when it later died playback stopped and
/// stayed stopped — a black screen the viewer could only fix by leaving and
/// coming back. On a 90-minute watch that looked like bad luck; on a broadcast
/// that runs for a day it is a certainty.
///
/// The dispatch queue lives in the player. What is pinned here is what it decides.
final class RecoveryPolicyTests: XCTestCase {

    func testSpacesAttemptsOutInsteadOfHammeringTheEdge() {
        var p = RecoveryPolicy()
        XCTAssertEqual(p.nextDelay(), 1)
        XCTAssertEqual(p.nextDelay(), 2)
        XCTAssertEqual(p.nextDelay(), 4)
        XCTAssertEqual(p.nextDelay(), 8)
        XCTAssertEqual(p.nextDelay(), 16)
    }

    func testGivesUpAfterABoundedNumberOfAttempts() {
        var p = RecoveryPolicy()
        for _ in 0..<mebiusMaxRecoveryAttempts {
            XCTAssertFalse(p.isExhausted, "budget must last the advertised number of attempts")
            _ = p.nextDelay()
        }
        XCTAssertTrue(p.isExhausted)
    }

    func testCapsTheWaitSoALongOutageIsNotAnHourOfSilence() {
        var p = RecoveryPolicy()
        for _ in 0..<12 {
            XCTAssertLessThanOrEqual(p.nextDelay(), 30)
        }
    }

    func testCountsConsecutiveFailuresSoAFlappingRouteCanRecoverAllDay() {
        var p = RecoveryPolicy()
        _ = p.nextDelay()
        _ = p.nextDelay()
        p.reset()
        XCTAssertFalse(p.isExhausted)
        XCTAssertEqual(p.nextDelay(), 1)
    }

    func testStallBudgetOutlastsTheFirstFrameBudget() {
        // A route that is merely slow must be allowed to finish: reopening a
        // healthy stream costs the viewer a rebuffer for nothing.
        XCTAssertGreaterThan(mebiusStallRecoveryTimeout, mebiusFirstFrameTimeout)
    }
}
