import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var library: LibraryStore
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
                .controlSize(.large)
                .frame(maxWidth: 380)
                Spacer()
                Button {
                    Task { await load(refresh: true) }
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.iconControl)
                .help("Refresh")
            }
            .padding(20)
            Divider()
            content
        }
        .navigationTitle("Favorites")
        .task { await load() }
        .onChange(of: favorites.songIDs) { _, newIDs in reconcileSongs(newIDs) }
        .onChange(of: favorites.albumIDs) { _, newIDs in reconcileAlbums(newIDs) }
        .onChange(of: favorites.artistIDs) { _, newIDs in reconcileArtists(newIDs) }
    }

    /// Mirror the truth in `FavoritesStore` against the locally-loaded `Starred2Container`
    /// without going to the network. New stars added from elsewhere appear on the next manual
    /// refresh; unstars (which the user can do from any view) remove the entry immediately so
    /// the Favorites list never shows a song that the store says is no longer starred.
    private func reconcileSongs(_ ids: Set<String>) {
        guard let data, let songs = data.song else { return }
        let filtered = songs.filter { ids.contains($0.id) }
        if filtered.count != songs.count {
            self.data = Starred2Container(song: filtered, album: data.album, artist: data.artist)
        }
    }

    private func reconcileAlbums(_ ids: Set<String>) {
        guard let data, let albums = data.album else { return }
        let filtered = albums.filter { ids.contains($0.id) }
        if filtered.count != albums.count {
            self.data = Starred2Container(song: data.song, album: filtered, artist: data.artist)
        }
    }

    private func reconcileArtists(_ ids: Set<String>) {
        guard let data, let artists = data.artist else { return }
        let filtered = artists.filter { ids.contains($0.id) }
        if filtered.count != artists.count {
            self.data = Starred2Container(song: data.song, album: data.album, artist: filtered)
        }
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
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
            .contentMargins(.bottom, miniPlayerSafeAreaInset, for: .scrollContent)
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
        await load(refresh: false)
    }

    private func load(refresh: Bool) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            data = try await library.starred(client: client, refresh: refresh)
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}
