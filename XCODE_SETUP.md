# Xcode setup (one-time)

Three targets: **TeslaStream2** (the app), **BroadcastExtension** (the ReplayKit upload
extension that encodes and sends frames), **BroadcastExtensionSetupUI** (Apple's optional
picker UI). Do these once after cloning.

## 1. Swift package
The project references the LiveKit Swift package
(`https://github.com/livekit/client-sdk-swift.git`, up to next major from `2.15.1`); Xcode
resolves it automatically on first open. It is needed to **compile** the app target
(`LiveKitPublisher.swift`, the dormant WebRTC publisher). The broadcast extension no longer
imports it — the extension is a plain `RPBroadcastSampleHandler` that JPEG-encodes frames and
pushes them over a WebSocket — but the package is still linked to that target; that is
harmless and can be removed from the extension's *Frameworks, Libraries* list if you want a
smaller extension binary.

## 2. App Group (critical)
Both the app and the extension must have the **App Groups** capability with
`group.com.zekeyeagar.teslastream`. The app writes `domain`, `streamKey`, `publishSecret`
and `mode` there (`StreamManager.syncToAppGroup()`); the extension reads them to know where
to connect. If you change the group id, change it in **both** entitlements files, in
`Config.appGroup`, and in the literal in `BroadcastExtension/SampleHandler.swift`.

## 3. App target Info keys
Already in `TeslaStream2/Info.plist`:
- `RTCAppGroupIdentifier` / `RTCScreenSharingExtension` — used only by the dormant LiveKit
  path; harmless to keep.
- `UIBackgroundModes` → `audio`.

The microphone usage string is a **build setting** rather than a plist entry
(`INFOPLIST_KEY_NSMicrophoneUsageDescription` on the app target's Debug and Release
configurations); Xcode merges it into the generated Info.plist.

## 4. Signing
Automatic signing with your team on all three targets. Bundle ids are
`com.zekeyeagar.TeslaStream2`, `.BroadcastExtension`, `.BroadcastExtensionSetupUI`. The
extension's bundle id must stay a child of the app's.

## 5. Point at your relay
Set `domain` in `TeslaStream2/Config.swift` (default `tesycast.com`). The app derives the
watch URL `https://<domain>/watch/<code>`, `POST /mode`, and `GET /status` from it; the
extension derives `wss://<domain>/ingest/<code>?secret=<publishSecret>` (the secret is
mandatory — the relay closes the socket with `4001` without it, `4003` if it is wrong).

## 6. Build & test
Build to a **real iPhone** (ReplayKit does not run in the simulator). Open the streaming
screen, tap the broadcast button and start. Then open `https://<domain>/watch/<code>` on a
laptop — you should see your screen painting frame by frame with a `LIVE` badge — and then
in the Tesla. Switch to another app on the phone: the stream should keep flowing.

A quick way to see frame sizes and rate from a laptop while testing: connect a WebSocket to
`wss://<domain>/view/<code>` and count binary messages (see `worker/test/e2e.mjs` for the
protocol; send `ack` every 4 frames or the relay will hold you at a 4-frame window).
