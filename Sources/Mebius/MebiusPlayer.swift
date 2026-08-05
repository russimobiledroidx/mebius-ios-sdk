import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Plays a Mebius stream into a ``MebiusVideoView``.
///
/// Create one via ``MebiusClient/createPlayer(mode:)``, then call
/// ``play(streamId:view:)``. The delivery mechanism is selected automatically
/// based on the chosen ``MebiusPlayerMode``.
///
/// All methods must be called on the main thread; all callbacks are delivered
/// on the main thread.
public final class MebiusPlayer {

    /// The playback mode chosen for this player.
    public let mode: MebiusPlayerMode

    /// Whether the player is currently playing.
    public private(set) var isPlaying: Bool = false

    /// The stream id currently playing, if any.
    public private(set) var streamId: String?

    /// Current volume, from 0 (muted) to 1 (full).
    public private(set) var volume: Float = 1.0

    /// Delegate that receives player events on the main thread.
    public weak var delegate: MebiusPlayerDelegate?

    /// Invoked on the main thread when playback starts.
    public var onPlaying: (() -> Void)?
    /// Invoked on the main thread when playback buffers.
    public var onBuffering: (() -> Void)?
    /// Invoked on the main thread when playback ends.
    public var onEnded: (() -> Void)?
    /// Invoked on the main thread with periodic statistics.
    public var onStats: ((MebiusPlayerStats) -> Void)?
    /// Invoked on the main thread when an error occurs.
    public var onError: ((MebiusError) -> Void)?

    private weak var client: MebiusClient?
    private let gateway: URL
    private let token: String

    // At most one of these is active: the route currently being attempted.
    private var subscribeTransport: SubscribeTransport?
    private var scalePlayback: ScalePlayback?

    // Routes to attempt, in the gateway's preferred order. A LIST rather than one
    // transport is the point: a route that opens successfully is not yet a route
    // that plays, so the player has to be able to move on.
    private let routes: [PlaybackRoute]
    private var routeIndex = 0
    private var routeAccepted = false
    private var watchdog: DispatchWorkItem?

    // The render target for the route walk. UIKit-gated because the view type is:
    // the package builds on macOS for tooling, where there is nothing to render into.
    #if canImport(UIKit)
    private var pendingView: MebiusVideoView?
    #endif

    init(
        client: MebiusClient,
        gateway: URL,
        token: String,
        mode: MebiusPlayerMode,
        deliveries: [MebiusDelivery] = []
    ) {
        self.client = client
        self.gateway = gateway
        self.token = token
        self.mode = mode
        self.routes = buildPlaybackRoutes(mode: mode, deliveries: deliveries)
    }

    #if canImport(UIKit)
    /// Starts playing the given stream into a view.
    ///
    /// - Parameters:
    ///   - streamId: The stream identifier to play.
    ///   - view: The ``MebiusVideoView`` to render into.
    public func play(streamId: String, view: MebiusVideoView) {
        assert(Thread.isMainThread, "Mebius must be used on the main thread")

        guard let client, client.isConnected else {
            emitError(.notConnected)
            return
        }

        self.streamId = streamId
        view.detach()
        self.pendingView = view
        routeIndex = 0
        routeAccepted = false
        startCurrentRoute()
    }

    /// Opens the route at `routeIndex`, then arms the watchdog.
    private func startCurrentRoute() {
        guard
            let client,
            let view = pendingView,
            let streamId,
            routeIndex < routes.count
        else { return }

        let route = routes[routeIndex]
        let endpoints = client.gatewayEndpoints

        if route.isRealtime {
            let config = SubscribeConfig(
                gateway: endpoints.lowLatencySubscribeURL(streamId: streamId, token: client.currentToken),
                token: client.currentToken,
                streamId: streamId
            )
            let transport = TransportRegistry.factory.makeLowLatencySubscribeTransport(config: config)
            transport.delegate = self
            transport.setVolume(volume)
            transport.attachRenderer(to: view)
            self.subscribeTransport = transport
            transport.start()
        } else {
            // A gateway-offered route when there is one, the origin playlist otherwise.
            // deliveryURL returns nil for a path it cannot resolve safely; skipping
            // straight to the next route is the right answer there, because fetching it
            // would send the viewer's token to a host Mebius did not choose.
            let url: URL?
            if let path = route.deliveryPath {
                url = endpoints.deliveryURL(path: path, token: client.currentToken)
            } else {
                url = endpoints.originPlaylistURL(streamId: streamId, token: client.currentToken)
            }
            guard let url else {
                advance(after: .connectionFailed)
                return
            }
            let playback = ScalePlayback(url: url, token: client.currentToken)
            playback.delegate = self
            self.scalePlayback = playback
            playback.start(in: view)
            playback.setVolume(volume)
        }

        armWatchdog()
    }

