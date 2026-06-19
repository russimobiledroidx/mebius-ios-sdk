import Foundation

/// Entry point for the Mebius live streaming SDK.
///
/// Initialize Mebius once with your application id and Mebius gateway endpoint,
/// then call ``connect(token:)`` with a short-lived token minted by your backend.
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
    }

    /// Creates a client and begins connecting to the Mebius gateway using a
    /// short-lived token from your backend.
    ///
    /// The returned client begins connecting asynchronously. Observe the
    /// connection result via ``MebiusClient/delegate`` or the
    /// ``MebiusClient/onConnected`` / ``MebiusClient/onError`` closures.
    ///
    /// - Parameter token: A short-lived JWT minted by your backend.
    /// - Returns: A connecting ``MebiusClient``.
    public func connect(token: String) -> MebiusClient {
        let client = MebiusClient(appId: appId, gateway: gateway, token: token)
        client.beginConnecting()
        return client
    }
}
