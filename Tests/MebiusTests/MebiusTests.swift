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

final class QualityLadderTests: XCTestCase {

    private let ladder = [
        MebiusRendition(id: "1080p", height: 1080, bitrateKbps: 5000, path: "/d/wide/s1/1080p"),
        MebiusRendition(id: "720p", height: 720, bitrateKbps: 2800, path: "/d/wide/s1/720p"),
        MebiusRendition(id: "480p", height: 480, bitrateKbps: 1000, path: "/d/wide/s1/480p"),
    ]

    private let tokenBody = """
    {"token":"t","deliveries":[
      {"kind":"fast","path":"/d/fast/s1","renditions":[{"id":"720p","height":720,"bitrateKbps":2800,"path":"/d/fast/s1/720p"}]},
      {"kind":"wide","path":"/d/wide/s1","extra":true,"renditions":[
        {"id":"1080p","height":1080,"bitrateKbps":5000,"path":"/d/wide/s1/1080p","codec":"avc1"},
        {"id":"720p","height":720,"bitrateKbps":2800,"path":"/d/wide/s1/720p"},
        {"id":"480p","height":480,"bitrateKbps":1000,"path":"/d/wide/s1/480p"},
        {"height":360}]},
      {"kind":"local","path":"/live/s1/index.m3u8"}]}
    """

