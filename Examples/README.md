# Examples

Copy-paste screens for both UI frameworks:

- [`SwiftUIExample`](SwiftUIExample) — `WatchView`, `BroadcastView`, and the
  `UIViewRepresentable` wrapper for `MebiusVideoView`.
- [`UIKitExample`](UIKitExample) — the same two screens as view controllers.

## Nothing compiles these, and that has cost us

These files are not members of any target in `Package.swift`, so `swift build`,
`swift test` and CI all skip them. That is why they drifted: they went on calling
`createPlayer(mode:)` with an explicit mode long after `.auto` became the default, and
they never passed `deliveries` at all — which silently costs edge delivery, the exact
thing `deliveries` exists to buy.

`swiftc -parse` catches a syntax error in them but nothing more. It will happily parse
a call to a method that no longer exists, so treat a clean parse as meaning very
little.

**If you change the public API, change these by hand and read them.** The real fix is
an Xcode project that builds them against the iOS SDK, which this repo does not have
yet — worth adding before the API grows again.
