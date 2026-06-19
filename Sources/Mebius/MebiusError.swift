import Foundation

/// Errors surfaced by the Mebius SDK.
///
/// All cases use Mebius terminology. They never expose underlying transport or
/// infrastructure details to the developer.
public enum MebiusError: Error, Equatable {

    /// The authentication token supplied to ``Mebius/connect(token:)`` has
    /// expired. The application is expected to obtain a fresh token from its
    /// backend and reconnect. Maps to the wire code `TOKEN_EXPIRED`.
    case tokenExpired

    /// A required device permission (camera and/or microphone) was denied by
    /// the user. Maps to the wire code `PERMISSION_DENIED`.
    case permissionDenied

    /// The SDK could not establish or maintain a connection to the Mebius
    /// gateway. Maps to the wire code `CONNECTION_FAILED`.
    case connectionFailed

    /// An operation was requested that requires an active connection, but the
    /// client is not currently connected. Maps to the wire code `NOT_CONNECTED`.
    case notConnected

    /// The requested stream does not exist or is not currently available.
    /// Maps to the wire code `STREAM_NOT_FOUND`.
    case streamNotFound

    /// An unspecified error occurred. The associated message uses Mebius
    /// terminology and is safe to surface to developers.
    case unknown(message: String)

    /// The stable wire code associated with this error.
    public var code: String {
        switch self {
        case .tokenExpired: return "TOKEN_EXPIRED"
        case .permissionDenied: return "PERMISSION_DENIED"
        case .connectionFailed: return "CONNECTION_FAILED"
        case .notConnected: return "NOT_CONNECTED"
        case .streamNotFound: return "STREAM_NOT_FOUND"
        case .unknown: return "UNKNOWN"
        }
    }

    /// Creates a ``MebiusError`` from a stable wire code. Unknown codes map to
    /// ``MebiusError/unknown(message:)``.
    public init(code: String, message: String? = nil) {
        switch code.uppercased() {
        case "TOKEN_EXPIRED": self = .tokenExpired
        case "PERMISSION_DENIED": self = .permissionDenied
        case "CONNECTION_FAILED": self = .connectionFailed
        case "NOT_CONNECTED": self = .notConnected
        case "STREAM_NOT_FOUND": self = .streamNotFound
        default: self = .unknown(message: message ?? "An unknown Mebius error occurred.")
        }
    }
}

extension MebiusError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .tokenExpired:
            return "Mebius token expired. Request a fresh token from your backend and reconnect."
        case .permissionDenied:
            return "Mebius permission denied. Camera and/or microphone access was not granted."
        case .connectionFailed:
            return "Mebius connection failed. Could not reach the Mebius gateway."
        case .notConnected:
            return "Mebius client is not connected. Call connect(token:) before this operation."
        case .streamNotFound:
            return "Mebius stream not found. The requested stream is unavailable."
        case .unknown(let message):
            return "Mebius error: \(message)"
        }
    }
}
