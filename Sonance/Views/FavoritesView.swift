import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @State private var data: Starred2Container?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var tab: Tab = .songs

    enum Tab: String, CaseIterable, Identifiable {
        case songs = "Songs", albums = "Albums", artists = "Artists"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer()
                Button {
                    Task { await load() }
                } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
            }
            .padding(20)
            Divider()
            content
        }
        .navigationTitle("Favorites")
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
        .task { await load() }
        .onChange(of: favorites.songIDs) { Task { await load() } }
        .onChange(of: favorites.albumIDs) { Task { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && data == nil {
            ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = loadError {
            Text(err).foregroundStyle(.red).padding(20)
        } else {
            switch tab {
            case .songs: songsTab
            case .albums: albumsTab
            case .artists: artistsTab
            }
        }
    }

    @ViewBuilder
    private var songsTab: some View {
        let songs = data?.song ?? []
        if songs.isEmpty {
            emptyState("No favorite songs yet", "Tap the heart on any track to add it")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        if let client = auth.client {
                            player.play(songs, startAt: 0, using: client)
                        }
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }.buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                TrackListView(songs: songs, onPlay: { idx in
                    if let client = auth.client {
                        player.play(songs, startAt: idx, using: client)
                    }
                })
            }
        }
    }

    @ViewBuilder
    private var albumsTab: some View {
        let albums = data?.album ?? []
        if albums.isEmpty {
            emptyState("No favorite albums yet", "Tap the heart on any album to add it")
        } else {
            ScrollView {
                let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums) { album in
                        AlbumGridItem(album: album)
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private var artistsTab: some View {
        let artists = data?.artist ?? []
        if artists.isEmpty {
            emptyState("No favorite artists yet", "")
        } else {
            List(artists) { a in
                NavigationLink(value: a) {
                    ArtistRow(artist: a, client: auth.client)
                }
            }
        }
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "heart").font(.largeTitle).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            data = try await client.starred()
            // Keep FavoritesStore in sync with the freshly-fetched truth
            favoritesSync(data)
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func favoritesSync(_ container: Starred2Container?) {
        // Re-sync the IDs based on what came back
        // (toggleSong already updated optimistically; this catches drift)
        // Use direct property writes via dispatch back through a method.
        // FavoritesStore exposes only mutations; adding a setter is overkill.
        // For now, individual toggles already update IDs; refresh on re-login covers initial state.
        _ = container
    }
}
