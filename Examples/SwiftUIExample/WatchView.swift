import SwiftUI
import Mebius

/// SwiftUI screen that watches a Mebius stream.
struct WatchView: View {
    let token: String
    /// The `deliveries` list your backend returned alongside the token. Forward it
    /// untouched: without it every viewer is served from Mebius origin instead of
    /// the nearest edge, which on mobile is billed per viewer.
    var deliveries: [MebiusDelivery] = []
    let gateway = URL(string: "https://gateway.mebius.io")!
    let streamId = "demo-stream"

    @State private var client: MebiusClient?
    @State private var player: MebiusPlayer?
    @State private var volume: Double = 1.0
    @State private var status = "Connecting…"

    var body: some View {
        VStack(spacing: 0) {
            MebiusVideoViewRepresentable { view in
                let mebius = Mebius(appId: "your-app-id", gateway: gateway)
                let client = mebius.connect(token: token, deliveries: deliveries)
                self.client = client

                // .auto is the default: Mebius picks per viewer and moves to another
                // route by itself if the one it picked delivers no video. Use
                // client.createMonitor() instead when watching the other side of a
                // co-broadcast, where a second of delay breaks the interaction.
                let player = client.createPlayer()
                player.onPlaying = { status = "Playing" }
                player.onBuffering = { status = "Buffering…" }
                player.onEnded = { status = "Ended" }
                player.onError = { status = "Error: \($0.code)" }
                self.player = player

                client.onConnected = { player.play(streamId: streamId, view: view) }
            }
            .ignoresSafeArea()

            VStack {
                Slider(value: $volume, in: 0...1) { _ in
                    player?.setVolume(Float(volume))
                }
                Text(status).font(.caption).foregroundColor(.secondary)
            }
            .padding()
        }
        .onDisappear {
            player?.stop()
            client?.disconnect()
        }
    }
}
