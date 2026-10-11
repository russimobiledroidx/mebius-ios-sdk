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
    /// Playback can keep up again after having started — the end of a rebuffer.
    func scalePlaybackDidResume(_ playback: ScalePlayback)
    func scalePlaybackDidEnd(_ playback: ScalePlayback)
    func scalePlayback(_ playback: ScalePlayback, didReportStats stats: MebiusPlayerStats)
    func scalePlayback(_ playback: ScalePlayback, didFail error: MebiusError)
    /// AVPlayer moved to another variant: what it now reports playing. Either value
    /// is 0 or negative when unknown.
    func scalePlayback(_ playback: ScalePlayback, didSwitchToHeight height: Double, bitrate: Double)
}

final class ScalePlayback {
    weak var delegate: ScalePlaybackDelegate?

    private var url: URL
    private let token: String
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statsTimer: Timer?
    private var observers: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var accessLogObserver: NSObjectProtocol?
    private var hasReportedPlaying = false

    // Variant limits, kept here so a swapped-in item gets them too. Zero is no limit.
    private var peakBitRate: Double = 0
    private var maxResolution: CGSize = .zero

    init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    #if canImport(UIKit)
    func start(in view: MebiusVideoView) {
        assert(Thread.isMainThread, "Mebius playback must be started on the main thread")

        let item = makeItem()
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        self.playerItem = item
        self.player = player
        view.attachScalePlayer(player)

        observe(item)
        player.play()
        startStatsTimer()
    }
    #endif

    /// Replaces the item with one for `url` on the SAME AVPlayer, so volume and mute
    /// carry over untouched and the view keeps its layer.
    func reopen(url: URL) {
        guard let player else { return }
        removeItemObservers()
        self.url = url
        let item = makeItem()
        playerItem = item
        player.replaceCurrentItem(with: item)
        observe(item)
        player.play()
    }

    /// Bounds which variant of a master playlist AVPlayer may pick. Zero lifts a limit.
    func setLimits(peakBitRate: Double, maxResolution: CGSize) {
        self.peakBitRate = peakBitRate
        self.maxResolution = maxResolution
        playerItem?.preferredPeakBitRate = peakBitRate
        playerItem?.preferredMaximumResolution = maxResolution
    }

    private func makeItem() -> AVPlayerItem {
        // Token is passed as an authorization header on the playlist request.
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = peakBitRate
        item.preferredMaximumResolution = maxResolution
        return item
    }

    private func observe(_ item: AVPlayerItem) {
        observeItem(item)
        observeEnd(item)
        observeAccessLog(item)
    }

    private func removeItemObservers() {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        for token in [endObserver, accessLogObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(token)
        }
        endObserver = nil
        accessLogObserver = nil
    }

    func setVolume(_ volume: Float) {
        player?.volume = max(0, min(1, volume))
    }

    func stop() {
        statsTimer?.invalidate()
        statsTimer = nil
        removeItemObservers()
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
            DispatchQueue.main.async { self.noteLikelyToKeepUp() }
        }

        observers = [statusObserver, bufferEmptyObserver, likelyToKeepUpObserver]
    }

    /// The first time per session is the start of playback; every later time is a
    /// recovery from a rebuffer. `hasReportedPlaying` is deliberately NOT reset by
    /// ``reopen(url:)``: a quality switch continues the session, and reporting it
    /// as a fresh start would re-run route acceptance. Reset only by ``stop()``.
    func noteLikelyToKeepUp() {
        if hasReportedPlaying {
            delegate?.scalePlaybackDidResume(self)
        } else {
            hasReportedPlaying = true
            delegate?.scalePlaybackDidStartPlaying(self)
        }
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

    // A new access-log entry is how AVPlayer announces a variant switch.
    private func observeAccessLog(_ item: AVPlayerItem) {
        accessLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            guard let self, let item else { return }
            let bitrate = item.accessLog()?.events.last?.indicatedBitrate ?? 0
            self.delegate?.scalePlayback(self, didSwitchToHeight: Double(item.presentationSize.height), bitrate: bitrate)
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
