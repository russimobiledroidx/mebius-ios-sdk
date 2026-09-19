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

    /// Invoked on the main thread after the session's credential was renewed.
    public var onTokenRefreshed: (() -> Void)?

    private var token: String
    private let deliveries: [MebiusDelivery]
    private let endpoints: GatewayEndpoints
    private let getToken: MebiusTokenProvider?
    private var refreshWork: DispatchWorkItem?
    private var refreshFailures = 0

    /// Bumped whenever the credential is replaced by anyone.
    ///
    /// An automatic renewal waits on an app-supplied provider, and during that wait
    /// the app may call ``updateToken(_:)`` itself. Without this counter the
    /// provider's late answer would silently overwrite the token the app just set —
    /// and re-arm a schedule for it. A refresh holding a stale generation has been
    /// superseded and drops its result.
    private var tokenGeneration = 0

    /// Renew this far ahead of expiry.
    ///
    /// Wide enough that a slow backend, a couple of retries and a timer delayed by
    /// a backgrounded app all still land before the old credential dies. The old one
    /// keeps working the whole time, so being early costs nothing.
    private static let refreshMargin: TimeInterval = 60

    /// First retry delay after a failed renewal; doubles up to `retryMax`.
    private static let retryBase: TimeInterval = 2
    private static let retryMax: TimeInterval = 30

    init(
        appId: String,
        gateway: URL,
        token: String,
        deliveries: [MebiusDelivery] = [],
        getToken: MebiusTokenProvider? = nil
    ) {
        self.deliveries = deliveries
        self.appId = appId
        self.gateway = gateway
        self.token = token
        self.getToken = getToken
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
            self.scheduleRefresh(readToken(self.token).expiresAt)
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

    /// Replaces the credential this session authenticates with, in place.
    ///
    /// Publishing and playback are NOT stopped: there is no renegotiation, no track
    /// rebuild and no reconnect. Broadcasters and players read the token lazily, so
    /// the new one is simply what their next gateway request carries. For a camera
    /// publisher that is the difference between a six-hour broadcast and one that
    /// drops mid-match to reconnect.
    ///
    /// - Parameter token: A fresh short-lived JWT from your backend.
    /// - Throws: ``MebiusError/tokenExpired`` if `token` is empty, or
    ///   ``MebiusError/streamNotFound`` if it is scoped to a different stream than
    ///   the current one — swapping in a credential for another stream would not
    ///   renew this session, it would break it on the next request, far from the
    ///   line that caused it.
    public func updateToken(_ token: String) throws {
        // Main thread, like every other mutating entry point in this SDK. The
        // automatic renewal hops to main before touching this same state, so a
        // background caller here would race it on `refreshWork` — a reference-typed
        // optional with no synchronisation — and lose a cancel, or worse. Backend
        // completion handlers commonly fire off-main, so this is a real path, not a
        // theoretical one; the README example dispatches to main for that reason.
        assert(Thread.isMainThread, "Mebius must be used on the main thread")
        guard !token.isEmpty else { throw MebiusError.tokenExpired }
        let next = readToken(token)
        let current = readToken(self.token)
        if let nextStream = next.streamId,
           let currentStream = current.streamId,
           nextStream != currentStream {
            throw MebiusError.streamNotFound
        }
        self.token = token
        refreshFailures = 0
        tokenGeneration += 1
        scheduleRefresh(next.expiresAt)
    }

    /// Arms the renewal that keeps this session alive past `expiresAt`.
    ///
    /// Nothing is armed without a `getToken` provider. That is deliberate and is the
    /// compatibility guarantee: an app written against 0.2.x sees exactly the
    /// behaviour it saw before — the gateway rejects the expired token on the next
    /// request and the SDK reports it then, at the same moment it always did. No new
    /// timer, no new error, no new callback.
    private func scheduleRefresh(_ expiresAt: Date?) {
        // An unreadable expiry is not a reason to DISARM. A token this SDK cannot
        // parse is still one the gateway may well accept, and silently turning
        // auto-renewal off for the rest of the session — with no event and no error
        // — is the worst available answer. Leave whatever is already armed.
        guard let getToken, let expiresAt else { return }
        refreshWork?.cancel()
        refreshWork = nil
        let lead = max(0, expiresAt.timeIntervalSinceNow - Self.refreshMargin)
        let work = DispatchWorkItem { [weak self] in
            self?.refresh(using: getToken, previousExpiry: expiresAt)
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lead, execute: work)
    }

    private func refresh(using getToken: @escaping MebiusTokenProvider, previousExpiry: Date) {
        guard isConnected else { return }
        let generation = tokenGeneration
        getToken { [weak self] next in
            // Providers are the app's own code and may answer on any queue; every
            // piece of state below is main-thread-owned.
            DispatchQueue.main.async {
                self?.applyRefreshed(
                    next,
                    using: getToken,
                    previousExpiry: previousExpiry,
                    generation: generation
                )
            }
        }
    }

    private func applyRefreshed(
        _ next: String?,
        using getToken: @escaping MebiusTokenProvider,
        previousExpiry: Date,
        generation: Int
    ) {
        // Disconnected, or the credential was replaced by updateToken while the
        // provider was thinking. Either way this answer is stale: applying it would
        // revive a dead session or undo the app's own swap.
        guard isConnected, generation == tokenGeneration else { return }
        guard let next, !next.isEmpty else {
            onRefreshFailed(using: getToken, expiry: previousExpiry)
            return
        }
        let info = readToken(next)
        let current = readToken(token)
        if let nextStream = info.streamId,
           let currentStream = current.streamId,
           nextStream != currentStream {
            // The same guard updateToken applies by hand. A provider closure holding
            // a stale stream id would otherwise install a credential that breaks the
            // session on its next request, with nothing pointing at the cause.
            onRefreshFailed(using: getToken, expiry: previousExpiry)
            return
        }
        if let expiry = info.expiresAt, expiry <= previousExpiry {
            // A token that does not outlive the one it replaces cannot keep the
            // session alive, so it is a failed mint — handled as one. This used to
            // fail the session outright, which killed a live broadcast a full margin
            // BEFORE its credential actually expired, for the very common case of a
            // backend briefly re-serving a cached token. Retrying inside the
            // remaining window still ends in one `.tokenExpired` if the provider
            // never produces a newer token.
            onRefreshFailed(using: getToken, expiry: previousExpiry)
            return
        }
        refreshFailures = 0
        token = next
        tokenGeneration += 1
        delegate?.mebiusClientDidRefreshToken(self)
        onTokenRefreshed?()
        scheduleRefresh(info.expiresAt)
    }

    /// A failed renewal is not a dead session: the current token is valid until
    /// `expiry` and the broadcast is still live. Retry inside that window, and report
    /// expiry only once the window has actually run out.
    private func onRefreshFailed(using getToken: @escaping MebiusTokenProvider, expiry: Date) {
        // disconnect() may have run while the provider was thinking. Re-arming here
        // would leave a live timer owned by nobody.
        guard isConnected else { return }
        let remaining = expiry.timeIntervalSinceNow
        guard remaining > 0 else {
            transition(to: .failed(.tokenExpired))
            return
        }
        refreshFailures += 1
        let backoff = Self.retryBase * pow(2, Double(refreshFailures - 1))
        let delay = min(backoff, Self.retryMax, remaining)
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refresh(using: getToken, previousExpiry: expiry)
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Disconnects the client from the Mebius gateway.
    public func disconnect() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshWork?.cancel()
            self?.refreshWork = nil
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
