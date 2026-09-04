# Changelog

All notable changes to the Mebius iOS SDK.

This SDK follows [Semantic Versioning](https://semver.org). The public API is
stable within a major version; breaking changes bump the major version across
all Mebius platform SDKs simultaneously.

## 0.2.3
- **Fixed: a viewer could get stuck on a black frame forever on the real-time
  route.** Playback was reported from the peer connection reaching `connected`,
  which means ICE and DTLS completed — true before any media flows, and still
  true if none ever does. That satisfied the player's 8-second first-frame budget
  for a route that had sent nothing, so the player never advanced to the next
  route and there was no error to react to. Playback is now reported when a frame
  actually arrives.
- Two consequences worth knowing. A low-latency player can now legitimately fall
  off the real-time route onto a buffered one — that is the fix working, not a
  regression. And the 8-second budget now has to cover decoder warm-up and the
  first keyframe as well as negotiation; a publisher slow to send one will fall
  back rather than fail.
- Teardown releases the remote tracks and closes the frame probe before removing
  it, so a frame still in flight cannot report playback for a route that has
  already stopped.

  Known limitation, unchanged: a broadcast with no camera — audio only — cannot be
  played on the real-time route, on any Mebius SDK. Audio arrives, but the
  first-frame budget is waiting for a picture that never comes. Publish with video
  if you need the real-time route.

## 0.2.2
- Published H264 preference on the publishing transceiver. libwebrtc negotiated
  VP8, which the gateway's segment-based deliveries cannot carry, so viewers off
  the real-time route received audio only while the device showed a healthy
  preview. (No entry was recorded at release; backfilled.)

## 0.2.1
- `MebiusPlayer.mode` and delivery-route handling. (No entry was recorded at
  release; backfilled from the release commit.)

## 0.2.0
- Ordered playback routes with a per-route first-frame budget, and `deliveries`
  passed through from the access token. (No entry was recorded at release;
  backfilled from the release commit.)

## 0.1.0
- Initial release: `Mebius`, `MebiusClient`, `MebiusBroadcaster`, `MebiusPlayer`, `MebiusVideoView`.
- Broadcast, sub-second and scaled playback, delegate + closure events, `MebiusError`.
