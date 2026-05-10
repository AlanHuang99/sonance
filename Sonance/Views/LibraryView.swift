import SwiftUI

enum LibrarySection: String, Hashable, CaseIterable, Identifiable {
    case albums = "Albums"
    case artists = "Artists"
    case songs = "Songs"
    case playlists = "Playlists"
    case favorites = "Favorites"
    case search = "Search"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .albums: return "square.stack"
        case .artists: return "person.2"
        case .songs: return "music.note"
        case .playlists: return "music.note.list"
        case .favorites: return "heart.fill"
        case .search: return "magnifyingglass"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var favorites: FavoritesStore
    @State private var selection: LibrarySection? = .albums

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(LibrarySection.allCases, id: \.self) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    ServerFooter()
                        .background(.bar)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            NavigationStack {
                switch selection {
                case .albums: AlbumsView()
                case .artists: ArtistsView()
                case .songs: SongsView()
                case .playlists: PlaylistsView()
                case .favorites: FavoritesView()
                case .search: SearchView()
                case .none: PlaceholderView(title: "Select a section")
                }
            }
        }
        .task {
            if let client = auth.client {
                await favorites.refresh(client: client)
            }
        }
    }
}

/// Server info chip at the bottom of the sidebar with a menu for refresh / sign out.
struct ServerFooter: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var favorites: FavoritesStore

    var body: some View {
        Menu {
            Button("Refresh Favorites") {
                if let client = auth.client {
                    Task { await favorites.refresh(client: client) }
                }
            }
            Divider()
            Button("Sign Out", role: .destructive) {
                favorites.clear()
                auth.signOut()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayHost)
                        .font(.caption).fontWeight(.medium)
                        .lineLimit(1)
                    Text(auth.credentials?.username ?? "")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var displayHost: String {
        guard let raw = auth.credentials?.serverURL else { return "Not signed in" }
        if let url = URL(string: raw), let host = url.host {
            if let port = url.port { return "\(host):\(port)" }
            return host
        }
        return raw
    }
}

struct PlaceholderView: View {
    let title: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.largeTitle)
            Text("Not implemented yet").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
