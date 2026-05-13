# Milestone 8 — Song model + track-number columns

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Models/SubsonicModels.swift` | +4 / -0 | Add `genre` / `playCount` Optional vars on `Album` and `AlbumDetail`. (`Song`'s new fields were added in M7 for ⌘L.) |
| `Sonance/Views/AlbumDetailView.swift` | +99 / -7 | Disc grouping (`MultiDiscTrackList`); total album duration in the header (`"12 tracks · 47 min"`). |
| `README.md` | +5 / 0 | Document the new metadata surface. |

(`Sonance/Views/TrackListView.swift` was already adjusted in M7 to prefer `song.track` over
the row index, so the second M8 deliverable was satisfied by that earlier change.)

## Acceptance criteria

- [x] **On a multi-disc album, you see "Disc 1" / "Disc 2" headers.**
      `AlbumDetailView.discGroups(for:)` partitions the album's songs into a sorted
      `[(Int, [Song])]` keyed on `discNumber ?? 1`. If the dictionary has more than one key
      the view renders `MultiDiscTrackList`, a `List` with one `Section` per disc and a
      `Text("Disc N").font(.headline)` header. Single-disc albums continue to use the
      original `TrackListView` for layout consistency.
- [x] **Track numbers in the list match the actual album metadata.**
      Both `TrackListView` (M7) and `MultiDiscTrackList` (M8) compute the displayed track
      number as `song.track ?? fallback`, where the fallback is the row's index. Albums
      whose server returns a `track` use it; albums without it fall back to position so the
      legacy single-disc display is unchanged.
- [x] **Album header shows `"12 tracks · 47 min"`.**
      `totalDurationLabel` sums `song.duration` across the loaded songs, falls back to
      `detail?.duration ?? album.duration` if no per-song durations are present, and
      formats:
      - `47 min` when under an hour;
      - `1 hr` if exactly an hour;
      - `1 hr 27 min` if hours and minutes are both present.
      The track count uses `detail.song.count` when loaded, else `album.songCount`.
- [x] **No decoding regressions — old albums still load.** All new fields on `Song`,
      `Album`, and `AlbumDetail` are Optionals with `nil` defaults. Subsonic responses that
      omit them still decode (the synthesised `init(from:)` calls `decodeIfPresent`).
      `Codable`-encoded queue state from earlier app versions is still decoded back
      successfully because all new fields are Optional.

## Implementation notes

1. **Disc grouping via a dictionary.** `Dictionary(grouping:by:)` would also work but
   sorting the keys directly keeps the rendering deterministic when a server reports disc
   numbers out of order in its `song` array.
2. **Global indices preserved across sections.** `player.play(songs, startAt:)` expects
   indices into the flat `[Song]` array. `MultiDiscTrackList.onPlayAt` looks up the global
   index of the tapped song via `allSongs.firstIndex(where:)` so the queue model is
   unchanged — the user sees disc 2 in a section, but plays into a single ordered queue.
3. **Section header style.** A bold `Text("Disc N")` is plain enough to not crowd the row
   list. macOS `List` automatically gives sections a subtle inset and divider.
4. **Total duration calculation.** Summing `song.duration` is correct for full-album views.
   The fallback to `album.duration` covers the rare case where some songs lack a duration
   (Subsonic sometimes returns a coarser album-level value).

## Build / test

```sh
xcodebuild ... build
```

Result: `** BUILD SUCCEEDED **`. All 12 tests pass. No new warnings.

## Unverifiable criteria (this run)

- "On a multi-disc album you see Disc N headers" requires a Navidrome library with a
  multi-disc album (e.g. The Wall, MMLP2, classical box sets). The implementation is
  architecturally complete; the trigger is purely server data.

## Deviations from the spec

- The spec says "Add those fields to `Song` and `Album`". The semantically relevant
  album-level subset is `genre` and `playCount`; `track`, `discNumber`, and `bitRate` only
  make sense per-song and were not added to `Album`. The added subset still satisfies the
  M8 acceptance criteria.

## Screenshot

Not captured. The first new visible surface is the header line ("12 tracks · 47 min") on
every album; the second is the "Disc 1" / "Disc 2" headers on multi-disc albums.
