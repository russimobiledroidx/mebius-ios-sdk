import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Internal transport abstraction
//
// This file is part of the private implementation. The protocols below
// describe the real-time transport that publishes and subscribes to media via
// the Mebius gateway. The concrete real-time implementation uses libwebrtc
// (WHIP for publish, WHEP for low-latency play). That concrete code lives in a
// separate file compiled only for CocoaPods consumers (see RTC files guarded by
// the MEBIUS_RTC flag). The pure-Swift SPM build uses a stub so the public
// surface and the scale (AVPlayer) path compile without libwebrtc.

/// Describes the configuration handed to a publish transport.
struct PublishConfig {
    let gateway: URL
    let token: String
    let streamId: String
    let video: Bool
    let audio: Bool
}

/// Describes the configuration handed to a low-latency subscribe transport.
struct SubscribeConfig {
    let gateway: URL
    let token: String
    let streamId: String
}

/// Receives lifecycle callbacks from a publish transport. All callbacks are
/// invoked on the main thread by the implementation.
protocol PublishTransportDelegate: AnyObject {
    func publishTransportDidStart(_ transport: PublishTransport)
    func publishTransportDidStop(_ transport: PublishTransport)
    func publishTransport(_ transport: PublishTransport, didReportStats stats: MebiusBroadcastStats)
    func publishTransport(_ transport: PublishTransport, didFail error: MebiusError)
}

/// Receives lifecycle callbacks from a low-latency subscribe transport. All
/// callbacks are invoked on the main thread by the implementation.
protocol SubscribeTransportDelegate: AnyObject {
    func subscribeTransportDidStartPlaying(_ transport: SubscribeTransport)
    func subscribeTransportDidBuffer(_ transport: SubscribeTransport)
    func subscribeTransportDidEnd(_ transport: SubscribeTransport)
    func subscribeTransport(_ transport: SubscribeTransport, didReportStats stats: MebiusPlayerStats)
    func subscribeTransport(_ transport: SubscribeTransport, didFail error: MebiusError)
}

// The real-time publish transport. Internally backed by libwebrtc (WHIP).
protocol PublishTransport: AnyObject {
    var delegate: PublishTransportDelegate? { get set }
    func start()
    func stop()
    func switchCamera()
    func setMicEnabled(_ enabled: Bool)
    func setCameraEnabled(_ enabled: Bool)
    #if canImport(UIKit)
    /// Attaches the local camera preview to a render view.
    func attachPreview(to view: MebiusVideoView)
    #endif
}

// The real-time subscribe transport. Internally backed by libwebrtc (WHEP).
protocol SubscribeTransport: AnyObject {
    var delegate: SubscribeTransportDelegate? { get set }
    func start()
    func stop()
    func setVolume(_ volume: Float)
    #if canImport(UIKit)
    func attachRenderer(to view: MebiusVideoView)
    #endif
}

/// Factory that produces transports. The active factory is swapped at runtime:
/// the SPM build registers ``StubTransportFactory``; the CocoaPods build with
/// libwebrtc registers the concrete WebRTC factory in its `+load`/bootstrap.
protocol TransportFactory: AnyObject {
    func makePublishTransport(config: PublishConfig) -> PublishTransport
    func makeLowLatencySubscribeTransport(config: SubscribeConfig) -> SubscribeTransport
}

/// Global registry for the transport factory.
enum TransportRegistry {
    private static let lock = NSLock()
    private static var _factory: TransportFactory = StubTransportFactory()

    static var factory: TransportFactory {
        get { lock.lock(); defer { lock.unlock() }; return _factory }
        set { lock.lock(); defer { lock.unlock() }; _factory = newValue }
    }

    /// Called by the concrete real-time transport (CocoaPods build) to take
    /// over from the stub.
    static func register(_ factory: TransportFactory) {
        self.factory = factory
    }
}
