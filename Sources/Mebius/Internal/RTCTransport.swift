import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Concrete real-time transport (libwebrtc)
//
// This file is compiled ONLY when the SDK is built with the libwebrtc binary
// available, signalled by the `MEBIUS_RTC` Swift compilation condition. That
// flag is set by the CocoaPods distribution (see Mebius.podspec), which brings
// in the WebRTC binary that is not available to a plain `swift build`.
//
// It wires the real-time path:
//   - publish   -> RTCPeerConnection negotiated against the gateway publish URL
//                  via a WHIP SDP exchange (HTTP POST offer, 201 + answer).
//   - subscribe (low latency) -> recvonly RTCPeerConnection negotiated against
//                  the gateway subscribe URL via a WHEP SDP exchange.
//   - camera capture + local/remote render views are bridged into
//                  MebiusVideoView.
//
// The transport protocols are identical to the stub so the rest of the SDK is
// unchanged regardless of which factory is active.

#if MEBIUS_RTC
import WebRTC

// MARK: Shared factory

/// Lazily-created process-wide peer-connection factory. libwebrtc requires a
/// single factory to own the media engine; creating one per connection leaks
/// audio units.
private enum RTCFactory {
    static let shared: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        // Publish H264, whatever the encoder factory's default order happens to
        // be on this libwebrtc build.
        //
        // A VP8 offer is a dead end for every viewer who is not on the
        // real-time route: the gateway's segment-based deliveries cannot carry
        // VP8, so they drop the video track and the broadcast arrives as audio
        // only — with a healthy preview, bitrate and connection state on the
        // device the whole time. That is exactly what happened on the web SDK,
        // where Chrome does default to VP8.
        //
        // preferredCodec only moves H264 to the front of supportedCodecs; the
        // rest stay available, so a device that cannot encode H264 still
        // negotiates something.
        if let h264 = encoder.supportedCodecs().first(where: { $0.name == kRTCVideoCodecH264Name }) {
            encoder.preferredCodec = h264
        }
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()
}

// MARK: WHIP/WHEP signaling

/// Performs the one-shot SDP offer/answer exchange used by WHIP (publish) and
/// WHEP (subscribe). Both speak the same wire contract: POST the local offer as
/// `application/sdp` carrying the Mebius access token, expect a `201` whose body is
/// the SDP answer.
///
/// `url` must already carry `?token=` — GatewayEndpoints puts it there. The
/// gateway's MediaMTX auth hook reads the query and ignores `Authorization`, so a
/// header-only request is rejected with 401 however valid the token is, which is
/// what this transport did before. The Bearer header is still sent as a courtesy to
/// gateways that prefer it, but the query is what is enforced.
private enum WHIPWHEPSignaling {
    static func exchange(
        offer: String,
        url: URL,
        token: String,
        completion: @escaping (Result<String, MebiusError>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.setValue("application/sdp", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = offer.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(.failure(.connectionFailed))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.connectionFailed))
                return
            }
            switch http.statusCode {
            case 200, 201:
                guard let data, let answer = String(data: data, encoding: .utf8), !answer.isEmpty else {
                    completion(.failure(.connectionFailed))
                    return
                }
                completion(.success(answer))
            case 401, 403:
                completion(.failure(.tokenExpired))
            case 404:
                completion(.failure(.streamNotFound))
            default:
                completion(.failure(.connectionFailed))
            }
        }.resume()
    }
}

// MARK: Factory

final class RTCTransportFactory: TransportFactory {
    func makePublishTransport(config: PublishConfig) -> PublishTransport {
        RTCPublishTransport(config: config)
    }
    func makeLowLatencySubscribeTransport(config: SubscribeConfig) -> SubscribeTransport {
        RTCSubscribeTransport(config: config)
    }
}

// MARK: Publish (WHIP)

final class RTCPublishTransport: NSObject, PublishTransport, RTCPeerConnectionDelegate {
    weak var delegate: PublishTransportDelegate?

    private let config: PublishConfig
    private let endpoints: GatewayEndpoints

    private var peerConnection: RTCPeerConnection?
    private var videoSource: RTCVideoSource?
    private var videoTrack: RTCVideoTrack?
    private var audioTrack: RTCAudioTrack?
    private var capturer: RTCCameraVideoCapturer?
    private var usingFrontCamera = true
    private var statsTimer: Timer?
    private var started = false

    #if canImport(UIKit)
    private weak var previewView: MebiusVideoView?
    private var localRenderer: RTCMTLVideoView?
    #endif

