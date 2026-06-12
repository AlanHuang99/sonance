# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] — 2026-06-12

### Added

- In-app updates via Sparkle. A "Check for Updates…" item under the app menu downloads, verifies, installs, and relaunches the new version, with an optional "Automatically Check for Updates" toggle. This ships in the directly-distributed build only; the base target stays free of Sparkle for a future Mac App Store submission, which provides its own updates.

## [0.4.0] — 2026-06-12

### Added

- Saved accounts can carry an optional nickname, shown in the sidebar, the server footer, the Accounts editor, and the login screen. Nicknames persist across credential re-saves and reconnects.
- Sidebar header showing the app icon and name above the navigation list.

### Changed

- Cover art is center-cropped to a square for any source aspect ratio, so wide or tall artwork fills its tile consistently instead of being displayed in full.
- Larger, more consistent tap targets throughout: the mini-player, Now Playing, and menu-bar transports; the favorite, volume, and close buttons; the segmented pickers and search fields; and the primary action buttons.
- Taller, more legible sidebar navigation rows.

### Fixed

- Non-square cover art no longer overflows its grid tile and overlaps adjacent albums in the grid.

## [0.3.1] — 2026-05-13

### Fixed

- Cross-link navigation (clicking an artist or album name from inside another
  section's detail page) now reliably opens the destination's detail view.
  The previous design used a single `NavigationStack` whose root view's type
  swapped on every section change; SwiftUI dropped pushes during that swap
  frame, so the user landed on the target section's root with no detail
  visible. `LibraryView` now hosts one `NavigationStack` per section, each
  with a stable root view and its own `NavigationPath`. Cross-link routing
  prepares the target section's path before flipping the visible section.
- Similar-artists names on the Artist page (and other scrolling detail
  surfaces) are no longer hidden under the mini-player bar. Each detail-pane
  `ScrollView` now reserves a bottom content margin equal to the mini-player
  height; `NavigationSplitView`'s detail column does not propagate the
  outer `safeAreaInset` to inner `ScrollView`s on macOS 14, so the inset is
  applied explicitly.

### Added

- Track rows in mixed-album contexts (Search, Favorites songs, Discover
  songs, smart and regular playlists) show a 36 × 36 album cover thumbnail
  before the title, with the play / currently-playing indicator overlaid on
  hover. Album detail keeps the prior track-number column because every
  track would carry the same album thumbnail there.
- Always-visible volume control in the mini-player: a speaker icon button
  that reflects the current volume level and pops a slider on click. The
  prior inline slider lived inside a `ViewThatFits` that hid it on narrow
  windows. The popover includes a mute toggle that remembers the prior
  level.
- Inline volume slider in the Now Playing pane, since the mini-player is
  hidden while Now Playing is open.

### Changed

- DMG installer now opens to a 540 × 360 icon-view window with Sonance.app
  on the left and an Applications shortcut on the right (sidebar / toolbar
  / status bar hidden, icons at 128 pt), so the drag-to-install gesture is
  immediately obvious. `make-dmg.sh` is self-contained — no extra tooling
  dependency on top of the macOS `hdiutil` / `osascript` already used by CI.

## [0.3.0] — 2026-05-13

### Added

- Artist and album names in track rows, the album-detail header, the Now
  Playing pane, and the mini-player are clickable links to the corresponding
  detail page. A hover underline marks the affordance. Queue rows gained
  "Go to Album" / "Go to Artist" in their context menu.
- Discover tab replaces the old Songs tab, with a Songs / Albums / Artists /
  Playlists picker. Random songs and albums come from `getRandomSongs` and
  `getAlbumList2(type: random)`; random artists and playlists shuffle the
  cached index.
- Genres tab backed by `getGenres`, drilling into albums via
  `getAlbumList2(type: byGenre)`.
- Artist detail page enriched with the artist image, biography, and similar
  artists from `getArtistInfo2`, plus Play All / Shuffle All over the whole
  discography and a Star / Unstar toolbar button.
- Multi-disc album section headers show per-disc track count and duration.
- Search gained an All / Artists / Albums / Songs scope picker that filters
  the visible result sections in place.
- Albums grid auto-scrolls keyboard-selected tiles into view.
- Repeat and Shuffle now publish to `MPRemoteCommandCenter`, so the system's
  three-state repeat and shuffle controls reflect and steer the player.
- Network diagnostics counters are exposed as a collapsible panel in the
  Accounts section.

### Changed

- Sidebar order is now Albums, Artists, Discover, Genres, Playlists,
  Favorites. Keyboard shortcuts ⌘1..⌘6 follow the new order.

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

[0.4.0]: https://github.com/AlanHuang99/sonance/releases/tag/v0.4.0
[0.3.1]: https://github.com/AlanHuang99/sonance/releases/tag/v0.3.1
[0.3.0]: https://github.com/AlanHuang99/sonance/releases/tag/v0.3.0
[0.2.0]: https://github.com/AlanHuang99/sonance/releases/tag/v0.2.0
[0.1.2]: https://github.com/AlanHuang99/sonance/releases/tag/v0.1.2
[0.1.1]: https://github.com/AlanHuang99/sonance/releases/tag/v0.1.1
[0.1.0]: https://github.com/AlanHuang99/sonance/releases/tag/v0.1.0
