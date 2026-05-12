import Foundation
import os

enum NetworkDiagnostics {
    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]
    private static let logger = Logger(subsystem: "com.alanhuang.Sonance", category: "Network")

    static func record(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        let count = counts[key, default: 0]
        lock.unlock()

        #if DEBUG
        logger.debug("\(key, privacy: .public) request count: \(count)")
        #endif
    }

    static func snapshot() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }

    static func reset() {
        lock.lock()
        counts.removeAll()
        lock.unlock()
    }
}
