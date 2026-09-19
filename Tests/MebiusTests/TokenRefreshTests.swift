import XCTest
@testable import Mebius

/// CR-1 on iOS: a session that outlives the credential it opened with.
///
/// What is worth proving here, in order:
///  * without `getToken`, 0.2.x behaviour is untouched — no renewal, no new event;
///  * with it, the credential is renewed and swapped in place;
///  * a provider that fails does not end the broadcast while the old token lives;
///  * a token for another stream is refused, and refusing does not damage the
///    session.
final class TokenRefreshTests: XCTestCase {

    private let gateway = URL(string: "https://gateway.mebius.io")!

    // MARK: - Reading a token

    func testReadTokenReadsExpAndStreamId() {
        let info = readToken(jwt(streamId: "s_match"))
        XCTAssertEqual(info.streamId, "s_match")
        XCTAssertNotNil(info.expiresAt)
    }

    func testReadTokenShrugsOffAnythingUnreadable() {
        for junk in ["", "not-a-jwt", "a.b", "a.!!!.c"] {
            XCTAssertNil(readToken(junk).expiresAt, junk)
            XCTAssertNil(readToken(junk).streamId, junk)
        }
    }

    // MARK: - Without a provider (0.2.x behaviour)

    func testWithoutGetTokenNothingIsRenewedAndNothingNewIsReported() {
        let mebius = Mebius(appId: "app", gateway: gateway)
        // Already expired. Any renewal that was going to happen would be due
        // immediately, and any new proactive error would fire now — neither may.
        let client = mebius.connect(token: jwt(expiresIn: -3600))

        let connected = expectation(description: "connected")
        client.onConnected = { connected.fulfill() }
        var errors: [MebiusError] = []
        var refreshes = 0
        client.onError = { errors.append($0) }
        client.onTokenRefreshed = { refreshes += 1 }
        wait(for: [connected], timeout: 1.0)
        settle()

        XCTAssertEqual(client.state, .connected)
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(refreshes, 0)
    }

    // MARK: - With a provider

    func testGetTokenRenewsAndSwapsTheCredentialInPlace() {
        let mebius = Mebius(appId: "app", gateway: gateway)
        var mints = 0
        // Expiry already inside the renewal margin, so the renewal is due at once
        // and the test does not have to wait an hour for it.
        let client = mebius.connect(
            token: jwt(streamId: "s_match", expiresIn: 30),
            getToken: { done in
                mints += 1
                done(self.jwt(streamId: "s_match", expiresIn: 3600 * Double(mints + 1)))
            }
        )

        let refreshed = expectation(description: "refreshed")
        client.onTokenRefreshed = { refreshed.fulfill() }
        wait(for: [refreshed], timeout: 2.0)

        XCTAssertEqual(mints, 1)
        // Renewing is not reconnecting: the session was never torn down.
        XCTAssertEqual(client.state, .connected)
        // Decode rather than compare strings: re-minting a JWT here would embed a
        // second, later `Date()`, so a run that straddles a whole second would fail
        // on a byte comparison while the SDK behaved perfectly.
        let installed = readToken(client.currentToken)
        XCTAssertEqual(installed.streamId, "s_match")
        XCTAssertGreaterThan(installed.expiresAt ?? .distantPast, Date().addingTimeInterval(3000))
    }

    func testAFailingProviderDoesNotEndASessionWhoseTokenIsStillValid() {
        let mebius = Mebius(appId: "app", gateway: gateway)
        var attempts = 0
        let tried = expectation(description: "provider called")
        // Half a minute of life left: there IS a window to retry inside.
        let client = mebius.connect(
            token: jwt(expiresIn: 30),
            getToken: { done in
                attempts += 1
                if attempts == 1 { tried.fulfill() }
                done(nil) // could not mint
            }
        )
        var errors: [MebiusError] = []
        client.onError = { errors.append($0) }
        wait(for: [tried], timeout: 2.0)
        settle()

        XCTAssertGreaterThanOrEqual(attempts, 1)
        // The old credential is still good, so expiry must not be reported yet.
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(client.state, .connected)
    }

