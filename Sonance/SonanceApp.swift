import SwiftUI

@main
struct SonanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var auth = AuthStore()
    @StateObject private var player = Player()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var navigation = NavigationCoordinator()
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
            CommandGroup(replacing: .textEditing) {
                Button("Find") { navigation.focusSearch() }
                    .keyboardShortcut("f", modifiers: [.command])
            }
            CommandMenu("Go") {
                Button("Albums") { navigation.switch_(to: .albums) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Artists") { navigation.switch_(to: .artists) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Songs") { navigation.switch_(to: .songs) }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Playlists") { navigation.switch_(to: .playlists) }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Favorites") { navigation.switch_(to: .favorites) }
                    .keyboardShortcut("5", modifiers: [.command])
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
            }
        }
    }
}
