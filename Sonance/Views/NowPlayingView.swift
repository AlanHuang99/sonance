import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var navigation: NavigationCoordinator
    let onDismiss: () -> Void
    @State private var rightTab: RightTab = .queue

    enum RightTab: String, CaseIterable, Identifiable {
        case queue = "Queue", lyrics = "Lyrics"
        var id: String { rawValue }
    }

    var body: some View {
        contentStack
            .background(
                NowPlayingBackdrop(
                    coverArtID: player.currentSong?.coverArt,
                    client: auth.client
                )
                .ignoresSafeArea()
            )
    }

    private var contentStack: some View {
        VStack(spacing: 0) {
            // Top chrome: drag handle + close
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tertiary)
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.iconControl)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Close (Esc)")
                .padding(.trailing, 12)
            }
            .padding(.top, 10)
            .padding(.bottom, 6)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    leftPane.frame(width: 380)
                    Divider()
                    rightPane.frame(maxWidth: .infinity)
                }

                VStack(spacing: 0) {
                    leftPane
                        .frame(maxWidth: .infinity)
                    Divider()
                    rightPane
                        .frame(minHeight: 260)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var leftPane: some View {
        VStack(spacing: 16) {
            if let song = player.currentSong {
                ViewThatFits {
                    cover(for: song)
                        .frame(width: 280, height: 280)
                    cover(for: song)
                        .frame(width: 220, height: 220)
                    cover(for: song)
                        .frame(width: 160, height: 160)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 4) {
                    Text(song.title).font(.title2).bold().multilineTextAlignment(.center).lineLimit(2)
                    NavigableLabel(
                        text: song.artist ?? "—",
                        isEnabled: song.artistId != nil,
                        font: .title3,
                        tooltip: song.artistId == nil ? nil : "Go to Artist",
                        action: { goToArtist(song) }
                    )
                    if let album = song.album, !album.isEmpty {
                        NavigableLabel(
                            text: album,
                            isEnabled: song.albumId != nil,
                            font: .callout,
                            tooltip: song.albumId == nil ? nil : "Go to Album",
                            action: { goToAlbum(song) }
                        )
                    }
                }

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 0.1)
                    )
                    HStack {
                        Text(formatTime(player.currentTime))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTime(player.duration))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 24) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.iconControl(hitTarget: 54, glyph: 28))
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    }
                    .buttonStyle(.iconControl(hitTarget: 72, glyph: 60, weight: .regular))
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.iconControl(hitTarget: 54, glyph: 28))
                }

                HStack(spacing: 20) {
                    Button { player.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(player.isShuffled ? Color.accentColor : .secondary)
                    }
                    .help("Shuffle")
                    Button { player.cycleRepeat() } label: {
                        Image(systemName: player.repeatMode.systemImage)
                            .foregroundStyle(player.repeatMode == .off ? .secondary : Color.accentColor)
                    }
                    .help("Repeat: \(player.repeatMode.rawValue)")
                    Button {
                        if let c = auth.client {
                            Task { await favorites.toggleSong(song.id, client: c) }
                        }
                    } label: {
                        Image(systemName: favorites.isSongFavorite(song.id) ? "heart.fill" : "heart")
                            .foregroundStyle(favorites.isSongFavorite(song.id) ? Color.pink : .secondary)
                    }
                    .help(favorites.isSongFavorite(song.id) ? "Remove favorite" : "Add favorite")
                }
                .buttonStyle(.iconControl(hitTarget: 40, glyph: 21))

                // Inline volume row. The mini-player is hidden while Now Playing is open, so
                // without this control the user has no way to adjust volume from inside the
                // panel.
                HStack(spacing: 10) {
                    Image(systemName: volumeIconName)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .frame(width: 18)
                    Slider(value: $player.volume, in: 0...1)
                        .frame(maxWidth: 220)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 18)
                }
                .padding(.top, 4)

                Spacer(minLength: 0)
            } else {
                Text("Nothing playing").foregroundStyle(.secondary).frame(maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    private var rightPane: some View {
        VStack(spacing: 0) {
            Picker("", selection: $rightTab) {
                ForEach(RightTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider()
            switch rightTab {
            case .queue:
                QueuePaneView()
            case .lyrics:
                if let song = player.currentSong {
                    LyricsPaneView(song: song)
                } else {
                    Text("Nothing playing").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func cover(for song: Song) -> some View {
        CoverArtImage(coverArtID: song.coverArt, size: 600, client: auth.client, corner: 8)
    }

    private var volumeIconName: String {
        let v = player.volume
        if v <= 0 { return "speaker.slash" }
        if v < 0.34 { return "speaker.wave.1" }
        if v < 0.67 { return "speaker.wave.2" }
        return "speaker.wave.3"
    }

    private func formatTime(_ s: TimeInterval) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func goToAlbum(_ song: Song) {
        guard let album = albumStub(from: song) else { return }
        navigation.requestAlbumNavigation(album)
        onDismiss()
    }

    private func goToArtist(_ song: Song) {
        guard let artistId = song.artistId else { return }
        navigation.requestArtistNavigation(Artist(id: artistId, name: song.artist ?? "", coverArt: nil, albumCount: nil))
        onDismiss()
    }
}

/// Ambient backdrop: the current cover, scaled up and heavily blurred behind a translucent
/// material so text on top stays legible against either very light or very dark artwork.
struct NowPlayingBackdrop: View {
    let coverArtID: String?
    let client: SubsonicClient?
    @State private var image: NSImage?
    @State private var imageKey: String?
    @State private var loadingKey: String?

    var body: some View {
        ZStack {
            Color.black
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(2.0)
                        .blur(radius: 60, opaque: true)
                        .clipped()
                } else {
                    Color.black
                }
            }
            .id(imageKey ?? "none")
            .transition(.opacity)
        }
        .overlay(.regularMaterial.opacity(0.6))
        .animation(.easeInOut(duration: 0.4), value: imageKey)
        .task(id: cacheKey) { await load() }
    }

    private var cacheKey: String? {
        guard let coverArtID, let client else { return nil }
        return client.coverArtCacheKey(id: coverArtID, size: 600)
    }

    private func load() async {
        guard let coverArtID, let client, let key = cacheKey else {
            // Reset the loading token too — otherwise a previously-started load can complete
            // later, pass `guard loadingKey == key`, and repaint the backdrop with stale art.
            loadingKey = nil
            image = nil
            imageKey = nil
            return
        }
        loadingKey = key
        if let immediate = CoverArtCache.shared.memoryImage(forKey: key) {
            // `.task(id:)` cancels the previous task when `cacheKey` changes, but cancellation
            // is cooperative and this branch runs without an await. Skip the publish if we've
            // been cancelled so a stale memory hit from a superseded load doesn't briefly
            // repaint the backdrop with the wrong cover.
            guard !Task.isCancelled else { return }
            image = immediate
            imageKey = key
            return
        }
        let loaded = await CoverArtCache.shared.image(for: coverArtID, size: 600, client: client)
        guard !Task.isCancelled, loadingKey == key else { return }
        image = loaded
        imageKey = key
    }
}

struct QueuePaneView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var navigation: NavigationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up Next — \(player.queue.count) tracks").font(.headline)
                Spacer()
                Button("Clear") { player.clearQueue() }
                    .controlSize(.large)
                    .disabled(player.queue.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { idx, song in
                    QueueRow(index: idx + 1, song: song, isCurrent: idx == player.queueIndex)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { player.jumpTo(idx) }
                        .dropDestination(for: Song.self) { dropped, _ in
                            insertDropped(dropped, at: idx)
                            return true
                        }
                        .contextMenu {
                            Button("Play") { player.jumpTo(idx) }
                            Button("Remove") { player.removeFromQueue(at: idx) }
                            Divider()
                            Button("Go to Album") { goToAlbum(song) }
                                .disabled(song.albumId == nil)
                            Button("Go to Artist") { goToArtist(song) }
                                .disabled(song.artistId == nil)
                            Divider()
                            Button(favorites.isSongFavorite(song.id) ? "Remove Favorite" : "Add Favorite") {
                                if let c = auth.client {
                                    Task { await favorites.toggleSong(song.id, client: c) }
                                }
                            }
                        }
                }
                .onMove { source, destination in
                    if let src = source.first {
                        player.moveQueueItem(from: src, to: destination)
                    }
                }
            }
            .listStyle(.inset)
            // A drop on the empty area below the rows appends to the queue.
            .dropDestination(for: Song.self) { dropped, _ in
                insertDropped(dropped, at: player.queue.count)
                return true
            }
        }
    }

    private func insertDropped(_ songs: [Song], at index: Int) {
        guard let client = auth.client, !songs.isEmpty else { return }
        player.insert(songs, at: index, using: client)
    }

    private func goToAlbum(_ song: Song) {
        guard let album = albumStub(from: song) else { return }
        navigation.requestAlbumNavigation(album)
    }

    private func goToArtist(_ song: Song) {
        guard let artistId = song.artistId else { return }
        navigation.requestArtistNavigation(Artist(id: artistId, name: song.artist ?? "", coverArt: nil, albumCount: nil))
    }
}

struct QueueRow: View {
    let index: Int
    let song: Song
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.accentColor)
                } else {
                    Text("\(index)").foregroundStyle(.secondary)
                }
            }
            .font(.callout).monospacedDigit().frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).lineLimit(1).foregroundStyle(isCurrent ? Color.accentColor : .primary)
                Text(song.artist ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            Text(formatDuration(song.duration ?? 0))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct LyricsPaneView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    let song: Song
    @State private var lines: [LyricLine] = []
    @State private var loadError: String?
    @State private var loading = false
    @State private var followCurrentLine = true

    private var currentLineIndex: Int? {
        let nowMs = Int(player.currentTime * 1000)
        var found: Int? = nil
        for (i, line) in lines.enumerated() {
            if let s = line.start, s <= nowMs {
                found = i
            } else if let s = line.start, s > nowMs {
                break
            }
        }
        return found
    }

    private var hasTimings: Bool {
        lines.contains { $0.start != nil && $0.start! > 0 }
    }

    var body: some View {
        Group {
            if loading && lines.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                Text(err).foregroundStyle(.red).padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.alignleft").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No lyrics for this track").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if hasTimings {
                        HStack {
                            Spacer()
                            Toggle("Follow", isOn: $followCurrentLine)
                                .toggleStyle(.switch)
                                .controlSize(.regular)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        Divider()
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .center, spacing: 10) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                                    Text(line.value.isEmpty ? " " : line.value)
                                        .font(currentLineIndex == idx ? .title3 : .body)
                                        .fontWeight(currentLineIndex == idx ? .semibold : .regular)
                                        .foregroundStyle(currentLineIndex == idx ? Color.primary : .secondary)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 4)
                                        .id(idx)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if hasTimings, let s = line.start {
                                                player.seek(to: TimeInterval(s) / 1000)
                                                followCurrentLine = true
                                            }
                                        }
                                }
                            }
                            .padding(.vertical, 60)
                        }
                        .onChange(of: currentLineIndex) { _, newIdx in
                            guard followCurrentLine, let idx = newIdx else { return }
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(idx, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .task(id: song.id) { await load() }
    }

    private func load() async {
        guard let client = auth.client else { return }
        loading = true
        defer { loading = false }
        do {
            let groups = try await client.lyrics(songID: song.id)
            lines = groups.first?.line ?? []
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}
