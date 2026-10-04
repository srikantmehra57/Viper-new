import Foundation
import Darwin

/// Items found by a cleanup scan, ready for review. Nothing here has been changed.
public struct CleanupReport: Sendable {
    public let items: [RemovalItem]
    public let kept: [KeptItem]
    public let locations: [String]
    public let unavailable: [String]
    public let completedAt: Date

    public var totalBytes: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }

    public init(items: [RemovalItem], kept: [KeptItem], locations: [String], unavailable: [String], completedAt: Date) {
        self.items = items
        self.kept = kept
        self.locations = locations
        self.unavailable = unavailable
        self.completedAt = completedAt
    }
}

/// Moves reviewed cleanup items to the Trash. Every item is rechecked just before it moves.
public enum CleanupExecutor {
    public static func trash(_ items: [RemovalItem],
                             isAllowed: @Sendable (RemovalItem) async -> String?,
                             mayContinue: @Sendable () async -> Bool = { true },
                             trash: UninstallExecutor.Trasher = UninstallExecutor.systemTrash,
                             record: UninstallExecutor.OutcomeRecorder = { _ in true },
                             progress: @Sendable (String) async -> Void = { _ in }) async -> [RemovalOutcome] {
        var outcomes: [RemovalOutcome] = []
        for (index, item) in items.enumerated() {
            await progress("Moving \(index + 1) of \(items.count) to the Trash…")
            guard await mayContinue() else {
                let outcome = RemovalOutcome(item: item, result: .skipped("Reviewed changes were turned off, so Viper left this item alone."))
                outcomes.append(outcome)
                guard await record(outcome) else { break }
                continue
            }
            guard item.action == .trash, !item.isRequired else {
                let outcome = RemovalOutcome(item: item, result: .skipped("This item can’t be cleaned here."))
                outcomes.append(outcome)
                guard await record(outcome) else { break }
                continue
            }
            var reason = UninstallExecutor.identityChanged(item)
            if reason == nil { reason = await isAllowed(item) }
            let outcome = reason.map { RemovalOutcome(item: item, result: .skipped($0)) }
                ?? RemovalOutcome(item: item, result: UninstallExecutor.move(item, trash: trash))
            outcomes.append(outcome)
            guard await record(outcome) else { break }
        }
        return outcomes
    }
}

// MARK: - Leftovers

/// App files whose owning app is no longer installed.
public enum LeftoverScanner {
    struct Scope {
        let folder: String
        let kind: RemovalKind
        let suffix: String
        /// Rebuilt automatically if an app comes back, so it's selected by default.
        let recreatable: Bool
    }

    static let scopes: [Scope] = [
        .init(folder: "Preferences", kind: .preferences, suffix: ".plist", recreatable: false),
        .init(folder: "Application Support", kind: .appData, suffix: "", recreatable: false),
        .init(folder: "Containers", kind: .appData, suffix: "", recreatable: false),
        .init(folder: "Group Containers", kind: .appData, suffix: "", recreatable: false),
        .init(folder: "Application Scripts", kind: .appData, suffix: "", recreatable: true),
        .init(folder: "Caches", kind: .caches, suffix: "", recreatable: true),
        .init(folder: "HTTPStorages", kind: .caches, suffix: "", recreatable: true),
        .init(folder: "WebKit", kind: .caches, suffix: "", recreatable: true),
        .init(folder: "Cookies", kind: .caches, suffix: ".binarycookies", recreatable: true),
        .init(folder: "Logs", kind: .logs, suffix: "", recreatable: true),
        .init(folder: "Saved Application State", kind: .logs, suffix: ".savedState", recreatable: true),
        .init(folder: "LaunchAgents", kind: .launchItems, suffix: ".plist", recreatable: false)
    ]

