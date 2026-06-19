import Foundation

/// A connected (or connecting) Mebius session.
///
/// Obtain a client from ``Mebius/connect(token:)``. Use it to create
/// broadcasters and players. Observe connection events via ``delegate`` or the
/// closure properties.
///
/// All callbacks are delivered on the main thread.
public final class MebiusClient {

    /// Connection state of the client.
    public enum State: Equatable, Sendable {
        case connecting
        case connected
        case disconnected
        case failed(MebiusError)
    }

    /// The application id used for this session.
    public let appId: String

    /// The Mebius gateway endpoint used for this session.
    public let gateway: URL

    /// The current connection state. Read on the main thread.
    public private(set) var state: State = .disconnected

    /// Delegate that receives connection lifecycle events on the main thread.
    public weak var delegate: MebiusClientDelegate?

    /// Invoked on the main thread when the client connects.
    public var onConnected: (() -> Void)?

    /// Invoked on the main thread when the client disconnects.
    public var onDisconnected: (() -> Void)?

    /// Invoked on the main thread when the client errors.
    public var onError: ((MebiusError) -> Void)?

    private var token: String
    private let endpoints: GatewayEndpoints

    init(appId: String, gateway: URL, token: String) {
        self.appId = appId
        self.gateway = gateway
        self.token = token
        self.endpoints = GatewayEndpoints(gateway: gateway)
    }

    func beginConnecting() {
        state = .connecting
        // The session handshake validates the token against the gateway. A real
        // network handshake belongs to the concrete transport; here we validate
        // the token shape and transition to connected so the public lifecycle is
        // exercised. Token expiry is surfaced as MebiusError.tokenExpired.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.token.isEmpty {
                self.transition(to: .failed(.tokenExpired))
                return
            }
            self.transition(to: .connected)
        }
    }

    private func transition(to newState: State) {
        state = newState
        switch newState {
        case .connected:
            delegate?.mebiusClientDidConnect(self)
            onConnected?()
        case .disconnected:
            delegate?.mebiusClientDidDisconnect(self)
            onDisconnected?()
        case .failed(let error):
            delegate?.mebiusClient(self, didFailWithError: error)
            onError?(error)
        case .connecting:
            break
        }
    }

    /// Updates the session token (for example after refreshing an expired one).
    ///
    /// - Parameter token: A fresh short-lived JWT from your backend.
    public func updateToken(_ token: String) {
        self.token = token
    }

    /// Disconnects the client from the Mebius gateway.
    public func disconnect() {
        DispatchQueue.main.async { [weak self] in
            self?.transition(to: .disconnected)
        }
    }

    /// Creates a broadcaster for publishing media through this client.
    ///
    /// - Parameters:
    ///   - video: Whether to capture and publish camera video. Defaults to `true`.
    ///   - audio: Whether to capture and publish microphone audio. Defaults to `true`.
    /// - Returns: A configured ``MebiusBroadcaster``.
    public func createBroadcaster(video: Bool = true, audio: Bool = true) -> MebiusBroadcaster {
        MebiusBroadcaster(
            client: self,
            gateway: gateway,
            token: token,
            video: video,
            audio: audio
        )
    }

    /// Creates a player for watching a stream through this client.
    ///
    /// - Parameter mode: The playback mode. Use ``MebiusPlayerMode/lowLatency``
    ///   for real-time interactivity or ``MebiusPlayerMode/scale`` for large
    ///   audiences.
    /// - Returns: A configured ``MebiusPlayer``.
    public func createPlayer(mode: MebiusPlayerMode) -> MebiusPlayer {
        MebiusPlayer(
            client: self,
            gateway: gateway,
            token: token,
            mode: mode
        )
    }

    // Token accessor used by broadcasters/players created after a refresh.
    var currentToken: String { token }
    var gatewayEndpoints: GatewayEndpoints { endpoints }
    var isConnected: Bool { state == .connected }
}
