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
    @EnvironmentObject var navigation: NavigationCoordinator
    @State private var albums: [Album] = []
    @State private var seenIDs: Set<String> = []
    @State private var loadError: String?
    @State private var isLoadingInitial = false
    @State private var isLoadingMore = false
    @State private var hasMore: Bool = true
    @State private var sort: AlbumSort = .alphabeticalByName
    /// Bumped on every sort change so a stale in-flight load can detect that it shouldn't
    /// apply its results.
    @State private var loadGeneration: Int = 0
    @State private var selectedIndex: Int?
    @State private var columnCount: Int = 1
    @FocusState private var gridFocused: Bool

    private static let pageSize = 100

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            if isLoadingInitial && albums.isEmpty {
                ProgressView().padding(40)
            } else if let err = loadError, albums.isEmpty {
                Text(err).foregroundStyle(.red).padding(40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    sortMenu
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    GeometryReader { geom in
                        Color.clear
                            .onAppear { updateColumnCount(width: geom.size.width) }
                            .onChange(of: geom.size.width) { _, w in updateColumnCount(width: w) }
                    }
                    .frame(height: 0)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(albums.enumerated()), id: \.element.id) { idx, album in
                            AlbumGridItem(album: album, isSelected: selectedIndex == idx)
                        }
                        if hasMore && !albums.isEmpty {
                            loadMoreSentinel
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .navigationTitle("Albums")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await reload(refresh: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoadingInitial)
            }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .task { await reload() }
        .onChange(of: sort) { _, _ in Task { await reload() } }
        .onKeyPress(.leftArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.rightArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(by: -columnCount); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: columnCount); return .handled }
        .onKeyPress(.return) {
            guard let i = selectedIndex, i >= 0, i < albums.count else { return .ignored }
            navigation.requestAlbumNavigation(albums[i])
            return .handled
        }
    }

    private func updateColumnCount(width: CGFloat) {
        // Mirror `.adaptive(minimum: 160)` with 16 pt spacing and 20 pt padding on each side.
        let usable = max(0, width - 40)
        let cell = 160 + 16
        columnCount = max(1, Int(usable / CGFloat(cell)))
    }

    private func moveSelection(by delta: Int) {
        guard !albums.isEmpty else { return }
        let current = selectedIndex ?? -1
        let next = max(0, min(albums.count - 1, current + delta))
        selectedIndex = next
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AlbumSort.allCases) { option in
                Button {
                    sort = option
                } label: {
                    if sort == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Sort: \(sort.label)")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var loadMoreSentinel: some View {
        // Spanning the grid width keeps the spinner centered.
        HStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
                .opacity(isLoadingMore ? 1 : 0)
            Spacer()
        }
        .frame(height: 44)
        .gridCellColumns(columns.count)
        .onAppear {
            Task { await loadMore() }
        }
    }

    /// Reset to page 0 and reload. Used by initial appearance, sort change, and the Refresh
    /// button. Bumps `loadGeneration` so any in-flight pagination request from the prior sort
    /// abandons its results.
    private func reload(refresh: Bool = false) async {
        guard let client = auth.client else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoadingInitial = true
        defer { isLoadingInitial = false }
        do {
            let page = try await client.albumList(type: sort.rawValue, size: Self.pageSize, offset: 0)
            guard generation == loadGeneration else { return }
            albums = page
            seenIDs = Set(page.map(\.id))
            hasMore = page.count == Self.pageSize
            loadError = nil
        } catch let error as SubsonicError {
            guard generation == loadGeneration else { return }
            loadError = error.message
        } catch {
            guard generation == loadGeneration else { return }
            loadError = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let client = auth.client else { return }
        guard hasMore, !isLoadingMore, !isLoadingInitial else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.albumList(
                type: sort.rawValue,
                size: Self.pageSize,
                offset: albums.count
            )
            guard generation == loadGeneration else { return }
            // Skip anything we have already (covers `random` sort, which the server may overlap).
            let fresh = page.filter { !seenIDs.contains($0.id) }
            for album in fresh { seenIDs.insert(album.id) }
            albums.append(contentsOf: fresh)
            // If the server returned fewer than a full page we have reached the tail.
            hasMore = page.count == Self.pageSize && !fresh.isEmpty
        } catch {
            // A pagination error doesn't clear the existing grid; surface in the existing
            // load-error slot only if we have no other albums to show.
            if albums.isEmpty {
                loadError = (error as? SubsonicError)?.message ?? error.localizedDescription
            }
        }
    }
}

/// NavigationLink + tile + context menu, fetches album detail for queue actions.
struct AlbumGridItem: View {
    let album: Album
    var isSelected: Bool = false
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var library: LibraryStore
    @State private var actionError: String?

    var body: some View {
        NavigationLink(value: album) {
            AlbumTile(album: album, client: auth.client, isFavorite: favorites.isAlbumFavorite(album.id))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                )
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
