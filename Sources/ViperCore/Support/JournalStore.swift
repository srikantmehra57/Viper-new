import Foundation

public enum JournalStore {
    public struct Unreadable: Error, LocalizedError {
        public let preservedAt: URL
        public var errorDescription: String? {
            "A journal couldn’t be read, so it was saved as \(preservedAt.lastPathComponent) and nothing else was changed. Review that file in Settings before Viper changes anything."
        }
    }

    /// Moves a file that exists but does not decode. A missing file is left alone.
    public static func quarantineIfUnreadable<T: Decodable>(_ url: URL, as type: T.Type) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let data = try? Data(contentsOf: url), (try? InstallJournal.decoder.decode(T.self, from: data)) != nil { return nil }
        let aside = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".unreadable-" + UUID().uuidString)
        guard (try? FileManager.default.moveItem(at: url, to: aside)) != nil else { return nil }
        return aside
    }

    static func existing<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Unreadable(preservedAt: url)
        }
        if let data = try? Data(contentsOf: url), let value = try? InstallJournal.decoder.decode(T.self, from: data) { return value }
        guard let aside = quarantineIfUnreadable(url, as: T.self) else { throw Unreadable(preservedAt: url) }
        throw Unreadable(preservedAt: aside)
    }

    static func existingArray<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try existing([T].self, from: url)
    }
}
