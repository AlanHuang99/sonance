import SwiftUI

/// Discovery surface that lets the user shuffle through random songs, albums, artists, or
/// playlists. Replaces the prior "Songs" tab that always loaded random songs and confused the
/// label with a real "all songs" browse (which the app intentionally does not yet offer).
struct DiscoverView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: LibraryStore

    enum Mode: String, CaseIterable, Identifiable {
        case songs = "Songs", albums = "Albums", artists = "Artists", playlists = "Playlists"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .songs

    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var playlists: [Playlist] = []

    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .frame(maxWidth: 440)
                Spacer()
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .controlSize(.large)
                .disabled(isLoading)
                if mode == .songs {
                    Button {
                        if let client = auth.client, !songs.isEmpty {
                            player.play(songs, startAt: 0, using: client)
                        }
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(songs.isEmpty)
                }
            }
            .padding(20)
            Divider()
            content
        }
        .navigationTitle("Discover")
        .task(id: mode) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && currentIsEmpty {
            ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = loadError {
            Text(err).foregroundStyle(.red).padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch mode {
            case .songs:
                TrackListView(songs: songs, onPlay: { idx in
                    if let client = auth.client {
                        player.play(songs, startAt: idx, using: client)
                    }
                })
            case .albums:
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
            case .artists:
                List(artists) { artist in
                    NavigationLink(value: artist) {
                        ArtistRow(artist: artist, client: auth.client)
                    }
                }
                .reservesMiniPlayerBar()
            case .playlists:
                List(playlists) { playlist in
                    NavigationLink(value: playlist) {
                        PlaylistRow(playlist: playlist)
                    }
                }
                .reservesMiniPlayerBar()
            }
        }
    }

    private var currentIsEmpty: Bool {
        switch mode {
        case .songs: return songs.isEmpty
        case .albums: return albums.isEmpty
        case .artists: return artists.isEmpty
        case .playlists: return playlists.isEmpty
        }
    }

    private func load() async {
        await load(refresh: false)
    }

    private func load(refresh: Bool) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch mode {
            case .songs:
                songs = try await library.randomSongs(size: 100, client: client, refresh: refresh)
            case .albums:
                // Subsonic exposes random album sort natively; bypass the per-sort cache on
                // refresh so each Shuffle press genuinely re-rolls.
                albums = try await client.albumList(type: AlbumSort.random.rawValue, size: 60)
            case .artists:
                // No server API for random artists — shuffle the cached artist index. Honors
                // `refresh` so users who want a fresh shuffle of a refreshed index still get one.
                let all = try await library.artists(client: client, refresh: refresh)
                artists = Array(all.shuffled().prefix(40))
            case .playlists:
                let all = try await library.playlists(client: client, refresh: refresh)
                playlists = Array(all.shuffled().prefix(40))
            }
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}
