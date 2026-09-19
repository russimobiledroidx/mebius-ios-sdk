import Foundation

/// Reads — never VERIFIES — a Mebius access token.
///
/// The token is a short-lived JWT minted by the application backend; only the
/// gateway holds the secret, so the client can do nothing but peek at the
/// payload. Two fields matter:
///
/// * `exp`      — when to renew, so a session can outlive one credential.
/// * `streamId` — what the credential is for, so swapping in a token minted for
///                another stream fails loudly instead of quietly breaking the
///                session on its next request.
///
/// Anything unreadable yields nil. A malformed token is the gateway's problem to
/// reject, and guessing here would turn a clear 401 into a client-side mystery.
struct TokenInfo {
    /// Expiry, or nil when the token carries no readable `exp`.
    let expiresAt: Date?
    /// The stream this token is scoped to, or nil when unreadable.
    let streamId: String?

    static let unreadable = TokenInfo(expiresAt: nil, streamId: nil)
}

/// Decodes the payload of `token`. Never throws.
func readToken(_ token: String) -> TokenInfo {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count >= 2, let data = base64URLDecode(String(parts[1])) else {
        return .unreadable
    }
    guard
        let object = try? JSONSerialization.jsonObject(with: data),
        let payload = object as? [String: Any]
    else {
        return .unreadable
    }
    let expiresAt = (payload["exp"] as? NSNumber).map {
        Date(timeIntervalSince1970: $0.doubleValue)
    }
    let streamId = (payload["streamId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    return TokenInfo(expiresAt: expiresAt, streamId: streamId)
}

/// base64url with the padding a JWT omits. Foundation only decodes standard
/// base64, so the two substitutions and the padding have to be done by hand.
private func base64URLDecode(_ input: String) -> Data? {
    var s = input.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = s.count % 4
    if remainder > 0 {
        s += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: s)
}
