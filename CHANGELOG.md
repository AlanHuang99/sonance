# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-05-13

### Added

- Two-tier cover-art cache (in-memory `NSCache` + on-disk LRU) with stable
  cache keys and a memoized salt+token per `SubsonicClient` for cover-art and
  stream URLs.
- System Now Playing integration via `MPNowPlayingInfoCenter` and
  `MPRemoteCommandCenter`: Control Center, the menu-bar Now Playing widget,
  media keys, AirPods double-tap, and Control Center scrubbing.
- Gapless playback: `Player` uses `AVQueuePlayer` and preloads the next track
  when within 10 s of the current track's end.
- Albums grid pagination (100 per page) with an end-of-grid sentinel that
  loads the next page on scroll, and an inline sort menu at the top.
- Ambient backdrop in the Now Playing panel: the current cover scaled and
  blurred behind a translucent material, cross-fading on track change. The
  mini-player slides out of the safe area while the panel is open.
- Keyboard navigation: `⌘F` (search), `⌘1`–`⌘5` (sidebar sections), `⌘L`
  (current track's album), arrow keys + `Return` in track lists and the
  albums grid.
- Multi-disc album grouping with "Disc N" section headers and total album
  duration in the album header.
- Playlist editing for non-smart playlists: create, rename, delete,
  drag-to-reorder, and add tracks via a search-based picker. Smart (`.nsp`)
  playlists remain read-only.
- Mini-player navigation: click the title to open the current album, click
  the artist name to open the artist, right-click the cover for Play Next on
  Album / Go to Album / Go to Artist / Show in Library.
- Drag and drop: drag a track from any list onto the Now Playing queue to
  insert at that position.

### Changed

- `FavoritesView` no longer issues a full `getStarred2` re-fetch on every
  heart toggle; it reconciles the local container against the
  `FavoritesStore` ID sets in place.
- `Song`, `Album`, and `AlbumDetail` now decode additional optional fields
  (`albumId`, `artistId`, `track`, `discNumber`, `bitRate`, `genre`,
  `playCount`).

## [0.1.2] — 2026-05-12

- Performance: caching, queue tests.

## [0.1.1] — 2026-05-11

- CI: update checkout action.

## [0.1.0] — 2026-05-11

- Initial release.

[0.2.0]: https://github.com/AlanHuang99/sonance/releases/tag/v0.2.0
[0.1.2]: https://github.com/AlanHuang99/sonance/releases/tag/v0.1.2
[0.1.1]: https://github.com/AlanHuang99/sonance/releases/tag/v0.1.1
[0.1.0]: https://github.com/AlanHuang99/sonance/releases/tag/v0.1.0
