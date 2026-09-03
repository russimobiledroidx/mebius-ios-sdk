#if MEBIUS_RTC
import Foundation
import CoreGraphics
import WebRTC

/// An `RTCVideoRenderer` that exists only to notice the first decoded frame.
///
/// Attached to the remote track alongside the display renderer, so playback is
/// reported when a picture actually arrives rather than when the peer connection
/// says `connected` — which is ICE and DTLS, true before any media flows and
/// still true if none ever does.
///
/// All the logic worth testing lives in `FirstFrameLatch`, which carries no
/// libwebrtc types and is therefore covered by `swift test`; this file is only
/// the protocol conformance, and is compiled solely by the CocoaPods
/// distribution that brings the WebRTC binary.
final class FirstFrameRenderer: NSObject, RTCVideoRenderer {
    private let latch: FirstFrameLatch

    init(onFirstFrame: @escaping () -> Void) {
        self.latch = FirstFrameLatch(onFirstFrame: onFirstFrame)
        super.init()
    }

    /// Size changes carry no frame, so they are not evidence of playback.
    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard frame != nil else { return }
        latch.frameArrived()
    }
}
#endif
