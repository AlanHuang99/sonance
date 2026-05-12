import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    private var albumLists: [String: [Album]] = [:]
    private var albumListTasks: [String: Task<[Album], Error>] = [:]

    private var artistsByAccount: [String: [Artist]] = [:]
    private var artistTasks: [String: Task<[Artist], Error>] = [:]

    private var albumDetails: [String: AlbumDetail] = [:]
    private var albumDetailTasks: [String: Task<AlbumDetail, Error>] = [:]

    private var artistDetails: [String: ArtistDetail] = [:]
    private var artistDetailTasks: [String: Task<ArtistDetail, Error>] = [:]

    private var randomSongsByAccount: [String: [Song]] = [:]
    private var randomSongTasks: [String: Task<[Song], Error>] = [:]

    private var starredByAccount: [String: Starred2Container] = [:]
    private var starredTasks: [String: Task<Starred2Container, Error>] = [:]

    private var playlistsByAccount: [String: [Playlist]] = [:]
    private var playlistTasks: [String: Task<[Playlist], Error>] = [:]

    private var playlistDetails: [String: PlaylistDetail] = [:]
    private var playlistDetailTasks: [String: Task<PlaylistDetail, Error>] = [:]

    private var searchResults: [String: SearchResult] = [:]
    private var searchTasks: [String: Task<SearchResult, Error>] = [:]

    func clear() {
        albumListTasks.values.forEach { $0.cancel() }
        artistTasks.values.forEach { $0.cancel() }
        albumDetailTasks.values.forEach { $0.cancel() }
        artistDetailTasks.values.forEach { $0.cancel() }
        randomSongTasks.values.forEach { $0.cancel() }
        starredTasks.values.forEach { $0.cancel() }
        playlistTasks.values.forEach { $0.cancel() }
        playlistDetailTasks.values.forEach { $0.cancel() }
        searchTasks.values.forEach { $0.cancel() }
        albumListTasks.removeAll()
        artistTasks.removeAll()
        albumDetailTasks.removeAll()
        artistDetailTasks.removeAll()
        randomSongTasks.removeAll()
        starredTasks.removeAll()
        playlistTasks.removeAll()
        playlistDetailTasks.removeAll()
        searchTasks.removeAll()
        albumLists.removeAll()
        artistsByAccount.removeAll()
        albumDetails.removeAll()
        artistDetails.removeAll()
        randomSongsByAccount.removeAll()
        starredByAccount.removeAll()
        playlistsByAccount.removeAll()
        playlistDetails.removeAll()
        searchResults.removeAll()
    }

    func albumList(sort: AlbumSort, size: Int, client: SubsonicClient, refresh: Bool = false) async throws -> [Album] {
        let key = "\(account(client))|albums|\(sort.rawValue)|\(size)"
        if !refresh, let cached = albumLists[key] { return cached }
        if !refresh, let task = albumListTasks[key] { return try await task.value }

        let task = Task<[Album], Error> {
            try await client.albumList(type: sort.rawValue, size: size)
        }
        albumListTasks[key] = task
        defer { albumListTasks[key] = nil }

        let value = try await task.value
        albumLists[key] = value
        return value
    }

    func artists(client: SubsonicClient, refresh: Bool = false) async throws -> [Artist] {
        let key = "\(account(client))|artists"
        if !refresh, let cached = artistsByAccount[key] { return cached }
        if !refresh, let task = artistTasks[key] { return try await task.value }

        let task = Task<[Artist], Error> {
            try await client.artists()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        artistTasks[key] = task
        defer { artistTasks[key] = nil }

        let value = try await task.value
        artistsByAccount[key] = value
        return value
    }

    func albumDetail(id: String, client: SubsonicClient, refresh: Bool = false) async throws -> AlbumDetail {
        let key = "\(account(client))|album|\(id)"
        if !refresh, let cached = albumDetails[key] { return cached }
        if !refresh, let task = albumDetailTasks[key] { return try await task.value }

        let task = Task<AlbumDetail, Error> { try await client.album(id: id) }
        albumDetailTasks[key] = task
        defer { albumDetailTasks[key] = nil }

        let value = try await task.value
        albumDetails[key] = value
        return value
    }

    func artistDetail(id: String, client: SubsonicClient, refresh: Bool = false) async throws -> ArtistDetail {
        let key = "\(account(client))|artist|\(id)"
        if !refresh, let cached = artistDetails[key] { return cached }
        if !refresh, let task = artistDetailTasks[key] { return try await task.value }

        let task = Task<ArtistDetail, Error> { try await client.artist(id: id) }
        artistDetailTasks[key] = task
        defer { artistDetailTasks[key] = nil }

        let value = try await task.value
        artistDetails[key] = value
        return value
    }

    func randomSongs(size: Int, client: SubsonicClient, refresh: Bool = false) async throws -> [Song] {
        let key = "\(account(client))|random|\(size)"
        if !refresh, let cached = randomSongsByAccount[key] { return cached }
        if !refresh, let task = randomSongTasks[key] { return try await task.value }

        let task = Task<[Song], Error> { try await client.randomSongs(size: size) }
        randomSongTasks[key] = task
        defer { randomSongTasks[key] = nil }

        let value = try await task.value
        randomSongsByAccount[key] = value
        return value
    }

    func starred(client: SubsonicClient, refresh: Bool = false) async throws -> Starred2Container {
        let key = "\(account(client))|starred"
        if !refresh, let cached = starredByAccount[key] { return cached }
        if !refresh, let task = starredTasks[key] { return try await task.value }

        let task = Task<Starred2Container, Error> { try await client.starred() }
        starredTasks[key] = task
        defer { starredTasks[key] = nil }

        let value = try await task.value
        starredByAccount[key] = value
        return value
    }

    func playlists(client: SubsonicClient, refresh: Bool = false) async throws -> [Playlist] {
        let key = "\(account(client))|playlists"
        if !refresh, let cached = playlistsByAccount[key] { return cached }
        if !refresh, let task = playlistTasks[key] { return try await task.value }

        let task = Task<[Playlist], Error> {
            try await client.playlists()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        playlistTasks[key] = task
        defer { playlistTasks[key] = nil }

        let value = try await task.value
        playlistsByAccount[key] = value
        return value
    }

    func playlistDetail(id: String, client: SubsonicClient, refresh: Bool = false) async throws -> PlaylistDetail {
        let key = "\(account(client))|playlist|\(id)"
        if !refresh, let cached = playlistDetails[key] { return cached }
        if !refresh, let task = playlistDetailTasks[key] { return try await task.value }

        let task = Task<PlaylistDetail, Error> { try await client.playlist(id: id) }
        playlistDetailTasks[key] = task
        defer { playlistDetailTasks[key] = nil }

        let value = try await task.value
        playlistDetails[key] = value
        return value
    }

    func search(query: String, client: SubsonicClient, refresh: Bool = false) async throws -> SearchResult {
        let normalized = normalizeSearch(query)
        let key = "\(account(client))|search|\(normalized)"
        if !refresh, let cached = searchResults[key] { return cached }
        if !refresh, let task = searchTasks[key] { return try await task.value }

        let task = Task<SearchResult, Error> { try await client.search(normalized) }
        searchTasks[key] = task
        defer { searchTasks[key] = nil }

        let value = try await task.value
        searchResults[key] = value
        return value
    }

    func normalizeSearch(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func account(_ client: SubsonicClient) -> String {
        client.credentials.accountID
    }
}
