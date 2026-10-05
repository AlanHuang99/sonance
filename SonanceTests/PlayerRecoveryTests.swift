import AVFoundation
import Combine
import XCTest
@testable import Sonance

final class PlayerRecoveryTests: XCTestCase {
    private var mediaURL: URL!
    private var defaults: UserDefaults!
    private var defaultsDomain: String!

    override func setUpWithError() throws {
        defaultsDomain = "SonanceTests.Playback.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsDomain)
        mediaURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480_000))
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: mediaURL, settings: format.settings)
        try file.write(from: buffer)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsDomain)
        try FileManager.default.removeItem(at: mediaURL)
    }

    @MainActor
    func testDelayedEndAfterJumpDoesNotSkipNewTrack() async throws {
        let (player, avPlayer) = makePlayer()
        defer { player.stop() }
        player.play(try songs(), using: client())
        let oldItem = try XCTUnwrap(avPlayer.currentItem)

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        player.jumpTo(1)
        await drainCallbacks()

        XCTAssertEqual(player.currentSong?.id, "b")
        XCTAssertEqual(player.queueIndex, 1)
    }

    @MainActor
    func testDelayedEndAfterStopDoesNotRestartPlayback() async throws {
        let (player, avPlayer) = makePlayer()
        defer { player.stop() }
        player.play(try songs(), using: client())
        let item = try XCTUnwrap(avPlayer.currentItem)

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        player.stop()
        await drainCallbacks()

        XCTAssertNil(player.currentSong)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(avPlayer.currentItem)
    }

    @MainActor
    func testFailureDoesNotLeavePlayerClaimingToPlayAnEmptyQueue() async throws {
        let (player, avPlayer) = makePlayer()
        defer { player.stop() }
        player.play(try songs(), using: client())
        let item = try XCTUnwrap(avPlayer.currentItem)
        // This is the sequence observed in the live Core Audio failure: the backend
        // removes the failed item and emits FailedToPlayToEnd rather than DidPlayToEnd.
        avPlayer.removeAllItems()
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey:
                NSError(domain: AVFoundationErrorDomain, code: -11800)]
        )
        await drainCallbacks()

        XCTAssertFalse(player.isPlaying && avPlayer.currentItem == nil,
                       "A failed output must leave a playable item or a stopped playback state")
        XCTAssertEqual(player.currentSong?.id, "a", "Failure must preserve the selected track for retry")
    }

    @MainActor
    func testRetryIsBoundedAndPreservesTrackAndPosition() async throws {
        let (player, avPlayer) = makePlayer()
        defer { player.stop() }
        player.play(try songs(), using: client())
        player.seek(to: 12)
        let firstItem = try XCTUnwrap(avPlayer.currentItem)
        postFailure(firstItem)
        await drainCallbacks()
        let retryItem = try XCTUnwrap(avPlayer.currentItem)
        XCTAssertFalse(firstItem === retryItem)
        XCTAssertEqual(player.currentSong?.id, "a")
        XCTAssertEqual(player.currentTime, 12, accuracy: 0.5)

        postFailure(retryItem)
        await drainCallbacks()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.playbackError)
        XCTAssertNil(avPlayer.currentItem)
        XCTAssertEqual(player.currentSong?.id, "a")
        XCTAssertEqual(player.queueIndex, 0)
    }

    @MainActor
    func testDuplicateFailureFromReplacedItemDoesNotStopRetry() async throws {
        let (player, avPlayer) = makePlayer()
        defer { player.stop() }
        player.play(try songs(), using: client())
        let firstItem = try XCTUnwrap(avPlayer.currentItem)
        postFailure(firstItem)
        await drainCallbacks()
        let retryItem = try XCTUnwrap(avPlayer.currentItem)
        postFailure(firstItem)
        await drainCallbacks()
        XCTAssertTrue(avPlayer.currentItem === retryItem)
        XCTAssertTrue(player.isPlaying)
        XCTAssertNil(player.playbackError)
    }

    @MainActor
    func testPauseDuringDelayedEndKeepsNextTrackPaused() async throws {
        let (player, avPlayer) = makePlayer()
        defer { player.stop() }
        player.play(try songs(), using: client())
        let item = try XCTUnwrap(avPlayer.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        player.togglePlayPause()
        await drainCallbacks()
        XCTAssertEqual(player.currentSong?.id, "b")
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(avPlayer.rate, 0)
    }

    @MainActor
    func testQueueEditAfterAutomaticAdvanceKeepsAudioAndModelTogether() async throws {
        let (player, avPlayer) = makePlayer()
        defer { player.stop() }
        player.play(try songs(), using: client())
        await avPlayer.seek(to: CMTime(seconds: 55, preferredTimescale: 1000))
        let preload = expectation(description: "next track was preloaded")
        for _ in 0..<50 {
            if avPlayer.items().count == 2 { preload.fulfill(); break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await fulfillment(of: [preload], timeout: 1)
        XCTAssertEqual(avPlayer.items().count, 2)

        avPlayer.advanceToNextItem()
        let advancedItem = try XCTUnwrap(avPlayer.currentItem)
        // A user action can run before the deferred end/KVO handler reconciles the model.
        player.playNext([try songs()[2]], using: client())
        await drainCallbacks()

        XCTAssertTrue(avPlayer.currentItem === advancedItem, "Editing the queue must preserve the advanced audio")
        XCTAssertEqual(player.currentSong?.id, "b")
        XCTAssertEqual(player.queueIndex, 1)
        XCTAssertEqual(player.queue.map(\.id), ["a", "b", "c", "c"])
    }

    @MainActor
    func testDelayedResumeSeekCannotUndoPause() async throws {
        let backend = HoldingSeekQueuePlayer()
        let (player, _) = makePlayer(avPlayer: backend)
        defer { player.stop() }
        try storePausedState(position: 12)
        player.restorePaused(client: client())
        player.togglePlayPause()
        await waitForSeeks(backend)
        player.togglePlayPause()
        let unexpectedResume = expectation(description: "a cancelled resume must keep playback paused")
        unexpectedResume.isInverted = true
        unexpectedResume.assertForOverFulfill = false
        backend.onPlay = { unexpectedResume.fulfill() }
        defer { backend.onPlay = nil }
        backend.finishSeeks()
        await fulfillment(of: [unexpectedResume], timeout: 0.5)

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(backend.rate, 0)
        XCTAssertEqual(player.currentSong?.id, "a")
    }

    @MainActor
    func testNewSeekDuringRestoreStillStartsPlayback() async throws {
        let backend = HoldingSeekQueuePlayer()
        let (player, _) = makePlayer(avPlayer: backend)
        defer { player.stop() }
        try storePausedState(position: 12)
        player.restorePaused(client: client())
        player.togglePlayPause()
        await waitForSeeks(backend)
        player.seek(to: 20)
        await waitForSeeks(backend, count: 2)
        let resumed = expectation(description: "the replacement seek starts playback")
        resumed.assertForOverFulfill = false
        backend.onPlay = { resumed.fulfill() }
        defer { backend.onPlay = nil }
        backend.finishSeeks()
        await fulfillment(of: [resumed], timeout: 3)

        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(backend.rate, 1)
        XCTAssertEqual(player.currentTime, 20, accuracy: 0.5)
    }

    @MainActor
    func testDelayedResumeSeekCannotStartReplacementTrack() async throws {
        let backend = HoldingSeekQueuePlayer()
        let (player, _) = makePlayer(avPlayer: backend)
        defer { player.stop() }
        try storePausedState(position: 12)
        player.restorePaused(client: client())
        player.togglePlayPause()
        await waitForSeeks(backend)
        player.jumpTo(1)
        player.togglePlayPause()
        let unexpectedResume = expectation(description: "the old seek must not start the replacement track")
        unexpectedResume.isInverted = true
        unexpectedResume.assertForOverFulfill = false
        // Observe new play requests, not delayed rate KVO from jumpTo's earlier play.
        backend.onPlay = { unexpectedResume.fulfill() }
        defer { backend.onPlay = nil }
        backend.finishSeeks()
        await fulfillment(of: [unexpectedResume], timeout: 0.5)

        XCTAssertEqual(player.currentSong?.id, "b")
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(backend.rate, 0)
    }

    @MainActor
    func testCancelledSeekCannotSeekReplacementTrackBeforeStarting() async throws {
        let (player, avPlayer) = makePlayer()
        defer { player.stop() }
        try storePausedState(position: 12)
        player.restorePaused(client: client())
        player.togglePlayPause()
        // Do not yield: the seek task is cancelled before its body begins running.
        player.jumpTo(1)
        let replacement = try XCTUnwrap(avPlayer.currentItem)
        let unexpectedSeek = expectation(description: "cancelled task must not move the replacement playhead")
        unexpectedSeek.isInverted = true
        unexpectedSeek.assertForOverFulfill = false
        let observation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped, object: replacement, queue: .main
        ) { _ in
            if replacement.currentTime().seconds >= 10 { unexpectedSeek.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observation) }
        await fulfillment(of: [unexpectedSeek], timeout: 0.5)
        XCTAssertLessThan(replacement.currentTime().seconds, 2)
        XCTAssertEqual(player.currentSong?.id, "b")
    }

    @MainActor
    func testFailedResumeSeekRetriesThenReportsError() async throws {
        let backend = HoldingSeekQueuePlayer()
        let (player, _) = makePlayer(avPlayer: backend)
        defer { player.stop() }
        try storePausedState(position: 12)
        player.restorePaused(client: client())
        player.togglePlayPause()
        await waitForSeeks(backend)
        let firstItem = try XCTUnwrap(backend.currentItem)
        let retry = expectation(description: "a rejected resume seek reloads the item")
        retry.assertForOverFulfill = false
        let observation = backend.observe(\.currentItem, options: [.new]) { backend, _ in
            if let item = backend.currentItem, item !== firstItem { retry.fulfill() }
        }
        defer { observation.invalidate() }
        backend.finishSeeks(success: false)
        await fulfillment(of: [retry], timeout: 3)
        XCTAssertFalse(backend.currentItem === firstItem, "A rejected resume seek must trigger recovery")
        await waitForSeeks(backend)
        let failure = expectation(description: "a second rejected seek reports an error")
        let subscription = player.$playbackError.compactMap { $0 }.prefix(1).sink { _ in failure.fulfill() }
        defer { subscription.cancel() }
        backend.finishSeeks(success: false)
        await fulfillment(of: [failure], timeout: 3)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.playbackError)
        XCTAssertNil(backend.currentItem)
    }

    @MainActor
    func testStallCallbackAfterPauseDoesNotRestartAudio() async throws {
        let (player, avPlayer) = makePlayer()
        defer { player.stop() }
        player.play(try songs(), using: client())
        let item = try XCTUnwrap(avPlayer.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: item)
        player.togglePlayPause()
        await drainCallbacks()
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isBuffering)
        XCTAssertEqual(avPlayer.rate, 0)
    }

    @MainActor
    func testAssetLoadFailureStopsWithRetryableError() async throws {
        let avPlayer = AVQueuePlayer()
        let missingFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let player = Player(avPlayer: avPlayer, userDefaults: defaults,
                            makePlayerItem: { _ in AVPlayerItem(url: missingFile) })
        defer { player.stop() }
        let failure = expectation(description: "asset failure is reported after bounded retry")
        let subscription = player.$playbackError.compactMap { $0 }.prefix(1).sink { _ in failure.fulfill() }
        defer { subscription.cancel() }
        player.play(try songs(), using: client())
        await fulfillment(of: [failure], timeout: 5)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.playbackError)
        XCTAssertNil(avPlayer.currentItem)
        XCTAssertEqual(player.currentSong?.id, "a")
    }

    @MainActor
    func testStallWatchdogRetriesWithoutSkippingAndStopsAfterRepeatedStall() async throws {
        let (player, avPlayer) = makePlayer(avPlayer: StalledQueuePlayer())
        defer { player.stop() }
        player.play(try songs(), using: client())
        let firstItem = try XCTUnwrap(avPlayer.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: firstItem)
        let retry = expectation(description: "stalled playback reloads")
        let observation = avPlayer.observe(\.currentItem, options: [.new]) { backend, _ in
            if let item = backend.currentItem, item !== firstItem { retry.fulfill() }
        }
        await fulfillment(of: [retry], timeout: 10)
        observation.invalidate()
        let retryItem = try XCTUnwrap(avPlayer.currentItem)
        XCTAssertEqual(player.currentSong?.id, "a")
        XCTAssertEqual(player.queueIndex, 0)

        let failure = expectation(description: "second persistent stall stops")
        let subscription = player.$playbackError.compactMap { $0 }.prefix(1).sink { _ in failure.fulfill() }
        defer { subscription.cancel() }
        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: retryItem)
        await fulfillment(of: [failure], timeout: 10)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.playbackError)
        XCTAssertNil(avPlayer.currentItem)
        XCTAssertEqual(player.currentSong?.id, "a")
    }

    @MainActor
    func testASecondStallAfterProgressGetsItsOwnWatchdog() async throws {
        let (player, avPlayer) = makePlayer(avPlayer: StalledQueuePlayer())
        defer { player.stop() }
        player.play(try songs(), using: client())
        let firstItem = try XCTUnwrap(avPlayer.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: firstItem)
        await drainCallbacks()
        // Simulate buffered playback making progress before another network interruption.
        let moved = await avPlayer.seek(to: CMTime(seconds: 2, preferredTimescale: 1000))
        XCTAssertTrue(moved)
        XCTAssertGreaterThan(firstItem.currentTime().seconds, 1)
        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: firstItem)
        let retry = expectation(description: "new stall has its own recovery deadline")
        let observation = avPlayer.observe(\.currentItem, options: [.new]) { backend, _ in
            if let item = backend.currentItem, item !== firstItem { retry.fulfill() }
        }
        defer { observation.invalidate() }
        await fulfillment(of: [retry], timeout: 10)
        XCTAssertEqual(player.currentSong?.id, "a")
        XCTAssertEqual(player.queueIndex, 0)
    }

    @MainActor
    func testPauseCancelsAnAlreadyRunningStallWatchdog() async throws {
        let (player, avPlayer) = makePlayer(avPlayer: StalledQueuePlayer())
        defer { player.stop() }
        player.play(try songs(), using: client())
        let item = try XCTUnwrap(avPlayer.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: item)
        await drainCallbacks()
        XCTAssertTrue(player.isBuffering)
        player.togglePlayPause()
        let unexpectedRecovery = expectation(description: "paused audio must not reload later")
        unexpectedRecovery.isInverted = true
        let observation = avPlayer.observe(\.currentItem, options: [.new]) { _, _ in unexpectedRecovery.fulfill() }
        defer { observation.invalidate() }
        await fulfillment(of: [unexpectedRecovery], timeout: 8.5)
        XCTAssertTrue(avPlayer.currentItem === item)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isBuffering)
        XCTAssertNil(player.playbackError)
    }

    private func storePausedState(position: Double) throws {
        let queue = try JSONSerialization.jsonObject(with: JSONEncoder().encode(songs()))
        let state: [String: Any] = [
            "queue": queue, "unshuffledQueue": queue, "queueIndex": 0,
            "currentTime": position, "isShuffled": false, "repeatMode": "off", "volume": 0
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: state), forKey: "sonance.playerState")
    }

    private func postFailure(_ item: AVPlayerItem) {
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: AVFoundationErrorDomain, code: -11800)])
    }

    @MainActor
    private func makePlayer(avPlayer: AVQueuePlayer = AVQueuePlayer()) -> (Player, AVQueuePlayer) {
        let url = mediaURL!
        avPlayer.isMuted = true
        return (Player(avPlayer: avPlayer, userDefaults: defaults, makePlayerItem: { _ in AVPlayerItem(url: url) }), avPlayer)
    }

    @MainActor
    private func drainCallbacks() async {
        // Yield through the main queue after notification handlers enqueue MainActor tasks.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    private func waitForSeeks(_ backend: HoldingSeekQueuePlayer, count: Int = 1) async {
        let pending = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in backend.pendingSeekCount >= count }, object: nil
        )
        await fulfillment(of: [pending], timeout: 3)
    }

    private func client() -> SubsonicClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackStubURLProtocol.self]
        return SubsonicClient(credentials: ServerCredentials(
            serverURL: "http://127.0.0.1:9", username: "test", password: "test"
        ), urlSession: URLSession(configuration: configuration))
    }

    private func songs() throws -> [Song] {
        try JSONDecoder().decode([Song].self, from: Data(
            #"[{"id":"a","title":"A","duration":60},{"id":"b","title":"B","duration":60},{"id":"c","title":"C","duration":60}]"#.utf8
        ))
    }
}

