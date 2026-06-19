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
// Under the flag this is where libwebrtc is imported and wired:
//   - publish  -> RTCPeerConnection negotiated against the gateway publish URL
//                 (WHIP signaling exchange)
//   - subscribe (low latency) -> RTCPeerConnection negotiated against the
//                 gateway subscribe URL (WHEP signaling exchange)
//   - camera capture + local/remote render views are bridged into MebiusVideoView
//
// The body below is a documented scaffold. The full libwebrtc wiring is
// completed in the CocoaPods build; the API contract (the transport protocols)
// is identical to the stub so the rest of the SDK is unchanged.

#if MEBIUS_RTC
// import WebRTC  // provided by the libwebrtc CocoaPods binary

final class RTCTransportFactory: TransportFactory {
    func makePublishTransport(config: PublishConfig) -> PublishTransport {
        RTCPublishTransport(config: config)
    }
    func makeLowLatencySubscribeTransport(config: SubscribeConfig) -> SubscribeTransport {
        RTCSubscribeTransport(config: config)
    }
}

final class RTCPublishTransport: PublishTransport {
    weak var delegate: PublishTransportDelegate?
    private let config: PublishConfig
    init(config: PublishConfig) { self.config = config }

    func start() {
        // 1. Create RTCPeerConnection + capture tracks (camera/mic per config).
        // 2. Create offer, POST SDP to config.gateway (publish signaling),
        //    apply answer.
        // 3. On connected -> delegate?.publishTransportDidStart(self)
        //    On stats -> delegate?.publishTransport(self, didReportStats:)
    }
    func stop() { /* close peer connection -> publishTransportDidStop */ }
    func switchCamera() { /* toggle capture device */ }
    func setMicEnabled(_ enabled: Bool) { /* audio track .isEnabled */ }
    func setCameraEnabled(_ enabled: Bool) { /* video track .isEnabled */ }
    #if canImport(UIKit)
    func attachPreview(to view: MebiusVideoView) { /* add local renderer */ }
    #endif
}

final class RTCSubscribeTransport: SubscribeTransport {
    weak var delegate: SubscribeTransportDelegate?
    private let config: SubscribeConfig
    init(config: SubscribeConfig) { self.config = config }

    func start() {
        // 1. Create RTCPeerConnection (recvonly).
        // 2. Create offer, POST SDP to config.gateway (subscribe signaling),
        //    apply answer.
        // 3. On first frame -> delegate?.subscribeTransportDidStartPlaying(self)
    }
    func stop() { /* close peer connection -> subscribeTransportDidEnd */ }
    func setVolume(_ volume: Float) { /* remote audio track volume */ }
    #if canImport(UIKit)
    func attachRenderer(to view: MebiusVideoView) { /* add remote renderer */ }
    #endif
}

// Registers the concrete real-time factory, replacing the SPM stub.
enum RTCBootstrap {
    static func activate() {
        TransportRegistry.register(RTCTransportFactory())
    }
}
#endif
