import SwiftUI

struct SongsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: LibraryStore
    @State private var songs: [Song] = []
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Random songs").font(.title2).bold()
                Spacer()
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                Button {
                    if let client = auth.client, !songs.isEmpty {
                        player.play(songs, startAt: 0, using: client)
                    }
                } label: {
                    Label("Play All", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(songs.isEmpty)
            }
            .padding(20)
            Divider()
            if isLoading && songs.isEmpty {
                ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                Text(err).foregroundStyle(.red).padding(40)
            } else {
                TrackListView(songs: songs, onPlay: { idx in
                    if let client = auth.client {
                        player.play(songs, startAt: idx, using: client)
                    }
                })
            }
        }
        .navigationTitle("Songs")
        .task { await load() }
    }

    private func load() async {
        await load(refresh: false)
    }

    private func load(refresh: Bool) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            songs = try await library.randomSongs(size: 100, client: client, refresh: refresh)
            loadError = nil
        } catch let error as SubsonicError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}
