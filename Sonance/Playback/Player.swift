import Foundation
import AVFoundation
import Combine
import os

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
    @Published private(set) var isBuffering: Bool = false
    @Published private(set) var playbackError: String?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 {
        didSet { avPlayer.volume = max(0, min(1, volume)) }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var isShuffled: Bool = false

    /// Snapshot of the queue order before shuffle, used to restore on un-shuffle.
    private var unshuffledQueue: [Song] = []

    private let avPlayer: AVQueuePlayer
    private let userDefaults: UserDefaults
    private let makePlayerItem: (URL) -> AVPlayerItem
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var playbackStatusObserver: NSKeyValueObservation?
    private var currentItemObserver: NSKeyValueObservation?
    /// Keep identity even when AVQueuePlayer removes a failed/finished item.
    private var activeItem: AVPlayerItem?
    private var recoveryTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var recoveryAttempts = 0
    private let logger = Logger(subsystem: "com.alanhuang.Sonance", category: "Playback")
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

    init(
        avPlayer: AVQueuePlayer = AVQueuePlayer(),
        userDefaults: UserDefaults = .standard,
        makePlayerItem: @escaping (URL) -> AVPlayerItem = { AVPlayerItem(url: $0) }
    ) {
        self.avPlayer = avPlayer
        self.userDefaults = userDefaults
        self.makePlayerItem = makePlayerItem
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        currentItemObserver = avPlayer.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.reconcileAutomaticAdvance() }
        }
        playbackStatusObserver = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isBuffering = self.isPlaying && self.avPlayer.timeControlStatus != .playing
                NowPlayingCenter.shared.updatePlaybackAnchor(
                    isPlaying: self.isPlaying && !self.isBuffering, elapsed: self.currentTime
                )
            }
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let item = self?.avPlayer.currentItem
            Task { @MainActor in
                guard let self, let item, item === self.activeItem,
                      self.avPlayer.currentItem === item, self.resumeTask == nil else { return }
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
            isPlaying: isPlaying && !isBuffering,
            elapsed: currentTime,
            duration: duration,
            client: activeClient
        )
    }

    func restorePaused(client: SubsonicClient) {
        guard currentSong == nil else { return }
        guard let data = userDefaults.data(forKey: Self.stateKey),
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
        NowPlayingCenter.shared.syncRepeatShuffle()
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
            userDefaults.set(data, forKey: Self.stateKey)
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
        userDefaults.removeObject(forKey: Self.stateKey)
    }

    deinit {
        recoveryTask?.cancel()
        resumeTask?.cancel()
        if let timeObserver { avPlayer.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
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
        reconcileAutomaticAdvance()
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
        reconcileAutomaticAdvance()
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
        reconcileAutomaticAdvance()
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
        reconcileAutomaticAdvance()
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
        reconcileAutomaticAdvance()
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
        reconcileAutomaticAdvance()
        guard currentSong != nil else { return }
        if isPlaying {
            resumeTask?.cancel()
            resumeTask = nil
            recoveryTask?.cancel()
            recoveryTask = nil
            avPlayer.pause()
            isPlaying = false
            isBuffering = false
        } else if avPlayer.currentItem == nil {
            // Restored state or a terminal failure: retry at the saved position.
            playCurrent(startAt: currentTime > 0 ? currentTime : nil)
            return
        } else {
            avPlayer.play()
            isPlaying = true
        }
        NowPlayingCenter.shared.updatePlaybackAnchor(isPlaying: isPlaying, elapsed: currentTime)
    }

    func next() {
        reconcileAutomaticAdvance()
        advanceOrStop()
    }

    func previous() {
        reconcileAutomaticAdvance()
        if currentTime > 3 {
            seek(to: 0)
        } else if queueIndex > 0 {
            queueIndex -= 1
            playCurrent()
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: TimeInterval) {
        reconcileAutomaticAdvance()
        guard seconds.isFinite else { return }
        resumeTask?.cancel()
        resumeTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        let seconds = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = seconds
        if avPlayer.currentItem != nil { seekCurrentItem(to: seconds) }
        NowPlayingCenter.shared.updatePlaybackAnchor(isPlaying: isPlaying, elapsed: seconds)
    }

    func stop() {
        resumeTask?.cancel()
        resumeTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        activeItem = nil
        removeItemObservers()
        avPlayer.pause()
        clearPreload()
        avPlayer.removeAllItems()
        currentSong = nil
        isPlaying = false
        isBuffering = false
        playbackError = nil
        currentTime = 0
        duration = 0
        hasScrobbledCurrent = false
        NowPlayingCenter.shared.clear()
    }

    // MARK: - Repeat / Shuffle

    func cycleRepeat() {
        reconcileAutomaticAdvance()
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        clearPreload()
        saveState()
        NowPlayingCenter.shared.syncRepeatShuffle()
    }

    func toggleShuffle() {
        reconcileAutomaticAdvance()
        PlaybackQueueLogic.toggleShuffle(queue: &queue, queueIndex: &queueIndex, isShuffled: &isShuffled, unshuffledQueue: &unshuffledQueue, currentSong: currentSong)
        clearPreload()
        saveState()
        NowPlayingCenter.shared.syncRepeatShuffle()
    }

    // MARK: - Internal

    private func playCurrent(startAt resumeTime: TimeInterval? = nil, recovering: Bool = false, shouldPlay: Bool = true) {
        guard queueIndex >= 0, queueIndex < queue.count, let client = activeClient else {
            stop()
            return
        }
        let song = queue[queueIndex]
        resumeTask?.cancel()
        resumeTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        activeItem = nil
        removeItemObservers()
        currentSong = song
        if !recovering {
            recoveryAttempts = 0
            hasScrobbledCurrent = false
        }
        playbackError = nil
        guard let url = client.streamURL(id: song.id) else {
            isPlaying = false
            isBuffering = false
            playbackError = "Unable to open this track. Check the server address and try again."
            return
        }
        let item = makePlayerItem(url)
        clearPreload()
        avPlayer.removeAllItems()
        installEndObserver(for: item)
        avPlayer.insert(item, after: nil)
        avPlayer.volume = volume
        isPlaying = shouldPlay
        isBuffering = shouldPlay
        if let resumeTime, resumeTime > 0 {
            currentTime = resumeTime
            seekCurrentItem(to: resumeTime)
        } else {
            currentTime = 0
            if shouldPlay { avPlayer.play() }
            else { avPlayer.pause() }
        }
        duration = TimeInterval(song.duration ?? 0)
        saveState()
        syncNowPlaying()

        // "Now playing" scrobble
        if !recovering {
            Task.detached { await Self.scrobble(songID: song.id, submission: false, client: client) }
        }
    }

    private func seekCurrentItem(to seconds: TimeInterval) {
        guard let item = avPlayer.currentItem else { return }
        resumeTask?.cancel()
        resumeTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.activeItem === item,
                  self.avPlayer.currentItem === item else { return }
            let finished = await self.avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000))
            guard !Task.isCancelled, self.activeItem === item, self.avPlayer.currentItem === item else { return }
            self.resumeTask = nil
            guard finished else {
                self.handlePlaybackFailure(for: item, error: item.error as NSError?)
                return
            }
            if self.isPlaying { self.avPlayer.play() }
        }
    }

    private func installEndObserver(for item: AVPlayerItem) {
        removeItemObservers()
        activeItem = item
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeItem === item else { return }
                self.handleTrackEnd()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            Task { @MainActor in self?.handlePlaybackFailure(for: item, error: error) }
        }
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackStall(for: item) }
        }
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard item.status == .failed else { return }
                self?.handlePlaybackFailure(for: item, error: item.error as NSError?)
            }
        }
    }

    private func removeItemObservers() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        endObserver = nil
        failureObserver = nil
        stallObserver = nil
        itemStatusObserver = nil
    }

    private func handlePlaybackFailure(for item: AVPlayerItem, error: NSError?) {
        guard activeItem === item else { return }
        // Error descriptions and AVAsset URLs can contain Subsonic authentication tokens.
        // Record only domain/code and state, never a stream URL or arbitrary userInfo.
        logger.error("Playback failed: domain=\(error?.domain ?? "unknown", privacy: .public) code=\(error?.code ?? 0) position=\(self.currentTime) recoveryAttempts=\(self.recoveryAttempts)")
        if isPlaying, recoveryAttempts < 1 {
            recoveryAttempts += 1
            playCurrent(startAt: currentTime, recovering: true)
            return
        }
        resumeTask?.cancel()
        resumeTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        activeItem = nil
        removeItemObservers()
        avPlayer.pause()
        clearPreload()
        avPlayer.removeAllItems()
        isPlaying = false
        isBuffering = false
        playbackError = "Playback stopped. Check your connection and audio output, then press Play to retry."
        NowPlayingCenter.shared.updatePlaybackAnchor(isPlaying: false, elapsed: currentTime)
        saveState()
    }

    private func handlePlaybackStall(for item: AVPlayerItem) {
        guard activeItem === item, isPlaying else { return }
        // Each stall gets a deadline from its own playhead. Progress between two stalls
        // must not cause an older watchdog to suppress recovery for the newer stall.
        recoveryTask?.cancel()
        recoveryTask = nil
        logger.notice("Playback stalled at \(self.currentTime)")
        isBuffering = true
        let stalledTime = item.currentTime().seconds
        // A file stream may pause when its buffer empties. Reassert playback intent so
        // AVPlayer resumes as data arrives, while allowing its normal buffering policy.
        avPlayer.play()
        recoveryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) }
            catch { return }
            guard let self, !Task.isCancelled, self.activeItem === item, self.isPlaying else { return }
            self.recoveryTask = nil
            let time = item.currentTime().seconds
            self.isBuffering = self.isPlaying && self.avPlayer.timeControlStatus != .playing
            guard !time.isFinite || !stalledTime.isFinite || time <= stalledTime + 0.1 else { return }
            self.handlePlaybackFailure(for: item, error: nil)
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
        let item = makePlayerItem(url)
        guard avPlayer.canInsert(item, after: avPlayer.currentItem) else { return }
        avPlayer.insert(item, after: avPlayer.currentItem)
        preloadedNextItem = item
        preloadedNextIndex = nextIdx
    }

    private func clearPreload() {
        if let item = preloadedNextItem, item !== avPlayer.currentItem {
            // Per Apple: `AVQueuePlayer.remove(_:)` on the currently playing item is
            // equivalent to `advanceToNextItem()`. If `AVQueuePlayer` has already advanced
            // to the preloaded item at the track boundary but `handleTrackEnd` hasn't run
            // yet to clear our markers, calling `remove` here would silently skip the new
            // track. Public queue actions reconcile the model before clearing the preload.
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
            playCurrent(shouldPlay: isPlaying)
        case .all, .off:
            if !reconcileAutomaticAdvance() { advanceOrStop(shouldPlay: isPlaying) }
        }
    }

    /// Reconcile by item identity before a user action can invalidate preload indices.
    /// KVO and end notifications may both arrive; clearing the markers makes this idempotent.
    @discardableResult
    private func reconcileAutomaticAdvance() -> Bool {
        guard let item = preloadedNextItem, avPlayer.currentItem === item,
              let index = preloadedNextIndex, queue.indices.contains(index) else { return false }
        resumeTask?.cancel()
        resumeTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        preloadedNextItem = nil
        preloadedNextIndex = nil
        queueIndex = index
        let song = queue[index]
        currentSong = song
        hasScrobbledCurrent = false
        recoveryAttempts = 0
        playbackError = nil
        installEndObserver(for: item)
        duration = TimeInterval(song.duration ?? 0)
        let time = item.currentTime().seconds
        currentTime = time.isFinite ? max(0, time) : 0
        if !isPlaying { avPlayer.pause() }
        isBuffering = isPlaying && avPlayer.timeControlStatus != .playing
        syncNowPlaying()
        if let client = activeClient {
            Task.detached { await Self.scrobble(songID: song.id, submission: false, client: client) }
        }
        saveState()
        return true
    }

    private func advanceOrStop(shouldPlay: Bool = true) {
        if let next = PlaybackQueueLogic.nextIndex(queue: queue, queueIndex: queueIndex, repeatMode: repeatMode) {
            queueIndex = next
            playCurrent(shouldPlay: shouldPlay)
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
