import SwiftUI

struct SearchView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: LibraryStore
    @State private var query = ""
    @State private var result: SearchResult?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchGeneration = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search artists, albums, songs", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            }
            .padding(20)
            Divider()
            content
        }
        .navigationTitle("Search")
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
    }

    @ViewBuilder
    private var content: some View {
        if query.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                Text("Type to search").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading && result == nil {
            ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = loadError {
            Text(err).foregroundStyle(.red).padding(20)
        } else if let r = result {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let artists = r.artist, !artists.isEmpty {
                        sectionHeader("Artists", count: artists.count)
                        ForEach(artists) { artist in
                            NavigationLink(value: artist) {
                                ArtistRow(artist: artist, client: auth.client)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let albums = r.album, !albums.isEmpty {
                        sectionHeader("Albums", count: albums.count)
                        let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(albums) { album in
                                AlbumGridItem(album: album)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    if let songs = r.song, !songs.isEmpty {
                        sectionHeader("Songs", count: songs.count)
                        TrackListView(songs: songs, onPlay: { idx in
                            if let client = auth.client {
                                player.play(songs, startAt: idx, using: client)
                            }
                        })
                        .frame(minHeight: CGFloat(min(songs.count, 12)) * 50)
                    }
                    if (r.artist?.isEmpty ?? true) && (r.album?.isEmpty ?? true) && (r.song?.isEmpty ?? true) {
                        Text("No results for \"\(query)\"").foregroundStyle(.secondary).padding(20)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(.headline)
            .padding(.horizontal, 20)
    }

    private func scheduleSearch(_ q: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            if Task.isCancelled { return }
            await runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        guard let client = auth.client else { return }
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            result = nil
            loadError = nil
            isLoading = false
            return
        }
        let normalized = library.normalizeSearch(trimmed)
        let generation = UUID()
        searchGeneration = generation
        isLoading = true
        do {
            let next = try await library.search(query: trimmed, client: client)
            guard searchGeneration == generation,
                  library.normalizeSearch(query) == normalized else { return }
            result = next
            loadError = nil
        } catch let error as SubsonicError {
            guard searchGeneration == generation else { return }
            loadError = error.message
        } catch {
            guard searchGeneration == generation else { return }
            loadError = error.localizedDescription
        }
        if searchGeneration == generation {
            isLoading = false
        }
    }
}
