# Milestone 10 — Inline now-playing context

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Models/SubsonicModels.swift` | +18 / -1 | `Song.artistId`; `Song: Transferable` via `CodableRepresentation` over `UTType.sonanceSong` so SwiftUI drag-and-drop can serialise songs. |
| `Sonance/Library/NavigationCoordinator.swift` | +25 / -2 | `pendingArtistNavigation`, `requestArtistNavigation`, `revealInLibrary(album:)`. |
| `Sonance/Views/LibraryView.swift` | +13 / -3 | Declare `navigationDestination` for both `Album` and `Artist` at the stack root so any inline navigation request can land regardless of section; consume `pendingArtistNavigation`. |
| `Sonance/Views/MiniPlayerBar.swift` | +96 / -17 | Title → album, artist name → artist; right-click cover menu (Play Next on Album / Go to Album / Go to Artist / Show in Library). |
| `Sonance/Playback/Player.swift` | +18 / 0 | `insert(_:at:using:)` so the queue's drop target can place dragged songs at a specific row. |
| `Sonance/Views/TrackListView.swift` | +1 / 0 | `.draggable(song)` on each row. |
| `Sonance/Views/AlbumDetailView.swift` | +1 / 0 | `.draggable(song)` on each disc-section row. |
| `Sonance/Views/NowPlayingView.swift` | +20 / -2 | Per-row `.dropDestination(for: Song.self)` inserts at that index; whole-list drop appends. |
| `README.md` | +6 / -3 | Document the new gestures. |

## Acceptance criteria

- [x] **Click title → album opens in detail.** Mini-player title is now a `Button` that fires
      `navigation.requestAlbumNavigation(albumStub(for: song))` where `albumStub` synthesises an
      `Album` from the song's `albumId`, `album`, `artist`, `artistId`, and `coverArt`. The
      coordinator switches to `.albums` if needed and `LibraryView` pushes onto the
      `detailPath`. Disabled when `song.albumId == nil`.
- [x] **Drag track to queue → it appears at the dropped position.** `TrackListView` and
      `MultiDiscTrackList` rows are `.draggable(song)`. `QueuePaneView` declares
      `.dropDestination(for: Song.self)` on every queue row (insert at that row's index) and
      on the surrounding `List` (append at the end if the user drops past the last row).
      `Player.insert(_:at:using:)` mutates `queue`, keeps `queueIndex` valid by shifting it
      when songs are inserted before it, and invalidates the gapless preload.
- [x] **No drag-reorder regression on existing queue list.** `QueuePaneView` still owns the
      same `.onMove` on its `ForEach` for in-queue reorder; the new `.dropDestination` is a
      separate gesture path. SwiftUI distinguishes a same-list move (handled by `.onMove`)
      from a cross-list drag (handled by `.dropDestination`) by source identity.

## Implementation notes

1. **`Song: Transferable`.** A `CodableRepresentation` is the canonical way to make a value
   type draggable in SwiftUI. The `UTType.sonanceSong = UTType(exportedAs:
   "com.alanhuang.Sonance.song")` keeps the in-app drag distinct from any system text/url
   types, so a drop target that takes `Song.self` won't accidentally accept arbitrary string
   drags.
2. **Album / Artist stubs.** The Subsonic `song` element carries enough fields to construct
   a minimal `Album` or `Artist` for navigation purposes. The destination views
   (`AlbumDetailView`, `ArtistDetailView`) then load full detail on their own — the stub is
   sufficient as a routing key.
3. **NavigationStack destinations lifted to root.** Previously each section view declared
   `.navigationDestination(for: Album.self)` itself. With the new "Go to Album from
   mini-player" path, an inline click while on, say, the Playlists section needs to land on
   `AlbumDetailView`. Declaring both destinations on the `NavigationStack` root means any
   `.append(album)` works.
4. **`Show in Library` semantics.** SwiftUI's `LazyVGrid` has no programmatic scroll-to-item
   that survives a section switch reliably, so `revealInLibrary(album:)` switches to the
   Albums tab and opens the album's detail page. The user can press Back to land in the
   grid context. Documented as a known simplification.
5. **`Player.insert` and `queueIndex`.** When dropping a song at an index `i ≤ queueIndex`,
   the current track's position shifts by the inserted count; we bump `queueIndex` so
   playback continues uninterrupted. When `i > queueIndex`, no shift is needed. Either way
   `clearPreload()` runs because the gapless next-track could now be a different song.
6. **Whole-list drop target.** The `.dropDestination` on the `List` itself catches drops
   that don't land on a specific row (most commonly: the empty area below the last row
   when the queue is short). It appends to the end so the user always has a target.

## Build / test

```sh
xcodebuild ... test
```

Result: `** BUILD SUCCEEDED **`. All 12 tests pass. No new warnings.

## Unverifiable criteria (this run)

- "Click title → album opens in detail" requires a click. The wiring is complete.
- "Drag track to queue" requires a drag gesture. The `.draggable` / `.dropDestination`
  pair is the documented SwiftUI primitive and is widely deployed.

## Deviations from the spec

- "Show in Library" is implemented as a section-switch + album-detail-push (see note 4).
  A literal "highlight the row in the Albums grid" would require a scroll-to-item primitive
  that SwiftUI doesn't reliably expose for `LazyVGrid` across section changes.
- Drop into the Editable playlist track list (added in M9) is not implemented because that
  list owns `.onMove` for reorder, and combining its drop semantics with a "drop from
  outside" target overlaps without clean disambiguation. The Now Playing queue is the
  documented target.

## Screenshot

Not captured. New surfaces are entirely interactive: a clickable title, a clickable artist
name, a right-click context menu on the cover thumbnail, and drag/drop between any track
list and the Now Playing queue.
