import SwiftUI

struct TrackListView: View {
    let songs: [Song]
    let onPlay: (Int) -> Void

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @State private var selectedSongID: Song.ID?

    var body: some View {
        List(selection: $selectedSongID) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                TrackRow(
                    index: trackNumberLabel(song: song, fallback: idx + 1),
                    song: song,
                    isCurrent: player.currentSong?.id == song.id,
                    isFavorite: favorites.isSongFavorite(song.id),
                    onToggleFavorite: { toggleFavorite(song) }
                )
                .tag(song.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onPlay(idx) }
                .draggable(song)
                .contextMenu {
                    Button("Play") { onPlay(idx) }
                    Button("Play Next") { playNext(song) }
                    Button("Add to Queue") { addToQueue(song) }
                    Divider()
                    Button(favorites.isSongFavorite(song.id) ? "Remove Favorite" : "Add Favorite") {
                        toggleFavorite(song)
                    }
                }
            }
        }
        .listStyle(.inset)
        .onKeyPress(.return) {
            guard let id = selectedSongID,
                  let idx = songs.firstIndex(where: { $0.id == id }) else { return .ignored }
            onPlay(idx)
            return .handled
        }
    }

    /// Server-reported track number when available, otherwise the row's position in the list.
    private func trackNumberLabel(song: Song, fallback: Int) -> Int {
        song.track ?? fallback
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

struct TrackRow: View {
    let index: Int
    let song: Song
    let isCurrent: Bool
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.accentColor)
                } else if isHovered {
                    Image(systemName: "play.fill").foregroundStyle(.secondary)
                } else {
                    Text("\(index)").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .monospacedDigit()
            .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                Text(song.artist ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(song.album ?? "—")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .leading)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? Color.pink : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "Remove favorite" : "Add favorite")

            Text(formatDuration(song.duration ?? 0))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
