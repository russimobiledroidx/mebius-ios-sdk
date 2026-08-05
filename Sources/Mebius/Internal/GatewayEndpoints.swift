import Foundation

// MARK: - Gateway endpoint resolution (private)
//
// All Mebius media flows through the configured `gateway`. This helper derives
// the concrete per-operation URLs from the single gateway base. No external
// infrastructure host is ever constructed or exposed here; everything is
// relative to the developer-supplied gateway.
//
// Every URL below carries the access token in the QUERY, not in a header. That is
// not a style choice: the gateway's auth hook and its playback gate both read the
// query, and playlist entries inherit `?token=` automatically because the gateway
// rewrites them — which a request header cannot do for the media the player fetches
// afterwards. All three URLs in the previous version of this file were wrong in a
// way that could only fail: they addressed `/publish/`, `/subscribe/` and `/scale/`,
// none of which the gateway routes, and playback sent the token as a Bearer header
// the gate does not read.

struct GatewayEndpoints {
    let gateway: URL

    // Real-time publish endpoint. The path was `/publish/{id}`, which the gateway
    // does not route.
    func publishURL(streamId: String, token: String) -> URL {
        tokenized(gateway.appendingPathComponent("whip").appendingPathComponent(streamId), token)
    }

    // Real-time low-latency subscribe endpoint. The path was `/subscribe/{id}` — also
    // not a route the gateway serves.
    func lowLatencySubscribeURL(streamId: String, token: String) -> URL {
        tokenized(gateway.appendingPathComponent("whep").appendingPathComponent(streamId), token)
    }

    // Origin playlist. The fallback route: always available, but every byte of it is
    // served by Mebius origin rather than an edge, so prefer a gateway-offered route.
    func originPlaylistURL(streamId: String, token: String) -> URL {
        tokenized(
            gateway
                .appendingPathComponent("live")
                .appendingPathComponent(streamId)
                .appendingPathComponent("index.m3u8"),
            token
        )
    }

    // A route the gateway itself offered, as a gateway-relative path.
    //
    // The caller must have checked `MebiusDelivery.isResolvable` first. Returns nil
    // rather than trusting a path it cannot resolve safely: an absolute path here
    // would send the viewer's access token to a host Mebius did not choose.
    func deliveryURL(path: String, token: String) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("://") else { return nil }
        guard var components = URLComponents(url: gateway, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + path
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    // Every URL in this type carries the token, including the two real-time ones.
    // An earlier version left those to the signaling layer, which is compiled only
    // under CocoaPods (`#if MEBIUS_RTC`) — so no SwiftPM test could reach the rule and
    // removing it passed every check. Keeping it here puts it where the tests are.
    private func tokenized(_ url: URL, _ token: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "token", value: token)]
        return components.url ?? url
    }
}
