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
                    if let count = trackCount {
                        Text("•").foregroundStyle(.secondary)
                        Text("\(count) track\(count == 1 ? "" : "s")")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let dur = totalDurationLabel {
                        Text("•").foregroundStyle(.secondary)
                        Text(dur).font(.callout).foregroundStyle(.secondary)
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
            let groups = discGroups(for: songs)
            if groups.count > 1 {
                MultiDiscTrackList(
                    groups: groups,
                    allSongs: songs,
                    onPlayAt: { idx in playSong(at: idx) }
                )
            } else {
                TrackListView(songs: songs, onPlay: { idx in playSong(at: idx) })
            }
        } else {
            Text("No tracks").foregroundStyle(.secondary).padding(40).frame(maxWidth: .infinity)
        }
    }

    private var trackCount: Int? {
        detail?.song?.count ?? album.songCount
    }

    private var totalDurationSeconds: Int? {
        if let songs = detail?.song {
            let sum = songs.compactMap(\.duration).reduce(0, +)
            return sum > 0 ? sum : (detail?.duration ?? album.duration)
        }
        return detail?.duration ?? album.duration
    }

    private var totalDurationLabel: String? {
        guard let seconds = totalDurationSeconds, seconds > 0 else { return nil }
        let totalMinutes = (seconds + 30) / 60
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }

    /// Group songs by `discNumber`. Songs without a disc number land in disc 1. Returns a list
    /// of `(disc, songs)` in ascending disc order; if all songs share a single (effective) disc
    /// the caller treats the album as single-disc.
    private func discGroups(for songs: [Song]) -> [(Int, [Song])] {
        var byDisc: [Int: [Song]] = [:]
        for song in songs {
            byDisc[song.discNumber ?? 1, default: []].append(song)
        }
        return byDisc.keys.sorted().map { ($0, byDisc[$0] ?? []) }
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

/// Sectioned list of tracks for multi-disc albums. Reuses `TrackRow` for row visuals and
/// translates per-disc taps back to the global song index so playback uses the same flat
/// queue as a single-disc album.
struct MultiDiscTrackList: View {
    let groups: [(Int, [Song])]
    let allSongs: [Song]
    let onPlayAt: (Int) -> Void
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @State private var selectedSongID: Song.ID?

    var body: some View {
        List(selection: $selectedSongID) {
            ForEach(groups, id: \.0) { disc, songsInDisc in
                Section {
                    ForEach(songsInDisc) { song in
                        let globalIdx = allSongs.firstIndex(where: { $0.id == song.id }) ?? 0
                        TrackRow(
                            index: song.track ?? (globalIdx + 1),
                            song: song,
                            isCurrent: player.currentSong?.id == song.id,
                            isFavorite: favorites.isSongFavorite(song.id),
                            onToggleFavorite: { toggleFavorite(song) }
                        )
                        .tag(song.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { onPlayAt(globalIdx) }
                        .contextMenu {
                            Button("Play") { onPlayAt(globalIdx) }
                            Button("Play Next") { playNext(song) }
                            Button("Add to Queue") { addToQueue(song) }
                            Divider()
                            Button(favorites.isSongFavorite(song.id) ? "Remove Favorite" : "Add Favorite") {
                                toggleFavorite(song)
                            }
                        }
                    }
                } header: {
                    Text("Disc \(disc)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.inset)
        .onKeyPress(.return) {
            guard let id = selectedSongID,
                  let idx = allSongs.firstIndex(where: { $0.id == id }) else { return .ignored }
            onPlayAt(idx)
            return .handled
        }
    }

    private func toggleFavorite(_ song: Song) {
        guard let client = auth.client else { return }
        Task { await favorites.toggleSong(song.id, client: client) }
    }

    private func playNext(_ song: Song) {
        guard let client = auth.client else { return }
        player.playNext([song], using: client)
    }

    private func addToQueue(_ song: Song) {
        guard let client = auth.client else { return }
        player.appendToQueue([song], using: client)
    }
}
