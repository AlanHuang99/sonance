# Milestone 2 — System Now Playing integration

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Playback/NowPlayingCenter.swift` | +131 / 0 | New `@MainActor` singleton that bridges `Player` to `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`. |
| `Sonance/Playback/Player.swift` | +20 / -2 | Hook `init`/`playCurrent`/`togglePlayPause`/`seek`/`stop`/`restorePaused` to `NowPlayingCenter`; push the duration when the asset reports it. |
| `README.md` | +9 / 0 | Documents the new system integration. |

## Acceptance criteria

- [x] **macOS Control Center → Now Playing shows current Sonance track, artist, artwork.**
      `update(song:isPlaying:elapsed:duration:client:)` writes `MPMediaItemPropertyTitle`,
      `MPMediaItemPropertyArtist`, `MPMediaItemPropertyAlbumTitle`,
      `MPMediaItemPropertyPlaybackDuration`, `MPNowPlayingInfoPropertyElapsedPlaybackTime`,
      `MPNowPlayingInfoPropertyPlaybackRate`, and `MPNowPlayingInfoPropertyMediaType =
      MPNowPlayingInfoMediaType.audio.rawValue`. Artwork is loaded async via `CoverArtCache`
      (size 600) and pushed as an `MPMediaItemArtwork`. _Live screen-capture of Control Center
      is **not performed** — see Unverifiable below._
- [x] **Pressing F8 (or the play/pause key) toggles playback.** `MPRemoteCommandCenter.shared()
      .togglePlayPauseCommand` calls `player.togglePlayPause()`. The system delivers media-key
      events to the active audio app once `MPNowPlayingInfoCenter` has been populated. _Live
      keypress verification is **not performed** — see Unverifiable below._
- [~] **AirPods double-tap advances tracks.** `nextTrackCommand` is wired to `player.next()`.
      Whether AirPods are paired or available cannot be tested from this environment, so the
      criterion is _architecturally satisfied_ but not _empirically_ verified. The spec
      explicitly says to document such gaps.
- [x] **Scrubbing in Control Center actually scrubs the song.**
      `changePlaybackPositionCommand` calls `player.seek(to:)`; `seek(to:)` now also publishes
      the new elapsed time + rate as a fresh anchor to `MPNowPlayingInfoCenter` so the system
      UI does not snap back to the old position before resuming.
- [x] **When nothing is playing, Control Center hides Sonance.**
      `Player.stop()` now calls `NowPlayingCenter.shared.clear()`, which sets
      `nowPlayingInfo = nil` and `playbackState = .stopped`. (macOS auto-hides the Now Playing
      widget when there is no active audio app.)
- [x] **No retain cycles when playing 10 tracks back-to-back.** Argued from the architecture:
      - `NowPlayingCenter` holds a `weak var player: Player?` — does not retain the player.
      - All `MPRemoteCommandCenter` closures capture `[weak self]`.
      - Per-track artwork is loaded via a single `artworkTask` member that is cancelled before
        the next load begins, and only one closure (`Task { [weak self] in ... }`) captures
        `self` weakly.
      - The `Player`'s pre-existing periodic time observer remains the only persistent
        AVPlayer callback, and it is removed in `deinit`.
      _Live `leaks` / Allocations Instrument trace is **not performed** — see Unverifiable below._

## Implementation notes

1. **Singleton + weak Player back-ref.** `NowPlayingCenter.shared` is `@MainActor` and stores
   `weak var player: Player?`. Player's init calls `attach(player: self)`, which idempotently
   registers the remote commands. Only one `Player` exists per app lifecycle (`@StateObject` in
   `SonanceApp`), but the weak ref still avoids any chance of a leak loop.
2. **Anchor model.** Apple's docs say that `MPNowPlayingInfoCenter` extrapolates elapsed time
   from the published `MPNowPlayingInfoPropertyElapsedPlaybackTime` plus the published
   `MPNowPlayingInfoPropertyPlaybackRate`. The bridge therefore only pushes a new anchor at the
   moments where the elapsed/rate model would otherwise drift: `play`, `pause`, `seek`, track
   change. It does **not** push every periodic-time tick.
3. **Duration backfill.** Initial publish uses `song.duration` from the model (may be `0` if the
   server omits it). When the AVPlayerItem reports a real duration on the periodic observer,
   `syncNowPlaying()` re-pushes the full payload. The duration update is gated by
   `abs(d - self.duration) > 0.1` to avoid unnecessary pushes.
4. **Artwork dedup.** `publishedArtworkKey` and `artworkLoadingKey` together prevent re-fetching
   the same bitmap on pause/seek within the same track, and prevent multiple in-flight artwork
   loads for the same key.
5. **No new entitlements.** `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter` work without
   special entitlements in a sandboxed macOS app once the app has played audio. No edits to
   `project.yml`, `Sonance.entitlements`, or `Info.plist` were made (per spec rule 9).

## Build / test

```sh
xcodegen generate
xcodebuild -project Sonance.xcodeproj -scheme Sonance -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Result: `** BUILD SUCCEEDED **`. No new warnings. All 12 pre-existing tests still pass.

## Unverifiable criteria (this run)

Most of M2's acceptance criteria are sensory (visual Control Center, audible media-key
response, physical AirPods tap). They are **architecturally satisfied** by the wiring above,
but the literal "press F8 and see playback toggle" check requires a human at a Mac with the
app running, and is not performed.

- Live macOS Control Center → Now Playing screenshot.
- Live F8 / play-pause key keypress.
- AirPods double-tap (no AirPods in this environment).
- Live Control Center scrubbing.
- `leaks` / Allocations trace over 10 back-to-back tracks.

## Deviations from the spec

- The spec says "verify by playing 10 tracks back-to-back and checking memory doesn't climb
  monotonically." That is a live-app check; the static-analysis argument above is the closest
  this run can get without an interactive session.

## Screenshot

Same caveat as M1 — interactive `screencapture` is not performed from this non-interactive
session. The Sonance window's visible UI is unchanged by M2; the new surface lives in macOS's
own Control Center, not in the app window.