/// Only hold the external AVFoundation completion; queue membership, playback rate,
/// and the Player state machine stay real so the race can be exercised deterministically.
private final class HoldingSeekQueuePlayer: AVQueuePlayer {
    private let completionLock = NSLock()
    private var completions: [@Sendable (Bool) -> Void] = []
    private var playObserver: (@Sendable () -> Void)?

    var onPlay: (@Sendable () -> Void)? {
        get {
            completionLock.lock()
            defer { completionLock.unlock() }
            return playObserver
        }
        set {
            completionLock.lock()
            playObserver = newValue
            completionLock.unlock()
        }
    }

    override func play() {
        super.play()
        onPlay?()
    }

    var pendingSeekCount: Int {
        completionLock.lock()
        defer { completionLock.unlock() }
        return completions.count
    }

    override func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
        // Move the real playhead, then let the test control when the async caller resumes.
        super.seek(to: time) { [weak self] _ in
            guard let self else { return }
            self.completionLock.lock()
            self.completions.append(completionHandler)
            self.completionLock.unlock()
        }
    }

    func finishSeeks(success: Bool = true) {
        completionLock.lock()
        let pending = completions
        completions.removeAll()
        completionLock.unlock()
        pending.forEach { $0(success) }
    }
}

/// Simulate an output that never advances, while retaining AVFoundation's real item queue.
private final class StalledQueuePlayer: AVQueuePlayer {
    override func play() {}
}

private final class PlaybackStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"subsonic-response":{"status":"ok","version":"1.16.1"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
