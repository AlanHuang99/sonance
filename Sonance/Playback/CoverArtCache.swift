import AppKit
import CryptoKit
import Foundation
import os

/// Two-tier cover-art cache.
///
/// - Tier 1: `NSCache<NSString, NSImage>` of decoded images, `totalCostLimit` 64 MB.
/// - Tier 2: JPEG/PNG bytes on disk under `~/Library/Caches/com.alanhuang.Sonance/covers/`,
///   capped at 200 MB with LRU eviction on first miss after launch.
///
/// Keyed on `(accountID, coverArtID, size)` so rotating Subsonic auth params do not defeat reuse,
/// and so different sizes of the same cover live independently.
actor CoverArtCache {
    static let shared = CoverArtCache()

    private static let memoryByteLimit = 64 * 1024 * 1024
    private static let diskByteLimit = 200 * 1024 * 1024

    nonisolated(unsafe) private let memory: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = CoverArtCache.memoryByteLimit
        return c
    }()
    private let diskDir: URL
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var didPruneDisk = false
    private let logger = Logger(subsystem: "com.alanhuang.Sonance", category: "CoverArtCache")

    private(set) var memoryHits: Int = 0
    private(set) var diskHits: Int = 0
    private(set) var networkLoads: Int = 0
    private(set) var misses: Int = 0

    init(directoryName: String = "com.alanhuang.Sonance/covers") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.diskDir = caches.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    /// Fast, lock-free probe of the in-memory tier. Safe to call off-actor because `NSCache` is
    /// documented as thread-safe. Lets SwiftUI views render a memory hit without an actor hop.
    nonisolated func memoryImage(forKey cacheKey: String) -> NSImage? {
        memory.object(forKey: cacheKey as NSString)
    }

    func image(for id: String, size: Int, client: SubsonicClient) async -> NSImage? {
        let key = client.coverArtCacheKey(id: id, size: size)

        if let img = memory.object(forKey: key as NSString) {
            memoryHits += 1
            return img
        }

        if let pending = inFlight[key] {
            return await pending.value
        }

        let task = Task<NSImage?, Never> { [id, size, key, client] in
            await self.fetch(id: id, size: size, key: key, client: client)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func fetch(id: String, size: Int, key: String, client: SubsonicClient) async -> NSImage? {
        await pruneDiskIfNeeded()

        let diskURL = diskPath(for: key)
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            diskHits += 1
            store(image, key: key)
            touch(diskURL)
            return image
        }

        do {
            let data = try await client.coverArtData(id: id, size: size)
            networkLoads += 1
            guard let image = NSImage(data: data) else {
                misses += 1
                return nil
            }
            store(image, key: key)
            writeToDisk(data, at: diskURL)
            return image
        } catch {
            misses += 1
            logger.debug("network load failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func store(_ image: NSImage, key: String) {
        memory.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
    }

    private static func cost(of image: NSImage) -> Int {
        var maxPixels = 0
        for rep in image.representations {
            let pixels = rep.pixelsWide * rep.pixelsHigh
            if pixels > maxPixels { maxPixels = pixels }
        }
        if maxPixels == 0 {
            let s = image.size
            maxPixels = Int(s.width * s.height)
        }
        return max(maxPixels * 4, 1)
    }

    private func diskPath(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
        let name = hash.map { String(format: "%02x", $0) }.joined()
        return diskDir.appendingPathComponent(name + ".img")
    }

    private func writeToDisk(_ data: Data, at url: URL) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.debug("disk write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func pruneDiskIfNeeded() async {
        guard !didPruneDisk else { return }
        didPruneDisk = true
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: diskDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        struct Entry { let url: URL; let date: Date; let size: Int }
        var entries: [Entry] = []
        var total = 0
        for u in urls {
            let vals = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = vals?.contentModificationDate ?? .distantPast
            let size = vals?.fileSize ?? 0
            entries.append(Entry(url: u, date: date, size: size))
            total += size
        }
        guard total > Self.diskByteLimit else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
            if total <= Self.diskByteLimit { break }
        }
        logger.debug("pruned disk cache to \(total) bytes")
    }

    // MARK: - Diagnostics

    struct Diagnostics: Equatable, Sendable {
        let memoryHits: Int
        let diskHits: Int
        let networkLoads: Int
        let misses: Int
    }

    func diagnostics() -> Diagnostics {
        Diagnostics(memoryHits: memoryHits, diskHits: diskHits, networkLoads: networkLoads, misses: misses)
    }

    func resetDiagnostics() {
        memoryHits = 0
        diskHits = 0
        networkLoads = 0
        misses = 0
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: diskDir)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
        didPruneDisk = false
        resetDiagnostics()
    }
}
