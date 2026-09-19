import Foundation

/// Playback mode for a ``MebiusPlayer``.
///
/// The mode controls the latency/scalability trade-off. The underlying delivery
/// mechanism for each mode is selected automatically and is not exposed.
public enum MebiusPlayerMode: String, Equatable, Sendable {

    /// Let Mebius choose per viewer, and move to another route by itself if the
    /// chosen one stops delivering video. The recommended default.
    case auto = "auto"

    /// Optimized for the lowest possible latency (real-time, sub-second).
    /// Costs one per-viewer session on Mebius, so it is not the right choice for a
    /// plain audience — use ``auto`` for that, or `createMonitor()` for the other
    /// side of a co-broadcast.
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

/// One selectable rendition of a stream.
///
/// Mebius does not transcode into a ladder today, so a live stream has exactly
/// one rendition and ``MebiusPlayer/qualities`` is empty. That emptiness is the
/// signal, not an omission: a player UI can hide its quality menu because the
/// list says there is nothing to choose, rather than because someone guessed.
public struct MebiusQuality: Equatable, Sendable, Identifiable {
    /// Stable id to pass to ``MebiusPlayer/setQuality(_:)``.
    public let id: String
    /// Human-readable label, e.g. `"720p"`. Safe to show as-is.
    public let label: String
    /// Frame height in pixels, when the rendition has a fixed one.
    public let height: Int?
    /// Nominal video bitrate in kbps, when known.
    public let bitrateKbps: Int?

    public init(id: String, label: String, height: Int? = nil, bitrateKbps: Int? = nil) {
        self.id = id
        self.label = label
        self.height = height
        self.bitrateKbps = bitrateKbps
    }
}
