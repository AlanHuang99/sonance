import SwiftUI

/// Cover-art image that keeps a stable cache identity while Subsonic auth URLs
/// rotate their salt/token query params.
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
    private static let cache = NSCache<NSString, NSImage>()
    private static var inFlight: [String: Task<NSImage, Error>] = [:]
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
        if let cached = Self.cache.object(forKey: cacheKey as NSString) {
            state = .success(cached)
            loadingKey = nil
            return
        }

        loadingKey = cacheKey
        state = .loading

        do {
            let loaded = try await Self.image(cacheKey: cacheKey, coverArtID: coverArtID, size: size, client: client)
            guard !Task.isCancelled, loadingKey == cacheKey else { return }
            Self.cache.setObject(loaded, forKey: cacheKey as NSString)
            state = .success(loaded)
        } catch {
            if loadingKey == cacheKey {
                state = .failure(error.localizedDescription)
            }
        }
    }

    private static func image(cacheKey: String, coverArtID: String, size: Int, client: SubsonicClient) async throws -> NSImage {
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }
        if let task = inFlight[cacheKey] {
            return try await task.value
        }

        let task = Task<NSImage, Error> {
            let data = try await client.coverArtData(id: coverArtID, size: size)
            guard let image = NSImage(data: data) else {
                throw SubsonicError(code: -1, message: "Could not decode cover art")
            }
            return image
        }
        inFlight[cacheKey] = task
        defer { inFlight[cacheKey] = nil }

        let image = try await task.value
        cache.setObject(image, forKey: cacheKey as NSString)
        return image
    }
}

private enum CoverArtLoadState {
    case idle
    case loading
    case success(NSImage)
    case failure(String)
}
