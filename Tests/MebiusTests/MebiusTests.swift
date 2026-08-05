import XCTest
@testable import Mebius

final class MebiusTests: XCTestCase {

    private let gateway = URL(string: "https://gateway.mebius.io")!

    func testInitStoresAppIdAndGateway() {
        let mebius = Mebius(appId: "app-123", gateway: gateway)
        XCTAssertEqual(mebius.appId, "app-123")
        XCTAssertEqual(mebius.gateway, gateway)
    }

    func testConnectWithValidTokenConnects() {
        let mebius = Mebius(appId: "app", gateway: gateway)
        let client = mebius.connect(token: "valid-token")
        let expectation = expectation(description: "connected")
        client.onConnected = { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(client.state, .connected)
    }

    func testConnectWithEmptyTokenFailsWithTokenExpired() {
        let mebius = Mebius(appId: "app", gateway: gateway)
        let client = mebius.connect(token: "")
        let expectation = expectation(description: "error")
        var received: MebiusError?
        client.onError = { received = $0; expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received, .tokenExpired)
    }

    func testDisconnect() {
        let mebius = Mebius(appId: "app", gateway: gateway)
        let client = mebius.connect(token: "t")
        let connected = expectation(description: "connected")
        client.onConnected = { connected.fulfill() }
        wait(for: [connected], timeout: 1.0)

        let disconnected = expectation(description: "disconnected")
        client.onDisconnected = { disconnected.fulfill() }
        client.disconnect()
        wait(for: [disconnected], timeout: 1.0)
        XCTAssertEqual(client.state, .disconnected)
    }
}

final class MebiusErrorTests: XCTestCase {
    func testCodeMapping() {
        XCTAssertEqual(MebiusError.tokenExpired.code, "TOKEN_EXPIRED")
        XCTAssertEqual(MebiusError.permissionDenied.code, "PERMISSION_DENIED")
        XCTAssertEqual(MebiusError.connectionFailed.code, "CONNECTION_FAILED")
        XCTAssertEqual(MebiusError.notConnected.code, "NOT_CONNECTED")
        XCTAssertEqual(MebiusError.streamNotFound.code, "STREAM_NOT_FOUND")
        XCTAssertEqual(MebiusError.unknown(message: "x").code, "UNKNOWN")
    }

    func testInitFromCode() {
        XCTAssertEqual(MebiusError(code: "TOKEN_EXPIRED"), .tokenExpired)
        XCTAssertEqual(MebiusError(code: "permission_denied"), .permissionDenied)
        XCTAssertEqual(MebiusError(code: "CONNECTION_FAILED"), .connectionFailed)
        XCTAssertEqual(MebiusError(code: "NOT_CONNECTED"), .notConnected)
        XCTAssertEqual(MebiusError(code: "STREAM_NOT_FOUND"), .streamNotFound)
        if case .unknown = MebiusError(code: "SOMETHING_ELSE") {} else {
            XCTFail("expected unknown")
        }
    }

    func testErrorDescriptionsUseMebiusTerms() {
        for error: MebiusError in [.tokenExpired, .permissionDenied, .connectionFailed, .notConnected, .streamNotFound, .unknown(message: "boom")] {
            let desc = (error.errorDescription ?? "").lowercased()
            XCTAssertTrue(desc.contains("mebius"), "error description should use Mebius terminology")
            // Abstraction: no raw protocol/infra terms leak into error messages.
            for forbidden in ["whip", "whep", "hls", "mediamtx", "flv"] {
                XCTAssertFalse(desc.contains(forbidden), "\(forbidden) must not appear in error messages")
            }
        }
    }
}

final class MebiusPlayerModeTests: XCTestCase {
    func testModesAreDistinct() {
        XCTAssertNotEqual(MebiusPlayerMode.lowLatency, MebiusPlayerMode.scale)
    }
}

final class MebiusFactoryTests: XCTestCase {
    private let gateway = URL(string: "https://gateway.mebius.io")!

    func testCreateBroadcasterConfiguresFlags() {
        let client = Mebius(appId: "a", gateway: gateway).connect(token: "t")
        let broadcaster = client.createBroadcaster(video: true, audio: false)
        XCTAssertTrue(broadcaster.videoEnabled)
        XCTAssertFalse(broadcaster.audioEnabled)
    }

    func testCreatePlayerStoresMode() {
        let client = Mebius(appId: "a", gateway: gateway).connect(token: "t")
        let player = client.createPlayer(mode: .scale)
        XCTAssertEqual(player.mode, .scale)
        player.setVolume(2.0)
        XCTAssertEqual(player.volume, 1.0, "volume should clamp to 1")
        player.setVolume(-1.0)
        XCTAssertEqual(player.volume, 0.0, "volume should clamp to 0")
    }

