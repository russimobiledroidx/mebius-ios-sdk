# Mebius iOS SDK

Native Swift SDK for Mebius live video — broadcast from the camera and watch streams with a single, clean API.

[![CocoaPods](https://img.shields.io/badge/pod-v0.1.0-blue.svg)](https://cocoapods.org/pods/Mebius)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

---

## 1. Overview

Mebius gives you live broadcasting and playback in a few lines of Swift. You connect with a short-lived token from your backend, create a broadcaster or a player, and attach a `MebiusVideoView`. The transport is fully managed for you.

## 2. Requirements

| Requirement | Version |
|-------------|---------|
| iOS         | 13.0+   |
| Xcode       | 15.0+   |
| Swift       | 5.9+    |

Broadcasting needs camera and microphone access. Add these keys to your app's **Info.plist**:

```xml
<key>NSCameraUsageDescription</key>
<string>We use the camera so you can broadcast live video.</string>
<key>NSMicrophoneUsageDescription</key>
<string>We use the microphone so others can hear your broadcast.</string>
```

## 3. Installation

### Swift Package Manager

In Xcode: **File ▸ Add Package Dependencies…**, then enter the repository URL:

```
https://github.com/russimobiledroidx/mebius-ios-sdk.git
```

Choose the `Mebius` library and add it to your target.

> The SPM build ships the full public API and the scale playback path. The real-time (broadcast and low-latency playback) transport relies on a binary that is distributed via CocoaPods; for those features, install via CocoaPods.

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'Mebius'
```

Then run:

```sh
pod install
```

**Validating the podspec** (CocoaPods must be installed):

```sh
pod lib lint Mebius.podspec      # local lint
pod spec lint Mebius.podspec     # remote lint (needs a pushed tag)
```

## 4. Quick Start

### Authentication

Your app never holds the application secret. Your **backend** mints a short-lived JWT from `(appId + appSecret)` and returns it to the app. The SDK takes that token as a string. If a token expires, you receive a `MebiusError.tokenExpired` and should fetch a fresh token and reconnect.

### Initialize & connect

```swift
import Mebius

let mebius = Mebius(appId: "your-app-id",
                    gateway: URL(string: "https://gateway.mebius.io")!)

let client = mebius.connect(token: tokenFromYourBackend)

client.onConnected = { print("Connected") }
client.onError = { error in
    if error == .tokenExpired {
        // refresh token from backend, then client.updateToken(newToken) + reconnect
    }
}
```

### Broadcast

```swift
let videoView = MebiusVideoView()           // add to your view hierarchy

let broadcaster = client.createBroadcaster(video: true, audio: true)
broadcaster.attachPreview(to: videoView)

broadcaster.onStarted = { print("Live") }
broadcaster.start(streamId: "my-stream")

broadcaster.switchCamera()                  // flip front/back
broadcaster.setMicEnabled(false)            // mute
broadcaster.setCameraEnabled(false)         // camera off
broadcaster.stop()
```

### Watch

```swift
let videoView = MebiusVideoView()           // add to your view hierarchy

// .lowLatency for real-time, .scale for large audiences
let player = client.createPlayer(mode: .lowLatency)

player.onPlaying = { print("Playing") }
player.onBuffering = { print("Buffering") }
player.onEnded = { print("Ended") }

player.play(streamId: "my-stream", view: videoView)
player.setVolume(0.5)                        // 0...1
player.stop()
```

## 5. Integration

### SwiftUI (UIViewRepresentable)

```swift
import SwiftUI
import Mebius

struct MebiusVideoViewRepresentable: UIViewRepresentable {
    let onMake: (MebiusVideoView) -> Void
    func makeUIView(context: Context) -> MebiusVideoView {
        let view = MebiusVideoView()
        onMake(view)
        return view
    }
    func updateUIView(_ uiView: MebiusVideoView, context: Context) {}
}

struct WatchScreen: View {
    let client: MebiusClient
    @State private var player: MebiusPlayer?
    var body: some View {
        MebiusVideoViewRepresentable { view in
            let player = client.createPlayer(mode: .lowLatency)
            self.player = player
            client.onConnected = { player.play(streamId: "my-stream", view: view) }
        }
        .ignoresSafeArea()
        .onDisappear { player?.stop() }
    }
}
```

Full SwiftUI examples are in [`Examples/SwiftUIExample`](Examples/SwiftUIExample).

### UIKit

```swift
import UIKit
import Mebius

final class WatchViewController: UIViewController, MebiusPlayerDelegate {
    private let videoView = MebiusVideoView()
    private var player: MebiusPlayer?

    func startWatching(client: MebiusClient) {
        view.addSubview(videoView)
        videoView.frame = view.bounds
        let player = client.createPlayer(mode: .scale)
        player.delegate = self
        self.player = player
        client.onConnected = { [weak self] in
            guard let self else { return }
            player.play(streamId: "my-stream", view: self.videoView)
        }
    }

    func mebiusPlayerDidStartPlaying(_ player: MebiusPlayer) { /* … */ }
}
```

Full UIKit examples are in [`Examples/UIKitExample`](Examples/UIKitExample).

## 6. API Reference

| Type | Member | Signature |
|------|--------|-----------|
| `Mebius` | init | `init(appId: String, gateway: URL)` |
| `Mebius` | connect | `func connect(token: String) -> MebiusClient` |
| `MebiusClient` | createBroadcaster | `func createBroadcaster(video: Bool = true, audio: Bool = true) -> MebiusBroadcaster` |
| `MebiusClient` | createPlayer | `func createPlayer(mode: MebiusPlayerMode) -> MebiusPlayer` |
| `MebiusClient` | updateToken | `func updateToken(_ token: String)` |
| `MebiusClient` | disconnect | `func disconnect()` |
| `MebiusClient` | events | `onConnected`, `onDisconnected`, `onError` closures + `delegate` |
| `MebiusBroadcaster` | start | `func start(streamId: String)` |
| `MebiusBroadcaster` | stop | `func stop()` |
| `MebiusBroadcaster` | switchCamera | `func switchCamera()` |
| `MebiusBroadcaster` | setMicEnabled | `func setMicEnabled(_ enabled: Bool)` |
| `MebiusBroadcaster` | setCameraEnabled | `func setCameraEnabled(_ enabled: Bool)` |
| `MebiusBroadcaster` | attachPreview | `func attachPreview(to view: MebiusVideoView)` |
| `MebiusBroadcaster` | events | `onStarted`, `onStopped`, `onStats`, `onError` closures + `delegate` |
| `MebiusPlayer` | play | `func play(streamId: String, view: MebiusVideoView)` |
| `MebiusPlayer` | stop | `func stop()` |
| `MebiusPlayer` | setVolume | `func setVolume(_ volume: Float)` (0...1) |
| `MebiusPlayer` | events | `onPlaying`, `onBuffering`, `onEnded`, `onStats`, `onError` closures + `delegate` |
| `MebiusVideoView` | view | `UIView` subclass for preview/playback |
| `MebiusPlayerMode` | enum | `.lowLatency`, `.scale` |

### Delegate protocols

```swift
public protocol MebiusClientDelegate: AnyObject {
    func mebiusClientDidConnect(_ client: MebiusClient)
    func mebiusClientDidDisconnect(_ client: MebiusClient)
    func mebiusClient(_ client: MebiusClient, didFailWithError error: MebiusError)
}

public protocol MebiusBroadcasterDelegate: AnyObject {
    func mebiusBroadcasterDidStart(_ broadcaster: MebiusBroadcaster)
    func mebiusBroadcasterDidStop(_ broadcaster: MebiusBroadcaster)
    func mebiusBroadcaster(_ broadcaster: MebiusBroadcaster, didReportStats stats: MebiusBroadcastStats)
    func mebiusBroadcaster(_ broadcaster: MebiusBroadcaster, didFailWithError error: MebiusError)
}

public protocol MebiusPlayerDelegate: AnyObject {
    func mebiusPlayerDidStartPlaying(_ player: MebiusPlayer)
    func mebiusPlayerDidBuffer(_ player: MebiusPlayer)
    func mebiusPlayerDidEnd(_ player: MebiusPlayer)
    func mebiusPlayer(_ player: MebiusPlayer, didReportStats stats: MebiusPlayerStats)
    func mebiusPlayer(_ player: MebiusPlayer, didFailWithError error: MebiusError)
}
```

All delegate methods have default no-op implementations, so you only implement what you need. **All callbacks are delivered on the main thread.**

## 7. Error Handling

```swift
public enum MebiusError: Error {
    case tokenExpired       // "TOKEN_EXPIRED"     -> refresh token + reconnect
    case permissionDenied   // "PERMISSION_DENIED" -> prompt user to grant camera/mic
    case connectionFailed   // "CONNECTION_FAILED" -> retry with backoff
    case notConnected       // "NOT_CONNECTED"     -> connect() before this operation
    case streamNotFound     // "STREAM_NOT_FOUND"  -> verify the streamId
    case unknown(message: String)
}
```

Recovery example:

```swift
client.onError = { error in
    switch error {
    case .tokenExpired:
        fetchFreshToken { token in
            client.updateToken(token)
            // recreate broadcaster/player or call connect again
        }
    case .permissionDenied:
        showSettingsPrompt()
    case .connectionFailed:
        retryAfterBackoff()
    default:
        log(error.errorDescription ?? "")
    }
}
```

## 8. Troubleshooting

- **Permissions**: a black preview or `permissionDenied` usually means the `Info.plist` keys (Section 2) are missing or the user denied access. Send the user to Settings to re-enable.
- **Background audio**: to keep audio playing when backgrounded, enable the *Audio, AirPlay, and Picture in Picture* Background Mode and configure your `AVAudioSession` category (`.playback`) before playing.
- **Lifecycle / teardown**: always call `broadcaster.stop()` / `player.stop()` and `client.disconnect()` in `onDisappear` / `viewDidDisappear`. Hold strong references to the client, broadcaster, and player for as long as they are in use, or they will be deallocated. Create and use all Mebius objects on the **main thread**.

## 9. Versioning & Changelog

Mebius follows [Semantic Versioning](https://semver.org). The public API is stable within a major version; breaking changes bump the major version across all Mebius platform SDKs simultaneously.

### Changelog

#### 0.1.0
- Initial release: `Mebius`, `MebiusClient`, `MebiusBroadcaster`, `MebiusPlayer`, `MebiusVideoView`.
- Broadcast, low-latency and scale playback, delegate + closure events, `MebiusError`.

## 10. License

Released under the MIT License. See [LICENSE](LICENSE).