    func testAStaleTokenIsRetriedNotReportedWhileTheOldOneLives() {
        let mebius = Mebius(appId: "app", gateway: gateway)
        let stale = jwt(expiresIn: 30)
        var attempts = 0
        let retried = expectation(description: "retried")
        let client = mebius.connect(
            token: stale,
            getToken: { done in
                attempts += 1
                if attempts == 2 { retried.fulfill() }
                done(stale)
            }
        )
        var errors: [MebiusError] = []
        client.onError = { errors.append($0) }
        wait(for: [retried], timeout: 5.0)

        // A provider stuck on a cached credential is a FAILED mint, not a dead
        // session: the old token is good for another half minute, so ending the
        // broadcast now would be worse than not renewing at all.
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(client.state, .connected)
    }

    func testARenewalForAnotherStreamIsDroppedInsteadOfInstalled() {
        let mebius = Mebius(appId: "app", gateway: gateway)
        let original = jwt(streamId: "s_match", expiresIn: 30)
        var refreshes = 0
        let tried = expectation(description: "provider called")
        let client = mebius.connect(
            token: original,
            // A provider closure holding a stale stream id. Installing this would
            // break the session on its next request, far from the cause.
            getToken: { done in
                tried.fulfill()
                done(self.jwt(streamId: "s_other", expiresIn: 7200))
            }
        )
        client.onTokenRefreshed = { refreshes += 1 }
        wait(for: [tried], timeout: 5.0)
        settle()

        XCTAssertEqual(client.currentToken, original)
        XCTAssertEqual(refreshes, 0)
        XCTAssertEqual(client.state, .connected)
    }

    // MARK: - updateToken

    func testUpdateTokenReplacesTheCredentialWithoutRestartingAnything() throws {
        let client = connectedClient(token: jwt(streamId: "s_match"))
        let next = jwt(streamId: "s_match", expiresIn: 7200)

        try client.updateToken(next)

        XCTAssertEqual(client.currentToken, next)
        XCTAssertEqual(client.state, .connected)
    }

    func testUpdateTokenRefusesATokenForAnotherStreamAndTheSessionSurvives() {
        let original = jwt(streamId: "s_match")
        let client = connectedClient(token: original)

        XCTAssertThrowsError(try client.updateToken(jwt(streamId: "s_other"))) { error in
            XCTAssertEqual(error as? MebiusError, .streamNotFound)
        }
        // A rejected swap must not be a way to break a live broadcast.
        XCTAssertEqual(client.currentToken, original)
        XCTAssertEqual(client.state, .connected)
    }

    func testUpdateTokenRefusesAnEmptyToken() {
        let original = jwt()
        let client = connectedClient(token: original)

        XCTAssertThrowsError(try client.updateToken("")) { error in
            XCTAssertEqual(error as? MebiusError, .tokenExpired)
        }
        XCTAssertEqual(client.currentToken, original)
    }

    // MARK: - CR-2 qualities

    func testPlayerReportsNoRenditionsSoAUICanHideItsQualityMenu() {
        let player = connectedClient(token: jwt()).createPlayer()
        XCTAssertTrue(player.qualities.isEmpty)
    }

    func testSetQualityAcceptsAutoAndRefusesAnythingNotOnOffer() throws {
        let player = connectedClient(token: jwt()).createPlayer()
        try player.setQuality("auto")
        XCTAssertThrowsError(try player.setQuality("ngawur"))
    }

    // MARK: - Helpers

    private func connectedClient(token: String) -> MebiusClient {
        let client = Mebius(appId: "app", gateway: gateway).connect(token: token)
        let connected = expectation(description: "connected")
        client.onConnected = { connected.fulfill() }
        wait(for: [connected], timeout: 1.0)
        return client
    }

    /// Lets main-queue work scheduled with no delay actually run.
    private func settle() {
        let done = expectation(description: "settled")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1.0)
    }

    /// An unsigned JWT carrying just the claims this SDK reads. Nothing verifies it
    /// here; only the gateway holds the secret.
    ///
    /// `exp` is truncated to whole seconds, which is also what makes the token a
    /// stable string for equality checks within one test run.
    private func jwt(streamId: String? = nil, expiresIn: TimeInterval = 3600) -> String {
        var payload: [String: Any] = ["exp": floor(Date().addingTimeInterval(expiresIn).timeIntervalSince1970)]
        if let streamId { payload["streamId"] = streamId }
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).sig"
    }
}
