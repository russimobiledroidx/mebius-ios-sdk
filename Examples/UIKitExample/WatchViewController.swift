import UIKit
import Mebius

/// UIKit view controller that watches a Mebius stream.
final class WatchViewController: UIViewController {

    private let token: String
    private let gateway = URL(string: "https://gateway.mebius.io")!
    private let streamId = "demo-stream"

    private let videoView = MebiusVideoView()
    private let volumeSlider = UISlider()

    private var client: MebiusClient?
    private var player: MebiusPlayer?

    init(token: String) {
        self.token = token
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.videoContentMode = .aspectFit
        view.addSubview(videoView)

        volumeSlider.minimumValue = 0
        volumeSlider.maximumValue = 1
        volumeSlider.value = 1
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(volumeSlider)

        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            volumeSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            volumeSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            volumeSlider.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])

        let mebius = Mebius(appId: "your-app-id", gateway: gateway)
        let client = mebius.connect(token: token)
        self.client = client

        // Choose .scale for large audiences, .lowLatency for real-time.
        let player = client.createPlayer(mode: .scale)
        player.delegate = self
        self.player = player

        client.onConnected = { [weak self] in
            guard let self else { return }
            self.player?.play(streamId: self.streamId, view: self.videoView)
        }
    }

    @objc private func volumeChanged() {
        player?.setVolume(volumeSlider.value)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player?.stop()
        client?.disconnect()
    }
}

extension WatchViewController: MebiusPlayerDelegate {
    func mebiusPlayerDidStartPlaying(_ player: MebiusPlayer) {
        title = "Playing"
    }

    func mebiusPlayerDidBuffer(_ player: MebiusPlayer) {
        title = "Buffering…"
    }

    func mebiusPlayerDidEnd(_ player: MebiusPlayer) {
        title = "Ended"
    }

    func mebiusPlayer(_ player: MebiusPlayer, didFailWithError error: MebiusError) {
        let alert = UIAlertController(title: "Playback error", message: error.errorDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