    func testBroadcasterStartWhenNotConnectedEmitsNotConnected() {
        let client = MebiusClient(appId: "a", gateway: gateway, token: "t")
        // Do NOT call beginConnecting, so state stays .disconnected.
        let broadcaster = client.createBroadcaster()
        let exp = expectation(description: "error")
        var received: MebiusError?
        broadcaster.onError = { received = $0; exp.fulfill() }
        broadcaster.start(streamId: "stream-1")
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(received, .notConnected)
    }
}

final class GatewayEndpointsTests: XCTestCase {

    private let gateway = URL(string: "https://gateway.mebius.io")!

    func testAllEndpointsDeriveFromGateway() {
        let endpoints = GatewayEndpoints(gateway: gateway)
        for url in [
            endpoints.publishURL(streamId: "s", token: "t"),
            endpoints.lowLatencySubscribeURL(streamId: "s", token: "t"),
            endpoints.originPlaylistURL(streamId: "s", token: "t"),
        ] {
            XCTAssertTrue(url.absoluteString.hasPrefix("https://gateway.mebius.io"))
        }
    }

    /// Regression, and the reason the old bug survived: the previous version of this
    /// test asserted only the HOST prefix. All three endpoints pointed at paths the
    /// gateway does not route — `/publish/`, `/subscribe/`, `/scale/` — and every one
    /// of them passed, because the host was right. The path is the part that failed.
    func testEndpointPathsAreOnesTheGatewayActuallyRoutes() {
        let endpoints = GatewayEndpoints(gateway: gateway)

        XCTAssertEqual(endpoints.publishURL(streamId: "s", token: "t").path, "/whip/s")
        XCTAssertEqual(endpoints.lowLatencySubscribeURL(streamId: "s", token: "t").path, "/whep/s")
        XCTAssertEqual(endpoints.originPlaylistURL(streamId: "s", token: "t").path,
                       "/live/s/index.m3u8")

        for url in [
            endpoints.publishURL(streamId: "s", token: "t"),
            endpoints.lowLatencySubscribeURL(streamId: "s", token: "t"),
            endpoints.originPlaylistURL(streamId: "s", token: "t"),
        ] {
            for dead in ["/publish/", "/subscribe/", "/scale/"] {
                XCTAssertFalse(url.path.hasPrefix(dead), "\(url.path) uses unrouted \(dead)")
            }
        }
    }

    /// The gateway reads the access token from the QUERY, not from a header: its auth
    /// hook and playback gate both look there, and playlist entries inherit `?token=`
    /// because the gateway rewrites them. Playback used to send a Bearer header only,
    /// which the gate does not read — a guaranteed 401.
    func testPlaybackURLsCarryTheTokenInTheQuery() {
        let endpoints = GatewayEndpoints(gateway: gateway)
        let origin = URLComponents(url: endpoints.originPlaylistURL(streamId: "s", token: "tok"),
                                   resolvingAgainstBaseURL: false)
        XCTAssertEqual(origin?.queryItems?.first(where: { $0.name == "token" })?.value, "tok")

        let delivered = endpoints.deliveryURL(path: "/d/wide/s", token: "tok")
        XCTAssertEqual(delivered?.path, "/d/wide/s")
        let components = URLComponents(url: delivered!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "token" })?.value, "tok")
    }

    /// A delivery path is untrusted response data and the token is a bearer
    /// credential, so a path that could point off-host must not be resolved at all.
    func testDeliveryURLRefusesAnythingThatCouldLeakTheToken() {
        let endpoints = GatewayEndpoints(gateway: gateway)
        for hostile in ["https://evil.example/x", "//evil.example/x", "http://evil.example/x", "d/wide/s", ""] {
            XCTAssertNil(endpoints.deliveryURL(path: hostile, token: "tok"),
                         "resolved hostile path \(hostile)")
        }
    }

    /// Regression on the real-time path.
    ///
    /// WHIP/WHEP used to carry the token ONLY as an `Authorization: Bearer` header.
    /// The gateway's MediaMTX auth hook reads `?token=` from the query and ignores the
    /// header, so publishing and sub-second playback were rejected with 401 on every
    /// attempt, however valid the token was. The signaling layer now appends it, so
    /// these two URLs are deliberately token-less here — what this pins is that the
    /// PATHS are right and that nothing re-adds a token twice.
    func testRealtimeEndpointsCarryTheTokenInTheQuery() {
        let endpoints = GatewayEndpoints(gateway: gateway)
        for url in [
            endpoints.publishURL(streamId: "s", token: "tok"),
            endpoints.lowLatencySubscribeURL(streamId: "s", token: "tok"),
        ] {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(q?.first(where: { $0.name == "token" })?.value, "tok",
                           "\(url) would be rejected with 401 — the gateway reads ?token=")
        }
    }

    func testTokenIsEscapedRatherThanPastedIn() {
        let endpoints = GatewayEndpoints(gateway: gateway)
        let url = endpoints.deliveryURL(path: "/d/wide/s", token: "a b&c=d")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "token" })?.value, "a b&c=d")
    }
}

