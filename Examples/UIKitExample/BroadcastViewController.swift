import UIKit
import Mebius

/// UIKit view controller that broadcasts the camera to a Mebius stream.
final class BroadcastViewController: UIViewController {

    private let token: String
    private let gateway = URL(string: "https://gateway.mebius.io")!
    private let streamId = "demo-stream"

    private let videoView = MebiusVideoView()
    private let liveButton = UIButton(type: .system)

    private var client: MebiusClient?
    private var broadcaster: MebiusBroadcaster?
    private var isLive = false

    init(token: String) {
        self.token = token
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.videoContentMode = .aspectFill
        view.addSubview(videoView)

        liveButton.setTitle("Go Live", for: .normal)
        liveButton.addTarget(self, action: #selector(toggleLive), for: .touchUpInside)
        liveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(liveButton)

        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            liveButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            liveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])

        let mebius = Mebius(appId: "your-app-id", gateway: gateway)
        let client = mebius.connect(token: token)
        self.client = client

        let broadcaster = client.createBroadcaster(video: true, audio: true)
        broadcaster.delegate = self
        broadcaster.attachPreview(to: videoView)
        self.broadcaster = broadcaster
    }

    @objc private func toggleLive() {
        if isLive { broadcaster?.stop() }
        else { broadcaster?.start(streamId: streamId) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        broadcaster?.stop()
        client?.disconnect()
    }
}

extension BroadcastViewController: MebiusBroadcasterDelegate {
    func mebiusBroadcasterDidStart(_ broadcaster: MebiusBroadcaster) {
        isLive = true
        liveButton.setTitle("Stop", for: .normal)
    }

    func mebiusBroadcasterDidStop(_ broadcaster: MebiusBroadcaster) {
        isLive = false
        liveButton.setTitle("Go Live", for: .normal)
    }

    func mebiusBroadcaster(_ broadcaster: MebiusBroadcaster, didFailWithError error: MebiusError) {
        let alert = UIAlertController(title: "Broadcast error", message: error.errorDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
