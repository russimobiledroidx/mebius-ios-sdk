import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Scale-mode playback (private)
//
// The scale playback path is fully functional. It uses AVPlayer to render an
// adaptive HLS playlist served by the Mebius gateway. This is selected
// automatically when a player is created with mode .scale and requires no
// libwebrtc dependency, so it builds and runs under plain Swift Package Manager.

protocol ScalePlaybackDelegate: AnyObject {
    func scalePlaybackDidStartPlaying(_ playback: ScalePlayback)
    func scalePlaybackDidBuffer(_ playback: ScalePlayback)
    func scalePlaybackDidEnd(_ playback: ScalePlayback)
    func scalePlayback(_ playback: ScalePlayback, didReportStats stats: MebiusPlayerStats)
    func scalePlayback(_ playback: ScalePlayback, didFail error: MebiusError)
}

final class ScalePlayback {
    weak var delegate: ScalePlaybackDelegate?

    private let url: URL
    private let token: String
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statsTimer: Timer?
    private var observers: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var hasReportedPlaying = false

    init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    #if canImport(UIKit)
    func start(in view: MebiusVideoView) {
        assert(Thread.isMainThread, "Mebius playback must be started on the main thread")

        // Token is passed as an authorization header on the playlist request.
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
        )
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        self.playerItem = item
        self.player = player
        view.attachScalePlayer(player)

        observeItem(item)
        observeEnd(item)
        player.play()
        startStatsTimer()
    }
    #endif

    func setVolume(_ volume: Float) {
        player?.volume = max(0, min(1, volume))
    }

    func stop() {
        statsTimer?.invalidate()
        statsTimer = nil
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player = nil
        playerItem = nil
        hasReportedPlaying = false
    }

    private func observeItem(_ item: AVPlayerItem) {
        let statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .failed:
                    let message = item.error?.localizedDescription ?? "Playback failed."
                    self.delegate?.scalePlayback(self, didFail: .unknown(message: message))
                default:
                    break
                }
            }
        }

        let bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            guard let self, item.isPlaybackBufferEmpty else { return }
            DispatchQueue.main.async { self.delegate?.scalePlaybackDidBuffer(self) }
        }

        let likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self, item.isPlaybackLikelyToKeepUp else { return }
            DispatchQueue.main.async {
                if !self.hasReportedPlaying {
                    self.hasReportedPlaying = true
                    self.delegate?.scalePlaybackDidStartPlaying(self)
                }
            }
        }

        observers = [statusObserver, bufferEmptyObserver, likelyToKeepUpObserver]
    }

    private func observeEnd(_ item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.scalePlaybackDidEnd(self)
        }
    }

    private func startStatsTimer() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let item = self.playerItem else { return }
            let log = item.accessLog()
            let event = log?.events.last
            let stats = MebiusPlayerStats(
                bitrate: Int(event?.observedBitrate ?? 0),
                frameRate: 0,
                latency: nil,
                packetsReceived: Int(event?.numberOfBytesTransferred ?? 0)
            )
            DispatchQueue.main.async { self.delegate?.scalePlayback(self, didReportStats: stats) }
        }
    }
}
