import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Stub real-time transport
//
// This is the placeholder real-time transport used when the SDK is built via
// Swift Package Manager WITHOUT the libwebrtc binary (which ships only through
// CocoaPods). It satisfies the transport protocols so the public API and the
// scale (AVPlayer) playback path compile and behave deterministically.
//
// In a CocoaPods consumer with the real-time pod installed, the concrete
// libwebrtc-backed factory replaces this stub via TransportRegistry.register.
//
// The stub fails publish/low-latency operations with a clear Mebius error so
// developers running an SPM-only build understand the real-time path requires
// the CocoaPods distribution. The scale playback path does NOT use this stub.

final class StubTransportFactory: TransportFactory {
    func makePublishTransport(config: PublishConfig) -> PublishTransport {
        StubPublishTransport()
    }

    func makeLowLatencySubscribeTransport(config: SubscribeConfig) -> SubscribeTransport {
        StubSubscribeTransport()
    }
}

private let stubMessage =
    "The real-time transport is not available in this build. Install Mebius via " +
    "CocoaPods to enable broadcasting and low-latency playback."

final class StubPublishTransport: PublishTransport {
    weak var delegate: PublishTransportDelegate?

    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.publishTransport(self, didFail: .unknown(message: stubMessage))
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.publishTransportDidStop(self)
        }
    }

    func switchCamera() {}
    func setMicEnabled(_ enabled: Bool) {}
    func setCameraEnabled(_ enabled: Bool) {}

    #if canImport(UIKit)
    func attachPreview(to view: MebiusVideoView) {}
    #endif
}

final class StubSubscribeTransport: SubscribeTransport {
    weak var delegate: SubscribeTransportDelegate?

    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.subscribeTransport(self, didFail: .unknown(message: stubMessage))
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.subscribeTransportDidEnd(self)
        }
    }

    func setVolume(_ volume: Float) {}

    #if canImport(UIKit)
    func attachRenderer(to view: MebiusVideoView) {}
    #endif
}
