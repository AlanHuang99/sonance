import SwiftUI

enum AlbumSort: String, CaseIterable, Identifiable {
    case alphabeticalByName, newest, recent, frequent, random
    var id: String { rawValue }
    var label: String {
        switch self {
        case .alphabeticalByName: return "A–Z"
        case .newest: return "Newest"
        case .recent: return "Recently Played"
        case .frequent: return "Most Played"
        case .random: return "Random"
        }
    }
}

struct AlbumsView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var albums: [Album] = []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var sort: AlbumSort = .alphabeticalByName

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            if isLoading && albums.isEmpty {
                ProgressView().padding(40)
            } else if let err = loadError {
                Text(err).foregroundStyle(.red).padding(40)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums) { album in
                        AlbumGridItem(album: album)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Albums")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Picker("Sort", selection: $sort) {
                    ForEach(AlbumSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .onChange(of: sort) { Task { await load() } }
            }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .task { await load() }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            albums = try await client.albumList(type: sort.rawValue, size: 200)
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// NavigationLink + tile + context menu, fetches album detail for queue actions.
struct AlbumGridItem: View {
    let album: Album
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore

    var body: some View {
        NavigationLink(value: album) {
            AlbumTile(album: album, client: auth.client, isFavorite: favorites.isAlbumFavorite(album.id))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play") { Task { await fetchAndPlay() } }
            Button("Play Next") { Task { await fetchAndPlayNext() } }
            Button("Add to Queue") { Task { await fetchAndAppend() } }
            Divider()
            Button(favorites.isAlbumFavorite(album.id) ? "Remove Favorite" : "Add Favorite") {
                Task {
                    if let client = auth.client { await favorites.toggleAlbum(album.id, client: client) }
                }
            }
        }
    }

    private func fetchAndPlay() async {
        guard let client = auth.client else { return }
        if let songs = try? await client.album(id: album.id).song, !songs.isEmpty {
            await MainActor.run { player.play(songs, startAt: 0, using: client) }
        }
    }
    private func fetchAndPlayNext() async {
        guard let client = auth.client else { return }
        if let songs = try? await client.album(id: album.id).song, !songs.isEmpty {
            await MainActor.run { player.playNext(songs, using: client) }
        }
    }
    private func fetchAndAppend() async {
        guard let client = auth.client else { return }
        if let songs = try? await client.album(id: album.id).song, !songs.isEmpty {
            await MainActor.run { player.appendToQueue(songs, using: client) }
        }
    }
}

struct AlbumTile: View {
    let album: Album
    let client: SubsonicClient?
    var isFavorite: Bool = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SmoothCoverImage(
                url: album.coverArt.flatMap { client?.coverArtURL(id: $0) }
            )
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(isHovered ? 0.20 : 0), radius: isHovered ? 12 : 0, y: isHovered ? 6 : 0)
            .scaleEffect(isHovered ? 1.02 : 1.0)

            Text(album.name).font(.headline).lineLimit(1)
            if let artist = album.artist {
                Text(artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
