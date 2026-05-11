import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @State private var keyMonitor: Any?
    @State private var showingNowPlaying = false

    var body: some View {
        Group {
            if auth.isLoggedIn {
                ZStack(alignment: .bottom) {
                    LibraryView()
                        .id(auth.activeAccountID ?? "signed-in")
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            MiniPlayerBar(showingNowPlaying: $showingNowPlaying)
                        }
                        .task {
                            if let client = auth.client {
                                player.restorePaused(client: client)
                            }
                        }

                    if showingNowPlaying {
                        NowPlayingView(onDismiss: dismissNowPlaying)
                            .background(.regularMaterial)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(1)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showingNowPlaying)
            } else {
                LoginView()
            }
        }
        .onAppear { installSpaceKeyMonitor() }
        .onDisappear { removeSpaceKeyMonitor() }
    }

    private func dismissNowPlaying() {
        showingNowPlaying = false
    }

    private func installSpaceKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Space (keyCode 49) with no modifiers, and no text field focused → toggle playback.
            if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                if let window = NSApp.keyWindow {
                    let first = window.firstResponder
                    let isTextEditing = first is NSText
                        || first is NSTextView
                        || first?.className.contains("TextField") == true
                    if !isTextEditing && player.currentSong != nil {
                        player.togglePlayPause()
                        return nil
                    }
                }
            }
            return event
        }
    }

    private func removeSpaceKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
