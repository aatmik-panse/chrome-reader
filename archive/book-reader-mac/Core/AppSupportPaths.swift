import Foundation

/// Resolves and creates the on-disk locations the app owns.
/// The Mac app is non-sandboxed in v1; paths live under the real
/// Application Support directory, not a container.
enum AppSupportPaths {
    /// `~/Library/Application Support/com.profitoniumapps.instantbookreader/`
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
        return base.appendingPathComponent("com.profitoniumapps.instantbookreader",
                                          isDirectory: true)
    }

    /// `<root>/Books/`
    static var books: URL { root.appendingPathComponent("Books", isDirectory: true) }

    /// `<root>/Covers/`
    static var covers: URL { root.appendingPathComponent("Covers", isDirectory: true) }

    /// `<root>/Database/`
    static var database: URL { root.appendingPathComponent("Database", isDirectory: true) }

    /// Idempotent. Call on app launch.
    static func ensureCreated() throws {
        let fm = FileManager.default
        for url in [root, books, covers, database] {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }
}
