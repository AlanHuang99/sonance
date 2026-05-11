import SwiftUI

enum LibrarySection: String, Hashable, CaseIterable, Identifiable {
    case albums = "Albums"
    case artists = "Artists"
    case songs = "Songs"
    case playlists = "Playlists"
    case favorites = "Favorites"
    case search = "Search"
    case accounts = "Accounts"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .albums: return "square.stack"
        case .artists: return "person.2"
        case .songs: return "music.note"
        case .playlists: return "music.note.list"
        case .favorites: return "heart.fill"
        case .search: return "magnifyingglass"
        case .accounts: return "person.crop.circle.badge.gearshape"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @State private var selection: LibrarySection? = .albums

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
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
            NavigationStack {
                switch selection {
                case .albums: AlbumsView()
                case .artists: ArtistsView()
                case .songs: SongsView()
                case .playlists: PlaylistsView()
                case .favorites: FavoritesView()
                case .search: SearchView()
                case .accounts: AccountManagementView()
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

    private func switchToAccount(_ id: ServerAccount.ID) {
        player.clearQueue()
        favorites.clear()
        auth.switchToAccount(id: id)
    }
}

/// Server info chip at the bottom of the sidebar with a menu for refresh / sign out.
struct ServerFooter: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore

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
        auth.switchToAccount(id: id)
    }

    private func disconnect(forgetCurrentAccount: Bool = false) {
        player.clearQueue()
        favorites.clear()
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
