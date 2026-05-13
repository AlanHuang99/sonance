import SwiftUI

enum LibrarySection: String, Hashable, CaseIterable, Identifiable {
    case albums = "Albums"
    case artists = "Artists"
    case discover = "Discover"
    case genres = "Genres"
    case playlists = "Playlists"
    case favorites = "Favorites"
    case search = "Search"
    case accounts = "Accounts"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .albums: return "square.stack"
        case .artists: return "person.2"
        case .discover: return "shuffle"
        case .genres: return "guitars"
        case .playlists: return "music.note.list"
        case .favorites: return "heart.fill"
        case .search: return "magnifyingglass"
        case .accounts: return "person.crop.circle"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var navigation: NavigationCoordinator

    // Each section owns its own NavigationStack path. One global `NavigationStack` whose root
    // view *type* swaps (the prior `Group { switch ... }` design) loses pushes during the
    // swap: SwiftUI re-evaluates destination registrations against the new root identity and
    // silently reverts any path entry whose destination isn't resolved in that frame. Giving
    // every section its own stack means each stack's root view type is stable, and the only
    // moving piece during a cross-section jump is *which stack the user is looking at* — the
    // target stack's path is already prepared before the visible section swaps in.
    @State private var albumsPath = NavigationPath()
    @State private var artistsPath = NavigationPath()
    @State private var discoverPath = NavigationPath()
    @State private var genresPath = NavigationPath()
    @State private var playlistsPath = NavigationPath()
    @State private var favoritesPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var accountsPath = NavigationPath()

