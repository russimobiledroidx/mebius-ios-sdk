import SwiftUI
import Mebius

/// SwiftUI screen that watches a Mebius stream.
struct WatchView: View {
    let token: String
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
                let client = mebius.connect(token: token)
                self.client = client

                // Use .lowLatency for real-time, .scale for large audiences.
                let player = client.createPlayer(mode: .lowLatency)
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
