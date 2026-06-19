import SwiftUI
import Mebius

/// SwiftUI screen that broadcasts the camera to a Mebius stream.
struct BroadcastView: View {
    /// A short-lived token obtained from your backend.
    let token: String
    let gateway = URL(string: "https://gateway.mebius.io")!
    let streamId = "demo-stream"

    @State private var client: MebiusClient?
    @State private var broadcaster: MebiusBroadcaster?
    @State private var isLive = false
    @State private var micEnabled = true
    @State private var status = "Idle"

    var body: some View {
        VStack(spacing: 0) {
            MebiusVideoViewRepresentable { view in
                let mebius = Mebius(appId: "your-app-id", gateway: gateway)
                let client = mebius.connect(token: token)
                self.client = client

                let broadcaster = client.createBroadcaster(video: true, audio: true)
                broadcaster.attachPreview(to: view)
                broadcaster.onStarted = { isLive = true; status = "Live" }
                broadcaster.onStopped = { isLive = false; status = "Stopped" }
                broadcaster.onError = { status = "Error: \($0.code)" }
                self.broadcaster = broadcaster
            }
            .ignoresSafeArea()

            HStack(spacing: 16) {
                Button(isLive ? "Stop" : "Go Live") {
                    if isLive { broadcaster?.stop() }
                    else { broadcaster?.start(streamId: streamId) }
                }
                Button("Flip") { broadcaster?.switchCamera() }
                Button(micEnabled ? "Mute" : "Unmute") {
                    micEnabled.toggle()
                    broadcaster?.setMicEnabled(micEnabled)
                }
            }
            .padding()

            Text(status).font(.caption).foregroundColor(.secondary).padding(.bottom)
        }
        .onDisappear {
            broadcaster?.stop()
            client?.disconnect()
        }
    }
}
