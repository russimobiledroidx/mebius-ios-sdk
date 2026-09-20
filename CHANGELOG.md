# Changelog

## 0.4.0

- Publishing is capped at 2500 kbps by default, matching the studio's OBS encoder,
  so a broadcast costs the same whichever path it came from.
  `createBroadcaster(video:audio:maxBitrateKbps:)` changes it; 0 lifts it entirely.

  The cap is applied to the sender's encoding parameters, which is the only place
  it is real. The capture format bounds the SOURCE — how many pixels arrive per
  second — while the encoder still chooses how many bits to spend describing them,
  and high-motion content makes it spend near the top of its range.

  It matters far past the device: nothing transcodes anywhere in the path, so every
  viewer is delivered at exactly the bitrate published here. One broadcaster's
  setting is multiplied by the size of its audience.

## 0.3.0

- A delivery route that stops delivering is now reopened instead of leaving a
  frozen frame. Route selection ran exactly once, when playback started:
  whichever route produced the first frame served the rest of the session, and
  when it later died — a CDN edge restarting, the publisher reconnecting, the
  device changing network — the picture simply stopped. A `mebiusPlayerDidEnd`
  after that point ended the watch outright, and a failure was reported with
  nothing attempted.

  On a 90-minute watch that looked like bad luck. On a channel that runs for a
  day it is a certainty, because every one of those causes happens more than
  once a day, and the viewer's word for it is a black screen.

  The player now supervises the route it accepted. A route that reports it
  ended, that fails after delivering, or that stalls for longer than ten
  seconds, is treated as lost: it is torn down and the full route list is walked
  again, because the usual causes take out one route and not the others.
  Reopening backs off (1s, 2s, 4s, 8s, 16s) and gives up after five consecutive
  attempts — bounded on purpose, since every viewer of one broadcast fails at
  the same instant and an unbounded retry from a full room is how a recovery
  mechanism becomes the outage. `mebiusPlayerDidBuffer(_:)` fires as soon as
  reopening starts, `mebiusPlayerDidStartPlaying(_:)` when a route is serving
  again, and the end — or the failure that lost the route — only once the budget
  is spent.

  Refreshed credentials need no handling here: the client renews the token on
  its own schedule whether or not anything is playing, and every route stamps
  the current token as it builds its URL, so a route reopened after a long stall
  connects with today's credential.

- Fixed: a segmented route that failed during the initial route walk reported
  the error to the app instead of failing over to the next route, and a route
  the player had already abandoned could fail the one now playing. Both paths
  are now identity-checked and routed like the real-time one, which is the one
  thing the route list exists to do.

- A session can now outlive the token it opened with. Pass `getToken:` to
  `Mebius.connect` and the SDK mints a fresh credential shortly *before* `exp`
  rather than reacting to `.tokenExpired` afterwards, retrying with backoff for
  as long as the current token is still valid — so `.tokenExpired` now means the
  credential genuinely ran out, not that one mint failed. Each renewal calls
  `MebiusClientDelegate.mebiusClientDidRefreshToken(_:)` and the
  `onTokenRefreshed` closure.

  This is what a camera publisher needed: a match longer than the token's life
  used to cost a visible reconnect in the middle of it.

  A renewed token is refused — and retried, not fatal — when it is scoped to a
  different stream than the session, or when it does not outlive the token it
  replaces. A provider's late answer is also dropped if `updateToken` replaced
  the credential while it was being fetched, so the app's own swap always wins.

- `MebiusPlayer.qualities` reports the renditions a stream can actually be
  switched between, and `setQuality(_:)` selects one. `qualities` is empty for
  every Mebius stream today — the engine publishes a single rendition and does
  no ladder transcoding — which is the cue for a UI to HIDE its quality menu
  rather than offer a choice that does not exist. `setQuality` throws for an id
  that is not on offer instead of silently doing nothing; throwing does not
  touch playback. The list is per delivery route, announced through
  `mebiusPlayer(_:didChangeQualities:)` once per accepted route.

- Behaviour without `getToken:` is unchanged. No renewal is scheduled, no new
  timer is armed, and an expired token still surfaces exactly when and how it
  did in 0.2.3 — proven by a test rather than asserted.

### Source-breaking (one keyword)

`updateToken(_:)` now `throws`, so existing call sites need `try`:

```swift
try client.updateToken(newToken)   // was: client.updateToken(newToken)
```

It throws `.tokenExpired` for an empty token and `.streamNotFound` for one
scoped to a different stream. Silently accepting a credential for another stream
would not renew the session — it would break it on the next request, far from
the line that caused it. 0.2.3 remains published for anyone who would rather not
take the change yet.

`updateToken(_:)` must also be called on the main thread, like every other
mutating Mebius call. It shares state with the automatic renewal, which runs on
main; a backend completion handler usually does not, so dispatch to main first
(the README example does).
