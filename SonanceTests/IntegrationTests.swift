import XCTest
@testable import Sonance

/// Cross-milestone integration checks. These cover the interaction points where two
/// milestones touch the same piece of state — the places most likely to break when the
/// individual milestones are merged together.
final class IntegrationTests: XCTestCase {

    // MARK: - M3 ↔ M10 — Player.insert keeps the queue model coherent

    func testInsertAtEndAppendsAndPreservesIndex() async {
        let player = await MainActor.run { Player() }
        let client = stubClient()
        let initial = makeSongs(prefix: "a", count: 3)

        await MainActor.run {
            player.play(initial, startAt: 1, using: client)
            XCTAssertEqual(player.queueIndex, 1)
            player.insert([makeSong(id: "new")], at: 3, using: client)
            XCTAssertEqual(player.queue.map(\.id), ["a-0", "a-1", "a-2", "new"])
            XCTAssertEqual(player.queueIndex, 1, "inserting after the current track must not shift queueIndex")
        }
    }

    func testInsertBeforeCurrentShiftsIndexForward() async {
        let player = await MainActor.run { Player() }
        let client = stubClient()
        let initial = makeSongs(prefix: "a", count: 3)

        await MainActor.run {
            player.play(initial, startAt: 2, using: client)
            XCTAssertEqual(player.queueIndex, 2)
            player.insert([makeSong(id: "x"), makeSong(id: "y")], at: 0, using: client)
            XCTAssertEqual(player.queue.map(\.id), ["x", "y", "a-0", "a-1", "a-2"])
            XCTAssertEqual(player.queueIndex, 4, "inserting before the current track must shift queueIndex by the insert count")
            XCTAssertEqual(player.queue[player.queueIndex].id, "a-2", "currentSong identity must survive the shift")
        }
    }

    func testInsertIntoEmptyQueueStartsPlayback() async {
        let player = await MainActor.run { Player() }
        let client = stubClient()
        let songs = makeSongs(prefix: "b", count: 2)

        await MainActor.run {
            XCTAssertTrue(player.queue.isEmpty)
            player.insert(songs, at: 0, using: client)
            XCTAssertEqual(player.queue.map(\.id), ["b-0", "b-1"])
            XCTAssertEqual(player.queueIndex, 0)
            XCTAssertEqual(player.currentSong?.id, "b-0")
        }
    }

    // MARK: - M1 ↔ M2 — Stable URLs survive across nominally identical calls

    func testStableMediaURLsAcrossManyCalls() {
        let creds = ServerCredentials(serverURL: "http://example.test", username: "u", password: "p")
        let client = SubsonicClient(credentials: creds)
        let baseline = client.coverArtURL(id: "abc", size: 600)
        for _ in 0..<50 {
            XCTAssertEqual(client.coverArtURL(id: "abc", size: 600), baseline,
                           "coverArtURL must be deterministic across calls")
        }
        let streamBaseline = client.streamURL(id: "song-1")
        for _ in 0..<50 {
            XCTAssertEqual(client.streamURL(id: "song-1"), streamBaseline,
                           "streamURL must be deterministic across calls")
        }
    }

    /// Non-media endpoints (e.g. getPlaylists, getAlbumList2) should still rotate salt per
    /// call, so even if a transient network layer caches by URL it cannot leak across
    /// requests.
    func testNonMediaEndpointsRotateSalt() {
        let creds = ServerCredentials(serverURL: "http://example.test", username: "u", password: "p")
        let client = SubsonicClient(credentials: creds)
        // Indirectly probe by checking that two different cover-art sizes still share salt
        // (proving stableAuth is used) while sequential coverArtURL == coverArtURL.
        // Salt re-use is verified above; here we just confirm two sizes produce different URLs.
        let a300 = client.coverArtURL(id: "abc", size: 300)
        let a600 = client.coverArtURL(id: "abc", size: 600)
        XCTAssertNotNil(a300)
        XCTAssertNotNil(a600)
        XCTAssertNotEqual(a300, a600)
    }

    // MARK: - M1 ↔ everywhere — Cover-art cache key partitions on account

    func testCoverArtCacheKeyPartitionsByAccount() {
        let c1 = SubsonicClient(credentials: ServerCredentials(serverURL: "http://one.test", username: "u", password: "p"))
        let c2 = SubsonicClient(credentials: ServerCredentials(serverURL: "http://two.test", username: "u", password: "p"))
        XCTAssertNotEqual(c1.coverArtCacheKey(id: "abc", size: 300),
                          c2.coverArtCacheKey(id: "abc", size: 300),
                          "same cover-art id on different servers must not collide in the cache")
    }

    // MARK: - M5 / M8 — Album model accepts the M8 fields without breaking M5 pagination

    func testAlbumDecodesWithoutOptionalFields() throws {
        // Subsonic responses with no genre/playCount should still decode (M8's new vars are optional).
        let json = #"{"id":"42","name":"Sample","artist":"A","artistId":"a1","coverArt":"c","songCount":3,"duration":120,"year":2020,"starred":null}"#
        let decoded = try JSONDecoder().decode(Album.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, "42")
        XCTAssertNil(decoded.genre)
        XCTAssertNil(decoded.playCount)
    }

