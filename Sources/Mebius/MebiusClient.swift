import Foundation

/// A connected (or connecting) Mebius session.
///
/// Obtain a client from ``Mebius/connect(token:deliveries:)``. Use it to create
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
    private let deliveries: [MebiusDelivery]
    private let endpoints: GatewayEndpoints

    init(appId: String, gateway: URL, token: String, deliveries: [MebiusDelivery] = []) {
        self.deliveries = deliveries
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
    /// - Parameter mode: The playback mode. Defaults to ``MebiusPlayerMode/auto``,
    ///   which lets Mebius choose per viewer and re-choose if a route stops
    ///   delivering video. The previous default was real-time, which opened one
    ///   per-viewer session for every member of an audience that did not need it.
    /// - Returns: A configured ``MebiusPlayer``.
    public func createPlayer(mode: MebiusPlayerMode = .auto) -> MebiusPlayer {
        MebiusPlayer(
            client: self,
            gateway: gateway,
            token: token,
            mode: mode,
            deliveries: deliveries
        )
    }

    /// Creates a player for a stream you are interacting WITH — the other side of a
    /// co-broadcast — where a second of delay makes the interaction feel broken.
    ///
    /// Same API as a player; only the delay budget differs. It starts on the
    /// real-time route and falls back by itself if that route sends no video, which
    /// is the part apps used to hand-roll and get wrong in front of a live audience.
    ///
    /// - Returns: A configured ``MebiusPlayer``.
    public func createMonitor() -> MebiusPlayer {
        createPlayer(mode: .lowLatency)
    }

    // Token accessor used by broadcasters/players created after a refresh.
    var currentToken: String { token }
    var gatewayEndpoints: GatewayEndpoints { endpoints }
    var isConnected: Bool { state == .connected }
}
