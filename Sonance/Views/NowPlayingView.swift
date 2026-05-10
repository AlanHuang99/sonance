import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var favorites: FavoritesStore
    let onDismiss: () -> Void
    @State private var rightTab: RightTab = .queue

    enum RightTab: String, CaseIterable, Identifiable {
        case queue = "Queue", lyrics = "Lyrics"
        var id: String { rawValue }
    }

    var body: some View {
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
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Close (Esc)")
                .padding(.trailing, 12)
            }
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack(spacing: 0) {
                leftPane.frame(width: 380)
                Divider()
                rightPane.frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var leftPane: some View {
        VStack(spacing: 16) {
            if let song = player.currentSong {
                cover(for: song)
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 4) {
                    Text(song.title).font(.title2).bold().multilineTextAlignment(.center).lineLimit(2)
                    Text(song.artist ?? "—").font(.title3).foregroundStyle(.secondary).lineLimit(1)
                    if let album = song.album, !album.isEmpty {
                        Text(album).font(.callout).foregroundStyle(.secondary).lineLimit(1)
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

                HStack(spacing: 32) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.title)
                    }
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title)
                    }
                }
                .buttonStyle(.borderless)

                HStack(spacing: 28) {
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
                .buttonStyle(.borderless)
                .font(.title3)

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
        SmoothCoverImage(
            url: song.coverArt.flatMap { auth.client?.coverArtURL(id: $0, size: 600) },
            corner: 8
        )
    }

    private func formatTime(_ s: TimeInterval) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct QueuePaneView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up Next — \(player.queue.count) tracks").font(.headline)
                Spacer()
                Button("Clear") { player.clearQueue() }
                    .disabled(player.queue.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { idx, song in
                    QueueRow(index: idx + 1, song: song, isCurrent: idx == player.queueIndex)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { player.jumpTo(idx) }
                        .contextMenu {
                            Button("Play") { player.jumpTo(idx) }
                            Button("Remove") { player.removeFromQueue(at: idx) }
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
        }
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
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 60)
                    }
                    .onChange(of: currentLineIndex) { _, newIdx in
                        if let idx = newIdx {
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
