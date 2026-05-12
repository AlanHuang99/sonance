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
    /// Optional album the user wants to jump to (⌘L). `LibraryView` consumes it by pushing
    /// onto the detail `NavigationStack` and then clears it.
    @Published var pendingAlbumNavigation: Album?

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
}
