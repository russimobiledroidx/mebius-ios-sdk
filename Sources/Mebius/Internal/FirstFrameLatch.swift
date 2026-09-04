import Foundation

/// Reports the moment the real-time route actually renders a picture — once.
///
/// The player gives each route a first-frame budget because a route can connect
/// and then send nothing, producing no error to react to. That only works if
/// "playing" means a frame arrived. `RTCPeerConnectionState.connected` does not:
/// it means ICE and DTLS completed, which happens before any media flows and
/// stays true if none ever does. Reporting playback there defused the budget in
/// exactly the case it exists for, and left the viewer on a black frame.
///
/// Deliberately free of any libwebrtc type, so it compiles and is tested under a
/// plain `swift build` — the real-time transport itself sits behind the
/// `MEBIUS_RTC` condition and is unavailable to SPM.
///
/// `onFirstFrame` runs on whichever thread delivered the frame, and runs at most
/// once however many frames follow: a second "playing" would advance the route
/// list away from a route that is working.
final class FirstFrameLatch {
    private let lock = NSLock()
    private var fired = false
    private let onFirstFrame: () -> Void

    init(onFirstFrame: @escaping () -> Void) {
        self.onFirstFrame = onFirstFrame
    }

    /// Stops the latch reporting, permanently.
    ///
    /// Needed because removal is not enough on its own. `removeRenderer:` makes a
    /// blocking call onto libwebrtc's worker thread, so a frame already inside
    /// `renderFrame` makes removal *wait* for it: the latch fires, the callback
    /// hops to main, and playback gets reported after teardown returned. Closing
    /// the latch first means a frame in flight has nothing to report to.
    func cancel() {
        lock.lock()
        fired = true
        lock.unlock()
    }

    /// Called for each rendered frame. Only the first one is reported.
    func frameArrived() {
        lock.lock()
        let first = !fired
        fired = true
        lock.unlock()
        // Outside the lock: the callback hops to the main queue and calls into
        // the integrator's delegate, and holding a lock across that invites a
        // deadlock for no benefit.
        if first {
            onFirstFrame()
        }
    }
}
