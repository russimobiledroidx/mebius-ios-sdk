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
    /// Invoked on the main thread when the selectable renditions change.
    public var onQualitiesChanged: (([MebiusQuality]) -> Void)?

    /// Renditions this stream can actually be switched between.
    ///
    /// Empty means there is exactly one rendition — or a route with no such concept
    /// — and a UI should HIDE its quality menu rather than offer a choice that does
    /// not exist. That is the whole reason this exists: a player built against an
    /// HLS ladder has a menu, and without a programmatic answer the only options
    /// were to show a fake one or to delete the feature on a hunch.
    ///
    /// It is empty for every Mebius stream today: the engine publishes one rendition
    /// and does no ladder transcoding. The property is here so a client can be
    /// written once, against the honest answer, and keep working unchanged if that
    /// ever changes.
    ///
    /// The list is per ROUTE, so it is re-read on failover and announced through
    /// ``MebiusPlayerDelegate/mebiusPlayer(_:didChangeQualities:)``.
    public private(set) var qualities: [MebiusQuality] = []

    /// Chooses a rendition, or `"auto"` to let Mebius decide (the default).
    ///
    /// - Parameter id: `"auto"`, or an id from ``qualities``.
    /// - Throws: ``MebiusError/streamNotFound`` if `id` is neither — a UI that asks
    ///   for a rendition and gets no error would otherwise show the wrong state
    ///   forever. Throwing does not touch playback: the stream keeps running on
    ///   whatever it is running on.
    public func setQuality(_ id: String) throws {
        guard id == "auto" || qualities.contains(where: { $0.id == id }) else {
            throw MebiusError.streamNotFound
        }
        // With one rendition there is nothing to switch to, so an accepted call is a
        // no-op. No state is kept for it: an unread "selected id" would be a second
        // source of truth to keep in step with the route, for no reader.
    }

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

    // Reopening a route that WAS delivering and then stopped. See loseRoute().
    private var recovery = RecoveryPolicy()
    private var isRecovering = false
    private var recoveryCause: MebiusError?
    private var recoveryTask: DispatchWorkItem?
    private var stallTask: DispatchWorkItem?

    /// Set by ``stop()``. A recovery task can be several seconds deep in a
    /// backoff when the caller gives up, and it must not reopen a route into a
    /// player that has been torn down. A flag rather than blanking `streamId`,
    /// which is public: an app reading it back after stop() must still see the
    /// stream it was playing.
    private var isStopped = false

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
        isStopped = false
        isRecovering = false
        recoveryCause = nil
        recovery.reset()
        cancelStall()
        cancelRecovery()
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
            // Inside a recovery cycle this is not a verdict, it is one attempt that
            // found nothing serving. The next attempt is the answer.
            if isRecovering {
                scheduleRecoveryAttempt()
                return
            }
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
        cancelStall()
        // Proven healthy, so the recovery budget starts over. It counts
        // CONSECUTIVE failures, not failures for the life of the player.
        isRecovering = false
        recoveryCause = nil
        recovery.reset()
        isPlaying = true
        // Routes may differ in what they can offer, so the list is published per
        // accepted route rather than once per player.
        //
        // No Mebius route exposes a ladder — the engine publishes a single rendition
        // (`hlsVariant: lowLatency`, no ABR). Empty is the truthful answer, and this
        // is the one place that has to change if that stops being true.
        qualities = []
        delegate?.mebiusPlayer(self, didChangeQualities: qualities)
        onQualitiesChanged?(qualities)
        delegate?.mebiusPlayerDidStartPlaying(self)
        onPlaying?()
    }

    /// Routes a failure: try to get the stream back once video has arrived,
    /// otherwise skip to the next route.
    private func handleFailure(_ error: MebiusError) {
        if routeAccepted {
            loseRoute(error)
        } else {
            advance(after: error)
        }
    }

    /// Treats the serving route as dead and starts reopening the stream.
    ///
    /// This is the difference between a broadcast a viewer can leave running and
    /// one that has to be restarted by hand. Route selection ran once, in
    /// ``play(streamId:view:)``: whichever route produced a frame served the rest
    /// of the session, and when it later died — a CDN edge restarting, the
    /// publisher reconnecting, the phone changing network — playback stopped and
    /// stayed stopped.
    ///
    /// The reopen walks the full route list again rather than retrying the dead
    /// one, because the usual causes take out one route and not the others. The
    /// token needs no handling here: ``MebiusClient`` renews it on its own
    /// schedule, and every route stamps the current token as it builds its URL.
    ///
    /// - Parameter cause: the failure that lost the route, or `nil` when it simply
    ///   ended. Kept so that giving up reports what happened rather than a guess.
    private func loseRoute(_ cause: MebiusError?) {
        guard !isRecovering, routeAccepted else { return }
        isRecovering = true
        recoveryCause = cause
        cancelWatchdog()
        cancelStall()
        // Tell the app before the first backoff. A spinner a second late still
        // beats a still picture with nothing said about it.
        delegate?.mebiusPlayerDidBuffer(self)
        onBuffering?()
        subscribeTransport?.stop()
        scalePlayback?.stop()
        subscribeTransport = nil
        scalePlayback = nil
        scheduleRecoveryAttempt()
    }

    private func scheduleRecoveryAttempt() {
        cancelWatchdog()
        cancelRecovery()
        guard !recovery.isExhausted else {
            giveUp()
            return
        }
        let delay = recovery.nextDelay()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.recoveryTask = nil
            // stop() can land anywhere inside the backoff, and reopening into a
            // view the app has released is worse than not recovering at all.
            guard !self.isStopped, self.streamId != nil else { return }
            self.routeIndex = 0
            self.routeAccepted = false
            #if canImport(UIKit)
            guard self.pendingView != nil else { return }
            self.startCurrentRoute()
            #endif
        }
        recoveryTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    /// Every route refused for the whole budget. Either the broadcast really is
    /// over or this device is off the network; both end the session as far as the
    /// app is concerned, and the reason reported is the one that lost the route.
    private func giveUp() {
        isRecovering = false
        isPlaying = false
        subscribeTransport?.stop()
        scalePlayback?.stop()
        subscribeTransport = nil
        scalePlayback = nil
        let cause = recoveryCause
        recoveryCause = nil
        if let cause {
            delegate?.mebiusPlayer(self, didFailWithError: cause)
            onError?(cause)
        } else {
            delegate?.mebiusPlayerDidEnd(self)
            onEnded?()
        }
    }

    /// Starts the countdown that turns an endless stall into a lost route.
    ///
    /// Armed on the first buffering report and cancelled by playback. Re-arming on
    /// every repeat would push the deadline out forever, because a frozen AVPlayer
    /// keeps reporting.
    private func armStall() {
        guard stallTask == nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stallTask = nil
            self.loseRoute(nil)
        }
        stallTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + mebiusStallRecoveryTimeout, execute: task)
    }

    private func cancelStall() {
        stallTask?.cancel()
        stallTask = nil
    }

    private func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    /// A route that was delivering reported buffering.
    private func noteBuffering() {
        if routeAccepted { armStall() }
        delegate?.mebiusPlayerDidBuffer(self)
        onBuffering?()
    }

    /// A route reported the end of what it can serve.
    ///
    /// Not necessarily the end of the broadcast: a segmented route says this when
    /// the publisher reconnected, when the edge recycled the session, when the
    /// playlist went away for a moment. On a broadcast that runs for days that
    /// happens long before the host stops, so it is treated as a lost route and
    /// PROVEN to be an ending — ``giveUp()`` emits the end once reopening failed.
    private func noteEnded() {
        guard routeAccepted else {
            // It never delivered a frame, so this is not the broadcast ending —
            // it is a route that closed on us, and the next one is the answer.
            // Waiting for the first-frame watchdog instead would cost the viewer
            // the rest of that budget for information already in hand.
            advance(after: .connectionFailed)
            return
        }
        loseRoute(nil)
    }

    /// Stops playback and releases resources.
    public func stop() {
        assert(Thread.isMainThread, "Mebius must be used on the main thread")
        cancelWatchdog()
        cancelStall()
        cancelRecovery()
        isStopped = true
        isRecovering = false
        recoveryCause = nil
        recovery.reset()
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
        guard transport === subscribeTransport else { return }
        noteBuffering()
    }

    func subscribeTransportDidEnd(_ transport: SubscribeTransport) {
        guard transport === subscribeTransport else { return }
        noteEnded()
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
        guard playback === scalePlayback else { return }
        noteBuffering()
    }

    func scalePlaybackDidEnd(_ playback: ScalePlayback) {
        guard playback === scalePlayback else { return }
        noteEnded()
    }

    func scalePlayback(_ playback: ScalePlayback, didReportStats stats: MebiusPlayerStats) {
        delegate?.mebiusPlayer(self, didReportStats: stats)
        onStats?(stats)
    }

    func scalePlayback(_ playback: ScalePlayback, didFail error: MebiusError) {
        // Identity-checked and routed like the realtime path. Without the guard a
        // route the player had already abandoned could fail the one now playing;
        // without handleFailure a segmented route that broke during the walk
        // reported an error to the app instead of failing over to the next route,
        // which is the one thing the route list exists to do.
        guard playback === scalePlayback else { return }
        handleFailure(error)
    }
}
