import Foundation

/// Playback mode for a ``MebiusPlayer``.
///
/// The mode controls the latency/scalability trade-off. The underlying delivery
/// mechanism for each mode is selected automatically and is not exposed.
public enum MebiusPlayerMode: String, Equatable, Sendable {

    /// Optimized for the lowest possible latency (real-time, sub-second).
    /// Best for interactive use cases such as auctions, calls, or live Q&A.
    case lowLatency = "low-latency"

    /// Optimized for scale and resilience over large audiences, trading some
    /// latency for robustness. Best for one-to-many broadcasts.
    case scale = "scale"
}

/// Statistics reported periodically by a ``MebiusBroadcaster``.
public struct MebiusBroadcastStats: Equatable, Sendable {
    /// Outbound bitrate in bits per second.
    public let bitrate: Int
    /// Frames per second currently being captured/encoded.
    public let frameRate: Double
    /// Round-trip time to the gateway, in seconds, if known.
    public let roundTripTime: TimeInterval?
    /// Number of packets sent since the broadcast started.
    public let packetsSent: Int

    public init(bitrate: Int, frameRate: Double, roundTripTime: TimeInterval?, packetsSent: Int) {
        self.bitrate = bitrate
        self.frameRate = frameRate
        self.roundTripTime = roundTripTime
        self.packetsSent = packetsSent
    }
}

/// Statistics reported periodically by a ``MebiusPlayer``.
public struct MebiusPlayerStats: Equatable, Sendable {
    /// Inbound bitrate in bits per second.
    public let bitrate: Int
    /// Frames per second currently being rendered.
    public let frameRate: Double
    /// Estimated end-to-end latency, in seconds, if known.
    public let latency: TimeInterval?
    /// Number of packets received since playback started.
    public let packetsReceived: Int

    public init(bitrate: Int, frameRate: Double, latency: TimeInterval?, packetsReceived: Int) {
        self.bitrate = bitrate
        self.frameRate = frameRate
        self.latency = latency
        self.packetsReceived = packetsReceived
    }
}
