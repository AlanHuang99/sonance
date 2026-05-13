# Milestone 4 — FavoritesView in-place updates

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Views/FavoritesView.swift` | +30 / -17 | Replace `getStarred2`-on-toggle with in-place reconciliation; delete the dead `favoritesSync` stub. |
| `README.md` | +4 / -2 | Note that toggles no longer refetch. |

## Acceptance criteria

- [x] **Toggle 10 hearts on the Favorites view. Network shows 10 star/unstar calls, NOT 10
      `getStarred2` calls.** The two `.onChange(of: favorites.songIDs/albumIDs) { Task { await
      load(refresh: true) } }` modifiers are gone. The replacement `reconcileSongs/Albums/
      Artists` modifiers run synchronously on the main actor and never touch the network. The
      only network calls a toggle issues now are `star` / `unstar`, which `FavoritesStore`
      already issues from `toggleSong/Album/Artist`.
- [x] **The view still updates correctly on every toggle.** `FavoritesStore.songIDs/albumIDs/
      artistIDs` are `@Published`. The reconcile filters return new arrays and reassign the
      `data` `@State`. SwiftUI re-renders the tab content; the heart icons in `TrackRow`
      continue to react via `favorites.isSongFavorite(_:)`.
- [x] **No flicker on toggle.** The optimistic update in `FavoritesStore.toggleSong` flips the
      ID set the moment the user clicks, so the heart icon and the reconcile-driven list
      removal happen in the same render pass. No spinner appears (`isLoading` is unchanged by
      the reconcile path).

## Implementation notes

1. **Mirror-by-IDs.** A toggle in `FavoritesStore` updates one `Set<String>`. The view
   observes that set and rebuilds the matching `[Song]` / `[Album]` / `[Artist]` in `data`
   by filtering against the set. New stars added from other views (e.g. an `AlbumDetailView`
   heart) do **not** appear in the locally-loaded `Starred2Container` until a manual refresh
   — they cannot, because the store does not carry the full object, only the ID. Unstars
   propagate immediately because removal is well-defined from the ID alone.
2. **Avoids re-fetch storms.** The previous `.onChange(...) { Task { await load(refresh: true) } }`
   fired on every keystroke-equivalent change to the ID set, leading to one full
   `getStarred2` per toggle (and additional ones if the ID set transiently changed during
   rollback on a network failure).
3. **Dead-code removal.** `favoritesSync(_:)` was a stub that did nothing other than discard
   its argument; it has been deleted. The "Refresh" button continues to call `load(refresh:
   true)` for an explicit full reload.
4. **No struct mutation gymnastics.** `Starred2Container`'s `let` properties are immutable in
   place, so each reconcile constructs a fresh container via the memberwise initialiser.
   Cheap — these are arrays of optional structs holding mostly-IDs.

## Build / test

```sh
xcodebuild -project Sonance.xcodeproj -scheme Sonance -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Result: `** BUILD SUCCEEDED **`. All 12 tests still pass. No new warnings.

## Unverifiable criteria (this run)

- "Network panel (use Charles or just log in `SubsonicClient.get`) shows 10 star/unstar calls,
  NOT 10 `getStarred2` calls." `SubsonicClient.get`'s existing `NetworkDiagnostics.record(endpoint)`
  call already makes this observable in `os_log` and via `NetworkDiagnostics.snapshot()`, so a
  developer running the app can confirm. From this run we have the static guarantee: the
  modifiers that used to trigger `getStarred2` are deleted, and no other code path on the
  toggle calls `library.starred(...)` or `client.starred()`.

## Deviations from the spec

- The spec phrase "append/remove the matching song/album" cannot literally append a *new*
  star from outside FavoritesView without retaining the full `Song`/`Album` object somewhere.
  `FavoritesStore.toggleSong` only sees the ID. The implementation interprets the spec as
  "remove on unstar, refresh-button or natural re-entry to the tab for additions from
  elsewhere"; in-view additions are not possible because the entry doesn't exist in `data`
  until the next refresh.

## Screenshot

No interactive screenshot from this non-interactive session.
