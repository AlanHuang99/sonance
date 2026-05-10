import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var auth: AuthStore?
    private weak var player: Player?
    private weak var favorites: FavoritesStore?
    private var playerObserver: AnyCancellable?

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var visibilityWanted: Bool = true

    /// Called from SonanceApp once the StateObjects exist so the AppDelegate can
    /// drive the status item and popover with the same models the SwiftUI views use.
    func attach(auth: AuthStore, player: Player, favorites: FavoritesStore) {
        self.auth = auth
        self.player = player
        self.favorites = favorites
        // Update the status item glyph when playback starts/stops.
        playerObserver = player.$isPlaying.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItemImage() }
        }
        installStatusItemIfNeeded()
        updateStatusItemImage()
    }

    func refreshStatusItemVisibility(_ visible: Bool) {
        visibilityWanted = visible
        if visible {
            installStatusItemIfNeeded()
            updateStatusItemImage()
        } else {
            removeStatusItem()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItemIfNeeded()
    }

    /// Keep the app alive when the last window closes so the status item remains.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeStatusItem()
    }

    // MARK: - Status item

    private func installStatusItemIfNeeded() {
        guard visibilityWanted, statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "SonanceStatusItem"
        if let button = item.button {
            let img = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Sonance")
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }
        item.isVisible = true
        statusItem = item
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        popover?.close()
        popover = nil
    }

    private func updateStatusItemImage() {
        guard let button = statusItem?.button else { return }
        let symbol = (player?.isPlaying == true) ? "play.circle.fill" : "music.note"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Sonance")
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.close()
            return
        }
        guard let auth, let player, let favorites else { return }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 280, height: 200)
        let host = NSHostingController(
            rootView: MenuBarContentView()
                .environmentObject(auth)
                .environmentObject(player)
                .environmentObject(favorites)
        )
        pop.contentViewController = host
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover = pop
    }
}
