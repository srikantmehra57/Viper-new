import Darwin
import Foundation

/// Records what happened to each install. It is an outcome log, not a rollback mechanism.
public struct InstallJournalEntry: Codable, Identifiable, Sendable {
    public var id = UUID()
    public let date: Date
    public let appID: String
    public let appName: String
    public let source: String
    public let package: String
    public let runtime: String
    public let outcome: String
    public let version: String?
    public let detail: String

    public init(date: Date = Date(), appID: String, appName: String, source: String, package: String, runtime: String, outcome: String, version: String?, detail: String) {
        self.date = date
        self.appID = appID
        self.appName = appName
        self.source = source
        self.package = package
        self.runtime = runtime
        self.outcome = outcome
        self.version = version
        self.detail = detail
    }
}

public enum InstallJournal {
    public static func load(from url: URL) -> [InstallJournalEntry] {
        guard let data = try? Data(contentsOf: url), let entries = try? decoder.decode([InstallJournalEntry].self, from: data) else { return [] }
        return entries
    }

    /// Keeps the newest entries only, so the journal stays small.
    @discardableResult
    public static func append(_ entry: InstallJournalEntry, to url: URL, limit: Int = 200) throws -> [InstallJournalEntry] {
        let entries = Array((try JournalStore.existingArray(InstallJournalEntry.self, from: url) + [entry]).suffix(limit))
        try write(entries, to: url)
        return entries
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encoder.encode(value).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY)
        if directory >= 0 {
            defer { close(directory) }
            if fsync(directory) != 0 { throw CocoaError(.fileWriteUnknown) }
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Local cache of provider metadata. It is only refreshed when the user asks.
public struct CatalogMetadataCache: Codable, Sendable {
    public var refreshedAt: Date?
    public var items: [String: PackageMetadata]

    public init(refreshedAt: Date? = nil, items: [String: PackageMetadata] = [:]) {
        self.refreshedAt = refreshedAt
        self.items = items
    }

    public static func load(from url: URL) -> Self {
        guard let data = try? Data(contentsOf: url), let cache = try? InstallJournal.decoder.decode(Self.self, from: data) else { return .init() }
        return cache
    }

    public func save(to url: URL) throws { try InstallJournal.write(self, to: url) }
}
