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
    @EnvironmentObject var library: LibraryStore
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
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

    private func load(refresh: Bool = false) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            albums = try await library.albumList(sort: sort, size: 200, client: client, refresh: refresh)
            loadError = nil
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
    @EnvironmentObject var library: LibraryStore
    @State private var actionError: String?

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
        .alert("Album Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func fetchAndPlay() async {
        guard let client = auth.client else { return }
        do {
            let songs = try await library.albumDetail(id: album.id, client: client).song ?? []
            guard !songs.isEmpty else { return }
            await MainActor.run { player.play(songs, startAt: 0, using: client) }
        } catch {
            actionError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }

    private func fetchAndPlayNext() async {
        guard let client = auth.client else { return }
        do {
            let songs = try await library.albumDetail(id: album.id, client: client).song ?? []
            guard !songs.isEmpty else { return }
            await MainActor.run { player.playNext(songs, using: client) }
        } catch {
            actionError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }

    private func fetchAndAppend() async {
        guard let client = auth.client else { return }
        do {
            let songs = try await library.albumDetail(id: album.id, client: client).song ?? []
            guard !songs.isEmpty else { return }
            await MainActor.run { player.appendToQueue(songs, using: client) }
        } catch {
            actionError = (error as? SubsonicError)?.message ?? error.localizedDescription
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
            CoverArtImage(coverArtID: album.coverArt, size: 300, client: client)
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
