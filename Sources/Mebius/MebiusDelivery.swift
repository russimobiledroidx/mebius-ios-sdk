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

    public init(kind: String, path: String) {
        self.kind = kind
        self.path = path
    }

    /// Whether this route is safe to resolve against the Mebius gateway.
    ///
    /// The access token is a bearer credential and a delivery path arrives as data
    /// in a response. An absolute or protocol-relative path would send that token
    /// to a host Mebius did not choose, so those are rejected rather than fetched.
    public var isResolvable: Bool {
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
            return MebiusDelivery(kind: kind, path: path)
        }
    }

    /// Parses the `deliveries` array out of a whole token-response body.
    public static func list(fromTokenResponse body: [String: Any]?) -> [MebiusDelivery] {
        list(fromJSON: body?["deliveries"])
    }
}
