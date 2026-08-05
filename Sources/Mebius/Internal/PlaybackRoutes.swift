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

    init(isRealtime: Bool, deliveryPath: String? = nil) {
        self.isRealtime = isRealtime
        self.deliveryPath = deliveryPath
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
            routes.append(PlaybackRoute(isRealtime: false, deliveryPath: delivery.path))
        }
    }
    routes.append(PlaybackRoute(isRealtime: false))
    return routes
}
