import AppKit
import CryptoKit
import Foundation
import os

/// Two-tier cover-art cache.
///
/// - Tier 1: `NSCache<NSString, NSImage>` of decoded images, `totalCostLimit` 64 MB.
/// - Tier 2: JPEG/PNG bytes on disk under `~/Library/Caches/com.alanhuang.Sonance/covers/`,
///   capped at 200 MB with LRU eviction. The disk size is tracked across the session so the
///   cap is enforced continuously, not only on first miss after launch.
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
    /// `false` until the first `fetch` triggers `initialDiskScan` to populate
    /// `currentDiskBytes` from the existing on-disk files. Distinct from the old
    /// `didPruneDisk`, which permanently disabled pruning after the first run.
    private var didInitialScan = false
    /// Running estimate of total disk-cached bytes. Maintained by add (`writeToDisk`),
    /// remove (`prune`), and the initial scan. Used to short-circuit `prune` when under cap.
    private var currentDiskBytes: Int = 0
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
        initialDiskScanIfNeeded()

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
            // Account for the previous file at this URL (if any) so the byte counter stays
            // accurate across re-fetches of the same key.
            let previousSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try data.write(to: url, options: .atomic)
            currentDiskBytes += data.count - previousSize
            if currentDiskBytes > Self.diskByteLimit {
                prune()
            }
        } catch {
            logger.debug("disk write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    /// One-time directory walk to seed `currentDiskBytes` from existing files on disk. Runs on
    /// the first `fetch` after launch and prunes once if the survivors are already over cap.
    private func initialDiskScanIfNeeded() {
        guard !didInitialScan else { return }
        didInitialScan = true
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: diskDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }
        var total = 0
        for u in urls {
            total += (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        currentDiskBytes = total
        if currentDiskBytes > Self.diskByteLimit {
            prune()
        }
    }

    /// LRU-evict the oldest files until `currentDiskBytes <= diskByteLimit`. Called from the
    /// initial scan and after each disk write that pushes us over.
    private func prune() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: diskDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }
        struct Entry { let url: URL; let date: Date; let size: Int }
        let entries = urls.map { u -> Entry in
            let vals = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return Entry(
                url: u,
                date: vals?.contentModificationDate ?? .distantPast,
                size: vals?.fileSize ?? 0
            )
        }.sorted { $0.date < $1.date }

        var bytesRemaining = currentDiskBytes
        for entry in entries {
            if bytesRemaining <= Self.diskByteLimit { break }
            try? fm.removeItem(at: entry.url)
            bytesRemaining -= entry.size
        }
        currentDiskBytes = max(0, bytesRemaining)
        logger.debug("pruned disk cache to \(self.currentDiskBytes) bytes")
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
        didInitialScan = false
        currentDiskBytes = 0
        resetDiagnostics()
    }
}
