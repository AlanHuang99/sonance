import XCTest
@testable import Sonance

/// Regression tests for cross-link navigation.
///
/// The user-reported bug: clicking an artist link from inside an album-detail view (in the
/// Albums section) flipped to the Artists section but did not push the artist detail —
/// users landed on the Artists root with no detail visible. Root cause: a single
/// `NavigationStack` whose root view *type* swapped on every section change made SwiftUI
/// drop pushes during the swap frame, because destination registration was reconciling at
/// the same time as the path mutation.
///
/// Fix: one `NavigationStack` per section, each with a stable root view type and its own
/// `NavigationPath`. Cross-link navigation prepares the *target* section's path before
/// flipping the visible section, so the moment the target stack appears its path already
/// contains the destination. These tests pin the routing decision that drives that
/// behavior.
@MainActor
final class NavigationCoordinatorTests: XCTestCase {

    // MARK: - Cross-section (the user-reported bug)

    /// Clicking an artist link while in the Albums section must route the destination into
    /// the Artists section's stack and signal that the cross-section path should be reset.
    func testArtistFromAlbumsCrossesSection() {
        let artist = Artist(id: "a-1", name: "X", coverArt: nil, albumCount: nil)
        let decision = NavigationRequestRouting.decide(
            request: .artist(artist),
            currentSection: .albums
        )
        XCTAssertEqual(decision.targetSection, .artists)
        XCTAssertTrue(decision.crossesSection)
    }

    func testAlbumFromArtistsCrossesSection() {
        let album = sampleAlbum(id: "ab-1")
        let decision = NavigationRequestRouting.decide(
            request: .album(album),
            currentSection: .artists
        )
        XCTAssertEqual(decision.targetSection, .albums)
        XCTAssertTrue(decision.crossesSection)
    }

    /// Every non-target section that hosts cross-link entry points must produce a cross
    /// decision. Covering the full matrix here so a future section addition (or rename)
    /// trips the test if it gets wired up without thinking through navigation.
    func testCrossSectionMatrix() {
        let artist = Artist(id: "a", name: "n", coverArt: nil, albumCount: nil)
        let album = sampleAlbum(id: "a")

        let nonArtistSections: [LibrarySection] = [
            .albums, .discover, .genres, .playlists, .favorites, .search, .accounts
        ]
        for section in nonArtistSections {
            let decision = NavigationRequestRouting.decide(
                request: .artist(artist),
                currentSection: section
            )
            XCTAssertEqual(decision.targetSection, .artists,
                "request .artist must always target Artists, got \(decision.targetSection) from \(section)")
            XCTAssertTrue(decision.crossesSection,
                "request .artist from \(section) must cross sections")
        }

        let nonAlbumSections: [LibrarySection] = [
            .artists, .discover, .genres, .playlists, .favorites, .search, .accounts
        ]
        for section in nonAlbumSections {
            let decision = NavigationRequestRouting.decide(
                request: .album(album),
                currentSection: section
            )
            XCTAssertEqual(decision.targetSection, .albums)
            XCTAssertTrue(decision.crossesSection)
        }
    }

    // MARK: - Same-section (preserves back-stack)

    /// Clicking a similar-artist while already on an artist's detail page should NOT cross
    /// sections — the destination appends to the existing Artists path so the back button
    /// returns to the prior artist.
    func testArtistFromArtistsStaysInSection() {
        let artist = Artist(id: "a-2", name: "Similar", coverArt: nil, albumCount: nil)
        let decision = NavigationRequestRouting.decide(
            request: .artist(artist),
            currentSection: .artists
        )
        XCTAssertEqual(decision.targetSection, .artists)
        XCTAssertFalse(decision.crossesSection)
    }

    func testAlbumFromAlbumsStaysInSection() {
        let album = sampleAlbum(id: "ab-2")
        let decision = NavigationRequestRouting.decide(
            request: .album(album),
            currentSection: .albums
        )
        XCTAssertEqual(decision.targetSection, .albums)
        XCTAssertFalse(decision.crossesSection)
    }

    // MARK: - Edge case: nil current section

    /// Before the user picks a section (sidebar nothing-selected state) a cross-link must
    /// still route to the destination's owning section.
    func testNilCurrentSectionCrossesToTarget() {
        let artist = Artist(id: "a", name: "n", coverArt: nil, albumCount: nil)
        let decision = NavigationRequestRouting.decide(
            request: .artist(artist),
            currentSection: nil
        )
        XCTAssertEqual(decision.targetSection, .artists)
        XCTAssertTrue(decision.crossesSection)
    }

    // MARK: - Public API of NavigationCoordinator

    /// Convenience methods must funnel through the single `navigationRequest` channel
    /// `LibraryView` observes. Splitting these across separate channels is what regressed
    /// the previous fix — pinning the funnel here prevents that recurrence.
    func testCoordinatorPublishesArtistRequest() {
        let coordinator = NavigationCoordinator()
        XCTAssertNil(coordinator.navigationRequest)

        let artist = Artist(id: "a", name: "n", coverArt: nil, albumCount: nil)
        coordinator.requestArtistNavigation(artist)

        guard case .artist(let observed)? = coordinator.navigationRequest else {
            return XCTFail("requestArtistNavigation did not publish an .artist request")
        }
        XCTAssertEqual(observed, artist)
    }

    func testCoordinatorPublishesAlbumRequest() {
        let coordinator = NavigationCoordinator()
        let album = sampleAlbum(id: "ab")
        coordinator.requestAlbumNavigation(album)

        guard case .album(let observed)? = coordinator.navigationRequest else {
            return XCTFail("requestAlbumNavigation did not publish an .album request")
        }
        XCTAssertEqual(observed, album)
    }

    func testTargetSectionMapping() {
        let artist = Artist(id: "a", name: "n", coverArt: nil, albumCount: nil)
        let album = sampleAlbum(id: "ab")
        XCTAssertEqual(NavigationCoordinator.NavigationRequest.artist(artist).targetSection, .artists)
        XCTAssertEqual(NavigationCoordinator.NavigationRequest.album(album).targetSection, .albums)
    }

    // MARK: - Helpers

    private func sampleAlbum(id: String) -> Album {
        Album(
            id: id, name: "Name \(id)", artist: "A", artistId: nil,
            coverArt: nil, songCount: nil, duration: nil, year: nil, starred: nil
        )
    }
}
