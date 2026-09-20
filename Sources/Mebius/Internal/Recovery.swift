import Foundation

/// Ceiling on what a publisher's video encoder may send, in kbps.
///
/// 2500 matches what the studio's OBS encoder is configured to send, so a
/// broadcast costs the same whichever path it came from — a host on a phone and a
/// host in the studio bill identically.
///
/// A ceiling, not a target: WebRTC still spends less on still scenes. What it
/// removes is the open end, where a capable device answered high-motion content
/// with whatever it could encode.
///
/// Every Mebius SDK carries this same number. Changing it in one place without the
/// others makes the cost of a broadcast depend on which device made it.
public let mebiusDefaultMaxBitrateKbps = 2500

/// How long the picture may stand still before its route is treated as dead.
///
/// A route that stops delivering does not announce it: AVPlayer reports one more
/// buffering state, a peer connection goes on reporting `connected`, and the view
/// keeps its last decoded frame — which is what a viewer calls a black screen.
/// Deliberately longer than `mebiusFirstFrameTimeout`, because a route that is
/// merely slow deserves to finish and reopening a healthy stream costs the viewer
/// a rebuffer for nothing.
let mebiusStallRecoveryTimeout: TimeInterval = 10

/// How many times a lost route is reopened before the session is declared over.
///
/// The SDK cannot tell "the broadcast ended" from "the edge dropped us" — both
/// look like a route that stopped producing frames. So it assumes the recoverable
/// case, which is the common one on a long broadcast, and spends a bounded amount
/// of time proving itself wrong.
let mebiusMaxRecoveryAttempts = 5

private let recoveryBase: TimeInterval = 1

/// Ceiling on the reopen delay. Bounded because every viewer of one broadcast
/// fails at the same instant — an edge restart is not an individual event — and an
/// unbounded retry storm from a full room is how a recovery mechanism becomes the
/// outage.
private let recoveryMax: TimeInterval = 30

/// Counts reopen attempts and spaces them out.
///
/// Separate from the player because it is the only part of recovery with no
/// dispatch queue in it: the player owns the clock, this owns the arithmetic.
struct RecoveryPolicy {

    /// Attempts spent since the last ``reset()``.
    private(set) var attempts = 0

    /// Whether the budget is used up and the session should be declared over.
    var isExhausted: Bool { attempts >= mebiusMaxRecoveryAttempts }

    /// Delay before the next attempt, consuming one attempt from the budget.
    /// Doubles per attempt: 1s, 2s, 4s, 8s, 16s.
    mutating func nextDelay() -> TimeInterval {
        let delay = recoveryBase * pow(2, Double(attempts))
        attempts += 1
        return min(delay, recoveryMax)
    }

    /// Forgets the attempts spent, once playback is proven healthy again.
    ///
    /// The budget is for CONSECUTIVE failures: a long broadcast that loses its
    /// route once an hour must not run out of attempts by the afternoon.
    mutating func reset() {
        attempts = 0
    }
}
