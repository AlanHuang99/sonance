import Foundation
import SwiftUI

/// App-wide navigation hub for keyboard shortcuts.
///
/// `LibraryView` and the views inside it bind to this coordinator so commands declared on
/// `SonanceApp` (which lives above the views and therefore cannot reach `@State` in them)
/// can drive section switching, focus the search field, and request "go to current album".
@MainActor
final class NavigationCoordinator: ObservableObject {
    @Published var selectedSection: LibrarySection? = .albums
    /// Bumped each time the user requests focus on the search field (⌘F). `SearchView`
    /// observes this and re-applies `FocusState` true.
    @Published var searchFocusRequest: Int = 0
    /// Bumped each time the user explicitly switches sections (sidebar click, ⌘1..⌘5, ⌘F).
    /// `LibraryView` observes this to reset its detail `NavigationStack` path. Distinct from
    /// `selectedSection` so that programmatic section changes from `requestAlbumNavigation` /
    /// `requestArtistNavigation` can flip the section *without* wiping the just-pushed
    /// destination.
    @Published var sectionResetSignal: Int = 0
    /// Optional album the user wants to jump to. `LibraryView` consumes it by pushing onto
    /// the detail `NavigationStack` and then clears it.
    @Published var pendingAlbumNavigation: Album?
    /// Optional artist the user wants to jump to.
    @Published var pendingArtistNavigation: Artist?

    func focusSearch() {
        if selectedSection != .search {
            selectedSection = .search
            sectionResetSignal &+= 1
        }
        searchFocusRequest &+= 1
    }

    func switch_(to section: LibrarySection) {
        selectedSection = section
        sectionResetSignal &+= 1
    }

    func requestAlbumNavigation(_ album: Album) {
        // Flip the section directly without bumping `sectionResetSignal`. The pending-album
        // handler in `LibraryView` is responsible for appending to `detailPath`; the section
        // change here must not race with a path reset.
        if selectedSection != .albums {
            selectedSection = .albums
        }
        pendingAlbumNavigation = album
    }

    func requestArtistNavigation(_ artist: Artist) {
        if selectedSection != .artists {
            selectedSection = .artists
        }
        pendingArtistNavigation = artist
    }

    func revealInLibrary(album: Album?) {
        // "Show in Library" surfaces the user near the album in the Albums section. SwiftUI's
        // LazyVGrid does not expose a programmatic scroll-to-item that survives the section
        // switch, so this jumps to the Albums tab and opens the album's detail page (close
        // enough — the user can use the back button to land in the grid context).
        guard let album else {
            switch_(to: .albums)
            return
        }
        requestAlbumNavigation(album)
    }
}
