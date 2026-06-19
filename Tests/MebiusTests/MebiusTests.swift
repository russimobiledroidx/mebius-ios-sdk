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
    func testAllEndpointsDeriveFromGateway() {
        let gateway = URL(string: "https://gateway.mebius.io")!
        let endpoints = GatewayEndpoints(gateway: gateway)
        XCTAssertTrue(endpoints.publishURL(streamId: "s").absoluteString.hasPrefix("https://gateway.mebius.io"))
        XCTAssertTrue(endpoints.lowLatencySubscribeURL(streamId: "s").absoluteString.hasPrefix("https://gateway.mebius.io"))
        XCTAssertTrue(endpoints.scalePlaylistURL(streamId: "s").absoluteString.hasPrefix("https://gateway.mebius.io"))
    }
}
