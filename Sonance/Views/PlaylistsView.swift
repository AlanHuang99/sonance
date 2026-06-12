import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var library: LibraryStore
    @State private var playlists: [Playlist] = []
    @State private var selectedID: Playlist.ID?
    @State private var loadError: String?
    @State private var isLoading = false

    // Mutation state
    @State private var newPlaylistName: String = ""
    @State private var showingNewPlaylistPrompt = false
    @State private var renameTargetID: String?
    @State private var renameDraft: String = ""
    @State private var actionError: String?

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
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    newPlaylistName = ""
                    showingNewPlaylistPrompt = true
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .alert("New Playlist", isPresented: $showingNewPlaylistPrompt) {
            TextField("Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task { await createPlaylist(name: name) }
            }
        }
        .alert("Rename Playlist", isPresented: Binding(
            get: { renameTargetID != nil },
            set: { if !$0 { renameTargetID = nil } }
        )) {
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameTargetID = nil }
            Button("Save") {
                guard let id = renameTargetID else { return }
                let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                renameTargetID = nil
                guard !name.isEmpty else { return }
                Task { await renamePlaylist(id: id, name: name) }
            }
        }
        .alert("Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
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
                        PlaylistRow(playlist: p)
                            .tag(p.id as String?)
                            .contextMenu {
                                if !p.isSmart {
                                    Button("Rename") { beginRename(p) }
                                    Button("Delete", role: .destructive) {
                                        Task { await deletePlaylist(id: p.id) }
                                    }
                                } else {
                                    Text("Smart playlists are read-only")
                                        .foregroundStyle(.secondary)
                                }
                            }
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

    private func createPlaylist(name: String) async {
        guard let client = auth.client else { return }
        do {
            let created = try await client.createPlaylist(name: name)
            await load(refresh: true)
            if let createdID = created?.id, playlists.contains(where: { $0.id == createdID }) {
                // Prefer the server-returned ID: selecting by name is wrong if another
                // playlist with the same name already exists.
                selectedID = createdID
            } else if let newest = playlists.first(where: { $0.name == name }) {
                // Some servers reply to createPlaylist with just status=ok and no body. Fall
                // back to the name match — best-effort, and only meaningful if names are
                // unique.
                selectedID = newest.id
            }
        } catch {
            actionError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }

    private func beginRename(_ playlist: Playlist) {
        renameDraft = playlist.name
        renameTargetID = playlist.id
    }

    private func renamePlaylist(id: String, name: String) async {
        guard let client = auth.client else { return }
        do {
            try await client.renamePlaylist(id: id, to: name)
            await load(refresh: true)
        } catch {
            actionError = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }

    private func deletePlaylist(id: String) async {
        guard let client = auth.client else { return }
        do {
            try await client.deletePlaylist(id: id)
            if selectedID == id { selectedID = nil }
            await load(refresh: true)
        } catch {
            actionError = (error as? SubsonicError)?.message ?? error.localizedDescription
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
    @State private var actionError: String?
    @State private var showingAddTracks = false
    /// Single mutation queue covering reorder + removal + (future) other positional edits.
    /// Two separate chains would let a delete fire `updatePlaylist` against an unsynced
    /// reorder — Subsonic's index-based removal semantics need a strict total order across
    /// every mutation, not just within one family.
    @State private var mutationTask: Task<Void, Never>?

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
        .sheet(isPresented: $showingAddTracks) {
            AddTracksToPlaylistSheet(
                playlistID: summary.id,
                existingIDs: Set((detail?.entry ?? []).map(\.id)),
                onAdded: { addedIDs in
                    Task { await load(refresh: true) }
                }
            )
        }
        .alert("Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
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
                HStack(spacing: 10) {
                    Button {
                        playAll()
                    } label: {
                        Label("Play", systemImage: "play.fill").frame(width: 88)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled((detail?.entry?.isEmpty ?? true))
                    if !summary.isSmart {
                        Button {
                            showingAddTracks = true
                        } label: {
                            Label("Add Tracks", systemImage: "plus")
                        }
                        .controlSize(.large)
                    }
                }
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
            if summary.isSmart {
                TrackListView(songs: songs, onPlay: { idx in playSong(at: idx) })
            } else {
                EditablePlaylistTrackList(
                    playlistID: summary.id,
                    songs: songs,
                    onPlay: { idx in playSong(at: idx) },
                    onMoved: { newOrder in scheduleReorder(to: newOrder) },
                    onRemoveBatch: { indices in scheduleRemoval(indices: indices) }
                )
            }
        } else {
            VStack(spacing: 10) {
                Text("Empty playlist").foregroundStyle(.secondary)
                if !summary.isSmart {
                    Button("Add Tracks") { showingAddTracks = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .padding(40).frame(maxWidth: .infinity)
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

    private func scheduleReorder(to newSongs: [Song]) {
        enqueueMutation { [self] in await reorder(to: newSongs) }
    }

    private func scheduleRemoval(indices: [Int]) {
        enqueueMutation { [self] in await removeTracks(at: indices) }
    }

    /// Chain `work` onto the single mutation queue so reorders and removals are applied to
    /// the server in a strict total order. Index-based ops on Subsonic playlists are
    /// otherwise stateful in ways that don't compose with concurrent issuance.
    private func enqueueMutation(_ work: @escaping () async -> Void) {
        let prior = mutationTask
        mutationTask = Task {
            _ = await prior?.value
            await work()
        }
    }

    private func reorder(to newSongs: [Song]) async {
        guard let client = auth.client else { return }
        let originalSongs = detail?.entry ?? []
        let originalCount = originalSongs.count
        // Optimistic local update so the user sees the new order immediately.
        if let d = detail {
            detail = PlaylistDetail(
                id: d.id, name: d.name, comment: d.comment, songCount: d.songCount,
                duration: d.duration, owner: d.owner, coverArt: d.coverArt,
                readonly: d.readonly, entry: newSongs
            )
        }
        do {
            try await client.playlistReplaceContents(
                playlistID: summary.id,
                currentCount: originalCount,
                songIDs: newSongs.map(\.id)
            )
            await load(refresh: true)
        } catch {
            actionError = (error as? SubsonicError)?.message ?? error.localizedDescription
            // Rollback to the server's truth.
            await load(refresh: true)
        }
    }

    private func removeTracks(at indices: [Int]) async {
        guard let client = auth.client else { return }
        // Removal is positional; processing in descending order keeps each remaining index
        // valid against the live server state.
        let descending = indices.sorted(by: >)
        do {
            for i in descending {
                try await client.playlistRemoveSong(playlistID: summary.id, index: i)
            }
            await load(refresh: true)
        } catch {
            actionError = (error as? SubsonicError)?.message ?? error.localizedDescription
            // The playlist may be in a partial state — fetch authoritative truth.
            await load(refresh: true)
        }
    }
}

/// Reorderable + removable track list for non-smart playlists.
struct EditablePlaylistTrackList: View {
    let playlistID: String
    let songs: [Song]
    let onPlay: (Int) -> Void
    let onMoved: ([Song]) -> Void
    /// Always called with the indices to remove, in any order. The caller is responsible for
    /// serialising the network calls and sorting indices to keep them valid against the live
    /// server state.
    let onRemoveBatch: ([Int]) -> Void

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    /// Positional selection. A playlist may legitimately contain the same `Song.id` more
    /// than once, so keying selection on the song's identity would coalesce duplicate rows.
    @State private var selectedPosition: Int?

    var body: some View {
        List(selection: $selectedPosition) {
            ForEach(Array(songs.enumerated()), id: \.offset) { idx, song in
                TrackRow(
                    index: song.track ?? (idx + 1),
                    song: song,
                    isCurrent: player.currentSong?.id == song.id,
                    isFavorite: favorites.isSongFavorite(song.id),
                    onToggleFavorite: { toggleFavorite(song) },
                    showsCover: true
                )
                .tag(idx)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onPlay(idx) }
                .draggable(song)
                .contextMenu {
                    Button("Play") { onPlay(idx) }
                    Button("Remove from Playlist", role: .destructive) { onRemoveBatch([idx]) }
                    Divider()
                    Button(favorites.isSongFavorite(song.id) ? "Remove Favorite" : "Add Favorite") {
                        toggleFavorite(song)
                    }
                }
            }
            .onMove { indexSet, destination in
                var newOrder = songs
                newOrder.move(fromOffsets: indexSet, toOffset: destination)
                onMoved(newOrder)
            }
            .onDelete { indexSet in
                // Hand the whole IndexSet down. The parent serialises and sorts before
                // hitting the network so concurrent removals can't race against each other's
                // index shifts.
                onRemoveBatch(Array(indexSet))
            }
        }
        .listStyle(.inset)
        .onKeyPress(.return) {
            guard let idx = selectedPosition, idx >= 0, idx < songs.count else { return .ignored }
            onPlay(idx)
            return .handled
        }
    }

    private func toggleFavorite(_ song: Song) {
        guard let client = auth.client else { return }
        Task { await favorites.toggleSong(song.id, client: client) }
    }
}

/// Search-based picker that adds chosen tracks to a playlist. Selected tracks are added in
/// order (one network call per song; Subsonic does not support batched additions with our
/// scalar query parameters).
struct AddTracksToPlaylistSheet: View {
    let playlistID: String
    let existingIDs: Set<String>
    let onAdded: ([String]) -> Void

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [Song] = []
    @State private var selected: Set<String> = []
    @State private var debounceTask: Task<Void, Never>?
    @State private var isAdding = false
    @State private var error: String?
    /// Generation token so a late-arriving completion of a superseded query cannot overwrite
    /// the results the user is currently looking at.
    @State private var searchGeneration: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                TextField("Search songs to add", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onChange(of: query) { _, _ in scheduleSearch() }
            }
            .padding(16)
            Divider()
            if results.isEmpty {
                Text(query.isEmpty ? "Type to search" : "No results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selected) {
                    ForEach(results) { song in
                        HStack(spacing: 8) {
                            let already = existingIDs.contains(song.id)
                            Image(systemName: already
                                  ? "checkmark.circle.fill"
                                  : (selected.contains(song.id) ? "plus.circle.fill" : "plus.circle"))
                                .foregroundStyle(already ? Color.secondary : Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title).lineLimit(1)
                                Text(song.artist ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(song.album ?? "").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                                .frame(maxWidth: 200, alignment: .trailing)
                        }
                        .tag(song.id)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                if let error {
                    Text(error).foregroundStyle(.red).font(.caption).lineLimit(2)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .controlSize(.large)
                Button(isAdding ? "Adding…" : "Add \(addCount > 0 ? "\(addCount)" : "")") {
                    Task { await addSelected() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(addCount == 0 || isAdding)
            }
            .padding(12)
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private var addCount: Int {
        // Derive the count from the same visible result set `addSelected` will iterate over,
        // so stale selections held over from a previous query don't inflate the button's
        // count or enable a no-op "Add N" press after the user refines their search.
        results.lazy.filter { selected.contains($0.id) && !existingIDs.contains($0.id) }.count
    }

    private func scheduleSearch() {
        debounceTask?.cancel()
        let q = query
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        guard let client = auth.client else { return }
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration
        if trimmed.isEmpty {
            results = []
            error = nil
            return
        }
        do {
            let r = try await library.search(query: trimmed, client: client)
            // Bail if a newer search has already started; otherwise a late completion can
            // overwrite the user's current results with songs from a stale query, and they
            // could end up adding tracks they never saw.
            guard generation == searchGeneration else { return }
            results = r.song ?? []
            // A fresh successful result invalidates any stale error message — the user
            // should not see a red "previous query failed" line under live results.
            error = nil
        } catch is CancellationError {
            // Superseded by a newer search. The replacement run will refresh state; don't
            // surface cancellation as a user-visible failure.
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            guard generation == searchGeneration else { return }
            self.error = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }

    private func addSelected() async {
        guard let client = auth.client else { return }
        // Walk `results` (the order the user sees on screen) and pick the selected/not-yet-
        // in-playlist IDs in that order. Using `Array(selected.subtracting(...))` would
        // produce arbitrary set iteration order, so multi-track additions could land in the
        // playlist in a different order than the user picked them.
        let toAdd = results.lazy
            .map(\.id)
            .filter { selected.contains($0) && !existingIDs.contains($0) }
        let ordered = Array(toAdd)
        guard !ordered.isEmpty else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            for id in ordered {
                try await client.playlistAddSong(playlistID: playlistID, songID: id)
            }
            onAdded(ordered)
            dismiss()
        } catch {
            self.error = (error as? SubsonicError)?.message ?? error.localizedDescription
        }
    }
}