    private var selectionBinding: Binding<LibrarySection?> {
        // Sidebar selection: route writes through `switch_(to:)` so a user-initiated section
        // change also bumps `sectionResetSignal` and resets the target section's stack.
        // Cross-link writes (`requestAlbumNavigation` / `requestArtistNavigation`) use the
        // `navigationRequest` channel and update the destination section's path directly.
        Binding(
            get: { navigation.selectedSection },
            set: { newValue in
                if let newValue {
                    navigation.switch_(to: newValue)
                } else {
                    navigation.selectedSection = nil
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(LibrarySection.allCases, id: \.self) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                }
                if !auth.savedAccounts.isEmpty {
                    Section("Saved Accounts") {
                        ForEach(auth.savedAccounts) { account in
                            Button {
                                switchToAccount(account.id)
                            } label: {
                                let isCurrent = account.id == auth.activeAccountID
                                let icon = isCurrent ? "checkmark.circle.fill" : "server.rack"
                                let iconColor: Color = isCurrent ? .accentColor : .secondary
                                HStack {
                                    Image(systemName: icon)
                                        .foregroundStyle(iconColor)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(account.credentials.displayHost)
                                        Text(account.credentials.username)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if isCurrent {
                                        Spacer(minLength: 0)
                                        Text("Active")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(account.id == auth.activeAccountID)
                        }
                    }
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
            detailContent
        }
        .task {
            if let client = auth.client {
                await favorites.refresh(client: client)
            }
        }
        .onChange(of: navigation.sectionResetSignal) { _, _ in
            // A user-initiated section switch (sidebar click, ⌘1..⌘6, ⌘F) lands at the new
            // section's root. Only reset the *target* section's path — leaving the others
            // alone preserves their state in case the user comes back via sidebar later.
            resetPath(for: navigation.selectedSection)
        }
        .onChange(of: navigation.navigationRequest) { _, request in
            guard let request else { return }
            handleNavigationRequest(request)
            navigation.navigationRequest = nil
        }
    }

    /// Pick the NavigationStack for the currently-selected section. Each stack's root view
    /// has a stable type, so SwiftUI doesn't drop pushed destinations the way it did when a
    /// single stack's root view alternated between section types.
    @ViewBuilder
    private var detailContent: some View {
        switch navigation.selectedSection {
        case .albums:
            NavigationStack(path: $albumsPath) {
                AlbumsView().attachLibraryNavigationDestinations()
            }
        case .artists:
            NavigationStack(path: $artistsPath) {
                ArtistsView().attachLibraryNavigationDestinations()
            }
        case .discover:
            NavigationStack(path: $discoverPath) {
                DiscoverView().attachLibraryNavigationDestinations()
            }
        case .genres:
            NavigationStack(path: $genresPath) {
                GenresView().attachLibraryNavigationDestinations()
            }
        case .playlists:
            NavigationStack(path: $playlistsPath) {
                PlaylistsView().attachLibraryNavigationDestinations()
            }
        case .favorites:
            NavigationStack(path: $favoritesPath) {
                FavoritesView().attachLibraryNavigationDestinations()
            }
        case .search:
            NavigationStack(path: $searchPath) {
                SearchView().attachLibraryNavigationDestinations()
            }
        case .accounts:
            NavigationStack(path: $accountsPath) {
                AccountManagementView().attachLibraryNavigationDestinations()
            }
        case .none:
            PlaceholderView(title: "Select a section")
        }
    }

    private func handleNavigationRequest(_ request: NavigationCoordinator.NavigationRequest) {
        // Order matters: prepare the target section's path BEFORE flipping selectedSection.
        // When SwiftUI swaps in the target section's NavigationStack, its path already
        // contains the destination and the push renders on the first frame — there's no
        // "section flip" frame where the stack briefly has the wrong root for its path.
        let decision = NavigationRequestRouting.decide(
            request: request,
            currentSection: navigation.selectedSection
        )
        mutatePath(for: decision.targetSection) { path in
            if decision.crossesSection { path = NavigationPath() }
            switch request {
            case .album(let a): path.append(a)
            case .artist(let a): path.append(a)
            }
        }
        if decision.crossesSection {
            navigation.selectedSection = decision.targetSection
        }
    }

    private func mutatePath(for section: LibrarySection, _ mutate: (inout NavigationPath) -> Void) {
        switch section {
        case .albums: mutate(&albumsPath)
        case .artists: mutate(&artistsPath)
        case .discover: mutate(&discoverPath)
        case .genres: mutate(&genresPath)
        case .playlists: mutate(&playlistsPath)
        case .favorites: mutate(&favoritesPath)
        case .search: mutate(&searchPath)
        case .accounts: mutate(&accountsPath)
        }
    }

    private func resetPath(for section: LibrarySection?) {
        guard let section else { return }
        mutatePath(for: section) { $0 = NavigationPath() }
    }

    private func switchToAccount(_ id: ServerAccount.ID) {
        player.clearQueue()
        favorites.clear()
        library.clear()
        auth.switchToAccount(id: id)
    }
}

private extension View {
    /// Every section's NavigationStack registers the same set of destinations so a value
    /// pushed onto any stack resolves the same way. Cross-link pushes go through
    /// `handleNavigationRequest` which routes the destination into the target section's
    /// path, so in practice each stack only sees destinations relevant to its own pushes —
    /// but declaring the full set is the simplest contract and keeps NavigationLink(value:)
    /// usage uniform across views.
    func attachLibraryNavigationDestinations() -> some View {
        self
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
            .navigationDestination(for: Genre.self) { GenreDetailView(genre: $0) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(summary: $0) }
    }
}

/// Server info chip at the bottom of the sidebar with a menu for refresh / sign out.
struct ServerFooter: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        Menu {
            Button("Refresh Favorites") {
                if let client = auth.client {
                    Task { await favorites.refresh(client: client) }
                }
            }
            Divider()
            if !auth.savedAccounts.isEmpty {
                Menu("Switch Account") {
                    ForEach(auth.savedAccounts) { account in
                        Button {
                            switchToAccount(account.id)
                        } label: {
                            accountLabel(for: account)
                        }
                        .disabled(account.id == auth.activeAccountID)
                    }
                }
            }
            Button("Connect Another Server") {
                disconnect()
            }
            Button("Forget This Account", role: .destructive) {
                disconnect(forgetCurrentAccount: true)
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
        auth.credentials?.displayHost ?? "Not signed in"
    }

    private func accountLabel(for account: ServerAccount) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(account.credentials.displayHost)
                Text(account.credentials.username)
            }
        } icon: {
            Image(systemName: account.id == auth.activeAccountID ? "checkmark.circle.fill" : "server.rack")
        }
    }

    private func switchToAccount(_ id: ServerAccount.ID) {
        player.clearQueue()
        favorites.clear()
        library.clear()
        auth.switchToAccount(id: id)
    }

    private func disconnect(forgetCurrentAccount: Bool = false) {
        player.clearQueue()
        favorites.clear()
        library.clear()
        auth.signOut(forgetCurrentAccount: forgetCurrentAccount)
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
