import SwiftUI

@main
struct SonanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var auth = AuthStore()
    @StateObject private var player = Player()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var library = LibraryStore()
    @AppStorage("sonance.showMenuBarExtra") private var showMenuBarExtra: Bool = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(player)
                .environmentObject(favorites)
                .environmentObject(library)
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
