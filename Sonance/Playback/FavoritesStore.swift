import Foundation
import SwiftUI

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var songIDs: Set<String> = []
    @Published private(set) var albumIDs: Set<String> = []
    @Published private(set) var artistIDs: Set<String> = []
    @Published private(set) var lastError: String?

    func refresh(client: SubsonicClient) async {
        do {
            let starred = try await client.starred()
            songIDs = Set((starred.song ?? []).map(\.id))
            albumIDs = Set((starred.album ?? []).map(\.id))
            artistIDs = Set((starred.artist ?? []).map(\.id))
            lastError = nil
        } catch {
            lastError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }

    func clear() {
        songIDs = []
        albumIDs = []
        artistIDs = []
    }

    func isSongFavorite(_ id: String) -> Bool { songIDs.contains(id) }
    func isAlbumFavorite(_ id: String) -> Bool { albumIDs.contains(id) }
    func isArtistFavorite(_ id: String) -> Bool { artistIDs.contains(id) }

    func toggleSong(_ id: String, client: SubsonicClient) async {
        let wasStarred = songIDs.contains(id)
        if wasStarred { songIDs.remove(id) } else { songIDs.insert(id) }
        do {
            if wasStarred {
                try await client.unstar(songID: id)
            } else {
                try await client.star(songID: id)
            }
        } catch {
            // Roll back optimistic update on failure
            if wasStarred { songIDs.insert(id) } else { songIDs.remove(id) }
            lastError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }

    func toggleAlbum(_ id: String, client: SubsonicClient) async {
        let wasStarred = albumIDs.contains(id)
        if wasStarred { albumIDs.remove(id) } else { albumIDs.insert(id) }
        do {
            if wasStarred {
                try await client.unstar(albumID: id)
            } else {
                try await client.star(albumID: id)
            }
        } catch {
            if wasStarred { albumIDs.insert(id) } else { albumIDs.remove(id) }
            lastError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }

    func toggleArtist(_ id: String, client: SubsonicClient) async {
        let wasStarred = artistIDs.contains(id)
        if wasStarred { artistIDs.remove(id) } else { artistIDs.insert(id) }
        do {
            if wasStarred {
                try await client.unstar(artistID: id)
            } else {
                try await client.star(artistID: id)
            }
        } catch {
            if wasStarred { artistIDs.insert(id) } else { artistIDs.remove(id) }
            lastError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }
}