    /// - Parameter isKnownApp: asks Launch Services whether an app with this identifier exists anywhere, including other volumes.
    public static func scan(library: URL, installedIdentifiers: Set<String>, installedApplicationGroups: Set<String> = [], inventoryIncomplete: Bool = false,
                            isKnownApp: (String) -> Bool = { _ in false }, now: Date = Date()) throws -> CleanupReport {
        let manager = FileManager.default
        var items: [RemovalItem] = []
        var kept: [KeptItem] = []
        var locations: [String] = []
        var unavailable: [String] = []
        for scope in scopes {
            try Task.checkCancellation()
            let location = library.appendingPathComponent(scope.folder)
            guard manager.fileExists(atPath: location.path) else { continue }
            guard let entries = try? manager.contentsOfDirectory(at: location, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
                unavailable.append(location.path)
                continue
            }
            locations.append(location.path)
            for entry in entries {
                try Task.checkCancellation()
                let name = entry.lastPathComponent
                guard scope.suffix.isEmpty || name.hasSuffix(scope.suffix) else { continue }
                let (base, grouped) = UninstallPlanner.identifierBase(name)
                guard isCandidate(base, installedIdentifiers: installedIdentifiers) else { continue }
                // Group containers are owned by an exact signed entitlement, not by a broad vendor-name guess.
                if grouped, installedApplicationGroups.contains(name.lowercased()) {
                    kept.append(.init(url: entry, reason: "An installed app’s signed application-group entitlement uses this exact shared container."))
                    continue
                }
                if let owner = prefixes(of: base).first(where: isKnownApp) {
                    kept.append(.init(url: entry, reason: "macOS still knows an app with the identifier \(owner), possibly on another drive."))
                    continue
                }
                var evidence = "No installed app uses the identifier \(base), and macOS doesn’t know one elsewhere."
                if let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    evidence += " Last changed \(RelativeDateTimeFormatter().localizedString(for: modified, relativeTo: now))."
                }
                if inventoryIncomplete { evidence += " Some application folders couldn’t be read." }
                let warning: String? = switch scope.kind {
                case .launchItems: "A background item. If it’s still running, it stops after you log out or restart."
                case .appData: "May contain data you created in that app."
                default: nil
                }
                if let item = try UninstallPlanner.makeItem(entry, kind: scope.kind, confidence: scope.recreatable && !grouped ? .exact : .likely, reason: evidence, warning: warning) {
                    items.append(item)
                }
            }
        }
        return .init(items: items.sorted { ($0.size ?? 0) > ($1.size ?? 0) }, kept: kept, locations: locations, unavailable: unavailable, completedAt: now)
    }

    /// Only reverse-DNS identifiers from third parties. A missing match is evidence, not proof.
    public static func isCandidate(_ identifier: String, installedIdentifiers: Set<String>) -> Bool {
        let id = identifier.lowercased()
        let parts = id.split(separator: ".")
        guard parts.count >= 3, ["com", "org", "net", "io", "app", "dev", "co", "me", "ai", "tv", "us"].contains(String(parts[0])),
              !id.hasPrefix("com.apple."), !id.hasPrefix("group."),
              id.range(of: "^[a-z0-9-]+(\\.[a-z0-9_-]+){2,}$", options: .regularExpression) != nil else { return false }
        return !installedIdentifiers.contains {
            let installed = $0.lowercased()
            return installed == id || id.hasPrefix(installed + ".") || installed.hasPrefix(id + ".")
        }
    }

    /// com.vendor.app.helper → [com.vendor.app.helper, com.vendor.app]
    public static func prefixes(of identifier: String) -> [String] {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 3 else { return [identifier] }
        return (3...parts.count).reversed().map { parts.prefix($0).joined(separator: ".") }
    }

    public static func isAllowed(_ item: RemovalItem, library: URL) -> Bool {
        let parents = Set(scopes.map { library.appendingPathComponent($0.folder).resolvingSymlinksInPath().standardizedFileURL.path })
        return parents.contains(item.parentPath)
    }
}

// MARK: - Junk

/// Caches, logs, old temporary files, and developer build data that software recreates when needed.
public enum JunkScanner {
    public struct Environment: Sendable {
        public let home: URL
        public let temporaryDirectory: URL
        public let runningIdentifiers: Set<String>
        public let runningNames: Set<String>
        public let displayNames: [String: String]
        public let now: Date

