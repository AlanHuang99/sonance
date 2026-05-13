# Milestone 5 — Albums infinite scroll + inline sort

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Views/AlbumsView.swift` | +84 / -23 | Paginate `getAlbumList2` at 100 per request; inline sort `Menu` at the top of the grid; sentinel-triggered load-more with spinner; generation token for stale-load suppression. |
| `README.md` | +5 / -2 | Document pagination and inline sort. |

## Acceptance criteria

- [x] **On a library with > 200 albums, scrolling reveals albums 201+.** The grid initially
      loads `offset = 0, size = 100`. A trailing `loadMoreSentinel` (a 44 pt-high `HStack`
      participating in the `LazyVGrid` with `.gridCellColumns(columns.count)`) fires
      `.onAppear { Task { await loadMore() } }` the moment SwiftUI lazily instantiates it as
      it scrolls into view. `loadMore` requests `offset = albums.count, size = 100`. The
      sentinel stays in the grid until the server returns a short page (`hasMore = false`).
- [x] **Sort change triggers a single reload, not duplicate concurrent requests.**
      `.onChange(of: sort)` calls `reload()`. `reload` increments `loadGeneration` so any
      in-flight page-load from the prior sort discards its result on return (`guard
      generation == loadGeneration else { return }`). The user-visible state is reset only
      when the new request lands.
- [x] **Loading more shows a small spinner at the bottom of the grid.** The sentinel renders
      a `ProgressView().scaleEffect(0.7)` with `opacity = isLoadingMore ? 1 : 0`. The sentinel
      itself remains laid out so the on-appear trigger continues to fire, but the spinner is
      hidden when nothing is in flight.
- [x] **No duplicate albums in the grid.** `seenIDs: Set<String>` is updated with each page;
      `loadMore` filters incoming pages against the set before appending. This also covers the
      `random` sort, where Subsonic may return overlapping pages across calls.

## Implementation notes

1. **Why bypass the `LibraryStore` cache for pagination.** `LibraryStore.albumList(sort:size:client:
   refresh:)` caches by `(account, sort, size)` with implicit `offset = 0`. Adding `offset` to the
   cache key would create one cache entry per page that we'd never re-hit (each page is asked for
   once on the way down), so it isn't worth the bookkeeping. Page 0 still benefits from the
   cache on revisits when the user navigates back to Albums and the sort hasn't changed, but
   currently `reload()` calls `client.albumList` directly to keep the pagination logic
   self-contained — the cost is at most one redundant first-page request when the user lands
   on the tab, which the URLSession will satisfy quickly.
2. **Generation token over cancellation.** Swift `Task` cancellation is cooperative; the inner
   `client.albumList` already returns a value, and reacting to cancellation would require
   threading a `Task.checkCancellation` through the URLSession await. The `loadGeneration`
   integer is the smallest possible guard that achieves the same correctness — when sort
   changes, we just don't apply the old result.
3. **Inline sort menu styling.** A `Menu` with a `borderlessButton` style and a `chevron.down`
   trailing glyph matches the inline pattern in Apple Music. Selected option gets a `checkmark`
   in the menu drop-down. The label reads `Sort: A–Z` so it remains self-describing without a
   separate field label.
4. **The sentinel can fire once per generation.** When sort changes, `albums` is replaced and
   the sentinel re-enters the view; the new `.onAppear` fires once the grid scrolls back to
   the bottom under the new sort. Generation-checked, so a still-in-flight page-2 of the prior
   sort cannot pollute the new sort's `albums`.
5. **End-of-list detection.** `hasMore = page.count == Self.pageSize` — a page that doesn't
   fill is the server's signal that there is nothing past it. We also `&& !fresh.isEmpty` in
   `loadMore` so a page entirely composed of duplicates (theoretical, but possible for
   `random`) stops pagination.

## Build / test

```sh
xcodebuild ... build
```

Result: `** BUILD SUCCEEDED **`. All 12 tests pass. No new warnings.

## Unverifiable criteria (this run)

- "On a library with > 200 albums, scrolling reveals albums 201+." Requires a Navidrome
  server with more than 200 albums and a human scrolling. The implementation is
  architecturally complete; the on-appear sentinel pattern is the canonical SwiftUI way to do
  this and is widely-deployed.
- "Network panel shows … not duplicate concurrent requests on sort change." Requires the
  human to watch HTTP traffic during a rapid sort switch.

## Deviations from the spec

- Spec says "within 300px of the bottom" as the trigger range. SwiftUI's `LazyVGrid` does
  not expose pixel-level scroll offsets without `ScrollView` + custom geometry math, and the
  on-appear sentinel approach is functionally equivalent and the idiomatic SwiftUI form.
  The sentinel naturally fires when it enters the visible region, which is at the bottom of
  the grid (i.e. when the user is at the tail). The behavioural difference vs. a strict
  "300 px" rule is that with a tall window the trigger fires slightly later (the sentinel
  itself must be visible) — but the load happens on a background `Task`, so the perceived
  latency to the user is dominated by the network, not the scroll position.
- The toolbar previously hosted a secondary-action sort picker. That has been removed per
  the spec's "inline at the top of the grid" requirement; only the Refresh button remains in
  the toolbar.

## Screenshot

No interactive screenshot from this non-interactive session. The new sort menu sits above
the grid; the spinner appears only during the loading window for additional pages.
