import SwiftUI
import Mebius

/// Wraps the UIKit-based ``MebiusVideoView`` for use in SwiftUI.
///
/// Bind the created view back out via `onMake` so a broadcaster or player can
/// attach to it.
struct MebiusVideoViewRepresentable: UIViewRepresentable {
    /// Called once with the underlying view so the caller can attach a
    /// broadcaster preview or start a player into it.
    let onMake: (MebiusVideoView) -> Void

    func makeUIView(context: Context) -> MebiusVideoView {
        let view = MebiusVideoView()
        view.videoContentMode = .aspectFill
        onMake(view)
        return view
    }

    func updateUIView(_ uiView: MebiusVideoView, context: Context) {}
}
