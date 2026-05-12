import Foundation

struct SubsonicEnvelope<Body: Decodable>: Decodable {
    let subsonicResponse: SubsonicResponse<Body>

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct SubsonicResponse<Body: Decodable>: Decodable {
    let status: String
    let version: String
    let error: SubsonicErrorPayload?
    let body: Body?

    enum CodingKeys: String, CodingKey {
        case status, version, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try c.decode(String.self, forKey: .status)
        self.version = try c.decode(String.self, forKey: .version)
        self.error = try c.decodeIfPresent(SubsonicErrorPayload.self, forKey: .error)
        // Body fields live alongside status/version/error, so decode from the same level.
        self.body = try? Body(from: decoder)
    }
}

struct SubsonicErrorPayload: Decodable {
    let code: Int
    let message: String
}

struct PingResponse: Decodable {}

struct AlbumListResponse: Decodable {
    let albumList2: AlbumList2?
}

struct AlbumList2: Decodable {
    let album: [Album]?
}

struct ArtistsResponse: Decodable {
    let artists: ArtistsIndex?
}

struct ArtistsIndex: Decodable {
    let index: [ArtistIndexEntry]?
}

struct ArtistIndexEntry: Decodable {
    let name: String
    let artist: [Artist]?
}

struct PlaylistsResponse: Decodable {
    let playlists: PlaylistsContainer?
}

struct PlaylistsContainer: Decodable {
    let playlist: [Playlist]?
}

struct SearchResponse: Decodable {
    let searchResult3: SearchResult?
}

struct SearchResult: Decodable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

struct Album: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
    let starred: String?
}

struct AlbumDetailResponse: Decodable {
    let album: AlbumDetail?
}

struct AlbumDetail: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
    let starred: String?
    let song: [Song]?
}

struct ArtistDetailResponse: Decodable {
    let artist: ArtistDetail?
}

struct ArtistDetail: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int?
    let album: [Album]?
}

struct RandomSongsResponse: Decodable {
    let randomSongs: RandomSongsContainer?
}

struct RandomSongsContainer: Decodable {
    let song: [Song]?
}

struct Starred2Response: Decodable {
    let starred2: Starred2Container?
}

struct Starred2Container: Decodable {
    let song: [Song]?
    let album: [Album]?
    let artist: [Artist]?
}

// OpenSubsonic structured lyrics: getLyricsBySongId
struct LyricsListResponse: Decodable {
    let lyricsList: LyricsListContainer?
}

struct LyricsListContainer: Decodable {
    let structuredLyrics: [StructuredLyrics]?
}

struct StructuredLyrics: Decodable, Hashable {
    let displayArtist: String?
    let displayTitle: String?
    let lang: String?
    let synced: Bool?
    let line: [LyricLine]?
}

struct LyricLine: Decodable, Hashable, Identifiable {
    /// start time in milliseconds
    let start: Int?
    let value: String

    var id: String { "\(start ?? -1)|\(value)" }
}

struct Artist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int?
}

struct Song: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    var albumId: String? = nil
    let duration: Int?
    let coverArt: String?
    let starred: String?
    var track: Int? = nil
    var discNumber: Int? = nil
    var bitRate: Int? = nil
    var genre: String? = nil
    var playCount: Int? = nil
}

struct Playlist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let comment: String?
    let songCount: Int?
    let duration: Int?
    let owner: String?
    let coverArt: String?
    let readonly: Bool?

    // Navidrome surfaces .nsp smart playlists through the standard playlists API,
    // marking them readonly with an "Auto-imported from '*.nsp'" comment.
    var isSmart: Bool {
        readonly == true && (comment?.contains(".nsp") ?? false)
    }
}

struct PlaylistDetailResponse: Decodable {
    let playlist: PlaylistDetail?
}

struct PlaylistDetail: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let comment: String?
    let songCount: Int?
    let duration: Int?
    let owner: String?
    let coverArt: String?
    let readonly: Bool?
    let entry: [Song]?

    var isSmart: Bool {
        readonly == true && (comment?.contains(".nsp") ?? false)
    }
}
