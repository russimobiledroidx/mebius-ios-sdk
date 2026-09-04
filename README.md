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

## 3. Install (from GitHub)

Mebius is distributed **directly from its GitHub repository** — there is no public
package-registry or CocoaPods-trunk entry required. The repository is **private**,
so installation authenticates over **SSH**: make sure the developer's machine has a
GitHub SSH key set up and added to an account with access to
`russimobiledroidx/mebius-ios-sdk` (verify with `ssh -T git@github.com`). All
commands below use the SSH git URL, which is what resolves a private repo.

> Releases are tagged `v0.1.0` (see *Tag form* note at the end of this section).

### Swift Package Manager — via Xcode

1. **File ▸ Add Package Dependencies…**
2. In the search/URL field, paste the SSH URL:
   ```
   git@github.com:russimobiledroidx/mebius-ios-sdk.git
   ```
3. Set the dependency rule to **Up to Next Major Version** starting at `0.1.0`
   (or pick the exact tag `v0.1.0`).
4. Add the **`Mebius`** library product to your app target.

The SSH URL works for private repos as long as Xcode/SPM can use the developer's
GitHub SSH key.

### Swift Package Manager — via `Package.swift`

```swift
.package(url: "git@github.com:russimobiledroidx/mebius-ios-sdk.git", from: "0.1.0")
```

…and add `"Mebius"` to the dependencies of the target that uses it:

```swift
.target(
    name: "YourApp",
    dependencies: ["Mebius"]
)
```

### CocoaPods

Point the pod straight at the private git repo and the release tag in your `Podfile`:

```ruby
pod 'Mebius', :git => 'git@github.com:russimobiledroidx/mebius-ios-sdk.git', :tag => 'v0.1.0'
```

Then run:

```sh
pod install
```

The `:git` source above overrides the URL declared in the podspec at consume time,
so it always resolves the private repo over SSH.

> **The SPM build ships the full public API and the scaled playback path.** The
> real-time transport (broadcast and sub-second playback) sits behind a Swift
> protocol and ships as a documented placeholder in the SPM build; the concrete
> transport needs a binary distributed via CocoaPods. For those features, install
> via CocoaPods (see the `MEBIUS_RTC` flag in `Mebius.podspec`).

### Tag form (SPM vs CocoaPods)

Releases are published as the annotated git tag **`v0.2.1`**. SPM matches a SemVer
requirement such as `from: "0.2.1"` against tags **with or without** a leading `v`,
so the tag resolves correctly.

CocoaPods does not guess: it clones the exact string in `:tag`. The podspec used
`s.version.to_s`, which asked for a tag named `0.2.0` while the repo tags `v0.2.0` —
`pod trunk push` failed with *"Remote branch 0.2.0 not found in upstream origin"*. It
now reads `"v#{s.version}"`, so the two can no longer drift.

---

### Secondary: registry / trunk distribution

> CocoaPods trunk is now a published path — `pod 'Mebius'` with no `:git` works, and
> it is the only distribution that carries the real-time transport (SwiftPM does not
> set `MEBIUS_RTC`, so publish and sub-second playback fall back to the stub there).
> Validate a podspec before pushing with:
>
> ```sh
> pod lib lint Mebius.podspec      # local lint
> pod spec lint Mebius.podspec     # remote lint (needs a pushed tag)
> ```

## 4. Quick Start

### Authentication

Your app never holds the application secret. Your **backend** mints a short-lived JWT from `(appId + appSecret)` and returns it to the app. The SDK takes that token as a string. If a token expires, you receive a `MebiusError.tokenExpired` and should fetch a fresh token and reconnect.

### Initialize & connect

```swift
import Mebius

let mebius = Mebius(appId: "your-app-id",
                    gateway: URL(string: "https://gateway.mebius.io")!)

// Your backend returns `token` AND `deliveries` from one call. Pass both.
// Dropping `deliveries` still plays, but serves every viewer from Mebius origin
// instead of the nearest edge — on mobile that is billed per viewer.
let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
let client = mebius.connect(
    token: body?["token"] as? String ?? "",
    deliveries: MebiusDelivery.list(fromTokenResponse: body)
)

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

let player = client.createPlayer()   // mode defaults to .auto

player.onPlaying = { print("Playing") }
player.onBuffering = { print("Buffering") }
player.onEnded = { print("Ended") }

player.play(streamId: "my-stream", view: videoView)
```

### Playback modes

| Mode | When to use |
| --- | --- |
| `.auto` (default) | Recommended. Mebius picks per viewer and re-picks if a route stops delivering video. |
| `.lowLatency` | Two-way interaction (co-broadcast). Costs one per-viewer session, so not for a plain audience. |
| `.scale` | Largest audiences and unstable networks. |

Whatever the mode, playback walks an ordered route list and gives each route
**8 seconds** to deliver video before moving on. A route that opens is not yet a
route that plays: an edge with no ingest answers 200 with an empty stream, and a
real-time connection reports itself connected while zero frames arrive. Both used
to leave the viewer on a black frame with no error to react to.

### Watching the other side of a co-broadcast

```swift
let monitor = client.createMonitor()
monitor.play(streamId: opponentStreamId, view: videoView)
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
            let player = client.createPlayer()
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
| `Mebius` | connect | `func connect(token: String, deliveries: [MebiusDelivery] = []) -> MebiusClient` |
| `MebiusClient` | createBroadcaster | `func createBroadcaster(video: Bool = true, audio: Bool = true) -> MebiusBroadcaster` |
| `MebiusClient` | createPlayer | `func createPlayer(mode: MebiusPlayerMode = .auto) -> MebiusPlayer` |
| `MebiusClient` | createMonitor | `func createMonitor() -> MebiusPlayer` |
| `MebiusDelivery` | list | `static func list(fromTokenResponse: [String: Any]?) -> [MebiusDelivery]` |
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
| `MebiusPlayerMode` | enum | `.auto` (default), `.lowLatency`, `.scale` |

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

Release notes live in [CHANGELOG.md](CHANGELOG.md).

## 10. License

Released under the MIT License. See [LICENSE](LICENSE).
