import XCTest
@testable import Mebius

/// The first-frame signal for the real-time route.
///
/// A route that connects and sends nothing produces no error at all, which is
/// why the player arms a first-frame budget. The signal it reads therefore has
/// to mean "a picture arrived". `RTCPeerConnectionState.connected` does not: it
/// means ICE and DTLS completed, which is true before any media flows and stays
/// true if none ever does.
final class FirstFrameLatchTests: XCTestCase {

    func testCancelStopsAFrameInFlightFromReporting() {
        // Removal alone does not close this window: removeRenderer: blocks on
        // libwebrtc's worker thread, so a frame already inside renderFrame makes
        // removal wait for it — the latch would fire and report playback after
        // teardown had returned.
        var fired = 0
        let latch = FirstFrameLatch { fired += 1 }

        latch.cancel()
        latch.frameArrived()

        XCTAssertEqual(fired, 0)
    }

    func testCancelAfterPlayingDoesNotFireAgain() {
        var fired = 0
        let latch = FirstFrameLatch { fired += 1 }

        latch.frameArrived()
        latch.cancel()
        latch.frameArrived()

        XCTAssertEqual(fired, 1)
    }

    func testFiresOnTheFirstFrame() {
        var fired = 0
        let latch = FirstFrameLatch { fired += 1 }

        latch.frameArrived()

        XCTAssertEqual(fired, 1)
    }

    func testFiresOnceHoweverManyFramesFollow() {
        var fired = 0
        let latch = FirstFrameLatch { fired += 1 }

        for _ in 0..<30 { latch.frameArrived() }

        XCTAssertEqual(fired, 1)
    }

    func testFiresOnceUnderConcurrentDelivery() {
        // Frames arrive on libwebrtc's own thread while the player may still be
        // wiring up on the main one. A second "playing" would advance the route
        // list away from a route that is working.
        let counter = Counter()
        let latch = FirstFrameLatch { counter.increment() }
        let group = DispatchGroup()

        for _ in 0..<8 {
            DispatchQueue.global().async(group: group) { latch.frameArrived() }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)

        XCTAssertEqual(counter.value, 1)
    }

    /// Thread-safe tally, so the assertion measures the latch rather than a race
    /// in the test itself.
    private final class Counter {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }
}