    func testRenditionsDecodeFromTheTokenResponse() throws {
        let body = try JSONSerialization.jsonObject(with: Data(tokenBody.utf8)) as? [String: Any]
        let parsed = MebiusDelivery.list(fromTokenResponse: body)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[1].renditions, ladder, "the id-less rung is dropped, unknown fields ignored")
        XCTAssertTrue(parsed[2].renditions.isEmpty)
    }

    func testRenditionsDecodeWithCodableAndTolerateAbsence() throws {
        struct Body: Decodable { let deliveries: [MebiusDelivery] }
        let plain = try JSONDecoder().decode(Body.self, from: Data(#"{"deliveries":[{"kind":"wide","path":"/d/wide/s1","new":1}]}"#.utf8))
        XCTAssertEqual(plain.deliveries, [MebiusDelivery(kind: "wide", path: "/d/wide/s1")])

        let broken = try JSONDecoder().decode(Body.self, from: Data(#"{"deliveries":[{"kind":"wide","path":"/d/wide/s1","renditions":"x"}]}"#.utf8))
        XCTAssertTrue(broken.deliveries[0].renditions.isEmpty, "a bad ladder costs the menu, not the route")

        let laddered = try JSONDecoder().decode(Body.self, from: Data(#"{"deliveries":[{"kind":"wide","path":"/d/wide/s1","renditions":[{"id":"720p","height":720,"bitrateKbps":2800,"path":"/d/wide/s1/720p"}]}]}"#.utf8))
        XCTAssertEqual(laddered.deliveries[0].renditions, [ladder[1]])
    }

    func testOnlyTheWideRouteCarriesTheLadderAndOffHostRungsAreDropped() {
        let routes = buildPlaybackRoutes(mode: .auto, deliveries: [
            MebiusDelivery(kind: "wide", path: "/d/wide/s1",
                           renditions: ladder + [MebiusRendition(id: "evil", height: 240, path: "https://evil.example/x")]),
            MebiusDelivery(kind: "local", path: "/live/s1/index.m3u8", renditions: ladder),
        ])
        XCTAssertEqual(routes[0].renditions, ladder)
        XCTAssertTrue(routes[1].renditions.isEmpty)
        XCTAssertTrue(routes[2].renditions.isEmpty)
    }

    func testNoLadderLeavesEverythingAsItWas() {
        let routes = buildPlaybackRoutes(mode: .auto, deliveries: [MebiusDelivery(kind: "wide", path: "/d/wide/s1")])
        XCTAssertTrue(routes.allSatisfy { $0.renditions.isEmpty })
        XCTAssertEqual(scalePath(for: routes[0], quality: "auto"), "/d/wide/s1")
        XCTAssertEqual(peakBitRate([], maxHeight: 720), 0)
        XCTAssertNil(closestRendition([], height: 720, bitrate: 2_800_000))

        let player = Mebius(appId: "a", gateway: URL(string: "https://gateway.mebius.io")!)
            .connect(token: "t").createPlayer()
        XCTAssertTrue(player.qualities.isEmpty)
        XCTAssertNoThrow(try player.setQuality("auto"))
        XCTAssertThrowsError(try player.setQuality("720p"))
    }

    func testManualPickOpensTheRungWithTheSameToken() {
        let route = PlaybackRoute(isRealtime: false, deliveryPath: "/d/wide/s1", renditions: ladder)
        XCTAssertEqual(scalePath(for: route, quality: "auto"), "/d/wide/s1")
        XCTAssertEqual(scalePath(for: route, quality: "unknown"), "/d/wide/s1")
        let path = scalePath(for: route, quality: "720p")!
        let url = GatewayEndpoints(gateway: URL(string: "https://gateway.mebius.io")!)
            .deliveryURL(path: path, token: "tok")!
        XCTAssertEqual(url.absoluteString, "https://gateway.mebius.io/d/wide/s1/720p?token=tok")
    }

    func testRungPickUnderAMaxCap() {
        XCTAssertEqual(cappedRendition(ladder, maxHeight: nil)?.id, "1080p")
        XCTAssertEqual(cappedRendition(ladder, maxHeight: 1080)?.id, "1080p")
        XCTAssertEqual(cappedRendition(ladder, maxHeight: 900)?.id, "720p")
        XCTAssertEqual(cappedRendition(ladder, maxHeight: 360)?.id, "480p", "a cap below the ladder still plays")

        // Just below the cheapest excluded rung, so the allowed rung's audio and
        // overhead on top of its video bitrate do not exclude it too.
        XCTAssertEqual(peakBitRate(ladder, maxHeight: 720), 4_999_999)
        XCTAssertEqual(peakBitRate(ladder, maxHeight: 480), 2_799_999)
        XCTAssertEqual(peakBitRate(ladder, maxHeight: 1080), 0)
        XCTAssertEqual(peakBitRate(ladder, maxHeight: nil), 0)
    }

    func testAccessLogMapsToTheClosestRendition() {
        XCTAssertEqual(closestRendition(ladder, height: 720, bitrate: 0), "720p")
        XCTAssertEqual(closestRendition(ladder, height: 1072, bitrate: 1_000_000), "1080p", "height wins")
        XCTAssertEqual(closestRendition(ladder, height: 0, bitrate: 3_100_000), "720p")
        XCTAssertEqual(closestRendition(ladder, height: 0, bitrate: 900_000), "480p")
        XCTAssertNil(closestRendition(ladder, height: 0, bitrate: -1))
    }

    // MARK: Audit round

    func testCapWidthMatchesWhatTheGatewayAdvertises() {
        // 480 * 16 / 9 = 853 in integer maths, which excludes the 854x480 variant.
        XCTAssertEqual(ladderWidth(height: 480), 854)
        XCTAssertEqual(ladderWidth(height: 720), 1280)
        XCTAssertEqual(ladderWidth(height: 1080), 1920)
        XCTAssertEqual(ladderWidth(height: 360), 640)
        XCTAssertEqual(ladderWidth(height: 540), 960)
        XCTAssertEqual(ladderWidth(height: 1) % 2, 0, "rounded up to even")
    }

    func testAllowListKeepsLadderOrderAndIgnoresWhatIsNotOnIt() {
        XCTAssertEqual(allowedRenditions(ladder, allowed: nil), ladder)
        XCTAssertEqual(allowedRenditions(ladder, allowed: []), ladder)
        XCTAssertEqual(allowedRenditions(ladder, allowed: ["720p", "1080p", "4k"]).map(\.id), ["1080p", "720p"])
        XCTAssertEqual(allowedRenditions(ladder, allowed: ["4k"]), ladder, "naming no rung means every rung")
    }

    func testMasterFilterOnlyWhenTheAllowListNarrowsAuto() {
        let route = PlaybackRoute(isRealtime: false, deliveryPath: "/d/wide/s1", renditions: ladder)
        let endpoints = GatewayEndpoints(gateway: URL(string: "https://gateway.mebius.io")!)

        let filtered = endpoints.deliveryURL(
            path: scalePath(for: route, quality: "auto")!, token: "tok",
            query: masterFilter(for: route, quality: "auto", allowed: ["720p", "1080p"])
        )!
        XCTAssertEqual(filtered.absoluteString, "https://gateway.mebius.io/d/wide/s1?token=tok&q=1080p,720p")

        XCTAssertTrue(masterFilter(for: route, quality: "auto", allowed: nil).isEmpty)
        XCTAssertTrue(masterFilter(for: route, quality: "auto", allowed: ["480p", "720p", "1080p"]).isEmpty)
        XCTAssertTrue(masterFilter(for: route, quality: "720p", allowed: ["720p"]).isEmpty, "a pinned rung has no variants")
        let plain = PlaybackRoute(isRealtime: false, deliveryPath: "/d/wide/s1")
        XCTAssertTrue(masterFilter(for: plain, quality: "auto", allowed: ["720p"]).isEmpty, "no ladder, no change")
    }

    func testPinSurvivesFailoverOnlyOntoARouteThatOffersIt() {
        let laddered = PlaybackRoute(isRealtime: false, deliveryPath: "/d/wide/s1", renditions: ladder)
        let plain = PlaybackRoute(isRealtime: false, deliveryPath: "/live/s1/index.m3u8")
        XCTAssertEqual(resolvedQuality("720p", on: laddered, allowed: nil), "720p")
        XCTAssertEqual(resolvedQuality("720p", on: plain, allowed: nil), "auto")
        XCTAssertEqual(resolvedQuality("480p", on: laddered, allowed: ["1080p", "720p"]), "auto", "no longer allowed")
        XCTAssertEqual(resolvedQuality("auto", on: laddered, allowed: nil), "auto")
    }

    func testAllowListWithoutALadderChangesNothing() {
        let player = Mebius(appId: "a", gateway: URL(string: "https://gateway.mebius.io")!)
            .connect(token: "t").createPlayer()
        var announced = 0
        player.onQualitiesChanged = { _ in announced += 1 }
        player.setAllowedQualities(["1080p", "720p"])
        player.setMaxQuality(height: 0)
        XCTAssertTrue(player.qualities.isEmpty)
        XCTAssertEqual(announced, 0)
        XCTAssertThrowsError(try player.setQuality("720p"))
    }

    // MARK: Re-audit round

    func testCodableSkipsOnlyTheMalformedRung() throws {
        struct Body: Decodable { let deliveries: [MebiusDelivery] }
        let json = #"""
        {"deliveries":[{"kind":"wide","path":"/d/wide/s1","renditions":[
          {"id":"1080p","height":1080,"bitrateKbps":5000,"path":"/d/wide/s1/1080p"},
          {"height":360},
          "nonsense",
          {"id":"","path":"/d/wide/s1/x"},
          {"id":"720p","height":"tall","bitrateKbps":2800,"path":"/d/wide/s1/720p"},
          [1, 2],
          {"id":"480p","height":480,"bitrateKbps":1000,"path":"/d/wide/s1/480p"}]}]}
        """#
        let decoded = try JSONDecoder().decode(Body.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.deliveries[0].renditions, [
            ladder[0],
            MebiusRendition(id: "720p", height: nil, bitrateKbps: 2800, path: "/d/wide/s1/720p"),
            ladder[2],
        ])
    }

    func testOnlyTheFirstKeepUpStartsPlaybackAndLaterOnesResumeIt() {
        final class Recorder: ScalePlaybackDelegate {
            var events: [String] = []
            func scalePlaybackDidStartPlaying(_ playback: ScalePlayback) { events.append("start") }
            func scalePlaybackDidBuffer(_ playback: ScalePlayback) { events.append("buffer") }
            func scalePlaybackDidResume(_ playback: ScalePlayback) { events.append("resume") }
            func scalePlaybackDidEnd(_ playback: ScalePlayback) {}
            func scalePlayback(_ playback: ScalePlayback, didReportStats stats: MebiusPlayerStats) {}
            func scalePlayback(_ playback: ScalePlayback, didFail error: MebiusError) {}
            func scalePlayback(_ playback: ScalePlayback, didSwitchToHeight height: Double, bitrate: Double) {}
        }
        let recorder = Recorder()
        let playback = ScalePlayback(url: URL(string: "https://gateway.mebius.io/d/wide/s1")!, token: "t")
        playback.delegate = recorder

        playback.noteLikelyToKeepUp()
        // Without the resume, the stall timer armed by a mid-play rebuffer was never
        // cancelled, and a route that had recovered on its own was torn down anyway.
        playback.noteLikelyToKeepUp()
        playback.reopen(url: URL(string: "https://gateway.mebius.io/d/wide/s1/720p")!)
        playback.noteLikelyToKeepUp()
        XCTAssertEqual(recorder.events, ["start", "resume", "resume"], "a quality reopen is not a fresh start")

        playback.stop()
        playback.noteLikelyToKeepUp()
        XCTAssertEqual(recorder.events.last, "start", "stop() ends the session")
    }
}
