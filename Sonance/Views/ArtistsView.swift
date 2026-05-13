import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var library: LibraryStore
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
            artists = try await library.artists(client: client, refresh: refresh)
            loadError = nil
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
            CoverArtImage(coverArtID: artist.coverArt, size: 96, client: client, corner: 18, glyph: "person")
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                if let count = artist.albumCount {
                    Text("\(count) albums").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

}

struct ArtistDetailView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var navigation: NavigationCoordinator
    let artist: Artist
    @State private var detail: ArtistDetail?
    @State private var info: ArtistInfo?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var isExpanded = false
    /// Filled once the user clicks "Play All" / "Shuffle All" on the discography. Loading every
    /// album's tracks is N round-trips and the user may never want it; defer until requested.
    @State private var loadingDiscography = false
    @State private var discographyError: String?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if isLoading && detail == nil {
                    ProgressView().padding(40).frame(maxWidth: .infinity)
                } else if let err = loadError {
                    Text(err).foregroundStyle(.red).padding(20)
                } else {
                    if let info, info.biography?.isEmpty == false {
                        bio(info)
                    }
                    if let albums = detail?.album, !albums.isEmpty {
                        sectionHeader("Albums")
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(albums) { album in
                                AlbumGridItem(album: album)
                            }
                        }
                        .padding(.horizontal, 20)
                    } else {
                        Text("No albums").foregroundStyle(.secondary).padding(20)
                    }
                    if let similar = info?.similarArtist, !similar.isEmpty {
                        sectionHeader("Similar Artists")
                        similarArtistsList(similar)
                    }
                }
                if let err = discographyError {
                    Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal, 20)
                }
                Color.clear.frame(height: 20)
            }
        }
        .navigationTitle(artist.name)
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        .task { await load() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: toggleFavorite) {
                    Image(systemName: favorites.isArtistFavorite(artist.id) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.isArtistFavorite(artist.id) ? Color.pink : .secondary)
                }
                .help(favorites.isArtistFavorite(artist.id) ? "Remove favorite" : "Add favorite")
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            artistImage
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .overlay(Circle().stroke(.quaternary, lineWidth: 1))
            VStack(alignment: .leading, spacing: 8) {
                Text(artist.name).font(.largeTitle).bold().lineLimit(2)
                if let count = artist.albumCount ?? detail?.albumCount {
                    Text("\(count) album\(count == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await playDiscography(shuffled: false) }
                    } label: {
                        Label("Play All", systemImage: "play.fill").frame(width: 90)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((detail?.album?.isEmpty ?? true) || loadingDiscography)

                    Button {
                        Task { await playDiscography(shuffled: true) }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .disabled((detail?.album?.isEmpty ?? true) || loadingDiscography)

                    if loadingDiscography {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var artistImage: some View {
        // Prefer `getArtistInfo2`'s larger remote image when available; fall back to the
        // server's `coverArt` for the artist. Both can be missing on Subsonic-only servers
        // that don't index artist photos, in which case `CoverArtImage`'s glyph stands in.
        if let urlString = info?.largeImageUrl ?? info?.mediumImageUrl,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                case .failure: fallbackCoverArt
                case .empty: Color.gray.opacity(0.1)
                @unknown default: fallbackCoverArt
                }
            }
        } else {
            fallbackCoverArt
        }
    }

    private var fallbackCoverArt: some View {
        CoverArtImage(coverArtID: artist.coverArt ?? detail?.coverArt, size: 300, client: auth.client, corner: 0, glyph: "person")
    }

    @ViewBuilder
    private func bio(_ info: ArtistInfo) -> some View {
        if let biography = info.biography, !biography.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(cleanedBiography(biography))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                if shouldOfferExpand(biography) {
                    Button(isExpanded ? "Less" : "More") {
                        withAnimation { isExpanded.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Last.fm bios that Subsonic forwards are HTML-flavored — strip the `<a>` link wrappers so
    /// the user doesn't see raw tags. Conservative: only the most common tags Last.fm emits;
    /// anything else stays as-is so unfamiliar markup is at least visible, not dropped.
    private func cleanedBiography(_ s: String) -> String {
        s.replacingOccurrences(of: #"<a [^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "</a>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldOfferExpand(_ s: String) -> Bool {
        cleanedBiography(s).count > 220
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3).bold()
            .padding(.horizontal, 20)
            .padding(.top, 8)
    }

    private func similarArtistsList(_ similar: [Artist]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(similar) { sim in
                    Button {
                        navigation.requestArtistNavigation(sim)
                    } label: {
                        VStack(spacing: 6) {
                            CoverArtImage(coverArtID: sim.coverArt, size: 200, client: auth.client, corner: 100, glyph: "person")
                                .frame(width: 88, height: 88)
                                .clipShape(Circle())
                            Text(sim.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                .frame(width: 96)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func load(refresh: Bool = false) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let detailLoad = library.artistDetail(id: artist.id, client: client, refresh: refresh)
            async let infoLoad = library.artistInfo(id: artist.id, client: client, refresh: refresh)
            detail = try await detailLoad
            // Artist info is optional; some servers don't implement getArtistInfo2 and we don't
            // want a 404/501 there to mask the artist's actual discography.
            info = try? await infoLoad
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func toggleFavorite() {
        guard let client = auth.client else { return }
        Task { await favorites.toggleArtist(artist.id, client: client) }
    }

    private func playDiscography(shuffled: Bool) async {
        guard let client = auth.client, let albums = detail?.album, !albums.isEmpty else { return }
        loadingDiscography = true
        discographyError = nil
        defer { loadingDiscography = false }
        do {
            // Fetch each album's track list and concatenate. Run sequentially through the cache
            // so the per-album debounce + cache layer is honored; the user can see partial
            // progress is not visible, but typical artists have <30 albums so this stays under
            // a couple of seconds. If performance becomes a problem we can fan out via a
            // bounded TaskGroup.
            var all: [Song] = []
            for album in albums {
                let detail = try await library.albumDetail(id: album.id, client: client)
                if let songs = detail.song { all.append(contentsOf: songs) }
            }
            guard !all.isEmpty else { return }
            if shuffled { all.shuffle() }
            player.play(all, startAt: 0, using: client)
        } catch {
            discographyError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }
}
