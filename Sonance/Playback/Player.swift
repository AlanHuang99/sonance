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

    private let avPlayer = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var activeClient: SubsonicClient?
    private var hasScrobbledCurrent: Bool = false
    private var lastSavedSecond: Int = -1
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
                    if d.isFinite, d > 0 {
                        self.duration = d
                    }
                }
                // Submission scrobble at 50% (or 4 minutes), per Subsonic convention.
                if !self.hasScrobbledCurrent,
                   self.duration > 30,
                   self.currentTime >= min(self.duration * 0.5, 240),
                   let song = self.currentSong,
                   let client = self.activeClient {
                    self.hasScrobbledCurrent = true
                    Task.detached { try? await client.scrobble(songID: song.id, submission: true) }
                }
                // Persist state every 3 seconds
                let sec = Int(self.currentTime)
                if sec != self.lastSavedSecond, sec % 3 == 0 {
                    self.lastSavedSecond = sec
                    self.saveState()
                }
            }
        }
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
    }

    private func saveState() {
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
        queue = songs
        unshuffledQueue = songs
        isShuffled = false
        queueIndex = max(0, min(index, songs.count - 1))
        playCurrent()
    }

    func playNext(_ songs: [Song], using client: SubsonicClient) {
        activeClient = client
        if queue.isEmpty {
            play(songs, startAt: 0, using: client)
            return
        }
        let insertAt = queueIndex + 1
        queue.insert(contentsOf: songs, at: insertAt)
        if !isShuffled { unshuffledQueue = queue }
        saveState()
    }

    func appendToQueue(_ songs: [Song], using client: SubsonicClient) {
        activeClient = client
        if queue.isEmpty {
            play(songs, startAt: 0, using: client)
            return
        }
        queue.append(contentsOf: songs)
        if !isShuffled { unshuffledQueue = queue }
        saveState()
    }

    func jumpTo(_ index: Int) {
        guard index >= 0, index < queue.count else { return }
        queueIndex = index
        playCurrent()
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        if index == queueIndex {
            queue.remove(at: index)
            if !isShuffled, index < unshuffledQueue.count { unshuffledQueue.remove(at: index) }
            if queue.isEmpty {
                stop()
            } else {
                queueIndex = min(queueIndex, queue.count - 1)
                playCurrent()
            }
        } else {
            if index < queueIndex { queueIndex -= 1 }
            queue.remove(at: index)
            if !isShuffled, index < unshuffledQueue.count { unshuffledQueue.remove(at: index) }
        }
        saveState()
    }

    func moveQueueItem(from source: Int, to destination: Int) {
        guard source >= 0, source < queue.count, destination >= 0, destination <= queue.count, source != destination else { return }
        let song = queue.remove(at: source)
        let dest = destination > source ? destination - 1 : destination
        queue.insert(song, at: dest)
        if source == queueIndex {
            queueIndex = dest
        } else if source < queueIndex && dest >= queueIndex {
            queueIndex -= 1
        } else if source > queueIndex && dest <= queueIndex {
            queueIndex += 1
        }
        if !isShuffled { unshuffledQueue = queue }
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
    }

    func stop() {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        currentSong = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        hasScrobbledCurrent = false
    }

    // MARK: - Repeat / Shuffle

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        saveState()
    }

    func toggleShuffle() {
        if isShuffled {
            // Restore original order; keep current song as queueIndex
            let current = currentSong
            queue = unshuffledQueue
            if let current, let i = queue.firstIndex(of: current) {
                queueIndex = i
            }
            isShuffled = false
        } else {
            unshuffledQueue = queue
            let current = currentSong
            var rest = queue
            if let current, let i = rest.firstIndex(of: current) {
                rest.remove(at: i)
            }
            rest.shuffle()
            if let current {
                queue = [current] + rest
                queueIndex = 0
            } else {
                queue = rest
                queueIndex = 0
            }
            isShuffled = true
        }
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
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnd() }
        }
        avPlayer.replaceCurrentItem(with: item)
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

        // "Now playing" scrobble
        Task.detached { try? await client.scrobble(songID: song.id, submission: false) }
    }

    private func handleTrackEnd() {
        switch repeatMode {
        case .one:
            avPlayer.seek(to: .zero)
            avPlayer.play()
            isPlaying = true
            hasScrobbledCurrent = false
        case .all:
            if queueIndex + 1 < queue.count {
                queueIndex += 1
            } else {
                queueIndex = 0
            }
            playCurrent()
        case .off:
            advanceOrStop()
        }
    }

    private func advanceOrStop() {
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            playCurrent()
        } else if repeatMode == .all && !queue.isEmpty {
            queueIndex = 0
            playCurrent()
        } else {
            stop()
        }
    }
}
