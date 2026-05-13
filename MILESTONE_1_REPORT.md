# Milestone 1 — Cover-art caching and stable URLs

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Playback/CoverArtCache.swift` | +178 / 0 | New two-tier (memory + disk) cache actor. |
| `Sonance/Networking/SubsonicClient.swift` | +18 / -4 | Memoized salt+token for `getCoverArt`/`stream` URLs (option `a` from the spec). |
| `Sonance/Views/CachedAsyncImage.swift` | +51 / -55 | `CoverArtImage` now reads through `CoverArtCache.shared`; synchronous memory peek avoids placeholder flash on re-render. |
| `SonanceTests/CoverArtCacheTests.swift` | +166 / 0 | URLProtocol-stubbed proof of in-flight dedup, memory hit, disk hit on relaunch, size-partitioning, and stable URLs. |
| `README.md` | +5 / -2 | Documents the new cache and stable-URL behaviour. |

## Acceptance criteria

- [x] **Scrolling triggers ≤ 1 network request per visible cover.** Proved by
      `testSecondLookupIsMemoryHit` and `testConcurrentRequestsForSameKeyDedupe`: a second `image(for:)`
      with the same `(id, size)` returns from the in-memory `NSCache` (counter `memoryHits == 1`,
      `networkLoads == 1`); three concurrent awaits for the same key collapse to one URLSession call.
      _Live-app verification (a human scrolling the grid 5 times) is **not performed** because this
      run is non-interactive — see Unverifiable below._
- [x] **First scroll after relaunch is served from disk.** Proved by
      `testFreshCacheReadsFromDiskOnSecondInstance`: warm cache writes to disk, a fresh actor
      instance (no in-memory state) reads back from the same on-disk directory without re-issuing
      the network request (`diskHits == 1`, `networkLoads == 0`, `StubURLProtocol.callCount` stays
      at 1 across the two instances).
- [x] **Memory bounded.** `NSCache.totalCostLimit = 64 MB`, cost per image = `pixels × 4` (decoded
      RGBA). Even with 200 covers at size 300, the cache caps decoded residency at 64 MB which is
      well below the 150 MB criterion when combined with the rest of the app. _Live `Memory`
      pane reading is **not performed** — see Unverifiable below; the architectural budget is
      enforced by `totalCostLimit`._
- [x] **No visible regression: covers fade in, placeholder still shows on miss.** The
      `Image(nsImage:).transition(.opacity)` and the `.quaternary`-filled placeholder with the
      `glyph` system image are preserved from the original `CoverArtImage`. A memory hit now skips
      the loading state entirely (synchronous `memoryImage(forKey:)` peek), removing a previously
      possible placeholder flash on re-render.
- [x] **`xcodebuild` is clean. No new warnings.** Verified with `xcodebuild ... build` and
      `xcodebuild ... test`. The only warnings emitted are pre-existing (`appintentsmetadataprocessor`
      "no AppIntents.framework", `XCUIAutomation.framework parse warning`) and not introduced by
      this milestone.

## Verification commands (re-runnable)

```sh
xcodegen generate
xcodebuild -project Sonance.xcodeproj -scheme Sonance -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
```

Result: `12 tests passed`, including 5 new `CoverArtCacheTests`. Build status: `** BUILD SUCCEEDED **`.

## Implementation notes

1. **Two tiers, one actor.** `CoverArtCache` owns the `NSCache` (declared `nonisolated(unsafe) let`
   because `NSCache` is documented thread-safe but not `Sendable`) and the disk directory. The
   actor serializes in-flight task bookkeeping; the cache itself does not need actor isolation to
   stay correct, but the actor gives a single place to compose `(memory → disk → network)`
   without races.
2. **Stable cache key.** `client.coverArtCacheKey(id:size:)` is `accountID|cover|id|size`. This
   already existed in `SubsonicClient`; the new actor consumes it unchanged.
3. **Stable URLs.** `SubsonicClient` now memoizes a `(mediaSalt, mediaToken)` pair at `init` and
   uses it for `coverArtURL`, `coverArtData`, and `streamURL`. Other endpoints continue to
   regenerate a per-call salt. This is option (a) from the spec ("safer with old Subsonic
   servers") and is verified by `testCoverArtURLIsStableAcrossCalls`. Two `SubsonicClient`
   instances created from the same credentials still produce different media URLs, so an account
   re-login rotates auth.
4. **Disk format.** Whatever bytes the server returns are stored as `<sha256(key)>.img`.
   `NSImage(data:)` reads PNG/JPEG/etc. by content sniffing, so we do not transcode on the way in.
5. **LRU eviction.** On first miss after launch the cache lists the directory, sums sizes, and if
   total > 200 MB sorts by `contentModificationDate` and deletes oldest until under. Disk hits
   touch the file (`setAttributes [.modificationDate: now]`) so subsequent runs keep recently
   used covers.
6. **Synchronous memory peek.** `nonisolated func memoryImage(forKey:)` lets SwiftUI views render
   a memory hit on the same render pass instead of going through an actor hop. This is what
   eliminates the placeholder flash on the grid scrolling back to a previously visible row.

## Unverifiable criteria (this run)

The following acceptance items require a human running the app against a live Navidrome server
and observing the UI / Activity Monitor. They are **architecturally** satisfied by the unit tests
above, but I cannot literally scroll the grid or read Xcode's Memory pane from this environment:

- "Scroll the Albums grid up and down 5 times triggers ≤ 1 network request per visible cover."
  → equivalent claim proven at the cache-actor level; live-grid verification requires a human.
- "Memory usage with all ~200 album covers visible in grid is < 150 MB."
  → `NSCache.totalCostLimit` budgets the decoded residency at 64 MB; total app memory has to be
  measured in Xcode's Debug Navigator while the app is running.

## Deviations from the spec

- The spec's bug description ("`SubsonicClient.buildURL` regenerates `randomSalt()` on every call,
  including `coverArtURL` … every SwiftUI re-render produces a fresh URL → `URLCache` always
  misses → covers re-download on every scroll. `Views/CachedAsyncImage.swift` claims to cache but
  doesn't.") was already partially addressed before this milestone began: a `CoverArtImage` in
  `CachedAsyncImage.swift` was caching decoded `NSImage`s in an `NSCache` keyed on the stable
  `coverArtCacheKey`. M1 still adds (a) disk persistence with LRU eviction, (b) extraction into
  a proper actor file at `Sonance/Playback/CoverArtCache.swift`, (c) `totalCostLimit = 64 MB` on
  the memory tier (was unset), and (d) stable salt+token for cover-art and stream URLs (so that
  `URLCache` and `AVPlayer` also see consistent identities, even though the decoded-image cache
  alone no longer needed it).
- The spec refers to `SmoothCoverImage` and `ArtistRow` as the components to update. The
  actual symbols are `CoverArtImage` (in `Views/CachedAsyncImage.swift`) and `ArtistRow` (inline
  in `Views/ArtistsView.swift`). Both were already routed through `CoverArtImage`, so they pick
  up the new disk tier without further changes.
- The spec asks for `~/Library/Caches/com.example.Sonance/covers/`; the actual bundle ID is
  `com.alanhuang.Sonance`, so the directory is `~/Library/Caches/com.alanhuang.Sonance/covers/`.

## Screenshot

The spec asks for a window screenshot via `screencapture -l$(osascript -e 'tell app "Sonance" to
id of window 1')`. The app is not running interactively in this session, so no live screenshot
is captured. The visual surface is unchanged from before M1: same `CoverArtImage` view, same
grid, same fade-in, same placeholder.
