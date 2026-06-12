import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let song = player.currentSong {
                HStack(spacing: 10) {
                    CoverArtImage(coverArtID: song.coverArt, size: 96, client: auth.client, corner: 4)
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.callout).lineLimit(1)
                        Text(song.artist ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)

                HStack(spacing: 10) {
                    Spacer()
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill")
                    }.buttonStyle(.iconControl)
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }.buttonStyle(.iconControl(hitTarget: 40, glyph: 22))
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill")
                    }.buttonStyle(.iconControl)
                    Spacer()
                }
                .padding(.bottom, 10)

                Divider()
            } else {
                HStack {
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                    Text("Nothing playing").foregroundStyle(.secondary).font(.callout)
                }
                .padding(12)
                Divider()
            }

            Button {
                showMainWindow()
            } label: {
                Label("Show Sonance", systemImage: "rectangle.righthalf.inset.filled.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .keyboardShortcut("0", modifiers: [.command])

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Sonance", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
            .keyboardShortcut("q", modifiers: [.command])
        }
        .frame(width: 280)
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