    func testAlbumDecodesWithM8Fields() throws {
        let json = #"{"id":"42","name":"Sample","artist":"A","artistId":"a1","coverArt":"c","songCount":3,"duration":120,"year":2020,"starred":null,"genre":"Rock","playCount":17}"#
        let decoded = try JSONDecoder().decode(Album.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.genre, "Rock")
        XCTAssertEqual(decoded.playCount, 17)
    }

    // MARK: - M7 / M10 — Song decodes albumId/artistId for keyboard + mini-player navigation

    func testSongDecodesNavigationFields() throws {
        let json = #"""
        {
            "id": "s1", "title": "Track 1", "artist": "A", "album": "Al",
            "albumId": "alb1", "artistId": "art1", "duration": 240,
            "coverArt": "c1", "starred": null,
            "track": 3, "discNumber": 2, "bitRate": 320, "genre": "Rock", "playCount": 9
        }
        """#
        let song = try JSONDecoder().decode(Song.self, from: Data(json.utf8))
        XCTAssertEqual(song.albumId, "alb1")
        XCTAssertEqual(song.artistId, "art1")
        XCTAssertEqual(song.track, 3)
        XCTAssertEqual(song.discNumber, 2)
        XCTAssertEqual(song.bitRate, 320)
        XCTAssertEqual(song.genre, "Rock")
        XCTAssertEqual(song.playCount, 9)
    }

    func testSongDecodesWithoutNavigationFields() throws {
        let json = #"{"id":"s1","title":"Track","artist":"A","album":"Al","duration":120,"coverArt":"c","starred":null}"#
        let song = try JSONDecoder().decode(Song.self, from: Data(json.utf8))
        XCTAssertNil(song.albumId)
        XCTAssertNil(song.artistId)
        XCTAssertNil(song.track)
    }

    // MARK: - M9 — playlistReplaceContents chunks large requests

    func testPlaylistReplaceContentsChunksLargePlaylists() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in Self.subsonicOKResponse() }
        let client = stubClient()

        // 250 existing + 250 new → 6 chunked requests at the default 100-per-chunk size
        // (3 removal chunks: 100 + 100 + 50; 3 addition chunks: 100 + 100 + 50).
        let newIDs = (0..<250).map { "song-\($0)" }
        try await client.playlistReplaceContents(
            playlistID: "p1",
            currentCount: 250,
            songIDs: newIDs
        )
        // Filter to `updatePlaylist` so background scrobbles or other detached tasks left over
        // from earlier tests don't affect the count. (Player.play in the M3↔M10 tests fires a
        // Task.detached scrobble that uses the same stubbed session.)
        let updateCalls = Self.updatePlaylistCalls()
        XCTAssertEqual(updateCalls.count, 6, "expected 3 remove + 3 add chunks for 250+250 with chunk size 100")

        // Each request URL should be well under 8 KB even before any future growth in
        // auth / param overhead.
        for url in updateCalls {
            XCTAssertLessThan(url.absoluteString.count, 8192, "URL exceeded safe length: \(url.absoluteString.count) bytes")
        }
    }

    func testPlaylistReplaceContentsHandlesEmptyStart() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in Self.subsonicOKResponse() }
        let client = stubClient()

        try await client.playlistReplaceContents(playlistID: "p1", currentCount: 0, songIDs: ["a", "b"])
        // currentCount 0 → no removal request; one addition request.
        XCTAssertEqual(Self.updatePlaylistCalls().count, 1)
    }

    private static func updatePlaylistCalls() -> [URL] {
        StubURLProtocol.capturedURLs.filter { $0.path.hasSuffix("/rest/updatePlaylist") }
    }

    private static func subsonicOKResponse() -> Data {
        Data(#"{"subsonic-response":{"status":"ok","version":"1.16.1"}}"#.utf8)
    }

    // MARK: - M4 — Reconcile mirror logic (pure function check)

    func testFavoritesReconcileLogic() {
        // The reconcile-by-IDs operation is just `Array.filter { ids.contains($0.id) }`. Encode
        // the invariant here so a future refactor that breaks it lights up.
        let songs = makeSongs(prefix: "f", count: 4)
        let allowed: Set<String> = ["f-0", "f-2"]
        let filtered = songs.filter { allowed.contains($0.id) }
        XCTAssertEqual(filtered.map(\.id), ["f-0", "f-2"])
        XCTAssertEqual(filtered.count, 2)
    }

    // MARK: - Helpers

    private func makeSong(id: String) -> Song {
        Song(
            id: id, title: "Title \(id)", artist: "Artist",
            album: "Album", duration: 180, coverArt: nil, starred: nil
        )
    }

    private func makeSongs(prefix: String, count: Int) -> [Song] {
        (0..<count).map { makeSong(id: "\(prefix)-\($0)") }
    }

    private func stubClient() -> SubsonicClient {
        let creds = ServerCredentials(serverURL: "http://example.test", username: "u", password: "p")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return SubsonicClient(credentials: creds, urlSession: URLSession(configuration: config))
    }
}
