import SwiftUI

@main
struct SonanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var auth = AuthStore()
    @StateObject private var player = Player()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var navigation = NavigationCoordinator()
    #if SPARKLE
    @StateObject private var updaterController = UpdaterController()
    #endif
    @AppStorage("sonance.showMenuBarExtra") private var showMenuBarExtra: Bool = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(player)
                .environmentObject(favorites)
                .environmentObject(library)
                .environmentObject(navigation)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appDelegate.attach(auth: auth, player: player, favorites: favorites)
                    appDelegate.refreshStatusItemVisibility(showMenuBarExtra)
                }
                .onChange(of: showMenuBarExtra) { _, newValue in
                    appDelegate.refreshStatusItemVisibility(newValue)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            #if SPARKLE
            // "Check for Updates…" sits just under "About Sonance" in the app menu,
            // the standard macOS placement. Gated to the Direct build (Sparkle).
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updaterController.checkForUpdates() }
                    .disabled(!updaterController.canCheckForUpdates)
            }
            #endif
            // Add Find alongside the system text-editing items, not in place of them.
            // `replacing:` would wipe out any default Find/Find-Next slots SwiftUI may install;
            // `after:` injects our shortcut while preserving anything the platform provides.
            // Standard Edit actions (cut/copy/paste/undo/select-all) live in the separate
            // `.pasteboard` and `.undoRedo` groups and are unaffected either way.
            CommandGroup(after: .textEditing) {
                Button("Find") { navigation.focusSearch() }
                    .keyboardShortcut("f", modifiers: [.command])
            }
            CommandMenu("Go") {
                Button("Albums") { navigation.switch_(to: .albums) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Artists") { navigation.switch_(to: .artists) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Discover") { navigation.switch_(to: .discover) }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Genres") { navigation.switch_(to: .genres) }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Playlists") { navigation.switch_(to: .playlists) }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Favorites") { navigation.switch_(to: .favorites) }
                    .keyboardShortcut("6", modifiers: [.command])
                Divider()
                Button("Go to Current Album") {
                    guard let song = player.currentSong, let id = song.albumId else { return }
                    let album = Album(
                        id: id,
                        name: song.album ?? "",
                        artist: song.artist,
                        artistId: nil,
                        coverArt: song.coverArt,
                        songCount: nil,
                        duration: nil,
                        year: nil,
                        starred: nil
                    )
                    navigation.requestAlbumNavigation(album)
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(player.currentSong?.albumId == nil)
            }
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") {
                    player.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(player.currentSong == nil)
                Button("Next") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                    .disabled(player.currentSong == nil)
                Button("Previous") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .disabled(player.currentSong == nil)
            }
            CommandGroup(after: .appSettings) {
                Toggle("Show Menu Bar Icon", isOn: $showMenuBarExtra)
                #if SPARKLE
                Toggle("Automatically Check for Updates", isOn: Binding(
                    get: { updaterController.automaticallyChecksForUpdates },
                    set: { updaterController.automaticallyChecksForUpdates = $0 }
                ))
                #endif
            }
        }
    }
}