        public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                    runningIdentifiers: Set<String>, runningNames: Set<String>, displayNames: [String: String] = [:], now: Date = Date()) {
            self.home = home
            self.temporaryDirectory = temporaryDirectory
            self.runningIdentifiers = runningIdentifiers
            self.runningNames = Set(runningNames.map { $0.lowercased() })
            self.displayNames = displayNames
            self.now = now
        }
    }

    static let temporaryAge: TimeInterval = 3 * 24 * 3600
    /// macOS-owned caches without an com.apple prefix, and Viper's own.
    static let skippedCacheNames: Set<String> = ["CloudKit", "FamilyCircle", "familycircled", "Viper", "GeoServices", "PassKit", "Animoji", "GameKit", "Maps", "SiriTTS", "icloudmailagent", "storedownloadd"]
    /// Large downloads that live in Caches but take a long time to fetch again.
    static let slowToRebuild: Set<String> = ["ms-playwright", "JetBrains", "pypoetry", "huggingface", "Google/AndroidStudio"]

    public static func scan(_ environment: Environment) throws -> CleanupReport {
        var items: [RemovalItem] = []
        var kept: [KeptItem] = []
        var locations: [String] = []
        var unavailable: [String] = []
        let library = environment.home.appendingPathComponent("Library")

        func entries(_ folder: URL) -> [URL]? {
            guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
            guard let list = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else {
                unavailable.append(folder.path)
                return nil
            }
            locations.append(folder.path)
            return list.filter { !$0.lastPathComponent.hasPrefix(".") }
        }

        func runningOwner(_ name: String) -> String? {
            Self.runningOwner(name: name, identifiers: environment.runningIdentifiers, names: environment.runningNames, displayNames: environment.displayNames)
        }

        func add(_ url: URL, _ kind: RemovalKind, selected: Bool, reason: String, warning: String? = nil) throws {
            let confidence = Self.rebuildConfidence(url: url, rebuildable: selected, temporaryDirectory: environment.temporaryDirectory)
            if let item = try UninstallPlanner.makeItem(url, kind: kind, confidence: confidence, reason: reason, warning: warning), (item.size ?? 1) > 0 {
                items.append(item)
            }
        }

        for entry in entries(library.appendingPathComponent("Caches")) ?? [] {
            try Task.checkCancellation()
            let name = entry.lastPathComponent
            guard !name.hasPrefix("com.apple."), !skippedCacheNames.contains(name) else { continue }
            if let owner = runningOwner(name) {
                kept.append(.init(url: entry, reason: "\(owner) is open and uses this cache. Quit it, then scan again."))
                continue
            }
            if slowToRebuild.contains(name) {
                try add(entry, .caches, selected: false, reason: "Downloaded tools or data. They’re downloaded again when needed, which can take a long time.")
            } else {
                try add(entry, .caches, selected: true, reason: "App cache. Apps rebuild caches when they need them, which can make their next launch slower.")
            }
        }
        for entry in entries(library.appendingPathComponent("Logs")) ?? [] {
            try Task.checkCancellation()
            if let owner = runningOwner(entry.lastPathComponent) {
                kept.append(.init(url: entry, reason: "\(owner) is open and may be writing to these logs."))
                continue
            }
            try add(entry, .logs, selected: true, reason: "Log files. They help diagnose problems and aren’t needed for apps to work.")
        }

        let temporary = environment.temporaryDirectory.resolvingSymlinksInPath()
        for entry in entries(temporary) ?? [] {
            try Task.checkCancellation()
            let name = entry.lastPathComponent
            guard !name.hasPrefix("viper-"), !name.hasPrefix("com.apple."), name != "TemporaryItems" else { continue }
            guard let newest = newestChange(entry), environment.now.timeIntervalSince(newest) > temporaryAge else { continue }
            try add(entry, .temporary, selected: true, reason: "Temporary file not changed in \(RelativeDateTimeFormatter().localizedString(for: newest, relativeTo: environment.now).replacingOccurrences(of: " ago", with: "")). Apps use these while working and don’t need them later.")
        }

        let xcodeRunning = environment.runningIdentifiers.contains("com.apple.dt.Xcode")
        let developer = library.appendingPathComponent("Developer")
        for entry in entries(developer.appendingPathComponent("Xcode/DerivedData")) ?? [] {
            try Task.checkCancellation()
            if xcodeRunning { kept.append(.init(url: entry, reason: "Xcode is open. Quit it to clean build data.")); continue }
            try add(entry, .developer, selected: true, reason: "Xcode build data. Xcode rebuilds it the next time you build this project.")
        }
        for folder in ["Xcode/iOS DeviceSupport", "Xcode/watchOS DeviceSupport", "Xcode/macOS DeviceSupport"] {
            for entry in entries(developer.appendingPathComponent(folder)) ?? [] {
                try add(entry, .developer, selected: false, reason: "Device debugging symbols. Xcode copies them again when you connect that device, which can take a while.")
            }
        }
        for entry in entries(developer.appendingPathComponent("CoreSimulator/Caches")) ?? [] {
            try add(entry, .developer, selected: !xcodeRunning, reason: "Simulator caches. They’re rebuilt when a simulator starts.")
        }
        let npmCache = environment.home.appendingPathComponent(".npm/_cacache")
        if FileIdentity.read(npmCache) != nil {
            locations.append(npmCache.path)
            try add(npmCache, .developer, selected: true, reason: "npm’s download cache. npm downloads packages again when needed.")
        }
        return .init(items: items.sorted { ($0.size ?? 0) > ($1.size ?? 0) }, kept: kept, locations: locations, unavailable: unavailable, completedAt: environment.now)
    }

    /// The open app this folder belongs to, when the name or bundle id makes that clear.
    /// A bundle-id piece such as `codex` in `com.openai.codex` matches `Codex` even if the app is named ChatGPT.
    public static func runningOwner(name: String, identifiers: Set<String>, names: Set<String>, displayNames: [String: String]) -> String? {
        let base = UninstallPlanner.identifierBase(name).base
        if let id = identifiers.first(where: { UninstallPlanner.belongs(base, to: $0) }) {
            return displayNames[id] ?? id
        }
        let lower = name.lowercased()
        for id in identifiers.sorted() {
            let parts = id.lowercased().split(separator: ".").map(String.init).filter { $0.count >= 5 }
            if parts.contains(where: { matchesToken(lower, token: $0) }) {
                return displayNames[id] ?? id
            }
        }
        if let running = names.first(where: { running in
            let token = running.lowercased()
            return token == lower || (token.split(separator: " ").first.map { $0.count >= 4 && lower.hasPrefix($0) } ?? false)
        }) {
            return displayNames[running] ?? displayNames[running.lowercased()] ?? running
        }
        return nil
    }

    /// `codex` matches `Codex`, and `openai` matches `openai-cache`. It does not match `codex` inside `mycodextra`.
    private static func matchesToken(_ name: String, token: String) -> Bool {
        if name == token { return true }
        guard name.hasPrefix(token) else { return false }
        let next = name[name.index(name.startIndex, offsetBy: token.count)]
        return !next.isLetter
    }

    /// Exact only for a bundle-identifier cache or a location Viper knows is rebuilt. A vendor folder name stays likely.
    static func rebuildConfidence(url: URL, rebuildable: Bool, temporaryDirectory: URL) -> MatchConfidence {
        guard rebuildable else { return .likely }
        let name = url.lastPathComponent
        if bundleIdentifierShaped(name) { return .exact }
        if url.path.contains("/Xcode/DerivedData/") || url.path.contains("/CoreSimulator/Caches/") || name == "_cacache" { return .exact }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        let temporary = temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        if parent == temporary { return .exact }
        return .likely
    }

    static func bundleIdentifierShaped(_ name: String) -> Bool {
        let base = UninstallPlanner.identifierBase(name).base.lowercased()
        let parts = base.split(separator: ".")
        guard parts.count >= 3, ["com", "org", "net", "io", "app", "dev", "co", "me", "ai", "tv", "us"].contains(String(parts[0])) else { return false }
        return base.range(of: "^[a-z0-9-]+(\\.[a-z0-9_-]+){2,}$", options: .regularExpression) != nil
    }

    public static func allowedParents(home: URL, temporaryDirectory: URL) -> Set<String> {
        let library = home.appendingPathComponent("Library")
        let folders = [library.appendingPathComponent("Caches"), library.appendingPathComponent("Logs"), temporaryDirectory,
                       library.appendingPathComponent("Developer/Xcode/DerivedData"), library.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
                       library.appendingPathComponent("Developer/Xcode/watchOS DeviceSupport"), library.appendingPathComponent("Developer/Xcode/macOS DeviceSupport"),
                       library.appendingPathComponent("Developer/CoreSimulator/Caches"), home.appendingPathComponent(".npm")]
        return Set(folders.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
    }

    /// Newest modification inside an item, bounded so huge folders don't stall the scan.
    static func newestChange(_ url: URL, limit: Int = 5_000) -> Date? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        var newest = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return newest }
        var count = 0
        for case let child as URL in enumerator {
            count += 1
            if count > limit { return Date() }
            if let date = try? child.resourceValues(forKeys: Set(keys)).contentModificationDate, date > (newest ?? .distantPast) { newest = date }
        }
        return newest
    }
}

// MARK: - Storage files

public enum StorageCleanup {
    /// Personal files from a storage scan that may be moved to the Trash after review.
    public static func item(for file: StorageFile, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> RemovalItem? {
        guard blockedReason(file.url, home: home) == nil, let identity = FileIdentity.read(file.url),
              let signature = try? RemovalSignature.read(file.url),
              // A different size means the file changed after the scan. lstat avoids Foundation's cached resource values.
              currentAllocatedBytes(file.url) == file.allocatedBytes else { return nil }
        return RemovalItem(url: file.url, kind: .file, confidence: .exact, reason: "One of the largest files in this scan.", warning: nil, size: file.allocatedBytes,
                           identity: identity, signature: signature, parentPath: UninstallPlanner.canonicalParent(file.url), action: .trash, isRequired: false)
    }

    static func currentAllocatedBytes(_ url: URL) -> Int64? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return max(0, Int64(info.st_blocks) * 512)
    }

    public static func blockedReason(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        if url.pathComponents.contains(where: { $0.hasSuffix(".app") }) { return "Part of an app. Use the Uninstaller to remove apps." }
        switch RemovalPolicy.assess(url, home: home) {
        case .protected(let reason): return reason
        case .reviewRequired: return nil
        }
    }
}
