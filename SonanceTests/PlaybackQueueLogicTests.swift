import XCTest
@testable import Sonance

final class PlaybackQueueLogicTests: XCTestCase {
    func testPlayAllBoundsStartIndex() {
        let songs = songs(3)
        let state = PlaybackQueueLogic.replaceQueue(songs, startAt: 99)

        XCTAssertEqual(state.queue.map(\.id), ["song-0", "song-1", "song-2"])
        XCTAssertEqual(state.index, 2)
        XCTAssertEqual(state.unshuffled.map(\.id), state.queue.map(\.id))
    }

    func testPlayNextInsertion() {
        var queue = songs(3)
        var unshuffled = queue

        PlaybackQueueLogic.playNext([song(99)], queue: &queue, queueIndex: 1, isShuffled: false, unshuffledQueue: &unshuffled)

        XCTAssertEqual(queue.map(\.id), ["song-0", "song-1", "song-99", "song-2"])
        XCTAssertEqual(unshuffled.map(\.id), queue.map(\.id))
    }

    func testAppend() {
        var queue = songs(2)
        var unshuffled = queue

        PlaybackQueueLogic.append([song(3), song(4)], queue: &queue, isShuffled: false, unshuffledQueue: &unshuffled)

        XCTAssertEqual(queue.map(\.id), ["song-0", "song-1", "song-3", "song-4"])
        XCTAssertEqual(unshuffled.map(\.id), queue.map(\.id))
    }

    func testRemoveNonCurrentBeforeCurrentMovesIndexBack() {
        var queue = songs(4)
        var unshuffled = queue
        var index = 2

        let result = PlaybackQueueLogic.remove(at: 0, queue: &queue, queueIndex: &index, isShuffled: false, unshuffledQueue: &unshuffled)

        XCTAssertEqual(result, .unchanged)
        XCTAssertEqual(index, 1)
        XCTAssertEqual(queue.map(\.id), ["song-1", "song-2", "song-3"])
    }

    func testRemoveCurrentPlaysNextOrStops() {
        var queue = songs(2)
        var unshuffled = queue
        var index = 0

        var result = PlaybackQueueLogic.remove(at: 0, queue: &queue, queueIndex: &index, isShuffled: false, unshuffledQueue: &unshuffled)
        XCTAssertEqual(result, .playCurrent)
        XCTAssertEqual(index, 0)
        XCTAssertEqual(queue.map(\.id), ["song-1"])

        result = PlaybackQueueLogic.remove(at: 0, queue: &queue, queueIndex: &index, isShuffled: false, unshuffledQueue: &unshuffled)
        XCTAssertEqual(result, .stopped)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(index, 0)
    }

    func testShuffleAndUnshuffleKeepCurrentTrack() {
        var queue = songs(4)
        var unshuffled: [Song] = []
        var index = 2
        var shuffled = false
        let current = queue[index]

        PlaybackQueueLogic.toggleShuffle(
            queue: &queue,
            queueIndex: &index,
            isShuffled: &shuffled,
            unshuffledQueue: &unshuffled,
            currentSong: current,
            shuffle: { $0.reversed() }
        )

        XCTAssertTrue(shuffled)
        XCTAssertEqual(index, 0)
        XCTAssertEqual(queue.first?.id, current.id)

        PlaybackQueueLogic.toggleShuffle(
            queue: &queue,
            queueIndex: &index,
            isShuffled: &shuffled,
            unshuffledQueue: &unshuffled,
            currentSong: current
        )

        XCTAssertFalse(shuffled)
        XCTAssertEqual(queue.map(\.id), ["song-0", "song-1", "song-2", "song-3"])
        XCTAssertEqual(index, 2)
    }

    func testRepeatNextIndexEdges() {
        let queue = songs(2)

        XCTAssertEqual(PlaybackQueueLogic.nextIndex(queue: queue, queueIndex: 0, repeatMode: .off), 1)
        XCTAssertNil(PlaybackQueueLogic.nextIndex(queue: queue, queueIndex: 1, repeatMode: .off))
        XCTAssertEqual(PlaybackQueueLogic.nextIndex(queue: queue, queueIndex: 1, repeatMode: .all), 0)
        XCTAssertNil(PlaybackQueueLogic.nextIndex(queue: [], queueIndex: 0, repeatMode: .all))
    }

    private func songs(_ count: Int) -> [Song] {
        (0..<count).map(song)
    }

    private func song(_ index: Int) -> Song {
        Song(
            id: "song-\(index)",
            title: "Song \(index)",
            artist: "Artist",
            album: "Album",
            duration: 180,
            coverArt: nil,
            starred: nil
        )
    }
}
