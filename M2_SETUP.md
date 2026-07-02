# Milestone 2 — Xcode setup (one-time)

The M2 code is written, but LiveKit is a Swift package that must be added in Xcode,
and a few Info.plist/capability keys must be set. Do these once.

## 1. Add the LiveKit package
Xcode → **File → Add Package Dependencies…** → paste:
```
https://github.com/livekit/client-sdk-swift.git
```
Dependency Rule: **Up to Next Major**, from `2.0.0`. Click **Add Package**.
When prompted to choose targets for the **LiveKit** library product, add it to **BOTH**:
- `TeslaStream2` (the app)
- `BroadcastExtension`

(It pulls a prebuilt WebRTC binary — the first resolve can take a minute.)

## 2. App target Info keys
Select the **TeslaStream2** target → **Info** tab → add these rows (Key = Value):
- `RTCAppGroupIdentifier` = `group.com.zekeyeagar.teslastream`
- `RTCScreenSharingExtension` = `com.zekeyeagar.TeslaStream2.BroadcastExtension`
- `Privacy - Microphone Usage Description` = `CarCast plays your screen's audio on your Tesla.`

## 3. App target Background Mode (critical)
Target **TeslaStream2** → **Signing & Capabilities** → **+ Capability** → **Background Modes**
→ check **Audio, AirPlay, and Picture in Picture**.

> Why: with LiveKit the *app* (not the extension) publishes, so it must keep running
> while you're in another app (YouTube). The audio background mode + LiveKit's audio
> session keep it alive.

## 4. Already done in code (no action)
- `BroadcastExtension/Info.plist` already has `RTCAppGroupIdentifier`.
- Both targets already have the App Groups capability (`group.com.zekeyeagar.teslastream`).
- `SampleHandler` subclasses `LKSampleHandler`; the app connects the room in `StreamingView`.

## 5. Point at your server + deploy
- Set `domain` in `TeslaStream2/Config.swift` to your deployed domain (M2 needs a real
  VPS + domain — a Cloudflare tunnel can't carry WebRTC). See `deploy/README.md`.
- The app derives `wss://lk.<domain>` for signaling automatically.

## 6. Build & test (plan Verification C first!)
Build to a real iPhone. Start a broadcast, switch to YouTube, and confirm the stream
keeps flowing (this proves background-publish survival). Then open `https://<domain>/watch/<code>`
on a laptop, then the Tesla. Toggle **Compatibility mode** in the app to fall back to
the M1 MJPEG path on older Teslas.

## If a LiveKit symbol doesn't compile
The code targets LiveKit Swift SDK 2.x APIs (`Room`, `RoomOptions`,
`ScreenShareCaptureOptions(useBroadcastExtension:appAudio:)`, `VideoPublishOptions(preferredCodec:)`,
`LKSampleHandler`). If your resolved version renamed something, the fix is usually a
one-line tweak in `LiveKitPublisher.swift` or `BroadcastExtension/SampleHandler.swift` —
check the package's `Docs/ios-screen-sharing.md` for that version.
