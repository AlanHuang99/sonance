import SwiftUI

/// Browse the server's genre index, then drill into albums tagged with the chosen genre via
/// `getAlbumList2(type: byGenre, genre: ...)`. The Subsonic API exposes both endpoints directly.
struct GenresView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var library: LibraryStore
    @State private var genres: [Genre] = []
    @State private var loadError: String?
    @State private var isLoading = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        Group {
            if isLoading && genres.isEmpty {
                ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                Text(err).foregroundStyle(.red).padding(40)
            } else if genres.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "guitars").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No genres reported by the server").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(genres) { genre in
                            NavigationLink(value: genre) {
                                GenreCard(genre: genre)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Genres")
        .navigationDestination(for: Genre.self) { genre in
            GenreDetailView(genre: genre)
        }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    private func load(refresh: Bool = false) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            genres = try await library.genres(client: client, refresh: refresh)
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct GenreCard: View {
    let genre: Genre

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(genre.value).font(.headline).lineLimit(2)
            HStack(spacing: 6) {
                if let a = genre.albumCount {
                    Text("\(a) albums").font(.caption).foregroundStyle(.secondary)
                }
                if let s = genre.songCount {
                    if genre.albumCount != nil { Text("•").foregroundStyle(.secondary) }
                    Text("\(s) songs").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct GenreDetailView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var library: LibraryStore
    let genre: Genre
    @State private var albums: [Album] = []
    @State private var loadError: String?
    @State private var isLoading = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            if isLoading && albums.isEmpty {
                ProgressView().padding(40)
            } else if let err = loadError {
                Text(err).foregroundStyle(.red).padding(20)
            } else if albums.isEmpty {
                Text("No albums for \(genre.value)").foregroundStyle(.secondary).padding(20)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums) { album in
                        AlbumGridItem(album: album)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
        }
        .navigationTitle(genre.value)
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    private func load(refresh: Bool = false) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            albums = try await library.albumsByGenre(genre.value, client: client, refresh: refresh)
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}
