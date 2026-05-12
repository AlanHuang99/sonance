import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var library: LibraryStore
    @State private var playlists: [Playlist] = []
    @State private var selectedID: Playlist.ID?
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        HSplitView {
            playlistList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            playlistDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Playlists")
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

    private var playlistList: some View {
        Group {
            if isLoading && playlists.isEmpty {
                ProgressView().padding()
            } else if let err = loadError {
                Text(err).foregroundStyle(.red).padding()
            } else {
                List(selection: $selectedID) {
                    ForEach(playlists) { p in
                        PlaylistRow(playlist: p).tag(p.id as String?)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var playlistDetail: some View {
        if let id = selectedID, let p = playlists.first(where: { $0.id == id }) {
            PlaylistDetailView(summary: p)
                .id(id)
        } else {
            VStack(spacing: 8) {
                Text("Select a playlist").font(.title2)
                Text("Smart playlists (\(Image(systemName: "sparkles"))) come from .nsp files and are read-only.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        await load(refresh: false)
    }

    private func load(refresh: Bool) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            playlists = try await library.playlists(client: client, refresh: refresh)
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: playlist.isSmart ? "sparkles" : "music.note.list")
                .foregroundStyle(playlist.isSmart ? .yellow : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).lineLimit(1)
                HStack(spacing: 6) {
                    if let count = playlist.songCount {
                        Text("\(count) tracks").font(.caption).foregroundStyle(.secondary)
                    }
                    if playlist.isSmart {
                        Text("Smart").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.yellow.opacity(0.2), in: Capsule())
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: LibraryStore
    let summary: Playlist
    @State private var detail: PlaylistDetail?
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            tracks
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

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(summary.name).font(.title).bold()
                    if summary.isSmart {
                        Label("Smart", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.yellow.opacity(0.2), in: Capsule())
                            .foregroundStyle(.yellow)
                    }
                }
                if let owner = summary.owner {
                    Text("By \(owner)").font(.callout).foregroundStyle(.secondary)
                }
                if let comment = summary.comment, !comment.isEmpty {
                    Text(comment).font(.caption).foregroundStyle(.tertiary)
                }
                Button {
                    playAll()
                } label: {
                    Label("Play", systemImage: "play.fill").frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .disabled((detail?.entry?.isEmpty ?? true))
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var tracks: some View {
        if isLoading && detail == nil {
            ProgressView().padding(40).frame(maxWidth: .infinity)
        } else if let err = loadError {
            Text(err).foregroundStyle(.red).padding(40)
        } else if let songs = detail?.entry, !songs.isEmpty {
            TrackListView(songs: songs, onPlay: { idx in playSong(at: idx) })
        } else {
            Text("Empty playlist").foregroundStyle(.secondary).padding(40).frame(maxWidth: .infinity)
        }
    }

    private func load() async {
        await load(refresh: false)
    }

    private func load(refresh: Bool) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await library.playlistDetail(id: summary.id, client: client, refresh: refresh)
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func playAll() {
        guard let songs = detail?.entry, let client = auth.client else { return }
        player.play(songs, startAt: 0, using: client)
    }

    private func playSong(at index: Int) {
        guard let songs = detail?.entry, let client = auth.client else { return }
        player.play(songs, startAt: index, using: client)
    }
}
