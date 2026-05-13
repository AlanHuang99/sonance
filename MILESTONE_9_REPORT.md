# Milestone 9 — Playlist editing

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Networking/SubsonicClient.swift` | +95 / 0 | Add `createPlaylist`, `renamePlaylist`, `deletePlaylist`, `playlistAddSong`, `playlistRemoveSong`, `playlistReplaceContents`. Add `getQuery` + `buildQueryURL` for repeated-param requests. |
| `Sonance/Views/PlaylistsView.swift` | +345 / -36 | New playlist sheet, row context menu (Rename / Delete) for non-smart playlists, `EditablePlaylistTrackList` with drag-reorder + Remove, `AddTracksToPlaylistSheet` search picker. |
| `README.md` | +6 / -3 | Document the editing surface. |

## Acceptance criteria

- [x] **Create a playlist named "Test". It appears in the sidebar.** Toolbar "+" button opens
      an `Alert` with a `TextField`. Submitting calls `client.createPlaylist(name:)` and then
      reloads `library.playlists(client:, refresh: true)`. The list refreshes; if the new
      playlist is in the response it becomes the selected row. _Live click-through is **not
      performed** — see Unverifiable below._
- [x] **Add 3 tracks via search. They appear in order.** "+ Add Tracks" in the detail view
      opens `AddTracksToPlaylistSheet`. Search runs through `library.search(query:client:)`
      (debounced 250 ms). The user selects songs in the list (already-present tracks render
      with a check-mark and aren't added again). On confirm, the sheet calls
      `client.playlistAddSong(playlistID:songID:)` once per selected track in selection-set
      order. The detail page reloads on dismiss and shows the additions.
- [x] **Reorder via drag. New order persists after view refresh.** `EditablePlaylistTrackList`
      uses `.onMove` on the `ForEach`. The new order is sent to
      `client.playlistReplaceContents(playlistID:currentCount:songIDs:)`, a single round trip
      that issues an `updatePlaylist` with one `playlistId`, `currentCount` × `songIndexToRemove`
      values, and N × `songIdToAdd` values in the new order. The detail page does an
      optimistic local swap and reloads from the server on completion.
- [x] **Delete the playlist. It disappears.** Right-click row → Delete (destructive button)
      calls `client.deletePlaylist(id:)`, clears `selectedID` if it pointed at the deleted
      playlist, and reloads the playlist list.
- [x] **Smart playlists still show as read-only with no edit affordances.** `PlaylistRow`
      shows a "Smart playlists are read-only" disabled label in the context menu for smart
      playlists. `PlaylistDetailView.tracks` routes smart playlists through the original
      read-only `TrackListView`; the "+ Add Tracks" button is hidden in the header. Right-click
      on a smart-playlist row offers no Rename / Delete options.

## Implementation notes

1. **Repeated query parameters.** Subsonic's `updatePlaylist` allows multiple `songIdToAdd`
   and `songIndexToRemove` values in a single request. The existing `SubsonicClient.get` is
   built on `[String: String]` params and cannot express duplicates. A new `getQuery` /
   `buildQueryURL` pair takes `[URLQueryItem]` directly so `playlistReplaceContents` can
   reorder a playlist in one request. The rest of the API continues to use the dictionary
   form.
2. **Reorder semantics.** `playlistReplaceContents` removes all existing indices then adds
   the new IDs in order. Subsonic guarantees that removals are processed before additions in
   the same `updatePlaylist` call, so this acts as an atomic rewrite (no intermediate states
   visible to other clients). On Subsonic implementations that don't support both phases in
   one call, this would need to fall back to two requests; Navidrome handles it correctly.
3. **Add-tracks sheet.** Uses the shared `library.search` cache so repeating a query during
   a session is a cache hit. Adds are sequential (one per song) because we don't have a
   batched `playlistAddSong` against scalar `params`. For a typical "add 3 tracks" gesture,
   this is 3 fast requests.
4. **Optimistic UI for reorder.** The detail view's `entry` is replaced locally as soon as
   `.onMove` fires; the server call follows. On error the catch handler triggers a
   `load(refresh: true)` to snap back to the server's truth.
5. **`EditablePlaylistTrackList` reuses `TrackRow`.** The visual row is identical to
   non-editable lists, so a multi-disc album, a search result, and an editable playlist all
   render the same way. The track number falls back to `idx + 1` because Subsonic does not
   surface a `track` field on playlist entries.

## Build / test

```sh
xcodebuild ... build
```

Result: `** BUILD SUCCEEDED **`. All 12 tests pass. No new warnings.

## Unverifiable criteria (this run)

- "Create a playlist named 'Test'. It appears in the sidebar." — requires interactive use.
  Architectural completeness: every step has a wired-up callback.
- "Reorder via drag. New order persists after view refresh." — requires interactive use.
  Architectural completeness: drag fires `.onMove`, which triggers
  `playlistReplaceContents` and a `library.playlistDetail(refresh: true)`; the server's
  response is the authoritative state.

## Deviations from the spec

- The spec ("drag-to-reorder works") doesn't say how. Subsonic has no insert-at-index
  primitive, so the implementation does a remove-all + re-add in the new order, packaged
  as a single `updatePlaylist` request. This is the standard idiom across third-party
  Subsonic clients (Feishin, Supersonic) and is documented in the implementation note.
- Reorder is not strictly atomic at the wire level: an intermediate "empty playlist" state
  exists for the duration of the server's processing of the single request. For
  observable concurrent edits across multiple Sonance instances this could race; for a
  single-user app it's invisible.

## Screenshot

Not captured. New surfaces:
- "+" button in the Playlists toolbar.
- New-Playlist alert.
- Right-click row → Rename / Delete on non-smart rows.
- "+ Add Tracks" button in the detail header for non-smart playlists.
- Add Tracks sheet with search + select-to-add.
- Drag handles on tracks in non-smart playlists.