    #endif

    /// Gives the current route ``mebiusFirstFrameTimeout`` to report playback.
    ///
    /// This is the whole reason a route list exists. A route that connects and sends
    /// nothing produces no error at all, so without a timer playback sits on a black
    /// frame indefinitely — which is what happened before this existed.
    private func armWatchdog() {
        cancelWatchdog()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.routeAccepted else { return }
            self.advance(after: .connectionFailed)
        }
        watchdog = task
        DispatchQueue.main.asyncAfter(deadline: .now() + mebiusFirstFrameTimeout, execute: task)
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    /// Tears the dead route down and tries the next, or reports `error`.
    private func advance(after error: MebiusError) {
        cancelWatchdog()
        // Release before opening the next route. An AVPlayer or peer connection left
        // attached to the same view leaks for the session and can keep rendering over
        // the route that replaces it.
        subscribeTransport?.stop()
        scalePlayback?.stop()
        subscribeTransport = nil
        scalePlayback = nil

        routeIndex += 1
        guard routeIndex < routes.count else {
            isPlaying = false
            #if canImport(UIKit)
            pendingView = nil
            #endif
            delegate?.mebiusPlayer(self, didFailWithError: error)
            onError?(error)
            return
        }
        #if canImport(UIKit)
        startCurrentRoute()
        #endif
    }

    /// Records that a route actually delivered, and forwards the event.
    private func acceptRoute() {
        routeAccepted = true
        cancelWatchdog()
        isPlaying = true
        delegate?.mebiusPlayerDidStartPlaying(self)
        onPlaying?()
    }

    /// Routes a failure: a real failure once video has arrived, otherwise a skip.
    private func handleFailure(_ error: MebiusError) {
        if routeAccepted {
            isPlaying = false
            delegate?.mebiusPlayer(self, didFailWithError: error)
            onError?(error)
        } else {
            advance(after: error)
        }
    }

    /// Stops playback and releases resources.
    public func stop() {
        assert(Thread.isMainThread, "Mebius must be used on the main thread")
        subscribeTransport?.stop()
        scalePlayback?.stop()
        subscribeTransport = nil
        scalePlayback = nil
        isPlaying = false
    }

    /// Sets the playback volume.
    ///
    /// - Parameter volume: A value from 0 (muted) to 1 (full). Values outside
    ///   the range are clamped.
    public func setVolume(_ volume: Float) {
        let clamped = max(0, min(1, volume))
        self.volume = clamped
        subscribeTransport?.setVolume(clamped)
        scalePlayback?.setVolume(clamped)
    }

    private func emitError(_ error: MebiusError) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.mebiusPlayer(self, didFailWithError: error)
            self.onError?(error)
        }
    }
}

extension MebiusPlayer: SubscribeTransportDelegate {
    func subscribeTransportDidStartPlaying(_ transport: SubscribeTransport) {
        guard transport === subscribeTransport else { return }
        acceptRoute()
    }

    func subscribeTransportDidBuffer(_ transport: SubscribeTransport) {
        delegate?.mebiusPlayerDidBuffer(self)
        onBuffering?()
    }

    func subscribeTransportDidEnd(_ transport: SubscribeTransport) {
        isPlaying = false
        delegate?.mebiusPlayerDidEnd(self)
        onEnded?()
    }

    func subscribeTransport(_ transport: SubscribeTransport, didReportStats stats: MebiusPlayerStats) {
        delegate?.mebiusPlayer(self, didReportStats: stats)
        onStats?(stats)
    }

    func subscribeTransport(_ transport: SubscribeTransport, didFail error: MebiusError) {
        // A route already abandoned must not fail the one now playing.
        guard transport === subscribeTransport else { return }
        handleFailure(error)
    }
}

extension MebiusPlayer: ScalePlaybackDelegate {
    func scalePlaybackDidStartPlaying(_ playback: ScalePlayback) {
        guard playback === scalePlayback else { return }
        acceptRoute()
    }

    func scalePlaybackDidBuffer(_ playback: ScalePlayback) {
        delegate?.mebiusPlayerDidBuffer(self)
        onBuffering?()
    }

    func scalePlaybackDidEnd(_ playback: ScalePlayback) {
        isPlaying = false
        delegate?.mebiusPlayerDidEnd(self)
        onEnded?()
    }

    func scalePlayback(_ playback: ScalePlayback, didReportStats stats: MebiusPlayerStats) {
        delegate?.mebiusPlayer(self, didReportStats: stats)
        onStats?(stats)
    }

    func scalePlayback(_ playback: ScalePlayback, didFail error: MebiusError) {
        isPlaying = false
        delegate?.mebiusPlayer(self, didFailWithError: error)
        onError?(error)
    }
}
