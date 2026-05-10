import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var artists: [Artist] = []
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && artists.isEmpty {
                ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                Text(err).foregroundStyle(.red).padding(40)
            } else {
                List(artists) { artist in
                    NavigationLink(value: artist) {
                        ArtistRow(artist: artist, client: auth.client)
                    }
                }
            }
        }
        .navigationTitle("Artists")
        .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
        .task { await load() }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            artists = try await client.artists().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct ArtistRow: View {
    let artist: Artist
    let client: SubsonicClient?

    var body: some View {
        HStack(spacing: 12) {
            cover.frame(width: 36, height: 36).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                if let count = artist.albumCount {
                    Text("\(count) albums").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverID = artist.coverArt, let url = client?.coverArtURL(id: coverID, size: 96) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle().fill(.quaternary).overlay(Image(systemName: "person").foregroundStyle(.secondary))
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject var auth: AuthStore
    let artist: Artist
    @State private var detail: ArtistDetail?
    @State private var loadError: String?
    @State private var isLoading = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(artist.name).font(.largeTitle).bold().padding(.horizontal, 20).padding(.top, 16)
                if isLoading && detail == nil {
                    ProgressView().padding(40).frame(maxWidth: .infinity)
                } else if let err = loadError {
                    Text(err).foregroundStyle(.red).padding(20)
                } else if let albums = detail?.album, !albums.isEmpty {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(albums) { album in
                            AlbumGridItem(album: album)
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                } else {
                    Text("No albums").foregroundStyle(.secondary).padding(20)
                }
            }
        }
        .navigationTitle(artist.name)
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        .task { await load() }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await client.artist(id: artist.id)
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}
