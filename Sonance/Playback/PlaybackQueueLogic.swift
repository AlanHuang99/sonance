import Foundation

enum PlaybackQueueLogic {
    static func replaceQueue(_ songs: [Song], startAt index: Int) -> (queue: [Song], index: Int, unshuffled: [Song]) {
        let bounded = max(0, min(index, songs.count - 1))
        return (songs, bounded, songs)
    }

    static func playNext(_ songs: [Song], queue: inout [Song], queueIndex: Int, isShuffled: Bool, unshuffledQueue: inout [Song]) {
        let insertAt = min(queueIndex + 1, queue.count)
        queue.insert(contentsOf: songs, at: insertAt)
        if !isShuffled { unshuffledQueue = queue }
    }

    static func append(_ songs: [Song], queue: inout [Song], isShuffled: Bool, unshuffledQueue: inout [Song]) {
        queue.append(contentsOf: songs)
        if !isShuffled { unshuffledQueue = queue }
    }

    static func remove(at index: Int, queue: inout [Song], queueIndex: inout Int, isShuffled: Bool, unshuffledQueue: inout [Song]) -> QueueRemovalResult {
        guard index >= 0, index < queue.count else { return .unchanged }
        if index == queueIndex {
            queue.remove(at: index)
            if !isShuffled, index < unshuffledQueue.count { unshuffledQueue.remove(at: index) }
            if queue.isEmpty {
                queueIndex = 0
                return .stopped
            }
            queueIndex = min(queueIndex, queue.count - 1)
            return .playCurrent
        }

        if index < queueIndex { queueIndex -= 1 }
        queue.remove(at: index)
        if !isShuffled, index < unshuffledQueue.count { unshuffledQueue.remove(at: index) }
        return .unchanged
    }

    static func move(from source: Int, to destination: Int, queue: inout [Song], queueIndex: inout Int, isShuffled: Bool, unshuffledQueue: inout [Song]) {
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
    }

    static func toggleShuffle(queue: inout [Song], queueIndex: inout Int, isShuffled: inout Bool, unshuffledQueue: inout [Song], currentSong: Song?, shuffle: ([Song]) -> [Song] = { $0.shuffled() }) {
        if isShuffled {
            queue = unshuffledQueue
            if let currentSong, let index = queue.firstIndex(of: currentSong) {
                queueIndex = index
            } else {
                queueIndex = min(queueIndex, max(queue.count - 1, 0))
            }
            isShuffled = false
            return
        }

        unshuffledQueue = queue
        var rest = queue
        if let currentSong, let index = rest.firstIndex(of: currentSong) {
            rest.remove(at: index)
        }
        rest = shuffle(rest)
        if let currentSong {
            queue = [currentSong] + rest
            queueIndex = 0
        } else {
            queue = rest
            queueIndex = 0
        }
        isShuffled = true
    }

    static func nextIndex(queue: [Song], queueIndex: Int, repeatMode: RepeatMode) -> Int? {
        if queueIndex + 1 < queue.count { return queueIndex + 1 }
        if repeatMode == .all, !queue.isEmpty { return 0 }
        return nil
    }
}

enum QueueRemovalResult: Equatable {
    case unchanged
    case playCurrent
    case stopped
}
