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
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: cacheKey) {
            guard let cacheKey, let coverArtID, let client else {
                loader.clear()
                return
            }
            await loader.load(cacheKey: cacheKey) {
                client.coverArtURL(id: coverArtID, size: size)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: loader.image != nil)
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
    @Published private(set) var image: NSImage?
    private static let cache = NSCache<NSString, NSImage>()
    private var loadingKey: String?

    func clear() {
        image = nil
        loadingKey = nil
    }

    func load(cacheKey: String, url: @escaping () -> URL?) async {
        if let cached = Self.cache.object(forKey: cacheKey as NSString) {
            image = cached
            loadingKey = nil
            return
        }

        loadingKey = cacheKey
        guard let requestURL = url() else {
            if loadingKey == cacheKey { image = nil }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            guard !Task.isCancelled,
                  loadingKey == cacheKey,
                  let loaded = NSImage(data: data) else { return }
            Self.cache.setObject(loaded, forKey: cacheKey as NSString)
            image = loaded
        } catch {
            if loadingKey == cacheKey {
                image = nil
            }
        }
    }
}
