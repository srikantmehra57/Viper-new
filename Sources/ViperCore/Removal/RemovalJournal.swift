import Foundation

public struct RemovalJournalEntry: Codable, Identifiable, Sendable {
    public struct Item: Codable, Sendable {
        public let path: String
        public let kind: String
        public let outcome: String
        public let trashPath: String?
        public let detail: String
    }
    public var id = UUID()
    public let date: Date
    public let name: String
    public let items: [Item]

    public init(date: Date = Date(), name: String, outcomes: [RemovalOutcome]) {
        self.date = date
        self.name = name
        items = outcomes.map { outcome in
            switch outcome.result {
            case .removed(let trash): return .init(path: outcome.item.url.path, kind: outcome.item.kind.rawValue, outcome: outcome.restored ? "Put back" : "Removed", trashPath: trash?.path, detail: "")
            case .skipped(let reason): return .init(path: outcome.item.url.path, kind: outcome.item.kind.rawValue, outcome: "Skipped", trashPath: nil, detail: reason)
            case .failed(let reason): return .init(path: outcome.item.url.path, kind: outcome.item.kind.rawValue, outcome: "Failed", trashPath: nil, detail: reason)
            }
        }
    }
}

public enum RemovalJournal {
    public static func load(from url: URL) -> [RemovalJournalEntry] {
        guard let data = try? Data(contentsOf: url), let entries = try? InstallJournal.decoder.decode([RemovalJournalEntry].self, from: data) else { return [] }
        return entries
    }

    public static func append(_ entry: RemovalJournalEntry, to url: URL, limit: Int = 100) throws {
        let entries = try JournalStore.existingArray(RemovalJournalEntry.self, from: url)
        try InstallJournal.write(Array((entries + [entry]).suffix(limit)), to: url)
    }
}

/// A write-ahead record of exactly what Viper intends to change and what happened to each item.
public struct RemovalTransaction: Codable, Identifiable, Sendable {
    public enum State: String, Codable, Equatable, Sendable { case inProgress, completed }
    public struct Target: Codable, Sendable {
        public let path: String
        public let kind: String
        public let identity: FileIdentity?
        public var outcome: String?
        public var trashPath: String?
        public var detail: String?
    }

    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public let name: String
    public var state: State
    public var targets: [Target]

    public init(name: String, items: [RemovalItem], now: Date = Date()) {
        id = UUID()
        createdAt = now
        updatedAt = now
        self.name = name
        state = .inProgress
        targets = items.map { .init(path: $0.url.path, kind: $0.kind.rawValue, identity: $0.identity, outcome: nil, trashPath: nil, detail: nil) }
    }
}

public enum RemovalTransactionJournal {
    public static func load(from url: URL) -> [RemovalTransaction] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? InstallJournal.decoder.decode([RemovalTransaction].self, from: data) else { return [] }
        return entries
    }

    static func write(_ transaction: RemovalTransaction, to url: URL, limit: Int = 100) throws {
        var entries = try JournalStore.existingArray(RemovalTransaction.self, from: url)
        if let index = entries.firstIndex(where: { $0.id == transaction.id }) { entries[index] = transaction }
        else { entries.append(transaction) }
        try InstallJournal.write(trimmed(entries, limit: limit), to: url)
    }

    /// Drops the oldest completed records first. An in-progress plan is never evicted.
    static func trimmed(_ entries: [RemovalTransaction], limit: Int) -> [RemovalTransaction] {
        guard entries.count > limit else { return entries }
        let inProgress = entries.filter { $0.state == .inProgress }
        let completed = entries.filter { $0.state != .inProgress }
        let keptCompleted = Set(completed.suffix(max(0, limit - inProgress.count)).map(\.id))
        let keptProgress = Set(inProgress.map(\.id))
        return entries.filter { keptProgress.contains($0.id) || keptCompleted.contains($0.id) }
    }
}

public actor RemovalTransactionRecorder {
    private let url: URL
    private var transaction: RemovalTransaction

    public init(name: String, items: [RemovalItem], url: URL) throws {
        self.url = url
        transaction = RemovalTransaction(name: name, items: items)
        try RemovalTransactionJournal.write(transaction, to: url)
    }

    public func record(_ outcome: RemovalOutcome) throws {
        guard let index = transaction.targets.firstIndex(where: { $0.path == outcome.item.url.path }) else { return }
        switch outcome.result {
        case .removed(let trashURL):
            transaction.targets[index].outcome = "Removed"
            transaction.targets[index].trashPath = trashURL?.path
            transaction.targets[index].detail = nil
        case .skipped(let reason):
            transaction.targets[index].outcome = "Skipped"
            transaction.targets[index].detail = reason
        case .failed(let reason):
            transaction.targets[index].outcome = "Failed"
            transaction.targets[index].detail = reason
        }
        transaction.updatedAt = Date()
        try RemovalTransactionJournal.write(transaction, to: url)
    }

    public func complete() throws {
        transaction.state = .completed
        transaction.updatedAt = Date()
        try RemovalTransactionJournal.write(transaction, to: url)
    }
}
