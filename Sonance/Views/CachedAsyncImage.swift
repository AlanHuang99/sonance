import SwiftUI

/// Cover-art image backed by `CoverArtCache` (in-memory + on-disk) so scrolling and
/// revisits hit the local tiers instead of refetching from the Subsonic server.
struct CoverArtImage: View {
    let coverArtID: String?
    let size: Int
    let client: SubsonicClient?
    var corner: CGFloat = 6
    var glyph: String = "music.note"
    @StateObject private var loader = CoverArtImageLoader()

    private var cacheKey: String? {
        guard let coverArtID, let client else { return nil }
        return client.coverArtCacheKey(id: coverArtID, size: size)
    }

    var body: some View {
        ZStack {
            placeholder
            if case .success(let image) = loader.state {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if case .failure = loader.state {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: cacheKey) {
            guard let cacheKey, let coverArtID, let client else {
                loader.clear()
                return
            }
            await loader.load(cacheKey: cacheKey, coverArtID: coverArtID, size: size, client: client)
        }
        .animation(.easeInOut(duration: 0.18), value: loader.hasImage)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(.quaternary)
            .overlay(
                Image(systemName: glyph)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            )
    }
}

@MainActor
private final class CoverArtImageLoader: ObservableObject {
    @Published private(set) var state: CoverArtLoadState = .idle
    private var loadingKey: String?

    var hasImage: Bool {
        if case .success = state { return true }
        return false
    }

    func clear() {
        state = .idle
        loadingKey = nil
    }

    func load(cacheKey: String, coverArtID: String, size: Int, client: SubsonicClient) async {
        loadingKey = cacheKey

        // Fast path: synchronous peek at the in-memory tier so a SwiftUI re-render of an already
        // cached cover does not flash a placeholder while the actor hop completes.
        if let immediate = CoverArtCache.shared.memoryImage(forKey: cacheKey) {
            state = .success(immediate)
            return
        }

        if !state.isSuccess { state = .loading }

        let image = await CoverArtCache.shared.image(for: coverArtID, size: size, client: client)
        guard !Task.isCancelled, loadingKey == cacheKey else { return }
        if let image {
            state = .success(image)
        } else {
            state = .failure("Cover unavailable")
        }
    }
}

private enum CoverArtLoadState {
    case idle
    case loading
    case success(NSImage)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