final class PlaybackRouteTests: XCTestCase {

    private let deliveries = [
        MebiusDelivery(kind: "fast", path: "/d/fast/s1"),
        MebiusDelivery(kind: "wide", path: "/d/wide/s1"),
        MebiusDelivery(kind: "local", path: "/live/s1/index.m3u8"),
    ]

    func testGatewayOrderIsKeptAndOriginComesLast() {
        let routes = buildPlaybackRoutes(mode: .auto, deliveries: deliveries)
        // wide + local from the gateway, then origin. Origin must be last: every byte
        // of it is our bandwidth, unlike an edge route.
        XCTAssertEqual(routes.count, 3)
        XCTAssertEqual(routes[0].deliveryPath, "/d/wide/s1")
        XCTAssertEqual(routes[1].deliveryPath, "/live/s1/index.m3u8")
        XCTAssertNil(routes[2].deliveryPath)
    }

    func testBufferedRouteIsNeverOfferedOnThisPlatform() {
        // AVPlayer cannot play it. Declaring it would be a route that can never play.
        let paths = buildPlaybackRoutes(mode: .auto, deliveries: deliveries).map(\.deliveryPath)
        XCTAssertFalse(paths.contains("/d/fast/s1"))
    }

    func testLowLatencyTriesRealtimeFirstAndCanStillFallBack() {
        let routes = buildPlaybackRoutes(mode: .lowLatency, deliveries: deliveries)
        XCTAssertTrue(routes[0].isRealtime)
        XCTAssertGreaterThan(routes.count, 1)
    }

    func testUnresolvableAndUnknownRoutesAreSkipped() {
        let routes = buildPlaybackRoutes(mode: .auto, deliveries: [
            MebiusDelivery(kind: "wide", path: "https://evil.example/x"),
            MebiusDelivery(kind: "quantum", path: "/d/quantum/s1"),
        ])
        XCTAssertEqual(routes.count, 1)
        XCTAssertNil(routes[0].deliveryPath)
    }

    func testThereIsAlwaysAPlayableRouteWithNoDeliveries() {
        // Every existing integration passes none. They must keep working.
        XCTAssertEqual(buildPlaybackRoutes(mode: .scale, deliveries: []).count, 1)
    }

    func testParsingSkipsMalformedEntries() {
        // The list arrives over the network. One bad entry must cost a viewer one
        // route, never a failed play.
        let parsed = MebiusDelivery.list(fromJSON: [
            "nope",
            ["kind": "wide"],
            ["path": "/d/wide/s1"],
            ["kind": 1, "path": 2],
            ["kind": "wide", "path": "/d/wide/s1"],
        ])
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].path, "/d/wide/s1")
    }

    func testMissingDeliveriesFieldParsesToEmpty() {
        XCTAssertTrue(MebiusDelivery.list(fromJSON: nil).isEmpty)
        XCTAssertTrue(MebiusDelivery.list(fromTokenResponse: nil).isEmpty)
        XCTAssertTrue(MebiusDelivery.list(fromTokenResponse: ["token": "t"]).isEmpty)
    }

    func testFirstFrameBudgetMatchesTheOtherSDKs() {
        // Mirrored in web, Flutter and Android so a viewer sees the same behaviour on
        // every platform. Changing it here alone is a bug.
        XCTAssertEqual(mebiusFirstFrameTimeout, 8)
    }

    func testAPlainPlayerNoLongerDefaultsToARealtimeSession() {
        // The old default opened a per-viewer real-time session for every audience
        // member; only a monitor should ask for one.
        let client = Mebius(appId: "a", gateway: URL(string: "https://gateway.mebius.io")!)
            .connect(token: "t", deliveries: deliveries)
        XCTAssertEqual(client.createPlayer().mode, .auto)
        XCTAssertEqual(client.createMonitor().mode, .lowLatency)
    }
}
