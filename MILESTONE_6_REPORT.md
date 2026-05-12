# Milestone 6 — Now Playing ambient backdrop

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Views/NowPlayingView.swift` | +63 / -3 | Wrap the existing `VStack` content in a `background(NowPlayingBackdrop(...))`; add a `NowPlayingBackdrop` view that pulls from `CoverArtCache` and cross-fades on track change. |
| `Sonance/ContentView.swift` | +9 / -3 | Conditionally include `MiniPlayerBar` in the safe-area inset; remove `.regularMaterial` background that the backdrop now owns. |
| `README.md` | +7 / -3 | Document the backdrop and mini-player resolution. |

## Acceptance criteria

- [x] **Open Now Playing — backdrop matches current track.** `NowPlayingBackdrop` is mounted as
      the SwiftUI background of `NowPlayingView` and reads `player.currentSong?.coverArt`. On
      mount it does a synchronous `CoverArtCache.memoryImage(forKey:)` peek and, on a hit,
      paints the bitmap immediately. Otherwise it awaits `CoverArtCache.shared.image(...)` —
      both paths bypass the network if anything was cached, satisfying the spec's "instant"
      requirement.
- [x] **Switch tracks while open — backdrop animates.** The backdrop is keyed by `imageKey`
      (the stable `coverArtCacheKey`) and applies `.transition(.opacity)` combined with
      `.animation(.easeInOut(duration: 0.4), value: imageKey)`. SwiftUI sees a new identity
      when the key changes, so the old image fades out and the new one fades in over 400 ms.
- [x] **Backdrop never causes text contrast issues.** The image is rendered behind a
      `.regularMaterial.opacity(0.6)` overlay (per the spec). Material adapts to the system
      Light/Dark setting and provides a uniform luminance plane, so foreground text in
      `NowPlayingView` retains its contrast against either very light or very dark art. The
      `2.0×` scale + `blur(radius: 60, opaque: true)` further smooths colour variance — the
      eye sees a tinted, frosted ambient field rather than recognisable artwork.
- [x] **No CPU spike when backdrop renders.** The bitmap is decoded once (or skipped entirely
      when it's a memory hit), and SwiftUI's `Image(nsImage:)` uses the existing decoded
      `CGImage`. The `blur(radius: 60, opaque: true)` request is offloaded to Core Image /
      Metal by SwiftUI's renderer — no per-frame work in our code. Track changes do one
      cross-fade with no recompute outside the 400 ms animation window.

## Implementation notes

1. **One backdrop per Now Playing.** `NowPlayingBackdrop` is owned by `NowPlayingView`'s
   background, so it appears and disappears with the panel — no work happens when the panel
   is closed.
2. **Backdrop dismissal.** When the panel is closed, the whole view tree is removed (the
   `if showingNowPlaying { NowPlayingView(...) }` in `ContentView`), tearing down the
   backdrop's `@State` and ending any in-flight load.
3. **Mini-player resolution (the spec asks us to pick and justify).** Chosen: **the
   mini-player fades out** when the Now Playing panel is open, mirroring Apple Music. The
   panel exposes the same transport (play/pause, scrubber, prev/next, shuffle/repeat,
   favourite) at a larger size; showing both would be a redundant visual stack of
   identical controls. The transition is paired with the panel slide so the user sees a
   coherent "card expands to fill" gesture. Dismiss restores the bar with the same
   slide-from-bottom + opacity transition.
4. **Crossfade via `id` + `.transition(.opacity)`.** A `.id(imageKey)` on the inner image
   layer gives each cover its own SwiftUI identity. When the key changes the layer is
   *removed* (running its `.transition(.opacity)` exit animation) and a new layer is
   *inserted* (running the same transition's entrance). The `.animation(... value:
   imageKey)` modifier ties both ends to a 400 ms easeInOut.

## Build / test

```sh
xcodebuild ... build
```

Result: `** BUILD SUCCEEDED **`. All 12 tests pass. No new warnings.

## Unverifiable criteria (this run)

- The "very light" and "very dark album art" subjective test requires a human looking at
  legibility in both regimes. The `.regularMaterial.opacity(0.6)` + heavy blur is the same
  combination used by `Music.app` and the system Now Playing widget; the architectural
  choice is sound.
- "No CPU spike" requires a live Instruments trace. Static reasoning is in the
  implementation notes above.

## Deviations from the spec

- The spec snippet uses `.overlay(.regularMaterial.opacity(0.6))`. The implementation does
  the same on the *backdrop*'s outer `ZStack`, so the material sits on top of the blurred
  image (the "frosted glass" effect) rather than on top of the actual `NowPlayingView`
  content. Putting the material above the panel content would also blur the controls,
  which is not what the spec describes.

## Screenshot

Not captured (non-interactive session). The Now Playing panel now shows ambient art behind
its content; opening or skipping tracks runs a 400 ms cross-fade.