    init(config: PublishConfig) {
        self.config = config
        self.endpoints = GatewayEndpoints(gateway: config.gateway)
        super.init()
    }

    func start() {
        let rtcConfig = RTCConfiguration()
        rtcConfig.sdpSemantics = .unifiedPlan
        rtcConfig.bundlePolicy = .maxBundle
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = RTCFactory.shared.peerConnection(with: rtcConfig, constraints: constraints, delegate: self) else {
            fail(.connectionFailed)
            return
        }
        peerConnection = pc

        let streamId = "mebius-local"
        if config.audio {
            let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            let source = RTCFactory.shared.audioSource(with: audioConstraints)
            let track = RTCFactory.shared.audioTrack(with: source, trackId: "audio0")
            audioTrack = track
            pc.add(track, streamIds: [streamId])
        }
        if config.video {
            let source = RTCFactory.shared.videoSource()
            videoSource = source
            let track = RTCFactory.shared.videoTrack(with: source, trackId: "video0")
            videoTrack = track
            pc.add(track, streamIds: [streamId])
            startCapture(source: source)
            #if canImport(UIKit)
            attachLocalRendererIfPossible()
            #endif
        }

        let offerConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc.offer(for: offerConstraints) { [weak self] sdp, error in
            guard let self else { return }
            guard let sdp, error == nil else {
                self.fail(.connectionFailed)
                return
            }
            pc.setLocalDescription(sdp) { [weak self] error in
                guard let self else { return }
                if error != nil { self.fail(.connectionFailed); return }
                WHIPWHEPSignaling.exchange(
                    offer: sdp.sdp,
                    url: self.endpoints.publishURL(streamId: self.config.streamId, token: self.config.token),
                    token: self.config.token
                ) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .failure(let err):
                        self.fail(err)
                    case .success(let answerSDP):
                        let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
                        pc.setRemoteDescription(answer) { [weak self] error in
                            if error != nil { self?.fail(.connectionFailed) }
                        }
                    }
                }
            }
        }
    }

    private func startCapture(source: RTCVideoSource) {
        let capturer = RTCCameraVideoCapturer(delegate: source)
        self.capturer = capturer
        guard let device = selectCamera(front: usingFrontCamera),
              let format = selectFormat(for: device),
              let fps = selectFps(for: format) else { return }
        capturer.startCapture(with: device, format: format, fps: fps)
    }

    private func selectCamera(front: Bool) -> AVCaptureDevice? {
        let position: AVCaptureDevice.Position = front ? .front : .back
        return RTCCameraVideoCapturer.captureDevices().first { $0.position == position }
            ?? RTCCameraVideoCapturer.captureDevices().first
    }

    private func selectFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let target = 1280 * 720
        return RTCCameraVideoCapturer.supportedFormats(for: device).min { a, b in
            let da = a.formatDescription
            let db = b.formatDescription
            let dimA = CMVideoFormatDescriptionGetDimensions(da)
            let dimB = CMVideoFormatDescriptionGetDimensions(db)
            let areaA = Int(dimA.width) * Int(dimA.height)
            let areaB = Int(dimB.width) * Int(dimB.height)
            return abs(areaA - target) < abs(areaB - target)
        }
    }

    private func selectFps(for format: AVCaptureDevice.Format) -> Int? {
        let maxFps = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 30
        return Int(min(30, maxFps))
    }

    func stop() {
        capturer?.stopCapture()
        capturer = nil
        statsTimer?.invalidate()
        statsTimer = nil
        peerConnection?.close()
        peerConnection = nil
        #if canImport(UIKit)
        DispatchQueue.main.async { [weak self] in
            self?.localRenderer?.removeFromSuperview()
            self?.localRenderer = nil
        }
        #endif
        onMain { [weak self] in
            guard let self else { return }
            self.delegate?.publishTransportDidStop(self)
        }
    }

    func switchCamera() {
        usingFrontCamera.toggle()
        guard let source = videoSource else { return }
        capturer?.stopCapture { [weak self] in
            guard let self else { return }
            self.startCapture(source: source)
        }
    }

    func setMicEnabled(_ enabled: Bool) { audioTrack?.isEnabled = enabled }
    func setCameraEnabled(_ enabled: Bool) { videoTrack?.isEnabled = enabled }

    #if canImport(UIKit)
    func attachPreview(to view: MebiusVideoView) {
        previewView = view
        attachLocalRendererIfPossible()
    }

    private func attachLocalRendererIfPossible() {
        guard let view = previewView, let track = videoTrack else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let renderer = RTCMTLVideoView(frame: view.bounds)
            renderer.videoContentMode = .scaleAspectFill
            renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(renderer)
            self.localRenderer = renderer
            track.add(renderer)
        }
    }
    #endif

    private func startStatsTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statsTimer?.invalidate()
            self.statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.collectStats()
            }
        }
    }

    // Previous byte count and the moment it was read. Bitrate is a rate, so it can
    // only come from a delta between two samples; a single report cannot give it.
    private var lastBytesSent: Int64 = 0
    private var lastStatsAt: Date?

    private func collectStats() {
        guard let pc = peerConnection else { return }
        pc.statistics { [weak self] report in
            guard let self else { return }
            var frameRate = 0.0
            var packetsSent = 0
            var bytesSent: Int64 = 0
            var rtt: TimeInterval?
            for (_, stat) in report.statistics {
                if stat.type == "outbound-rtp" {
                    packetsSent += (stat.values["packetsSent"] as? NSNumber)?.intValue ?? 0
                    bytesSent += (stat.values["bytesSent"] as? NSNumber)?.int64Value ?? 0
                    if let fps = (stat.values["framesPerSecond"] as? NSNumber)?.doubleValue { frameRate = fps }
                } else if stat.type == "candidate-pair", let r = stat.values["currentRoundTripTime"] as? NSNumber {
                    rtt = r.doubleValue
                }
            }

            // `bitrate` was declared, never assigned, and reported as 0 forever — the
            // compiler flagged it as never-mutated, which is how it surfaced. A
            // broadcaster watching its own stats saw a healthy stream at 0 kbps.
            let now = Date()
            var bitrate = 0
            if let previous = self.lastStatsAt {
                let seconds = now.timeIntervalSince(previous)
                let deltaBytes = bytesSent - self.lastBytesSent
                if seconds > 0, deltaBytes > 0 {
                    bitrate = Int(Double(deltaBytes) * 8 / seconds)
                }
            }
            self.lastBytesSent = bytesSent
            self.lastStatsAt = now
            let stats = MebiusBroadcastStats(bitrate: bitrate, frameRate: frameRate, roundTripTime: rtt, packetsSent: packetsSent)
            self.onMain { self.delegate?.publishTransport(self, didReportStats: stats) }
        }
    }

    private func fail(_ error: MebiusError) {
        onMain { [weak self] in
            guard let self else { return }
            self.delegate?.publishTransport(self, didFail: error)
        }
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    // MARK: RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        switch newState {
        case .connected:
            guard !started else { return }
            started = true
            startStatsTimer()
            onMain { [weak self] in
                guard let self else { return }
                self.delegate?.publishTransportDidStart(self)
            }
        case .failed:
            fail(.connectionFailed)
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    // Required by RTCPeerConnectionDelegate. Mebius negotiates media only — no data
    // channel is ever created on our side — but the protocol has no default
    // implementation, so omitting it is a compile error under CocoaPods (which builds
    // against the real WebRTC binary). SwiftPM never compiles this file, so `swift
    // build` stayed green while `pod lib lint` failed on exactly this.
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: Subscribe (WHEP, low latency)

final class RTCSubscribeTransport: NSObject, SubscribeTransport, RTCPeerConnectionDelegate {
    weak var delegate: SubscribeTransportDelegate?

    private let config: SubscribeConfig
    private let endpoints: GatewayEndpoints

    private var peerConnection: RTCPeerConnection?
    private var remoteVideoTrack: RTCVideoTrack?
    private var remoteAudioTrack: RTCAudioTrack?
    private var statsTimer: Timer?
    private var playing = false

    #if canImport(UIKit)
    private weak var renderView: MebiusVideoView?
    private var remoteRenderer: RTCMTLVideoView?
    #endif

    init(config: SubscribeConfig) {
        self.config = config
        self.endpoints = GatewayEndpoints(gateway: config.gateway)
        super.init()
    }

    func start() {
        let rtcConfig = RTCConfiguration()
        rtcConfig.sdpSemantics = .unifiedPlan
        rtcConfig.bundlePolicy = .maxBundle
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = RTCFactory.shared.peerConnection(with: rtcConfig, constraints: constraints, delegate: self) else {
            fail(.connectionFailed)
            return
        }
        peerConnection = pc

        let recvInit = RTCRtpTransceiverInit()
        recvInit.direction = .recvOnly
        pc.addTransceiver(of: .video, init: recvInit)
        pc.addTransceiver(of: .audio, init: recvInit)

        let offerConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc.offer(for: offerConstraints) { [weak self] sdp, error in
            guard let self else { return }
            guard let sdp, error == nil else { self.fail(.connectionFailed); return }
            pc.setLocalDescription(sdp) { [weak self] error in
                guard let self else { return }
                if error != nil { self.fail(.connectionFailed); return }
                WHIPWHEPSignaling.exchange(
                    offer: sdp.sdp,
                    url: self.endpoints.lowLatencySubscribeURL(streamId: self.config.streamId, token: self.config.token),
                    token: self.config.token
                ) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .failure(let err):
                        self.fail(err)
                    case .success(let answerSDP):
                        let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
                        pc.setRemoteDescription(answer) { [weak self] error in
                            if error != nil { self?.fail(.connectionFailed) }
                        }
                    }
                }
            }
        }
    }

    func stop() {
        statsTimer?.invalidate()
        statsTimer = nil
        peerConnection?.close()
        peerConnection = nil
        #if canImport(UIKit)
        DispatchQueue.main.async { [weak self] in
            self?.remoteRenderer?.removeFromSuperview()
            self?.remoteRenderer = nil
        }
        #endif
        onMain { [weak self] in
            guard let self else { return }
            self.delegate?.subscribeTransportDidEnd(self)
        }
    }

    func setVolume(_ volume: Float) {
        remoteAudioTrack?.source.volume = Double(volume)
    }

    #if canImport(UIKit)
    func attachRenderer(to view: MebiusVideoView) {
        renderView = view
        attachRemoteRendererIfPossible()
    }

    private func attachRemoteRendererIfPossible() {
        guard let view = renderView, let track = remoteVideoTrack else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.remoteRenderer == nil {
                let renderer = RTCMTLVideoView(frame: view.bounds)
                renderer.videoContentMode = .scaleAspectFill
                renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(renderer)
                self.remoteRenderer = renderer
            }
            if let renderer = self.remoteRenderer {
                track.add(renderer)
            }
        }
    }
    #endif

    private func startStatsTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statsTimer?.invalidate()
            self.statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.collectStats()
            }
        }
    }

    private func collectStats() {
        guard let pc = peerConnection else { return }
        pc.statistics { [weak self] report in
            guard let self else { return }
            var frameRate = 0.0
            var packetsReceived = 0
            for (_, stat) in report.statistics where stat.type == "inbound-rtp" {
                packetsReceived += (stat.values["packetsReceived"] as? NSNumber)?.intValue ?? 0
                if let fps = (stat.values["framesPerSecond"] as? NSNumber)?.doubleValue { frameRate = fps }
            }
            let stats = MebiusPlayerStats(bitrate: 0, frameRate: frameRate, latency: nil, packetsReceived: packetsReceived)
            self.onMain { self.delegate?.subscribeTransport(self, didReportStats: stats) }
        }
    }

    private func fail(_ error: MebiusError) {
        onMain { [weak self] in
            guard let self else { return }
            self.delegate?.subscribeTransport(self, didFail: error)
        }
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    // MARK: RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let videoTrack = rtpReceiver.track as? RTCVideoTrack {
            remoteVideoTrack = videoTrack
            #if canImport(UIKit)
            attachRemoteRendererIfPossible()
            #endif
        } else if let audioTrack = rtpReceiver.track as? RTCAudioTrack {
            remoteAudioTrack = audioTrack
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        switch newState {
        case .connected:
            guard !playing else { return }
            playing = true
            startStatsTimer()
            onMain { [weak self] in
                guard let self else { return }
                self.delegate?.subscribeTransportDidStartPlaying(self)
            }
        case .failed:
            fail(.connectionFailed)
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    // Required by RTCPeerConnectionDelegate. Mebius negotiates media only — no data
    // channel is ever created on our side — but the protocol has no default
    // implementation, so omitting it is a compile error under CocoaPods (which builds
    // against the real WebRTC binary). SwiftPM never compiles this file, so `swift
    // build` stayed green while `pod lib lint` failed on exactly this.
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// Registers the concrete real-time factory, replacing the SPM stub.
enum RTCBootstrap {
    static func activate() {
        TransportRegistry.register(RTCTransportFactory())
    }
}
#endif
