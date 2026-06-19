#if canImport(UIKit)
import UIKit
import AVFoundation

/// A view that renders Mebius video — either a local camera preview for a
/// ``MebiusBroadcaster`` or remote video for a ``MebiusPlayer``.
///
/// Create one, add it to your view hierarchy, and pass it to
/// ``MebiusBroadcaster/attachPreview(to:)`` or ``MebiusPlayer/play(streamId:view:)``.
///
/// All interaction with this view must occur on the main thread.
public final class MebiusVideoView: UIView {

    /// How video content is fit within the view's bounds.
    public enum ContentMode: Sendable {
        /// Preserve aspect ratio; fit entirely within bounds (letterboxed).
        case aspectFit
        /// Preserve aspect ratio; fill bounds (cropped).
        case aspectFill
    }

    /// The content mode used to lay out the rendered video. Defaults to `.aspectFill`.
    public var videoContentMode: ContentMode = .aspectFill {
        didSet { applyContentMode() }
    }

    // Layer used for scale-mode (AVPlayer) playback. The real-time render
    // surface (when present) is attached as a subview by the transport.
    private var playerLayer: AVPlayerLayer?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    // MARK: Internal attachment points (used by the SDK implementation)

    func attachScalePlayer(_ player: AVPlayer) {
        playerLayer?.removeFromSuperlayer()
        let layer = AVPlayerLayer(player: player)
        layer.frame = bounds
        self.layer.addSublayer(layer)
        self.playerLayer = layer
        applyContentMode()
    }

    /// Detaches any rendered content and resets the view.
    func detach() {
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        subviews.forEach { $0.removeFromSuperview() }
    }

    private func applyContentMode() {
        let gravity: AVLayerVideoGravity = videoContentMode == .aspectFit ? .resizeAspect : .resizeAspectFill
        playerLayer?.videoGravity = gravity
    }
}
#endif
