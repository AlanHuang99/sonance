# Milestone 3 — Gapless playback via AVQueuePlayer

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Playback/Player.swift` | +63 / -22 | Switch `AVPlayer` → `AVQueuePlayer`; preload next item within 10 s of end; invalidate preload on queue/repeat/shuffle mutations; rebuild current item on repeat-one. |
| `README.md` | +4 / -1 | Document the gapless behaviour. |

## Acceptance criteria

- [x] **Play two known back-to-back tracks. The transition is silent.** Implemented by
      `preloadNextIfNeeded()` (invoked from the periodic time observer when
      `duration - currentTime ≤ 10`). The next `AVPlayerItem` is built from
      `client.streamURL(id:)` and inserted via `AVQueuePlayer.insert(_:after: currentItem)`.
      When the current item plays to end, `AVQueuePlayer` advances to the preloaded item with
      no asset-load latency. The model catches up in `handleTrackEnd`: `queueIndex = nextIdx`,
      `currentSong = queue[nextIdx]`, the end observer is rebound, scrobble fires, and Now
      Playing is re-synced. _Live audible verification is **not performed** — see
      Unverifiable below._
- [x] **`next()` from the middle of a track switches immediately.** `next()` calls
      `advanceOrStop()` → `playCurrent()`, which clears the preload, calls
      `avPlayer.removeAllItems()`, then `insert(item, after: nil)` and `play()`. The asset
      load latency is sub-second (`AVPlayerItem` over HTTP starts streaming on first read).
- [x] **Skipping rapidly (`next` 5 times in 1 second) doesn't crash or leak observers.**
      Every call path that re-arms the current item runs through `installEndObserver(for:)`,
      which first removes the previous observer with
      `NotificationCenter.default.removeObserver(endObserver)`. `clearPreload()` also removes
      the preloaded item from `AVQueuePlayer`'s queue before re-inserting. There is at most
      one end observer in flight at any time.
- [x] **Scrobbling still fires correctly per track.** `playCurrent` resets
      `hasScrobbledCurrent = false` and detaches a now-playing scrobble. The gapless transition
      branch in `handleTrackEnd` resets `hasScrobbledCurrent = false` and detaches a fresh
      now-playing scrobble. The submission scrobble at 50 % continues to fire from the periodic
      observer, gated by `hasScrobbledCurrent`.
- [x] **Repeat-one / repeat-all / shuffle still work.**
      - Repeat-one: `preloadNextIfNeeded` returns early; on end, `handleTrackEnd` calls
        `playCurrent()` which reloads the same `queueIndex`. (Plain `seek(to: .zero)` is not
        used because `AVQueuePlayer` pops the played-to-end item out of its queue, leaving
        `currentItem` nil.)
      - Repeat-all: `PlaybackQueueLogic.nextIndex(...)` wraps to 0 when at the end of the
        queue, so the preload is the first track; the gapless transition runs the same code
        path as a normal advance.
      - Shuffle: `toggleShuffle` calls `clearPreload()` so a stale "next" cannot survive a
        reorder; the next periodic tick re-preloads the right item against the shuffled queue.

## Implementation notes

1. **Why `AVQueuePlayer` is enough.** The spec asks for an internal queue of 1–2 items
   (current + next). `AVQueuePlayer` is exactly that primitive; we keep our own `[Song]`
   model for the user-facing queue and only mirror the immediate next item into the AV-level
   queue. The "deep" queue model in `PlaybackQueueLogic` is unchanged.
2. **Cache invalidation.** Any state change that could rename what "next" is calls
   `clearPreload()` so the next periodic tick rebuilds:
   - Queue mutations: `playNext`, `appendToQueue`, `removeFromQueue`, `moveQueueItem`,
     `clearQueue`.
   - Mode changes: `cycleRepeat`, `toggleShuffle`.
   - Reset paths: `playCurrent`, `stop`.
3. **Repeat-one without holes.** `AVQueuePlayer` removes a played-to-end item from its
   `items()`, so a naive `seek(to: .zero)` against the played-to-end item leaves a nil
   `currentItem`. The fix is to call `playCurrent()` on the same `queueIndex` and rebuild a
   fresh `AVPlayerItem`. This costs the user a small (sub-second) reload at the loop seam —
   the cost the spec criterion accepts ("Repeat-one still works") in exchange for
   correctness.
4. **End-observer hygiene.** Pulling `installEndObserver(for:)` out of `playCurrent` keeps a
   single place that removes the prior observer before adding the new one. `stop()` also
   explicitly removes it, matching the prior behaviour.
5. **`stop()` cleanup.** Switched from `replaceCurrentItem(with: nil)` to `removeAllItems()`
   plus an explicit end-observer removal. Mirrors `AVQueuePlayer` semantics and prevents
   leaks when the user closes the queue mid-track.

## Build / test

```sh
xcodebuild -project Sonance.xcodeproj -scheme Sonance -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
```

Result: `** BUILD SUCCEEDED **`, all 12 tests pass. No new warnings.

## Unverifiable criteria (this run)

- The gold-standard test of gapless playback is human listening to a known seamless album
  (Dark Side of the Moon track 4 → 5, classical recordings, live recordings). The implementation
  satisfies the architectural condition (preloaded `AVPlayerItem` inserted at least 10 s before
  the boundary; `AVQueuePlayer` advances atomically), but no audio-level proof is captured
  from this non-interactive session.
- "Skip 5 times in 1 second doesn't crash or leak observers" — the leak claim is argued from
  the source (every transition path removes the prior observer before adding a new one), but
  a live Instruments leaks trace is not run.

## Deviations from the spec

- Repeat-one is **not** gapless (it re-creates the `AVPlayerItem`). The spec criterion is
  "Repeat-one still works", which is met; gapless looping would require a different player
  topology (e.g. `AVPlayerLooper`) that is not warranted for this milestone.
- The spec calls for "Maintain the current queue model on top — the AVQueuePlayer's internal
  queue is just 1–2 items deep (current + next), not the full user queue." This is honored:
  `avPlayer.items().count` is at most 2 in steady state (current + preloaded), and is 0 or 1
  outside the 10 s preload window.

## Screenshot

No interactive screenshot from this non-interactive session. UI is unchanged by M3.
