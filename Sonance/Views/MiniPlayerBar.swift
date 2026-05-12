import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var favorites: FavoritesStore
    @Binding var showingNowPlaying: Bool

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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.callout).lineLimit(1)
                        Text(song.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
