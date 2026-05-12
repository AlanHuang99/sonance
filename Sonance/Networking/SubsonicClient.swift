import Foundation
import CryptoKit

final class SubsonicClient: @unchecked Sendable {
    let credentials: ServerCredentials
    private let urlSession: URLSession
    private let clientName = "Sonance"
    private let apiVersion = "1.16.1"

    /// Stable (salt, token) pair memoized per client instance for cover-art and stream URLs.
    /// Subsonic permits salt reuse; pinning these for media keeps URLs identical across calls so
    /// downstream caches (URLCache, AVPlayer, our cover-art cache key) see consistent identities.
    private let mediaSalt: String
    private let mediaToken: String

    init(credentials: ServerCredentials, urlSession: URLSession = .shared) {
        self.credentials = credentials
        self.urlSession = urlSession
        let salt = Self.randomSalt()
        self.mediaSalt = salt
        self.mediaToken = Self.md5(credentials.password + salt)
    }

    func ping() async throws {
        let _: PingResponse = try await get("ping", params: [:])
    }

    func albumList(type: String = "alphabeticalByName", size: Int = 100, offset: Int = 0) async throws -> [Album] {
        let resp: AlbumListResponse = try await get("getAlbumList2", params: [
            "type": type,
            "size": String(size),
            "offset": String(offset),
        ])
        return resp.albumList2?.album ?? []
    }

    func artists() async throws -> [Artist] {
        let resp: ArtistsResponse = try await get("getArtists", params: [:])
        return resp.artists?.index?.flatMap { $0.artist ?? [] } ?? []
    }

    func artist(id: String) async throws -> ArtistDetail {
        let resp: ArtistDetailResponse = try await get("getArtist", params: ["id": id])
        guard let a = resp.artist else { throw SubsonicError(code: -1, message: "Artist \(id) not found") }
        return a
    }

    func album(id: String) async throws -> AlbumDetail {
        let resp: AlbumDetailResponse = try await get("getAlbum", params: ["id": id])
        guard let a = resp.album else { throw SubsonicError(code: -1, message: "Album \(id) not found") }
        return a
    }

    func randomSongs(size: Int = 50) async throws -> [Song] {
        let resp: RandomSongsResponse = try await get("getRandomSongs", params: ["size": String(size)])
        return resp.randomSongs?.song ?? []
    }

    func starred() async throws -> Starred2Container {
        let resp: Starred2Response = try await get("getStarred2", params: [:])
        return resp.starred2 ?? Starred2Container(song: [], album: [], artist: [])
    }

    func star(songID: String? = nil, albumID: String? = nil, artistID: String? = nil) async throws {
        var params: [String: String] = [:]
        if let songID { params["id"] = songID }
        if let albumID { params["albumId"] = albumID }
        if let artistID { params["artistId"] = artistID }
        let _: PingResponse = try await get("star", params: params)
    }

    func unstar(songID: String? = nil, albumID: String? = nil, artistID: String? = nil) async throws {
        var params: [String: String] = [:]
        if let songID { params["id"] = songID }
        if let albumID { params["albumId"] = albumID }
        if let artistID { params["artistId"] = artistID }
        let _: PingResponse = try await get("unstar", params: params)
    }

    func lyrics(songID: String) async throws -> [StructuredLyrics] {
        let resp: LyricsListResponse = try await get("getLyricsBySongId", params: ["id": songID])
        return resp.lyricsList?.structuredLyrics ?? []
    }

    func scrobble(songID: String, submission: Bool) async throws {
        let _: PingResponse = try await get("scrobble", params: [
            "id": songID,
            "submission": submission ? "true" : "false",
        ])
    }

    func search(_ query: String) async throws -> SearchResult {
        let resp: SearchResponse = try await get("search3", params: ["query": query])
        return resp.searchResult3 ?? SearchResult(artist: nil, album: nil, song: nil)
    }

    func playlists() async throws -> [Playlist] {
        let resp: PlaylistsResponse = try await get("getPlaylists", params: [:])
        return resp.playlists?.playlist ?? []
    }

    func playlist(id: String) async throws -> PlaylistDetail {
        let resp: PlaylistDetailResponse = try await get("getPlaylist", params: ["id": id])
        guard let detail = resp.playlist else {
            throw SubsonicError(code: -1, message: "Playlist \(id) not found")
        }
        return detail
    }

    func streamURL(id: String) -> URL? {
        try? buildURL(endpoint: "stream", params: ["id": id], stableAuth: true)
    }

    func coverArtURL(id: String, size: Int = 300) -> URL? {
        try? buildURL(endpoint: "getCoverArt", params: ["id": id, "size": String(size)], stableAuth: true)
    }

    func coverArtData(id: String, size: Int = 300) async throws -> Data {
        NetworkDiagnostics.record("getCoverArt:\(size)")
        let url = try buildURL(endpoint: "getCoverArt", params: ["id": id, "size": String(size)], stableAuth: true)
        let (data, response) = try await urlSession.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError(code: http.statusCode, message: "Cover art request failed with HTTP \(http.statusCode)")
        }
        return data
    }

    func coverArtCacheKey(id: String, size: Int = 300) -> String {
        "\(credentials.accountID)|cover|\(id)|\(size)"
    }

    private func get<T: Decodable>(_ endpoint: String, params: [String: String]) async throws -> T {
        NetworkDiagnostics.record(endpoint)
        let url = try buildURL(endpoint: endpoint, params: params)
        let (data, _) = try await urlSession.data(from: url)
        let envelope = try JSONDecoder().decode(SubsonicEnvelope<T>.self, from: data)
        let resp = envelope.subsonicResponse
        if resp.status == "failed", let err = resp.error {
            throw SubsonicError(code: err.code, message: err.message)
        }
        guard let body = resp.body else {
            throw SubsonicError(code: -1, message: "Empty response from server")
        }
        return body
    }

    private func buildURL(endpoint: String, params: [String: String], stableAuth: Bool = false) throws -> URL {
        let trimmed = credentials.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else {
            throw SubsonicError(code: -1, message: "Invalid server URL")
        }
        var path = components.path
        if !path.hasSuffix("/") { path += "/" }
        components.path = path + "rest/" + endpoint
        let salt: String
        let token: String
        if stableAuth {
            salt = mediaSalt
            token = mediaToken
        } else {
            salt = Self.randomSalt()
            token = Self.md5(credentials.password + salt)
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "u", value: credentials.username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
        for (k, v) in params {
            items.append(URLQueryItem(name: k, value: v))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw SubsonicError(code: -1, message: "Could not construct request URL")
        }
        return url
    }

    private static func randomSalt(length: Int = 12) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func md5(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
