import Foundation

/// One playback route Mebius has prepared for a stream.
///
/// Your backend receives this list alongside the access token; hand it to
/// ``Mebius/connect(token:deliveries:)`` untouched. Both properties are opaque:
/// ``kind`` is a Mebius intent label, not a media format, and ``path`` is resolved
/// by Mebius against its own gateway. Reading either as a format or a URL will
/// break as soon as Mebius changes how a route is served — which is the reason the
/// list exists at all.
public struct MebiusDelivery: Equatable, Sendable, Decodable {

    /// Mebius intent label for this route.
    public let kind: String

    /// Mebius-relative path for this route.
    public let path: String

    /// The quality ladder behind this route, when it has one. Empty for a route that
    /// serves a single rendition — which is every route of a stream with no ladder.
    public let renditions: [MebiusRendition]

    public init(kind: String, path: String, renditions: [MebiusRendition] = []) {
        self.kind = kind
        self.path = path
        self.renditions = renditions
    }

    private enum CodingKeys: String, CodingKey { case kind, path, renditions }

    // Hand-written only so a missing or malformed `renditions` decodes as no ladder:
    // an older gateway sends none, and a bad ladder must cost the menu, not the route.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        path = try c.decode(String.self, forKey: .path)
        renditions = (try? c.decodeIfPresent([MebiusRendition].self, forKey: .renditions)) ?? []
    }

    /// Whether this route is safe to resolve against the Mebius gateway.
    ///
    /// The access token is a bearer credential and a delivery path arrives as data
    /// in a response. An absolute or protocol-relative path would send that token
    /// to a host Mebius did not choose, so those are rejected rather than fetched.
    public var isResolvable: Bool { Self.isResolvable(path) }

    static func isResolvable(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.hasPrefix("//") && !path.contains("://")
    }

    /// Parses the `deliveries` array from your token response, skipping any entry
    /// that is malformed.
    ///
    /// Skipping rather than throwing is deliberate: the list arrives over the
    /// network, and one bad entry must cost a viewer one route, not a failed play.
    ///
    /// - Parameter json: the raw `deliveries` value, as decoded JSON.
    public static func list(fromJSON json: Any?) -> [MebiusDelivery] {
        guard let array = json as? [Any] else { return [] }
        return array.compactMap { element in
            guard
                let object = element as? [String: Any],
                let kind = object["kind"] as? String, !kind.isEmpty,
                let path = object["path"] as? String, !path.isEmpty
            else { return nil }
            let renditions = (object["renditions"] as? [Any] ?? []).compactMap { rung -> MebiusRendition? in
                guard
                    let rung = rung as? [String: Any],
                    let id = rung["id"] as? String, !id.isEmpty,
                    let path = rung["path"] as? String, !path.isEmpty
                else { return nil }
                return MebiusRendition(
                    id: id,
                    height: (rung["height"] as? NSNumber)?.intValue,
                    bitrateKbps: (rung["bitrateKbps"] as? NSNumber)?.intValue,
                    path: path
                )
            }
            return MebiusDelivery(kind: kind, path: path, renditions: renditions)
        }
    }

    /// Parses the `deliveries` array out of a whole token-response body.
    public static func list(fromTokenResponse body: [String: Any]?) -> [MebiusDelivery] {
        list(fromJSON: body?["deliveries"])
    }
}

/// One rung of a route's quality ladder, as the gateway offered it.
///
/// ``path`` is opened exactly like ``MebiusDelivery/path``: gateway-relative, with
/// the same access token. Apps never need to read it — pick a rung by id through
/// ``MebiusPlayer/setQuality(_:)``.
public struct MebiusRendition: Equatable, Sendable, Decodable {
    /// Stable id, e.g. `"720p"`.
    public let id: String
    /// Frame height in pixels, when known.
    public let height: Int?
    /// Nominal video bitrate in kbps, when known.
    public let bitrateKbps: Int?
    /// Mebius-relative path of this rung alone.
    public let path: String

    public init(id: String, height: Int? = nil, bitrateKbps: Int? = nil, path: String) {
        self.id = id
        self.height = height
        self.bitrateKbps = bitrateKbps
        self.path = path
    }
}
