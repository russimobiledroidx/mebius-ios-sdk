import Foundation

// MARK: - Gateway endpoint resolution (private)
//
// All Mebius media flows through the configured `gateway`. This helper derives
// the concrete per-operation URLs from the single gateway base. No external
// infrastructure host is ever constructed or exposed here; everything is
// relative to the developer-supplied gateway.

struct GatewayEndpoints {
    let gateway: URL

    // Real-time publish endpoint (WHIP) — derived from the gateway base.
    func publishURL(streamId: String) -> URL {
        gateway.appendingPathComponent("publish").appendingPathComponent(streamId)
    }

    // Real-time low-latency subscribe endpoint (WHEP) — derived from the gateway.
    func lowLatencySubscribeURL(streamId: String) -> URL {
        gateway.appendingPathComponent("subscribe").appendingPathComponent(streamId)
    }

    // Scale playback playlist (HLS) — derived from the gateway base.
    func scalePlaylistURL(streamId: String) -> URL {
        gateway
            .appendingPathComponent("scale")
            .appendingPathComponent(streamId)
            .appendingPathComponent("index.m3u8")
    }
}
