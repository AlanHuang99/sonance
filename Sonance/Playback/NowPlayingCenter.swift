import AppKit
import MediaPlayer

/// Bridges `Player` to `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` so macOS Control
/// Center, the menu-bar Now Playing widget, AirPods double-tap, and external keyboard media
/// keys all see and steer Sonance.
@MainActor
final class NowPlayingCenter {
    static let shared = NowPlayingCenter()

    private weak var player: Player?
    private var commandsRegistered = false
    private var artworkLoadingKey: String?
    private var artworkTask: Task<Void, Never>?
    /// Stable `(album, coverArt)` identifier of the artwork last published. Lets us avoid
    /// re-fetching the bitmap when the user pauses/seeks within the same track.
    private var publishedArtworkKey: String?

    private init() {}

    /// Hook the singleton up to the live `Player`. Idempotent.
    func attach(player: Player) {
        self.player = player
        registerCommandsIfNeeded()
    }

    /// Push full metadata (title, artist, album, duration, elapsed, rate) and refresh artwork.
    func update(song: Song?, isPlaying: Bool, elapsed: TimeInterval, duration: TimeInterval, client: SubsonicClient?) {
        guard let song else {
            clear()
            return
        }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = song.album ?? ""
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused

        refreshArtwork(for: song, client: client)
    }

    /// Update only the rate/elapsed anchor (e.g. on play/pause toggle or after a seek). Keeps
    /// the existing title/artwork so Control Center doesn't flash.
    func updatePlaybackAnchor(isPlaying: Bool, elapsed: TimeInterval) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        guard !info.isEmpty else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkLoadingKey = nil
        publishedArtworkKey = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // MARK: - Artwork

    private func refreshArtwork(for song: Song, client: SubsonicClient?) {
        guard let coverArtID = song.coverArt, let client else {
            // Track without artwork — drop any stale artwork from prior song.
            if publishedArtworkKey != nil {
                publishedArtworkKey = nil
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = nil
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
            return
        }
        let key = "\(client.credentials.accountID)|\(coverArtID)"
        if publishedArtworkKey == key { return }
        if artworkLoadingKey == key { return }
        artworkLoadingKey = key

        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            let image = await CoverArtCache.shared.image(for: coverArtID, size: 600, client: client)
            await MainActor.run {
                guard let self else { return }
                guard self.artworkLoadingKey == key else { return }
                self.artworkLoadingKey = nil
                guard let image else { return }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                self.publishedArtworkKey = key
            }
        }
    }

    // MARK: - Remote commands

    private func registerCommandsIfNeeded() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let player = self?.player else { return .commandFailed }
            if !player.isPlaying { player.togglePlayPause() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let player = self?.player else { return .commandFailed }
            if player.isPlaying { player.togglePlayPause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let player = self?.player else { return .commandFailed }
            player.togglePlayPause()
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let player = self?.player else { return .commandFailed }
            player.next()
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let player = self?.player else { return .commandFailed }
            player.previous()
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let player = self?.player,
                  let pos = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            player.seek(to: pos.positionTime)
            return .success
        }

        // Disable commands we don't support so the UI doesn't show them as available.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.ratingCommand.isEnabled = false
        center.changeRepeatModeCommand.isEnabled = false
        center.changeShuffleModeCommand.isEnabled = false
    }
}
