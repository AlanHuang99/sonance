import Foundation
import AVFoundation
import Combine

enum RepeatMode: String, CaseIterable {
    case off, all, one
    var systemImage: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

@MainActor
final class Player: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var queue: [Song] = []
    @Published private(set) var queueIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 {
        didSet { avPlayer.volume = max(0, min(1, volume)) }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var isShuffled: Bool = false

    /// Snapshot of the queue order before shuffle, used to restore on un-shuffle.
    private var unshuffledQueue: [Song] = []

    private let avPlayer = AVQueuePlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var activeClient: SubsonicClient?
    private var hasScrobbledCurrent: Bool = false
    private var lastSavedSecond: Int = -1
    private var pendingSaveTask: Task<Void, Never>?
    /// One-deep preload for gapless transitions. When the current track is within 10 s of its end
    /// and we know what's next, the corresponding `AVPlayerItem` is inserted into the
    /// `AVQueuePlayer` so playback continues without re-loading at the boundary.
    private var preloadedNextItem: AVPlayerItem?
    private var preloadedNextIndex: Int?
    private static let stateKey = "sonance.playerState"

    private struct PersistedState: Codable {
        let queue: [Song]
        let queueIndex: Int
        let currentTime: TimeInterval
        let isShuffled: Bool
        let unshuffledQueue: [Song]
        let repeatMode: String
        let volume: Float
    }

    init() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let t = time.seconds
                self.currentTime = (t.isFinite && t >= 0) ? t : 0
                if let item = self.avPlayer.currentItem {
                    let d = item.duration.seconds
                    if d.isFinite, d > 0, abs(d - self.duration) > 0.1 {
                        self.duration = d
                        // Asset just became durationally known — refresh Now Playing.
                        self.syncNowPlaying()
                    }
                }
                // Submission scrobble at 50% (or 4 minutes), per Subsonic convention.
                if !self.hasScrobbledCurrent,
                   self.duration > 30,
                   self.currentTime >= min(self.duration * 0.5, 240),
                   let song = self.currentSong,
                   let client = self.activeClient {
                    self.hasScrobbledCurrent = true
                    Task.detached { await Self.scrobble(songID: song.id, submission: true, client: client) }
                }
                // Preload the next track when within 10 s of the current track's end so
                // AVQueuePlayer can advance with no audible gap.
                if self.duration > 0, self.duration - self.currentTime <= 10 {
                    self.preloadNextIfNeeded()
                }
                // Persist playhead state every 3 seconds; queue mutations save immediately.
                let sec = Int(self.currentTime)
                if sec != self.lastSavedSecond, sec % 3 == 0 {
                    self.lastSavedSecond = sec
                    self.scheduleStateSave()
                }
            }
        }
        NowPlayingCenter.shared.attach(player: self)
    }

    private func syncNowPlaying() {
        NowPlayingCenter.shared.update(
            song: currentSong,
            isPlaying: isPlaying,
            elapsed: currentTime,
            duration: duration,
            client: activeClient
        )
    }

    func restorePaused(client: SubsonicClient) {
        guard currentSong == nil else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data),
              !state.queue.isEmpty else { return }
        activeClient = client
        queue = state.queue
        unshuffledQueue = state.unshuffledQueue
        queueIndex = max(0, min(state.queueIndex, state.queue.count - 1))
        currentSong = state.queue[queueIndex]
        duration = TimeInterval(currentSong?.duration ?? 0)
        currentTime = state.currentTime
        isShuffled = state.isShuffled
        repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off
        volume = state.volume
        avPlayer.volume = volume
        isPlaying = false  // user must press play to actually start
        syncNowPlaying()
    }

    private func saveState() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        let state = PersistedState(
            queue: queue,
            queueIndex: queueIndex,
            currentTime: currentTime,
            isShuffled: isShuffled,
            unshuffledQueue: unshuffledQueue,
            repeatMode: repeatMode.rawValue,
            volume: volume
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    private func scheduleStateSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.saveState() }
        }
    }

    private func clearSavedState() {
        UserDefaults.standard.removeObject(forKey: Self.stateKey)
    }

    deinit {
        if let timeObserver { avPlayer.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    // MARK: - Play actions

    func play(_ songs: [Song], startAt index: Int = 0, using client: SubsonicClient) {
        guard !songs.isEmpty else { return }
        activeClient = client
        let state = PlaybackQueueLogic.replaceQueue(songs, startAt: index)
        queue = state.queue
        unshuffledQueue = state.unshuffled
        isShuffled = false
        queueIndex = state.index
        playCurrent()
    }

    func playNext(_ songs: [Song], using client: SubsonicClient) {
        activeClient = client
        if queue.isEmpty {
            play(songs, startAt: 0, using: client)
            return
        }
        PlaybackQueueLogic.playNext(songs, queue: &queue, queueIndex: queueIndex, isShuffled: isShuffled, unshuffledQueue: &unshuffledQueue)
        clearPreload()
        saveState()
    }

    func appendToQueue(_ songs: [Song], using client: SubsonicClient) {
        activeClient = client
        if queue.isEmpty {
            play(songs, startAt: 0, using: client)
            return
        }
        PlaybackQueueLogic.append(songs, queue: &queue, isShuffled: isShuffled, unshuffledQueue: &unshuffledQueue)
        clearPreload()
        saveState()
    }

    /// Insert the given songs at the given index in the user-facing queue. If the queue is
    /// empty, falls back to `play(songs:startAt:0)`. Indices outside the queue are clamped.
    /// Used by the Now Playing queue's drag-and-drop target.
    func insert(_ songs: [Song], at index: Int, using client: SubsonicClient) {
        activeClient = client
        if queue.isEmpty {
            play(songs, startAt: 0, using: client)
            return
        }
        let i = max(0, min(index, queue.count))
        queue.insert(contentsOf: songs, at: i)
        if isShuffled {
            // Append the inserted tracks to the pre-shuffle snapshot too so toggling shuffle
            // off later doesn't restore from a stale snapshot that drops them. The shuffled
            // queue has a precise insertion index, but the unshuffled order has no canonical
            // home for tracks added after shuffling started — appending at the end is the
            // conservative choice.
            unshuffledQueue.append(contentsOf: songs)
        } else {
            unshuffledQueue = queue
        }
        if i <= queueIndex { queueIndex += songs.count }
        clearPreload()
        saveState()
    }

    func jumpTo(_ index: Int) {
        guard index >= 0, index < queue.count else { return }
        queueIndex = index
        playCurrent()
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        let result = PlaybackQueueLogic.remove(at: index, queue: &queue, queueIndex: &queueIndex, isShuffled: isShuffled, unshuffledQueue: &unshuffledQueue)
        clearPreload()
        switch result {
        case .unchanged:
            break
        case .playCurrent:
            playCurrent()
        case .stopped:
            stop()
        }
        saveState()
    }

    func moveQueueItem(from source: Int, to destination: Int) {
        guard source >= 0, source < queue.count, destination >= 0, destination <= queue.count, source != destination else { return }
        PlaybackQueueLogic.move(from: source, to: destination, queue: &queue, queueIndex: &queueIndex, isShuffled: isShuffled, unshuffledQueue: &unshuffledQueue)
        clearPreload()
        saveState()
    }

    func clearQueue() {
        stop()
        queue = []
        unshuffledQueue = []
        queueIndex = 0
        clearSavedState()
    }

    func togglePlayPause() {
        guard currentSong != nil else { return }
        if avPlayer.currentItem == nil {
            // Restored-from-state but not yet started — load the item and seek to saved position.
            playCurrent(startAt: currentTime > 0 ? currentTime : nil)
            return
        }
        if isPlaying {
            avPlayer.pause()
            isPlaying = false
        } else {
            avPlayer.play()
            isPlaying = true
        }
        NowPlayingCenter.shared.updatePlaybackAnchor(isPlaying: isPlaying, elapsed: currentTime)
    }

    func next() { advanceOrStop() }

    func previous() {
        if currentTime > 3 {
            avPlayer.seek(to: .zero)
        } else if queueIndex > 0 {
            queueIndex -= 1
            playCurrent()
        } else {
            avPlayer.seek(to: .zero)
        }
    }

    func seek(to seconds: TimeInterval) {
        avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000))
        currentTime = seconds
        NowPlayingCenter.shared.updatePlaybackAnchor(isPlaying: isPlaying, elapsed: seconds)
    }

    func stop() {
        avPlayer.pause()
        clearPreload()
        avPlayer.removeAllItems()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        currentSong = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        hasScrobbledCurrent = false
        NowPlayingCenter.shared.clear()
    }

    // MARK: - Repeat / Shuffle

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        clearPreload()
        saveState()
    }

    func toggleShuffle() {
        PlaybackQueueLogic.toggleShuffle(queue: &queue, queueIndex: &queueIndex, isShuffled: &isShuffled, unshuffledQueue: &unshuffledQueue, currentSong: currentSong)
        clearPreload()
        saveState()
    }

    // MARK: - Internal

    private func playCurrent(startAt resumeTime: TimeInterval? = nil) {
        guard queueIndex >= 0, queueIndex < queue.count, let client = activeClient else {
            stop()
            return
        }
        let song = queue[queueIndex]
        currentSong = song
        hasScrobbledCurrent = false
        guard let url = client.streamURL(id: song.id) else { return }
        let item = AVPlayerItem(url: url)
        clearPreload()
        avPlayer.removeAllItems()
        installEndObserver(for: item)
        avPlayer.insert(item, after: nil)
        avPlayer.volume = volume
        if let resumeTime, resumeTime > 0 {
            currentTime = resumeTime
            Task { @MainActor in
                await avPlayer.seek(to: CMTime(seconds: resumeTime, preferredTimescale: 1000))
                avPlayer.play()
            }
        } else {
            currentTime = 0
            avPlayer.play()
        }
        isPlaying = true
        duration = TimeInterval(song.duration ?? 0)
        saveState()
        syncNowPlaying()

        // "Now playing" scrobble
        Task.detached { await Self.scrobble(songID: song.id, submission: false, client: client) }
    }

    private func installEndObserver(for item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnd() }
        }
    }

    private func preloadNextIfNeeded() {
        guard repeatMode != .one else { return }
        guard let client = activeClient else { return }
        guard let nextIdx = PlaybackQueueLogic.nextIndex(queue: queue, queueIndex: queueIndex, repeatMode: repeatMode) else { return }
        if preloadedNextIndex == nextIdx, preloadedNextItem != nil { return }
        clearPreload()
        let song = queue[nextIdx]
        guard let url = client.streamURL(id: song.id) else { return }
        let item = AVPlayerItem(url: url)
        guard avPlayer.canInsert(item, after: avPlayer.currentItem) else { return }
        avPlayer.insert(item, after: avPlayer.currentItem)
        preloadedNextItem = item
        preloadedNextIndex = nextIdx
    }

    private func clearPreload() {
        if let item = preloadedNextItem {
            avPlayer.remove(item)
        }
        preloadedNextItem = nil
        preloadedNextIndex = nil
    }

    private func handleTrackEnd() {
        switch repeatMode {
        case .one:
            // AVQueuePlayer pops the played-to-end item from its queue, so a plain
            // `seek(to: .zero)` would no-op against a nil currentItem. Re-load the same
            // queueIndex to start a fresh playback.
            playCurrent()
        case .all, .off:
            // Gapless path: AVQueuePlayer has already advanced to the preloaded item if we
            // preloaded it. Roll our model forward to match. (Queue mutations clear the
            // preload, so reaching this branch means the preloaded next is still authoritative.)
            if let nextIdx = preloadedNextIndex, let preloaded = preloadedNextItem,
               nextIdx < queue.count {
                queueIndex = nextIdx
                let song = queue[queueIndex]
                currentSong = song
                hasScrobbledCurrent = false
                preloadedNextItem = nil
                preloadedNextIndex = nil
                installEndObserver(for: preloaded)
                duration = TimeInterval(song.duration ?? 0)
                currentTime = 0
                isPlaying = true
                syncNowPlaying()
                if let client = activeClient {
                    Task.detached { await Self.scrobble(songID: song.id, submission: false, client: client) }
                }
                saveState()
            } else {
                advanceOrStop()
            }
        }
    }

    private func advanceOrStop() {
        if let next = PlaybackQueueLogic.nextIndex(queue: queue, queueIndex: queueIndex, repeatMode: repeatMode) {
            queueIndex = next
            playCurrent()
        } else {
            stop()
        }
    }

    private nonisolated static func scrobble(songID: String, submission: Bool, client: SubsonicClient) async {
        do {
            try await client.scrobble(songID: songID, submission: submission)
        } catch {
            #if DEBUG
            NSLog("Sonance scrobble failed: %@", (error as? SubsonicError)?.message ?? error.localizedDescription)
            #endif
        }
    }
}
