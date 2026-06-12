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

Unsigned universal Release build (base / App Store target):

```sh
./scripts/build-release-app.sh 0.1.0-local 1
```

Direct (Sparkle) build — pass the scheme as the third argument:

```sh
./scripts/build-release-app.sh 0.1.0-local 1 Sonance-Direct
```

## Auto-update (Sparkle)

In-app updates use [Sparkle](https://sparkle-project.org) and ship only in the
`Sonance-Direct` target. The base `Sonance` target is Sparkle-free for a future
Mac App Store submission. See the README's "Distribution channels" section for
the split.

**Do not add the Sparkle package dependency to the base `Sonance` target.** It is
deliberately absent so the App Store binary never links or embeds Sparkle. The
updater code lives behind `#if SPARKLE`, a condition set only on `Sonance-Direct`.

### One-time signing-key setup

Sparkle verifies updates with an EdDSA (ed25519) key pair. Generate it once with
the `generate_keys` tool from the Sparkle release bundle (or the SwiftPM
checkout's `bin/`):

```sh
generate_keys                 # stores the private key in your login keychain
generate_keys -x sparkle_private.key   # also export it to a file
```

- The command prints a base64 **public** key. Put it in `SUPublicEDKey` in
  `project.yml` (the `Sonance-Direct` target's `info.properties`), replacing the
  `REPLACE_WITH_ED25519_PUBLIC_KEY` placeholder, and re-run `xcodegen generate`.
- Store the exported private key as the `SPARKLE_ED_PRIVATE_KEY` GitHub Actions
  secret (the verbatim file contents). Keep the file out of the repo; the repo is
  public.

### Update feed (GitHub Pages)

`SUFeedURL` points at `https://alanhuang99.github.io/sonance/appcast.xml`. Enable
GitHub Pages for the repo, serving the `gh-pages` branch. The release workflow
signs each release zip and pushes an updated `appcast.xml` to that branch; the
binaries themselves stay on the GitHub Releases page.

The first Sparkle-enabled release cannot auto-update users already on an earlier,
Sparkle-free build — they download it once from the Releases page, and in-app
updates work from the next release onward.

### Testing an update locally

1. Build `Sonance-Direct` at a low version (e.g. `0.4.0`).
2. Build a newer version (e.g. `0.4.1`), zip it, and sign it with
   `sign_update Sonance-0.4.1.zip` to get the `edSignature`.
3. Write a local `appcast.xml` describing `0.4.1` with that signature and a
   `file://` (or local HTTP) enclosure URL, and point the older build's
   `SUFeedURL` at it.
4. Run the older build, choose "Check for Updates…", and confirm it downloads,
   verifies, installs, and relaunches into `0.4.1`.

## Releases and signing

Releases are published from Git tags by GitHub Actions (`.github/workflows/release.yml`). Pushing a tag like `v0.6.0` builds the `Sonance-Direct` target, signs it with a Developer ID Application certificate, notarizes it with Apple, publishes `Sonance-vX.Y.Z.dmg` and `Sonance-vX.Y.Z.zip` to the Releases page, signs the zip with Sparkle's EdDSA key, and updates `appcast.xml` on the GitHub Pages branch.

Required repository secrets:

- `MACOS_CERT_P12_BASE64` — base64-encoded Developer ID Application `.p12`
- `MACOS_CERT_P12_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `MACOS_NOTARY_API_KEY_P8_BASE64` — base64-encoded App Store Connect API key `.p8`
- `MACOS_NOTARY_API_KEY_ID`
- `MACOS_NOTARY_ISSUER_ID`
- `SPARKLE_ED_PRIVATE_KEY` — the Sparkle EdDSA private key (the verbatim contents of the file written by `generate_keys -x`). See "Auto-update (Sparkle)" above for the one-time key setup and enabling GitHub Pages for the feed.

Encode the certificate and notary key files for the secrets:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Tag and push to trigger a release:

```sh
git tag v0.6.0
git push origin v0.6.0
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
