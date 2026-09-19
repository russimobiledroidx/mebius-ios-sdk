import Foundation

/// Mints a fresh short-lived token from your backend.
///
/// Call the completion with the new token, or with `nil` if it could not be
/// minted — Mebius then retries with backoff for as long as the current token is
/// still valid. The completion may be called from any queue.
public typealias MebiusTokenProvider = (@escaping (String?) -> Void) -> Void

/// Entry point for the Mebius live streaming SDK.
///
/// Initialize Mebius once with your application id and Mebius gateway endpoint,
/// then call ``connect(token:deliveries:)`` with a short-lived token minted by your backend.
///
/// ```swift
/// let mebius = Mebius(appId: "your-app-id", gateway: URL(string: "https://gateway.mebius.io")!)
/// let client = mebius.connect(token: backendToken)
/// ```
///
/// - Important: The client never holds your application secret. Your backend
///   mints a short-lived token from (appId + appSecret) and hands it to the app.
public final class Mebius {

    /// The application id issued for your Mebius project.
    public let appId: String

    /// The Mebius signaling gateway endpoint. All media flows through this host.
    public let gateway: URL

    /// Creates a Mebius instance.
    ///
    /// - Parameters:
    ///   - appId: The application id issued for your Mebius project.
    ///   - gateway: The Mebius signaling gateway endpoint.
    public init(appId: String, gateway: URL) {
        self.appId = appId
        self.gateway = gateway
        Mebius.bootstrapRealtimeTransport()
    }

    /// In the CocoaPods build (`MEBIUS_RTC`) this swaps the stub transport for
    /// the libwebrtc-backed real-time transport. In the SPM build it is a no-op
    /// and the stub remains active.
    private static let bootstrapOnce: Void = {
        #if MEBIUS_RTC
        RTCBootstrap.activate()
        #endif
    }()

    private static func bootstrapRealtimeTransport() {
        _ = bootstrapOnce
    }

    /// Creates a client and begins connecting to the Mebius gateway using a
    /// short-lived token from your backend.
    ///
    /// The returned client begins connecting asynchronously. Observe the
    /// connection result via ``MebiusClient/delegate`` or the
    /// ``MebiusClient/onConnected`` / ``MebiusClient/onError`` closures.
    ///
    /// - Parameters:
    ///   - token: A short-lived JWT minted by your backend.
    ///   - deliveries: The route list your backend returned with the token. Pass it
    ///     through as-is; Mebius orders it and picks from it. Optional, but without it
    ///     every viewer is served from Mebius origin rather than the nearest edge —
    ///     on mobile that is billed per viewer.
    ///   - getToken: Makes the session outlive one token. Given a provider, Mebius
    ///     mints a fresh credential shortly BEFORE `exp` and swaps it in place — no
    ///     reconnect, no renegotiation, no visible gap. A failing provider is retried
    ///     with backoff for as long as the current token is still valid, so
    ///     ``MebiusError/tokenExpired`` is reported only when the credential has
    ///     genuinely run out. Each renewal calls
    ///     ``MebiusClientDelegate/mebiusClientDidRefreshToken(_:)``. Without it
    ///     nothing changes: no renewal is scheduled and expiry surfaces exactly when
    ///     it always did.
    /// - Returns: A connecting ``MebiusClient``.
    public func connect(
        token: String,
        deliveries: [MebiusDelivery] = [],
        getToken: MebiusTokenProvider? = nil
    ) -> MebiusClient {
        let client = MebiusClient(
            appId: appId,
            gateway: gateway,
            token: token,
            deliveries: deliveries,
            getToken: getToken
        )
        client.beginConnecting()
        return client
    }
}
