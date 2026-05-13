import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var navigation: NavigationCoordinator
    @Binding var showingNowPlaying: Bool
    @State private var actionError: String?

    var body: some View {
        if let song = player.currentSong {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    Button {
                        showingNowPlaying.toggle()
                    } label: {
                        cover(for: song)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.borderless)
                    .help(showingNowPlaying ? "Hide Now Playing" : "Show Now Playing")
                    .contextMenu { coverContextMenu(for: song) }

                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            goToAlbum(for: song)
                        } label: {
                            Text(song.title).font(.callout).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help(song.albumId == nil ? "" : "Go to Album")
                        .disabled(song.albumId == nil)

                        Button {
                            goToArtist(for: song)
                        } label: {
                            Text(song.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help(song.artistId == nil ? "" : "Go to Artist")
                        .disabled(song.artistId == nil)
                    }
                    .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
                    .layoutPriority(2)

                    Button {
                        if let c = auth.client {
                            Task { await favorites.toggleSong(song.id, client: c) }
                        }
                    } label: {
                        Image(systemName: favorites.isSongFavorite(song.id) ? "heart.fill" : "heart")
                            .foregroundStyle(favorites.isSongFavorite(song.id) ? Color.pink : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(favorites.isSongFavorite(song.id) ? "Remove favorite" : "Add favorite")

                    HStack(spacing: 8) {
                        Button { player.toggleShuffle() } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(player.isShuffled ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Shuffle")
                        Button { player.previous() } label: { Image(systemName: "backward.fill") }
                            .buttonStyle(.borderless)
                        Button { player.togglePlayPause() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        Button { player.next() } label: { Image(systemName: "forward.fill") }
                            .buttonStyle(.borderless)
                        Button { player.cycleRepeat() } label: {
                            Image(systemName: player.repeatMode.systemImage)
                                .foregroundStyle(player.repeatMode == .off ? .secondary : Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .help("Repeat: \(player.repeatMode.rawValue)")
                    }
                    .layoutPriority(3)

                    Spacer(minLength: 6)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            scrubber
                            volume
                        }
                        scrubber
                    }
                    .layoutPriority(1)
                    .frame(maxWidth: 360)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .alert("Action Failed", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    @ViewBuilder
    private func coverContextMenu(for song: Song) -> some View {
        Button("Play Next on Album") { Task { await playNextOnAlbum(for: song) } }
            .disabled(song.albumId == nil)
        Divider()
        Button("Go to Album") { goToAlbum(for: song) }
            .disabled(song.albumId == nil)
        Button("Go to Artist") { goToArtist(for: song) }
            .disabled(song.artistId == nil)
        Button("Show in Library") {
            navigation.revealInLibrary(album: albumStub(for: song))
        }
    }

    private func goToAlbum(for song: Song) {
        guard let album = albumStub(for: song) else { return }
        navigation.requestAlbumNavigation(album)
    }

    private func goToArtist(for song: Song) {
        guard let artistId = song.artistId else { return }
        let artist = Artist(id: artistId, name: song.artist ?? "", coverArt: nil, albumCount: nil)
        navigation.requestArtistNavigation(artist)
    }

    private func albumStub(for song: Song) -> Album? {
        guard let id = song.albumId else { return nil }
        return Album(
            id: id,
            name: song.album ?? "",
            artist: song.artist,
            artistId: song.artistId,
            coverArt: song.coverArt,
            songCount: nil,
            duration: nil,
            year: nil,
            starred: nil
        )
    }

    private func playNextOnAlbum(for song: Song) async {
        guard let client = auth.client, let albumId = song.albumId else { return }
        do {
            let songs = try await library.albumDetail(id: albumId, client: client).song ?? []
            guard !songs.isEmpty else { return }
            player.playNext(songs, using: client)
        } catch {
            actionError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }

    private var scrubber: some View {
        HStack(spacing: 6) {
            Text(formatTime(player.currentTime))
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 0.1)
            )
            .frame(minWidth: 120, idealWidth: 180, maxWidth: 240)
            Text(formatTime(player.duration))
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 36, alignment: .leading)
        }
    }

    private var volume: some View {
        HStack(spacing: 4) {
            Image(systemName: player.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                .foregroundStyle(.secondary)
                .font(.caption)
            Slider(value: $player.volume, in: 0...1).frame(width: 70)
        }
    }

    private func cover(for song: Song) -> some View {
        CoverArtImage(coverArtID: song.coverArt, size: 96, client: auth.client, corner: 4)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
