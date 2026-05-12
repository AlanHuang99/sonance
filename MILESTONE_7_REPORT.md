# Milestone 7 — Keyboard navigation

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `Sonance/Library/NavigationCoordinator.swift` | +30 / 0 | New `@MainActor` coordinator: `selectedSection`, `searchFocusRequest`, `pendingAlbumNavigation`. |
| `Sonance/SonanceApp.swift` | +30 / -7 | Inject coordinator; add `Find` (⌘F), `Go` menu (⌘1..⌘5, ⌘L), keep existing Playback menu. |
| `Sonance/Models/SubsonicModels.swift` | +6 / -1 | Add `albumId`, `track`, `discNumber`, `bitRate`, `genre`, `playCount` to `Song` (Optional, defaulted nil). Enables ⌘L. |
| `Sonance/Views/LibraryView.swift` | +18 / -6 | Bind sidebar `selection` to coordinator; add `detailPath` `NavigationStack`; consume `pendingAlbumNavigation`. |
| `Sonance/Views/SearchView.swift` | +7 / -0 | `@FocusState`; refocus on `searchFocusRequest` bumps. |
| `Sonance/Views/TrackListView.swift` | +13 / -3 | `List(selection:)`; `.onKeyPress(.return)` plays highlighted track; use `Song.track` for the row number when available. |
| `Sonance/Views/AlbumsView.swift` | +45 / -1 | `@FocusState`; selection index; `GeometryReader` to estimate `columnCount`; arrow-key navigation; Return → coordinator pushes onto detail stack. |
| `README.md` | +6 / -0 | Document the new shortcuts. |

## Acceptance criteria

- [x] **Each shortcut works when its view is visible.** ⌘1..⌘5 are first-responder-agnostic
      (declared on `CommandMenu` so they fire from anywhere). ⌘F flips to Search and focuses
      the text field. ⌘L is enabled only when `player.currentSong?.albumId` is non-nil and
      pushes the corresponding album onto the detail stack. ↑/↓/Return in `TrackListView`
      require the list to be focused (the user clicks into it once). ←/→/↑/↓/Return in
      `AlbumsView` require the grid to be focused.
- [x] **No shortcut steals input while typing in a text field.** ⌘1..⌘5 and ⌘L use ⌘
      modifiers, which the system always treats as menu commands rather than text input.
      ⌘F is normally an OS-level "find" — declared via `CommandGroup(replacing: .textEditing)`
      so it overrides any default Find behaviour the system would inject. The arrow-key
      handlers are bound to `.onKeyPress(...)` on the focused list/grid; while a `TextField`
      holds focus, the list does not receive the key event.
- [x] **⌘F works from any sidebar section, switching to Search if needed.**
      `NavigationCoordinator.focusSearch()` sets `selectedSection = .search` if not already
      there, then bumps `searchFocusRequest`, which `SearchView` observes to re-apply
      `searchFieldFocused = true`. `SearchView.onAppear` also sets focus, so the first ⌘F
      from another section both navigates and focuses.

## Implementation notes

1. **`NavigationCoordinator`.** Owns the live sidebar selection (`LibrarySection?`) and two
   "signal" properties: an `Int` that's incremented to request search focus, and an
   `Album?` that's set to request a programmatic push. `LibraryView` consumes both via
   `onChange`. Adding more app-wide nav commands (e.g. "Go to Now Playing") is a one-line
   addition.
2. **`detailPath` reset on section switch.** Without resetting the `NavigationStack` path,
   switching from Albums (with an open AlbumDetailView at the leaf) to Artists and back
   would land the user on the stale AlbumDetailView. `LibraryView.onChange(of:
   navigation.selectedSection)` clears `detailPath` so each section always opens at its root.
3. **`AlbumsView` grid navigation.** SwiftUI's `LazyVGrid` has no built-in focus traversal.
   The implementation:
   - Tracks `selectedIndex` and renders a 2 pt accent stroke on the selected `AlbumTile`.
   - Measures the rendered width via an invisible `GeometryReader` to estimate the column
     count, mirroring `.adaptive(minimum: 160)` with 16 pt spacing and 20 pt padding.
   - Maps ←/→ to `±1` and ↑/↓ to `±columnCount`, clamped to `0..<albums.count`.
   - Return calls `navigation.requestAlbumNavigation(albums[i])`, which sets the section
     and pushes the album onto the detail stack via the `pendingAlbumNavigation` path.
4. **`TrackListView` integration with `List(selection:)`.** Macros happily accept a
   `Binding<Song.ID?>` and the list itself handles ↑/↓. We only need `.onKeyPress(.return)`
   to add the play action. Multiple-selection isn't supported (intentional — playing five
   tracks at once is not a useful command).
5. **`Song.albumId` is now decoded.** Subsonic's `song` element has always carried an
   `albumId`; adding it as an Optional `var` with a `nil` default keeps the existing
   memberwise calls (used by tests) compiling and feeds ⌘L. The other M8-relevant fields
   are decoded here too (Optional, nil-default) so the bigger M8 work doesn't need to
   re-touch `Song`'s call sites.

## Build / test

```sh
xcodegen generate
xcodebuild ... test
```

Result: `** BUILD SUCCEEDED **`. All 12 tests pass. No new warnings.

## Unverifiable criteria (this run)

- "Each shortcut works when its view is visible" requires interactive use. Static argument:
  the `CommandMenu` declarations are picked up by AppKit's menu builder for free, and
  `.onKeyPress` is the documented macOS 14+ SwiftUI primitive. The full unit-test surface
  for these is a UI test — not in scope for this milestone.
- "No shortcut steals input while typing" — depends on system menu vs. responder routing;
  see the implementation note above for the architectural argument.

## Deviations from the spec

- **Spec lists Albums/Artists/Songs/Playlists/Favorites/Search (six sections) for ⌘1..⌘5
  (five shortcuts).** The implementation maps ⌘1..⌘5 to Albums, Artists, Songs, Playlists,
  Favorites (the user's likely-most-frequented order). Search is reachable via ⌘F (which
  also focuses the field), avoiding the awkward "press ⌘6 to focus search" extra step.
- **Album grid arrow navigation uses an estimated column count** based on rendered width.
  In a freshly opened window where the GeometryReader hasn't reported yet, the first up/down
  press may move by 1 (a left/right step). After the layout settles the columns are
  accurate.
- **Album grid focus needs a click before keys take effect.** `.focusable() + .focused($)`
  marks the grid as focusable, but macOS doesn't auto-focus a non-text view. A tab or click
  enters focus. Document; if tedious in practice, the next iteration could call
  `gridFocused = true` on `.task`.

## Screenshot

Not captured. The visible change in Albums is a 2 pt accent stroke on the selected tile
when the grid is focused; the visible change in track lists is a standard macOS row
selection.
