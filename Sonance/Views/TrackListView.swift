import SwiftUI

struct TrackListView: View {
    let songs: [Song]
    let onPlay: (Int) -> Void
    /// Render a small album cover thumbnail before the title on each row. Default on for
    /// mixed-source lists (search, favorites, discover, playlists) where covers vary per
    /// row and aid recognition. Album-detail call sites opt out (`showsCovers: false`)
    /// because every row would carry the same album thumbnail.
    var showsCovers: Bool = true

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var navigation: NavigationCoordinator
    /// Positional selection. A list of songs may legitimately contain the same `Song.id` more
    /// than once (e.g. smart playlists from `.nsp` rules), so keying on song identity would
    /// coalesce duplicate rows in SwiftUI's diffing.
    @State private var selectedPosition: Int?

    var body: some View {
        List(selection: $selectedPosition) {
            ForEach(Array(songs.enumerated()), id: \.offset) { idx, song in
                TrackRow(
                    index: trackNumberLabel(song: song, fallback: idx + 1),
                    song: song,
                    isCurrent: player.currentSong?.id == song.id,
                    isFavorite: favorites.isSongFavorite(song.id),
                    onToggleFavorite: { toggleFavorite(song) },
                    showsCover: showsCovers
                )
                .tag(idx)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onPlay(idx) }
                .draggable(song)
                .contextMenu {
                    Button("Play") { onPlay(idx) }
                    Button("Play Next") { playNext(song) }
                    Button("Add to Queue") { addToQueue(song) }
                    Divider()
                    Button("Go to Album") { goToAlbum(song) }
                        .disabled(song.albumId == nil)
                    Button("Go to Artist") { goToArtist(song) }
                        .disabled(song.artistId == nil)
                    Divider()
                    Button(favorites.isSongFavorite(song.id) ? "Remove Favorite" : "Add Favorite") {
                        toggleFavorite(song)
                    }
                }
            }
        }
        .listStyle(.inset)
        .onKeyPress(.return) {
            guard let idx = selectedPosition, idx >= 0, idx < songs.count else { return .ignored }
            onPlay(idx)
            return .handled
        }
    }

    private func goToAlbum(_ song: Song) {
        guard let album = albumStub(from: song) else { return }
        navigation.requestAlbumNavigation(album)
    }

    private func goToArtist(_ song: Song) {
        guard let artistId = song.artistId else { return }
        navigation.requestArtistNavigation(Artist(id: artistId, name: song.artist ?? "", coverArt: nil, albumCount: nil))
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
    /// See `TrackListView.showsCovers` for the rationale. When false the lead column shows
    /// the track number / play indicator (album-detail look). When true it shows a 36×36
    /// thumbnail with the play indicator overlaid on hover or while playing.
    var showsCover: Bool = false

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var navigation: NavigationCoordinator
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            leadIndicator

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                NavigableLabel(
                    text: song.artist ?? "—",
                    isEnabled: song.artistId != nil,
                    font: .caption,
                    tooltip: song.artistId == nil ? nil : "Go to Artist",
                    action: goToArtist
                )
            }

            Spacer()

            NavigableLabel(
                text: song.album ?? "—",
                isEnabled: song.albumId != nil,
                font: .callout,
                tooltip: song.albumId == nil ? nil : "Go to Album",
                action: goToAlbum
            )
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

    /// Lead column: either a 36-pt cover thumbnail with a play-state overlay, or the slim
    /// track-number / play-indicator column the album-detail look uses. Switching at this
    /// boundary keeps the rest of the row layout identical between modes.
    @ViewBuilder
    private var leadIndicator: some View {
        if showsCover {
            ZStack {
                CoverArtImage(coverArtID: song.coverArt, size: 96, client: auth.client, corner: 4)
                    .frame(width: 36, height: 36)
                if isCurrent || isHovered {
                    // Darken the cover so the white indicator glyph stays legible against
                    // bright artwork; current-track gets a slightly deeper veil so the
                    // accent color of the title is the dominant cue.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.black.opacity(isCurrent ? 0.55 : 0.45))
                        .frame(width: 36, height: 36)
                    Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.fill")
                        .foregroundStyle(.white)
                        .font(.callout)
                }
            }
            .frame(width: 36, height: 36)
        } else {
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
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func goToAlbum() {
        guard let album = albumStub(from: song) else { return }
        navigation.requestAlbumNavigation(album)
    }

    private func goToArtist() {
        guard let artistId = song.artistId else { return }
        navigation.requestArtistNavigation(Artist(id: artistId, name: song.artist ?? "", coverArt: nil, albumCount: nil))
    }
}

/// A `Text`-shaped label that becomes a tappable cross-link when enabled (with a hover-state
/// underline to advertise the affordance). Lives at file scope so any row/header can reuse it
/// without re-implementing the hover bookkeeping.
///
/// We deliberately don't use `Button` here: in `List` rows, a button inside a row fights with
/// the row's tap/double-tap/selection. A `Text` with `.onTapGesture` + `.contentShape` is
/// reliable inside `List` and behaves identically outside it.
struct NavigableLabel: View {
    let text: String
    let isEnabled: Bool
    let font: Font
    let tooltip: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .underline(isEnabled && isHovered)
            .contentShape(Rectangle())
            .help(tooltip ?? "")
            .onHover { hovering in
                guard isEnabled else { return }
                isHovered = hovering
            }
            .onTapGesture {
                guard isEnabled else { return }
                action()
            }
            .allowsHitTesting(isEnabled)
    }
}

func albumStub(from song: Song) -> Album? {
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
