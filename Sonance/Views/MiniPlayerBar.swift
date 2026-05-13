import SwiftUI

/// Bottom inset every scroll view in the detail pane should reserve so its last items aren't
/// hidden under the mini-player bar. We compute this once so the bar's height and the
/// scroll-view inset stay in sync — if the mini-player ever changes height, update this
/// constant and every detail view gets the new inset automatically.
///
/// Breakdown for the current bar: 1 pt divider + 8 pt vertical padding (top) + 48 pt cover
/// height + 8 pt vertical padding (bottom) = 65 pt; we round up to 80 to leave a small
/// breathing margin between the last content row and the bar's edge.
let miniPlayerSafeAreaInset: CGFloat = 80

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
                        HoverLinkText(
                            text: song.title,
                            font: .callout,
                            color: .primary,
                            isEnabled: song.albumId != nil,
                            tooltip: song.albumId == nil ? nil : "Go to Album",
                            action: { goToAlbum(for: song) }
                        )
                        HoverLinkText(
                            text: song.artist ?? "",
                            font: .caption,
                            color: .secondary,
                            isEnabled: song.artistId != nil,
                            tooltip: song.artistId == nil ? nil : "Go to Artist",
                            action: { goToArtist(for: song) }
                        )
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

                    // Scrubber always fits inline; volume is a small popover button so it
                    // never disappears on narrow windows the way the prior ViewThatFits
                    // layout did.
                    HStack(spacing: 10) {
                        scrubber
                        VolumeButton(volume: $player.volume)
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

/// Always-visible volume control. Click the speaker icon to pop a horizontal slider; the
/// icon itself reflects the current volume level (mute / 1 / 2 / 3 bars) so the bar gives
/// the user a quick read on volume without opening the popover. Replaces the prior inline
/// slider that lived inside a `ViewThatFits` and silently disappeared on narrow windows.
struct VolumeButton: View {
    @Binding var volume: Float
    @State private var isPopoverShown = false
    /// Remembered pre-mute volume. Letting the user toggle mute via the slider's slash icon
    /// without losing where they were is friendlier than forcing them to drag back to the
    /// previous level.
    @State private var preMuteVolume: Float = 1.0

    var body: some View {
        Button {
            isPopoverShown.toggle()
        } label: {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Volume")
        .popover(isPresented: $isPopoverShown, arrowEdge: .top) {
            HStack(spacing: 10) {
                Button {
                    toggleMute()
                } label: {
                    Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                        .foregroundStyle(volume == 0 ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(volume == 0 ? "Unmute" : "Mute")

                Slider(value: $volume, in: 0...1)
                    .frame(width: 160)

                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(12)
        }
    }

    private var iconName: String {
        if volume <= 0 { return "speaker.slash" }
        if volume < 0.34 { return "speaker.wave.1" }
        if volume < 0.67 { return "speaker.wave.2" }
        return "speaker.wave.3"
    }

    private func toggleMute() {
        if volume > 0 {
            preMuteVolume = volume
            volume = 0
        } else {
            // Restore a sensible default even if pre-mute was never captured (fresh launch
            // with volume already 0 is unusual, but guard anyway).
            volume = preMuteVolume > 0 ? preMuteVolume : 1.0
        }
    }
}

/// Mini-player title/artist link. Underlines on hover so the click affordance is discoverable
/// (the prior buttons rendered identically to plain text — see TrackRow's NavigableLabel for
/// the same pattern; this variant lives outside a `List` so it uses a real `Button` for keyboard
/// + accessibility wiring).
struct HoverLinkText: View {
    let text: String
    let font: Font
    let color: Color
    let isEnabled: Bool
    let tooltip: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .underline(isEnabled && isHovered)
        }
        .buttonStyle(.plain)
        .help(tooltip ?? "")
        .disabled(!isEnabled)
        .onHover { hovering in
            guard isEnabled else { return }
            isHovered = hovering
        }
    }
}
