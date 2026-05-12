# Sonance

A native macOS client for [Navidrome](https://www.navidrome.org/), built in SwiftUI.

Inspired by [Feishin](https://github.com/jeffvli/feishin) (functionality) and motivated by the
fact that Electron-based Subsonic clients (Feishin, Supersonic) feel sluggish on macOS.

## What works

- Sign-in to a Navidrome / Subsonic-API server (salted-MD5 token auth)
- **Albums** — grid view backed by `getAlbumList2`. Sort menu: A–Z / Newest / Recently Played /
  Most Played / Random. Heart overlay shows favorited albums. Right-click for Play / Play Next /
  Add to Queue / Toggle Favorite.
- **Artists** — alphabetical list; click to see their albums
- **Songs** — random sample from `getRandomSongs` (Shuffle to refresh)
- **Playlists** — read view of all server playlists, with **smart-playlist (NSP) detection**:
  Navidrome marks .nsp-derived playlists with `readonly: true` and `comment: "Auto-imported from
  '*.nsp'"`; both surface with a sparkles icon and a yellow "Smart" badge.
- **Favorites** — sidebar section with Songs / Albums / Artists tabs, backed by `getStarred2`.
  Heart buttons across the app toggle star/unstar via the Subsonic API; state stays in sync via
  a global `FavoritesStore`.
- **Search** — debounced search3 across artists, albums, and songs
- Shared in-memory library cache avoids re-fetching album lists, artists, details, playlists,
  favorites, random songs, and repeated search results during normal navigation. Refresh controls
  bypass cache intentionally.
- Cover art is served by a two-tier `CoverArtCache` actor: an in-memory `NSCache` capped at 64 MB
  by decoded-pixel cost, and a JPEG/PNG on-disk cache under
  `~/Library/Caches/com.alanhuang.Sonance/covers/` capped at 200 MB with LRU eviction on first
  miss after launch. Cover-art and stream URLs use a memoized salt+token per `SubsonicClient`,
  so URLs stay stable across SwiftUI re-renders and `URLCache`/`AVPlayer` can identify them.

### Playback

- AVPlayer-based streaming with auto-advance to the next track
- Queue: Play, Play Next, Add to Queue, Reorder, Remove, Clear, Play From Queue (jump-to)
- Shuffle (preserves the current track at index 0; Un-shuffle restores original order)
- Repeat: Off / All / One
- Submission scrobble at 50% (or 4 minutes), now-playing scrobble at start, via Subsonic `scrobble`
- Synced lyrics via OpenSubsonic `getLyricsBySongId` — current line highlighted, auto-scrolls,
  click any line to seek there

### Mini-player and Now Playing

- Bottom mini-player: cover, title/artist, heart, shuffle, prev/play-pause/next, repeat,
  scrubber + time, volume slider
- Click the cover thumbnail to **slide up an inline Now Playing panel** (not a separate window or
  modal sheet — it animates up within the same window over the library content, with a translucent
  blur background). Press **Esc** or click the chevron at the top-right to slide it back down.
- Now Playing layout: large cover, transport, scrubber, shuffle/repeat/heart row, plus tabbed
  right pane with **Queue** (drag to reorder, double-click to jump, right-click for Remove) and
  **Lyrics** (synced when available, click any line to seek there).

### Keyboard shortcuts

- **Space** — play / pause (when no text field has focus)
- **⌘P** — play / pause (always)
- **⌘→ / ⌘←** — next / previous track

### Persistence

- Server URL / username / password live in **macOS Keychain** (with one-shot migration from
  any prior UserDefaults entry). Debug builds use `UserDefaults` instead and include a local
  test-server preset so iterative rebuilds do not repeatedly prompt for Keychain access.
- The current queue + queue index + current time + shuffle/repeat state + volume are saved to
  `UserDefaults` on queue mutations and via a throttled playhead save. On launch, the mini-player shows
  the last track in a **paused** state at the correct scrubber position; press Play (or Space)
  to load the AVPlayerItem, seek to the saved time, and resume.

### Window + menu bar behavior

- Closing the window **does not quit the app** (`NSApplicationDelegate.applicationShouldTerminateAfterLastWindowClosed`
  returns `false`). Reopen by clicking the dock icon or via the menu bar item.
- An `NSStatusItem` is registered with `autosaveName = "SonanceStatusItem"` showing a music-note
  glyph that toggles to a play-circle when something's playing. Clicking it opens an `NSPopover`
  with the current track, prev/play/next, "Show Sonance", and "Quit". A toggle in the **Sonance > Settings**
  menu (`Show Menu Bar Icon`) lets you hide it.
- **Known limitation on macOS Tahoe (26)**: the menu bar collapses overflow items behind a `…`
  button when the bar is full. If you have a lot of menu bar utilities (Dropbox, Stage Manager,
  Focus, AirPods indicator, Bartender, etc.) the Sonance icon may sit behind that overflow.
  Click the `…` to find it, or remove items from the menu bar via System Settings → Control
  Center to free space.

### Sign Out

The Sign Out button is no longer in the window toolbar. It lives at the bottom of the sidebar
in a server-info chip showing the current host and username, with a menu offering "Refresh
Favorites", account switching, "Connect Another Server", and "Forget This Account". This matches
the pattern in apps like Linear / Notion / Slack.

## Feature parity vs. [vscode-subsonic-player](https://github.com/AlanHuang99/vscode-subsonic-player)

| Capability | vscode-subsonic-player | Sonance |
|---|---|---|
| Library browsing (recent / random / most-played albums) | ✅ | ✅ (sort menu) |
| Favorite songs view | ✅ | ✅ |
| Album / Playlist detail with play actions | ✅ | ✅ |
| Smart playlist (NSP) read | ✅ (Navidrome native API) | ✅ (Subsonic readonly + .nsp comment detection) |
| Queue: Play Now / Play Next / Add to Queue / Reorder / Remove / Clear | ✅ | ✅ |
| Favorites for tracks and albums | ✅ | ✅ (also artists) |
| Synced lyrics with click-to-seek | ✅ | ✅ |
| Search | ✅ | ✅ (debounced) |
| Random songs | ✅ | ✅ |
| Repeat / Shuffle | ✅ | ✅ |
| Volume control | ✅ | ✅ |
| Keyboard shortcuts (play/pause, next, prev) | ✅ | ✅ |
| Scrobbling (submission to Navidrome history) | — | ✅ |
| Multiple servers | ✅ | ✅ (saved accounts + switcher) |
| Keychain credential storage | ✅ | ✅ |
| Persistent queue across launches | ❌ | ✅ |
| Refresh Library command | ✅ | ✅ (per-view refresh controls) |

## What doesn't work yet

- Smart-playlist editing — the Subsonic API doesn't expose .nsp rule editing; this is a Navidrome
  limitation (Feishin and Supersonic have the same constraint). Editing requires writing the
  .nsp file or using Navidrome's web UI.
- Regular playlist editing (add/remove tracks, reorder)
- Sleep timer, AirPlay

## Build

```sh
brew install xcodegen
xcodegen generate
open Sonance.xcodeproj
```

For a one-shot ad-hoc build from the command line (no signing required):

```sh
xcodegen generate
xcodebuild \
  -project Sonance.xcodeproj \
  -scheme Sonance -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  build

open build/Build/Products/Debug/Sonance.app
```

If local network or keychain permission prompts are annoying during development, prefer a signed run from Xcode (or `xcodebuild` without forcing ad-hoc signing) so the app retains trusted OS grants between rebuilds.

For an easy local workflow:

```sh
./bin/dev.sh
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for exact CI-style build/test commands, a Navidrome smoke-test
checklist, request-count diagnostics, and current limitations.

## Installable releases

Releases are published from Git tags by GitHub Actions. A tag like `v0.1.0` builds a Release
app, signs it with a Developer ID Application certificate, submits it to Apple notarization,
staples the notarization ticket, then publishes both:

- `Sonance-v0.1.0.dmg` — easiest install path; open and drag Sonance to Applications
- `Sonance-v0.1.0.zip` — same notarized app as a zip

Required repository secrets:

- `MACOS_CERT_P12_BASE64` — base64-encoded Developer ID Application `.p12`
- `MACOS_CERT_P12_PASSWORD` — password for that `.p12`
- `MACOS_KEYCHAIN_PASSWORD` — temporary CI keychain password
- `MACOS_NOTARY_API_KEY_P8_BASE64` — base64-encoded App Store Connect API key `.p8`
- `MACOS_NOTARY_API_KEY_ID` — API key ID
- `MACOS_NOTARY_ISSUER_ID` — App Store Connect issuer ID

Helpful encoding commands:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Once the secrets are set, publish a release by pushing a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Local unsigned release build:

```sh
./scripts/build-release-app.sh 0.1.0-local 1
```

Local DMG packaging from that build:

```sh
./scripts/make-dmg.sh build/Build/Products/Release/Sonance.app build/Sonance-local.dmg
```

## Project layout

```
Sonance/
  SonanceApp.swift          # @main, hosts Auth + Player + LibraryStore as @StateObject
  ContentView.swift         # routes login vs library, places MiniPlayerBar via safeAreaInset
  Auth/                     # ServerCredentials, AuthStore (login state + persistence)
  Networking/               # SubsonicClient (URL building, auth tokens), SubsonicError
  Library/                  # LibraryStore shared cache + request de-duplication
  Models/                   # Decodable Subsonic response types
  Playback/Player.swift     # AVPlayer wrapper, queue, time/end observers
  Views/
    LoginView.swift
    LibraryView.swift       # NavigationSplitView host with sidebar
    AlbumsView.swift        # grid + AlbumTile
    AlbumDetailView.swift   # cover/title/play + track list (uses TrackListView)
    ArtistsView.swift       # list + ArtistDetailView (their albums)
    SongsView.swift         # random songs sample
    PlaylistsView.swift     # split view: list of playlists + selected detail
    SearchView.swift        # debounced search across types
    TrackListView.swift     # shared track list with double-click-to-play
    MiniPlayerBar.swift     # bottom bar with transport + scrubber
  Assets.xcassets/
    AppIcon.appiconset/     # generated by tools/make_icon.swift
    AccentColor.colorset/
  Sonance.entitlements      # sandbox + network client
  Info.plist                # generated by xcodegen; ATS allows arbitrary loads (HTTP servers OK)
tools/
  make_icon.swift           # CoreGraphics icon renderer; outputs all required AppIcon sizes
project.yml                 # XcodeGen project config
```

## Subsonic / Navidrome notes

- All API calls go through `SubsonicClient`. Auth uses the salted-MD5 token form (`u`, `t`, `s`)
  with a fresh salt per request, not plaintext passwords on the wire.
- The decoder uses a generic `SubsonicEnvelope<Body>` that decodes the body alongside `status` /
  `version` / `error` from the same JSON level — each endpoint just declares its own response
  type with its specific top-level field (`albumList2`, `playlists`, etc.).
- Streaming uses `getStream?id=...` URLs which are self-authenticating via query params, so
  AVPlayer can use them directly without custom URL session work.
- Cover art uses `getCoverArt?id=...&size=N`; the detail view requests size 400, the mini-player
  requests size 96, and grid tiles use the default 300.
- ATS in `Info.plist` has `NSAllowsArbitraryLoads = true` because most Navidrome installs are on
  plaintext HTTP behind a LAN; remove that if your server is HTTPS-only.

## Hard-won SwiftUI lessons baked into this codebase

- `List(data, selection:)` does **not** drive the selection binding reliably on macOS when `data`
  is `Identifiable`. Always use `List(selection:) { ForEach(items, id: \.self) { ... } }` for
  selectable sidebars and lists. Burned three iterations on this; see
  `Views/LibraryView.swift` and `Views/PlaylistsView.swift`.
- Synthetic mouse events via CGEvent / cliclick / osascript-click *can* hit a SwiftUI list row
  and trigger hover, but won't update a selection binding if that binding is broken. If clicks
  "don't change selection," check the binding pattern first before debugging the input layer.
- `@MainActor` `ObservableObject`s with `@Published` properties from `Combine` are the simplest
  way to plumb playback state into SwiftUI views. AVPlayer's periodic time observer needs a
  `Task { @MainActor in ... }` hop because it calls back on a queue you specify.
