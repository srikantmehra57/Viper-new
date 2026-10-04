import CoreServices
import Foundation

/// How much the user actually reaches for an app: Spotlight's use count plus Viper's own local history.
public struct AppUsage: Sendable, Equatable {
    public var spotlightUseCount: Int?
    public var spotlightLastUsed: Date?
    public var recentLaunches: [Date]
    public var lastActivated: Date?

    public init(spotlightUseCount: Int? = nil, spotlightLastUsed: Date? = nil, recentLaunches: [Date] = [], lastActivated: Date? = nil) {
        self.spotlightUseCount = spotlightUseCount
        self.spotlightLastUsed = spotlightLastUsed
        self.recentLaunches = recentLaunches
        self.lastActivated = lastActivated
    }
}

/// Launch counts macOS already keeps for Spotlight, read through the metadata store.
public enum SpotlightUsage {
    public static func read(_ appURL: URL) -> (useCount: Int?, lastUsed: Date?) {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, appURL as CFURL) else { return (nil, nil) }
        // These attribute names are part of the metadata store but not exported as SDK constants.
        let count = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? Int)
        let lastUsed = (MDItemCopyAttribute(item, "kMDItemLastUsedDate" as CFString) as? Date)
        return (count, lastUsed)
    }
}

/// Viper's own record of app launches and activations, kept locally in Application Support.
/// A non-critical cache: a missing or unreadable file just means a cold start, so it is never quarantined.
public struct UsageHistory: Codable {
    public struct Record: Codable {
        public var launches: [Date] = []
        public var lastActivated: Date?
    }
    public var apps: [String: Record] = [:]

    public static let launchHorizon: TimeInterval = 30 * 24 * 3600
    public static let launchLimit = 60

    public mutating func recordLaunch(_ bundleID: String, at date: Date = Date()) {
        var record = apps[bundleID] ?? Record()
        record.launches.append(date)
        record.launches = Array(record.launches.filter { date.timeIntervalSince($0) < Self.launchHorizon }.suffix(Self.launchLimit))
        apps[bundleID] = record
    }

    public mutating func recordActivation(_ bundleID: String, at date: Date = Date()) {
        var record = apps[bundleID] ?? Record()
        record.lastActivated = date
        record.launches = record.launches.filter { date.timeIntervalSince($0) < Self.launchHorizon }
        apps[bundleID] = record
    }

    public func usage(of bundleID: String) -> AppUsage {
        let record = apps[bundleID]
        return AppUsage(recentLaunches: record?.launches ?? [], lastActivated: record?.lastActivated)
    }

    public static func load(from url: URL) -> UsageHistory {
        guard let data = try? Data(contentsOf: url), let history = try? InstallJournal.decoder.decode(UsageHistory.self, from: data) else { return .init() }
        return history
    }

    public func save(to url: URL) throws { try InstallJournal.write(self, to: url) }
}
