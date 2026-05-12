# Development

## Commands

Install project tooling:

```sh
brew install xcodegen
```

Generate the Xcode project:

```sh
xcodegen generate
```

Debug build used by CI and local agents:

```sh
xcodebuild \
  -project Sonance.xcodeproj \
  -scheme Sonance \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY='-' \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Tests:

```sh
xcodebuild test \
  -project Sonance.xcodeproj \
  -scheme Sonance \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO
```

Unsigned universal Release build:

```sh
./scripts/build-release-app.sh 0.1.0-local 1
```

## Manual Navidrome Smoke Test

1. Launch the app and open `Accounts`.
2. Use `Test` on the default test server and confirm the status changes to success.
3. Use `Save & Connect`, then verify Albums, Artists, Songs, Favorites, Search, and Playlists load.
4. Open Albums, scroll through at least 200 items, switch to Search, then return to Albums. The grid should reuse cached album data and already-seen cover art.
5. Open the same album twice. It should reuse cached detail data unless `Refresh` is clicked.
6. Type a search query quickly, then replace it with a different query. Only the newest query should remain visible.
7. Play an album, use Play Next and Add to Queue, reorder queue rows, remove current and non-current rows, then relaunch and confirm the queue restores paused.
8. Open Now Playing at 900x600, 1200x800, and a wide window. Verify queue, lyrics, mini-player scrubber, and volume controls do not overlap.

## Diagnostics

Debug builds record endpoint request counts through `NetworkDiagnostics`. Counts are keyed by
Subsonic endpoint, for example `getAlbumList2`, `getAlbum`, `search3`, and `getCoverArt:300`.
Use `NetworkDiagnostics.snapshot()` while debugging to compare before/after navigation or scroll
flows.

## Known Limitations

- Playlist editing is not implemented.
- Smart playlist rule editing is not available through the Subsonic API.
- AirPlay and sleep timer are not implemented.
- Request diagnostics are currently a lightweight debug aid, not an in-app analytics panel.
