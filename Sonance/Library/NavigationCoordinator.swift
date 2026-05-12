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
    /// Optional album the user wants to jump to. `LibraryView` consumes it by pushing onto
    /// the detail `NavigationStack` and then clears it.
    @Published var pendingAlbumNavigation: Album?
    /// Optional artist the user wants to jump to.
    @Published var pendingArtistNavigation: Artist?

    func focusSearch() {
        if selectedSection != .search {
            selectedSection = .search
        }
        searchFocusRequest &+= 1
    }

    func switch_(to section: LibrarySection) {
        selectedSection = section
    }

    func requestAlbumNavigation(_ album: Album) {
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
