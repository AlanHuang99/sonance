import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var library: LibraryStore
    let album: Album
    @State private var detail: AlbumDetail?
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            tracks
        }
        .navigationTitle(album.name)
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            cover
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 6) {
                Text(album.name).font(.title).bold()
                if let artist = album.artist {
                    Text(artist).font(.title3).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let year = album.year { Text(String(year)).font(.callout) }
                    if let count = detail?.song?.count ?? album.songCount {
                        Text("•").foregroundStyle(.secondary)
                        Text("\(count) tracks").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    Button {
                        playAll()
                    } label: {
                        Label("Play", systemImage: "play.fill").frame(width: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((detail?.song?.isEmpty ?? true))

                    Button("Play Next") { playNext() }
                        .disabled((detail?.song?.isEmpty ?? true))
                    Button("Add to Queue") { addToQueue() }
                        .disabled((detail?.song?.isEmpty ?? true))

                    Button(action: toggleFavorite) {
                        Image(systemName: favorites.isAlbumFavorite(album.id) ? "heart.fill" : "heart")
                            .foregroundStyle(favorites.isAlbumFavorite(album.id) ? Color.pink : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(favorites.isAlbumFavorite(album.id) ? "Remove favorite" : "Add favorite")
                }
            }
            Spacer()
        }
        .padding(20)
    }

    private var cover: some View {
        CoverArtImage(coverArtID: album.coverArt, size: 400, client: auth.client)
    }

    @ViewBuilder
    private var tracks: some View {
        if isLoading && detail == nil {
            ProgressView().padding(40).frame(maxWidth: .infinity)
        } else if let err = loadError {
            Text(err).foregroundStyle(.red).padding(40)
        } else if let songs = detail?.song, !songs.isEmpty {
            TrackListView(songs: songs, onPlay: { idx in playSong(at: idx) })
        } else {
            Text("No tracks").foregroundStyle(.secondary).padding(40).frame(maxWidth: .infinity)
        }
    }

    private func load(refresh: Bool = false) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await library.albumDetail(id: album.id, client: client, refresh: refresh)
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func playAll() {
        guard let songs = detail?.song, let client = auth.client else { return }
        player.play(songs, startAt: 0, using: client)
    }

    private func playSong(at index: Int) {
        guard let songs = detail?.song, let client = auth.client else { return }
        player.play(songs, startAt: index, using: client)
    }

    private func playNext() {
        guard let songs = detail?.song, let client = auth.client else { return }
        player.playNext(songs, using: client)
    }

    private func addToQueue() {
        guard let songs = detail?.song, let client = auth.client else { return }
        player.appendToQueue(songs, using: client)
    }

    private func toggleFavorite() {
        guard let client = auth.client else { return }
        Task { await favorites.toggleAlbum(album.id, client: client) }
    }
}
