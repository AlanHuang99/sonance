#if SPARKLE
import Combine
import Sparkle
import SwiftUI

/// Thin wrapper around Sparkle's standard updater, exposed as an `ObservableObject`
/// so SwiftUI menu items can bind to `canCheckForUpdates` and enable/disable
/// themselves correctly while a check or download is in flight.
///
/// The whole file is gated behind the `SPARKLE` compilation condition, which is
/// defined only on the `Sonance-Direct` target. The base `Sonance` (App Store)
/// target never links Sparkle and compiles this to nothing.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors `SPUUpdater.canCheckForUpdates`; drives the menu item's enabled state.
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true boots the updater immediately. With
        // SUEnableAutomaticChecks=false in Info.plist, no background check is
        // scheduled until the user opts in via `automaticallyChecksForUpdates`.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Show Sparkle's standard "check for updates" flow (progress, release notes,
    /// install, relaunch). Safe to call only when `canCheckForUpdates` is true.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// User-facing toggle for scheduled background checks. Sparkle persists the
    /// choice in UserDefaults, overriding the Info.plist default once set.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
#endif
