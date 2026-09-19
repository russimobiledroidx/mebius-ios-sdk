import Foundation

/// Delegate that receives ``MebiusClient`` connection lifecycle events.
///
/// All delegate methods are invoked on the main thread.
public protocol MebiusClientDelegate: AnyObject {
    /// The client successfully connected to the Mebius gateway.
    func mebiusClientDidConnect(_ client: MebiusClient)
    /// The client disconnected from the Mebius gateway.
    func mebiusClientDidDisconnect(_ client: MebiusClient)
    /// The client encountered an error. Inspect `error` for the cause; on
    /// ``MebiusError/tokenExpired`` the app should refresh its token and reconnect.
    func mebiusClient(_ client: MebiusClient, didFailWithError error: MebiusError)
    /// A fresh access token was fetched and is now in use.
    ///
    /// Purely informational: publishing and playback continue uninterrupted and
    /// nothing needs to be done in response.
    func mebiusClientDidRefreshToken(_ client: MebiusClient)
}

public extension MebiusClientDelegate {
    func mebiusClientDidConnect(_ client: MebiusClient) {}
    func mebiusClientDidDisconnect(_ client: MebiusClient) {}
    func mebiusClient(_ client: MebiusClient, didFailWithError error: MebiusError) {}
    func mebiusClientDidRefreshToken(_ client: MebiusClient) {}
}

/// Delegate that receives ``MebiusBroadcaster`` events.
///
/// All delegate methods are invoked on the main thread.
public protocol MebiusBroadcasterDelegate: AnyObject {
    /// The broadcast started successfully.
    func mebiusBroadcasterDidStart(_ broadcaster: MebiusBroadcaster)
    /// The broadcast stopped.
    func mebiusBroadcasterDidStop(_ broadcaster: MebiusBroadcaster)
    /// Periodic broadcast statistics were reported.
    func mebiusBroadcaster(_ broadcaster: MebiusBroadcaster, didReportStats stats: MebiusBroadcastStats)
    /// The broadcaster encountered an error.
    func mebiusBroadcaster(_ broadcaster: MebiusBroadcaster, didFailWithError error: MebiusError)
}

public extension MebiusBroadcasterDelegate {
    func mebiusBroadcasterDidStart(_ broadcaster: MebiusBroadcaster) {}
    func mebiusBroadcasterDidStop(_ broadcaster: MebiusBroadcaster) {}
    func mebiusBroadcaster(_ broadcaster: MebiusBroadcaster, didReportStats stats: MebiusBroadcastStats) {}
    func mebiusBroadcaster(_ broadcaster: MebiusBroadcaster, didFailWithError error: MebiusError) {}
}

/// Delegate that receives ``MebiusPlayer`` events.
///
/// All delegate methods are invoked on the main thread.
public protocol MebiusPlayerDelegate: AnyObject {
    /// Playback started and the first frames are rendering.
    func mebiusPlayerDidStartPlaying(_ player: MebiusPlayer)
    /// Playback stalled and is buffering.
    func mebiusPlayerDidBuffer(_ player: MebiusPlayer)
    /// Playback ended (the stream finished or was stopped at the source).
    func mebiusPlayerDidEnd(_ player: MebiusPlayer)
    /// Periodic playback statistics were reported.
    func mebiusPlayer(_ player: MebiusPlayer, didReportStats stats: MebiusPlayerStats)
    /// The player encountered an error.
    func mebiusPlayer(_ player: MebiusPlayer, didFailWithError error: MebiusError)
    /// The selectable renditions changed, because the player moved to a
    /// different delivery route. Called once per accepted route, carrying the
    /// list as it now stands — today always empty, since no route offers a ladder.
    func mebiusPlayer(_ player: MebiusPlayer, didChangeQualities qualities: [MebiusQuality])
}

public extension MebiusPlayerDelegate {
    func mebiusPlayerDidStartPlaying(_ player: MebiusPlayer) {}
    func mebiusPlayerDidBuffer(_ player: MebiusPlayer) {}
    func mebiusPlayerDidEnd(_ player: MebiusPlayer) {}
    func mebiusPlayer(_ player: MebiusPlayer, didReportStats stats: MebiusPlayerStats) {}
    func mebiusPlayer(_ player: MebiusPlayer, didFailWithError error: MebiusError) {}
    func mebiusPlayer(_ player: MebiusPlayer, didChangeQualities qualities: [MebiusQuality]) {}
}
