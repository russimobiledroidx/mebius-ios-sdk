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

    // Exactly one of these is active depending on the selected mode.
    private var subscribeTransport: SubscribeTransport?
    private var scalePlayback: ScalePlayback?

    init(client: MebiusClient, gateway: URL, token: String, mode: MebiusPlayerMode) {
        self.client = client
        self.gateway = gateway
        self.token = token
        self.mode = mode
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
        let endpoints = client.gatewayEndpoints

        switch mode {
        case .lowLatency:
            // Real-time low-latency delivery (WHEP) via the gateway.
            let config = SubscribeConfig(
                gateway: endpoints.lowLatencySubscribeURL(streamId: streamId),
                token: client.currentToken,
                streamId: streamId
            )
            let transport = TransportRegistry.factory.makeLowLatencySubscribeTransport(config: config)
            transport.delegate = self
            transport.setVolume(volume)
            transport.attachRenderer(to: view)
            self.subscribeTransport = transport
            transport.start()

        case .scale:
            // Scale delivery (adaptive HLS) via AVPlayer. Auto-selected; the
            // mechanism is not exposed to the developer.
            let url = endpoints.scalePlaylistURL(streamId: streamId)
            let playback = ScalePlayback(url: url, token: client.currentToken)
            playback.delegate = self
            self.scalePlayback = playback
            playback.start(in: view)
            playback.setVolume(volume)
        }
    }
    #endif

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
        isPlaying = true
        delegate?.mebiusPlayerDidStartPlaying(self)
        onPlaying?()
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
        isPlaying = false
        delegate?.mebiusPlayer(self, didFailWithError: error)
        onError?(error)
    }
}

extension MebiusPlayer: ScalePlaybackDelegate {
    func scalePlaybackDidStartPlaying(_ playback: ScalePlayback) {
        isPlaying = true
        delegate?.mebiusPlayerDidStartPlaying(self)
        onPlaying?()
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
