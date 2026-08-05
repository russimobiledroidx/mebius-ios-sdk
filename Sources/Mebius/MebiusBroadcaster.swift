import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Publishes camera and microphone media to a Mebius stream.
///
/// Create one via ``MebiusClient/createBroadcaster(video:audio:)``, attach a
/// ``MebiusVideoView`` preview, then call ``start(streamId:)``.
///
/// All methods must be called on the main thread; all callbacks are delivered
/// on the main thread.
public final class MebiusBroadcaster {

    /// Whether camera video is enabled for this broadcaster.
    public private(set) var videoEnabled: Bool

    /// Whether microphone audio is enabled for this broadcaster.
    public private(set) var audioEnabled: Bool

    /// Whether the broadcaster is currently publishing.
    public private(set) var isBroadcasting: Bool = false

    /// The stream id currently being published, if any.
    public private(set) var streamId: String?

    /// Delegate that receives broadcaster events on the main thread.
    public weak var delegate: MebiusBroadcasterDelegate?

    /// Invoked on the main thread when the broadcast starts.
    public var onStarted: (() -> Void)?
    /// Invoked on the main thread when the broadcast stops.
    public var onStopped: (() -> Void)?
    /// Invoked on the main thread with periodic statistics.
    public var onStats: ((MebiusBroadcastStats) -> Void)?
    /// Invoked on the main thread when an error occurs.
    public var onError: ((MebiusError) -> Void)?

    private weak var client: MebiusClient?
    private let gateway: URL
    private let token: String
    private let video: Bool
    private let audio: Bool
    private var transport: PublishTransport?
    #if canImport(UIKit)
    private weak var previewView: MebiusVideoView?
    #endif

    init(client: MebiusClient, gateway: URL, token: String, video: Bool, audio: Bool) {
        self.client = client
        self.gateway = gateway
        self.token = token
        self.video = video
        self.audio = audio
        self.videoEnabled = video
        self.audioEnabled = audio
    }

    #if canImport(UIKit)
    /// Attaches a view to display the local camera preview.
    ///
    /// - Parameter view: The ``MebiusVideoView`` that should show the preview.
    public func attachPreview(to view: MebiusVideoView) {
        assert(Thread.isMainThread, "Mebius must be used on the main thread")
        self.previewView = view
        transport?.attachPreview(to: view)
    }
    #endif

    /// Starts publishing to the given stream id.
    ///
    /// - Parameter streamId: The stream identifier to publish to.
    public func start(streamId: String) {
        assert(Thread.isMainThread, "Mebius must be used on the main thread")

        guard let client, client.isConnected else {
            emitError(.notConnected)
            return
        }

        self.streamId = streamId

        let endpoints = client.gatewayEndpoints
        // Internally this opens a real-time publish session to the gateway. Which
        // transport carries it lives in Internal/ and is not part of this surface.
        let config = PublishConfig(
            gateway: endpoints.publishURL(streamId: streamId, token: client.currentToken),
            token: client.currentToken,
            streamId: streamId,
            video: video,
            audio: audio
        )

        let transport = TransportRegistry.factory.makePublishTransport(config: config)
        transport.delegate = self
        self.transport = transport

        #if canImport(UIKit)
        if let previewView { transport.attachPreview(to: previewView) }
        #endif

        transport.start()
    }

    /// Stops publishing.
    public func stop() {
        assert(Thread.isMainThread, "Mebius must be used on the main thread")
        transport?.stop()
    }

    /// Switches between the front and back cameras.
    public func switchCamera() {
        transport?.switchCamera()
    }

    /// Enables or disables the microphone.
    ///
    /// - Parameter enabled: `true` to unmute, `false` to mute.
    public func setMicEnabled(_ enabled: Bool) {
        audioEnabled = enabled
        transport?.setMicEnabled(enabled)
    }

    /// Enables or disables the camera.
    ///
    /// - Parameter enabled: `true` to enable video, `false` to disable.
    public func setCameraEnabled(_ enabled: Bool) {
        videoEnabled = enabled
        transport?.setCameraEnabled(enabled)
    }

    private func emitError(_ error: MebiusError) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.mebiusBroadcaster(self, didFailWithError: error)
            self.onError?(error)
        }
    }
}

extension MebiusBroadcaster: PublishTransportDelegate {
    func publishTransportDidStart(_ transport: PublishTransport) {
        isBroadcasting = true
        delegate?.mebiusBroadcasterDidStart(self)
        onStarted?()
    }

    func publishTransportDidStop(_ transport: PublishTransport) {
        isBroadcasting = false
        streamId = nil
        delegate?.mebiusBroadcasterDidStop(self)
        onStopped?()
    }

    func publishTransport(_ transport: PublishTransport, didReportStats stats: MebiusBroadcastStats) {
        delegate?.mebiusBroadcaster(self, didReportStats: stats)
        onStats?(stats)
    }

    func publishTransport(_ transport: PublishTransport, didFail error: MebiusError) {
        isBroadcasting = false
        delegate?.mebiusBroadcaster(self, didFailWithError: error)
        onError?(error)
    }
}
