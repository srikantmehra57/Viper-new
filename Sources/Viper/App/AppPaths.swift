import Foundation

/// Every file Viper keeps on disk. Journals and history live in Application Support; disposable caches in Caches.
enum AppPaths {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Viper", isDirectory: true)
    static let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Viper", isDirectory: true)

    static var removalJournal: URL { support.appendingPathComponent("removal-journal.json") }
    static var removalTransactions: URL { support.appendingPathComponent("removal-transactions.json") }
    static var installJournal: URL { support.appendingPathComponent("install-journal.json") }
    static var memoryJournal: URL { support.appendingPathComponent("memory-journal.json") }
    static var appUsage: URL { support.appendingPathComponent("app-usage.json") }
    static var scanSummary: URL { support.appendingPathComponent("scan-summary.json") }
    static var catalogMetadata: URL { caches.appendingPathComponent("catalog-metadata.json") }
}
