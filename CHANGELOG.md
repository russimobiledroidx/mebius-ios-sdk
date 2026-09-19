# Changelog

## 0.3.0

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
