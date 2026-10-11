import Foundation

// MARK: - Playback route selection (private)

/// How long one route gets to report playback before the player moves to the next.
///
/// Not arbitrary. A route can look healthy and deliver nothing: an edge with no
/// ingest yet answers 200 with an empty stream, and a real-time connection reports
/// itself connected while zero frames arrive. 8s survives a slow first segment on
/// mobile data and is short enough that the viewer has not left. Mirrored across
/// every Mebius SDK so a viewer sees the same behaviour on each platform.
let mebiusFirstFrameTimeout: TimeInterval = 8

/// Delivery kinds the gateway may offer. Neutral labels, never protocol names.
enum DeliveryKind {
    static let fast = "fast"
    static let wide = "wide"
    static let local = "local"
}

/// One route to attempt, in the order the gateway prefers.
///
/// `deliveryPath` is nil for the real-time route (signaled, so it never appears in
/// the delivery list) and for the origin fallback (addressed by stream id).
struct PlaybackRoute: Equatable {
    let isRealtime: Bool
    let deliveryPath: String?
    /// The route's quality ladder; empty when it serves one rendition.
    let renditions: [MebiusRendition]

    init(isRealtime: Bool, deliveryPath: String? = nil, renditions: [MebiusRendition] = []) {
        self.isRealtime = isRealtime
        self.deliveryPath = deliveryPath
        self.renditions = renditions
    }
}

/// Builds the ordered route list for `mode`.
///
/// The gateway's ordering is preserved verbatim — it knows which routes are actually
/// serving and what each costs to serve. The origin route is always appended last,
/// both as a guaranteed fallback and because every byte of it is billed to us,
/// unlike an edge route.
///
/// `fast` is deliberately skipped on this platform: AVPlayer cannot play it, so
/// offering it would be a route that can never play.
func buildPlaybackRoutes(
    mode: MebiusPlayerMode,
    deliveries: [MebiusDelivery]
) -> [PlaybackRoute] {
    var routes: [PlaybackRoute] = []
    if mode == .lowLatency {
        routes.append(PlaybackRoute(isRealtime: true))
    }
    for delivery in deliveries where delivery.isResolvable {
        if delivery.kind == DeliveryKind.wide || delivery.kind == DeliveryKind.local {
            // A rung is opened with the viewer's token exactly like the route, so it
            // gets the same off-host check — and only `wide` is an HLS master the
            // rungs belong to.
            let renditions = delivery.kind == DeliveryKind.wide
                ? delivery.renditions.filter { MebiusDelivery.isResolvable($0.path) }
                : []
            routes.append(PlaybackRoute(isRealtime: false, deliveryPath: delivery.path, renditions: renditions))
        }
    }
    routes.append(PlaybackRoute(isRealtime: false))
    return routes
}

// MARK: - Quality ladder (private)

/// The path to open for `route` with `quality` chosen: that rung's own playlist for
/// a manual pick, the route (the master, when it has a ladder) for `"auto"` or an
/// id this route does not carry.
///
/// A manual pick opens the rung rather than steering AVPlayer inside the master,
/// because AVPlayer offers no reliable way to pin one variant.
func scalePath(for route: PlaybackRoute, quality: String) -> String? {
    route.renditions.first(where: { $0.id == quality })?.path ?? route.deliveryPath
}

/// The rung a `maxHeight` cap leaves on top: the tallest that fits, or the shortest
/// when none does — a cap below the ladder still has to play something.
func cappedRendition(_ renditions: [MebiusRendition], maxHeight: Int?) -> MebiusRendition? {
    let byHeight = renditions.filter { $0.height != nil }.sorted { $0.height! < $1.height! }
    guard let maxHeight else { return byHeight.last }
    return byHeight.last(where: { $0.height! <= maxHeight }) ?? byHeight.first
}

/// `preferredPeakBitRate` for a `maxHeight` cap, in bits per second; 0 lifts it.
///
/// Set just below the cheapest rung the cap excludes, not at the allowed rung's own
/// bitrate: a variant's advertised BANDWIDTH includes audio and overhead on top of
/// its video bitrate, so a ceiling at the allowed rung would exclude it too.
func peakBitRate(_ renditions: [MebiusRendition], maxHeight: Int?) -> Double {
    guard let allowed = cappedRendition(renditions, maxHeight: maxHeight), let top = allowed.height else { return 0 }
    let excluded = renditions.compactMap { r -> Int? in
        guard let h = r.height, h > top else { return nil }
        return r.bitrateKbps
    }
    guard let next = excluded.min() else { return 0 }
    return Double(next * 1000 - 1)
}

/// The rung AVPlayer is most likely playing, from what its access log reports.
///
/// Height first — it is what the viewer sees and what the ids name; the indicated
/// bitrate only when no height is known yet (audio-only start, or a log entry that
/// arrived before the first frame). Either value is ignored when not positive.
func closestRendition(_ renditions: [MebiusRendition], height: Double, bitrate: Double) -> String? {
    if height > 0, let match = renditions
        .filter({ $0.height != nil })
        .min(by: { abs(Double($0.height!) - height) < abs(Double($1.height!) - height) }) {
        return match.id
    }
    let kbps = bitrate / 1000
    guard bitrate > 0 else { return nil }
    return renditions
        .filter { $0.bitrateKbps != nil }
        .min(by: { abs(Double($0.bitrateKbps!) - kbps) < abs(Double($1.bitrateKbps!) - kbps) })?
        .id
}
