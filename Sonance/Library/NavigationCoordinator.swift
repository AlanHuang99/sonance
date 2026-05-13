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
    /// `LibraryView` observes this to reset its detail `NavigationStack` path.
    @Published var sectionResetSignal: Int = 0
    /// A combined cross-link request: jump to the section that owns the destination and push
    /// the destination onto that section's detail stack. `LibraryView` consumes this with a
    /// single `.onChange` that applies the section switch, path reset, and destination push
    /// atomically — so SwiftUI sees the final `(root, path)` pair in one render pass and
    /// doesn't drop the push the way it does when section and path mutate across separate
    /// onChange handlers.
    @Published var navigationRequest: NavigationRequest?

    enum NavigationRequest: Equatable {
        case album(Album)
        case artist(Artist)

        var targetSection: LibrarySection {
            switch self {
            case .album: return .albums
            case .artist: return .artists
            }
        }
    }

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
        navigationRequest = .album(album)
    }

    func requestArtistNavigation(_ artist: Artist) {
        navigationRequest = .artist(artist)
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

/// Pure description of the section a request targets and whether it crosses sections.
/// `LibraryView.handleNavigationRequest` uses this to decide which per-section path to
/// mutate and whether to reset that path or append to it. Kept separate from the UI so unit
/// tests can pin the cross-section semantics without needing a SwiftUI runtime.
@MainActor
enum NavigationRequestRouting {
    struct Decision: Equatable {
        let targetSection: LibrarySection
        /// When true, the user is jumping to a different section than they were in — the
        /// target section's stack should be reset to a single-entry path holding just this
        /// destination. When false, the user is drilling within their current section and
        /// the destination should be appended on top of the existing path.
        let crossesSection: Bool
    }

    static func decide(
        request: NavigationCoordinator.NavigationRequest,
        currentSection: LibrarySection?
    ) -> Decision {
        let target = request.targetSection
        return Decision(
            targetSection: target,
            crossesSection: (currentSection != target)
        )
    }
}
