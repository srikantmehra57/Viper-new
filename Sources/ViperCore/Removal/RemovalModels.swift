import Foundation
import Darwin

// Discover → explain → select → preview → revalidate → execute → report. See docs/ARCHITECTURE.md, "Safety model".

/// Identity and mutation metadata read without following links. Used to detect swapped or edited files before removal.
public struct FileIdentity: Hashable, Codable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let mode: UInt32
    public let byteCount: Int64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int64
    public let changeSeconds: Int64
    public let changeNanoseconds: Int64

    public static func read(_ url: URL) -> FileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK else { return nil }
        return .init(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino), mode: UInt32(info.st_mode),
                     byteCount: Int64(info.st_size), modificationSeconds: Int64(info.st_mtimespec.tv_sec),
                     modificationNanoseconds: Int64(info.st_mtimespec.tv_nsec), changeSeconds: Int64(info.st_ctimespec.tv_sec),
                     changeNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }
}

/// A bounded recursive fingerprint of names and lstat metadata. File contents are never read.
public struct RemovalSignature: Hashable, Sendable {
    public static let defaultLimit = 200_000
    public let digest: UInt64
    public let entryCount: Int
    /// False when the tree is larger than the review limit. The root and the folders directly inside it are still covered.
    public let coversDescendants: Bool
    let descendantLimit: Int

    public static func read(_ url: URL, limit: Int = RemovalSignature.defaultLimit) throws -> RemovalSignature? {
        guard FileIdentity.read(url) != nil else { return nil }
        var digest: UInt64 = 1_469_598_103_934_665_603
        var count = 0
        var failed = false

        func mix(_ value: UInt64) {
            var value = value
            for _ in 0..<8 {
                digest ^= value & 0xff
                digest &*= 1_099_511_628_211
                value >>= 8
            }
        }
        func include(_ item: URL, relativePath: String) -> Bool {
            var info = stat()
            guard lstat(item.path, &info) == 0 else { return false }
            for byte in relativePath.utf8 {
                digest ^= UInt64(byte)
                digest &*= 1_099_511_628_211
            }
            mix(UInt64(info.st_mode)); mix(UInt64(UInt32(bitPattern: info.st_dev))); mix(UInt64(info.st_ino))
            mix(UInt64(bitPattern: Int64(info.st_size))); mix(UInt64(bitPattern: Int64(info.st_blocks)))
            mix(UInt64(bitPattern: Int64(info.st_mtimespec.tv_sec))); mix(UInt64(bitPattern: Int64(info.st_mtimespec.tv_nsec)))
            mix(UInt64(bitPattern: Int64(info.st_ctimespec.tv_sec))); mix(UInt64(bitPattern: Int64(info.st_ctimespec.tv_nsec)))
            return true
        }

        guard include(url, relativePath: ".") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .init(digest: digest, entryCount: 1, coversDescendants: true, descendantLimit: limit)
        }
        // Always fingerprint the outer shell, even when the deep walk is cut short.
        let shell = try shellEntries(url)
        var shellPaths = Set<String>()
        for entry in shell {
            guard include(entry.url, relativePath: entry.relative) else { return nil }
            shellPaths.insert(entry.url.path)
        }
        if shell.count > limit {
            return .init(digest: digest, entryCount: shell.count + 1, coversDescendants: false, descendantLimit: limit)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in
            failed = true
            return false
        }) else { return nil }
        for case let child as URL in enumerator {
            if shellPaths.contains(child.path) { continue }
            count += 1
            if count % 2_000 == 0 { try Task.checkCancellation() }
            guard shell.count + count <= limit else {
                return .init(digest: digest, entryCount: shell.count + 1, coversDescendants: false, descendantLimit: limit)
            }
            let relative = String(child.path.dropFirst(url.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard include(child, relativePath: relative) else { return nil }
        }
        return failed ? nil : .init(digest: digest, entryCount: shell.count + count + 1, coversDescendants: true, descendantLimit: limit)
    }

    /// The app itself, its immediate children, and one level below those. Deeper files stay on the bounded walk.
    private static func shellEntries(_ root: URL) throws -> [(url: URL, relative: String)] {
        let children = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var entries: [(url: URL, relative: String)] = []
        let budget = 8_000
        for child in children {
            try Task.checkCancellation()
            guard entries.count < budget else { break }
            entries.append((child, child.lastPathComponent))
            var info = stat()
            guard lstat(child.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
            let grandchildren = ((try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [])) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for grandchild in grandchildren {
                guard entries.count < budget else { break }
                entries.append((grandchild, child.lastPathComponent + "/" + grandchild.lastPathComponent))
            }
        }
        return entries
    }
}

public enum RemovalKind: String, CaseIterable, Sendable {
    case application = "App", package = "Package", preferences = "Settings & preferences", appData = "App data"
    case caches = "Caches & web data", logs = "Logs & saved state", launchItems = "Background items", homeSettings = "Home folder settings"
    case temporary = "Temporary files", developer = "Developer caches", file = "Files"
}

public enum MatchConfidence: String, Sendable { case exact, likely }

public struct PackageUninstall: Hashable, Sendable {
    public enum Kind: String, Sendable { case formula, cask, npm }
    public let runtime: PackageRuntime
    public let kind: Kind
    public let package: String

    public init?(runtime: PackageRuntime, kind: Kind, package: String) {
        guard runtime.manager == (kind == .npm ? .npm : .homebrew), PackageRequest.isValidName(package, manager: runtime.manager) else { return nil }
        self.runtime = runtime
        self.kind = kind
        self.package = package
    }

    public var arguments: [String] {
        switch kind {
        case .formula: return ["uninstall", "--formula", package]
        case .cask: return ["uninstall", "--cask", package]
        case .npm: return ["uninstall", "--global", package]
        }
    }
    public var displayCommand: String { ([runtime.executable.path] + arguments).joined(separator: " ") }
}

public enum RemovalAction: Hashable, Sendable {
    case trash
    case packageUninstall(PackageUninstall)
}

public struct RemovalItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let kind: RemovalKind
    public let confidence: MatchConfidence
    public let reason: String
    public let warning: String?
    /// Allocated bytes; nil when too large to measure quickly or not readable.
    public let size: Int64?
    public let identity: FileIdentity?
    /// Recursive review-time metadata. Missing only for package-manager-owned targets that are not moved directly.
    public let signature: RemovalSignature?
    /// Canonical parent folder at review time. Execution refuses the item if this changes.
    public let parentPath: String
    public let action: RemovalAction
    /// The app bundle or package itself. Everything else depends on it being removed first.
    public let isRequired: Bool

    public var selectedByDefault: Bool { isRequired || confidence == .exact }

    public init(url: URL, kind: RemovalKind, confidence: MatchConfidence, reason: String, warning: String?, size: Int64?,
                identity: FileIdentity?, signature: RemovalSignature? = nil, parentPath: String, action: RemovalAction, isRequired: Bool) {
        self.url = url
        self.kind = kind
        self.confidence = confidence
        self.reason = reason
        self.warning = warning
        self.size = size
        self.identity = identity
        self.signature = signature
        self.parentPath = parentPath
        self.action = action
        self.isRequired = isRequired
    }
}

public struct KeptItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let reason: String
}

public struct UninstallPlan: Sendable {
    public let name: String
    public let bundleIdentifier: String?
    public let items: [RemovalItem]
    public let kept: [KeptItem]
    /// Hard stops. Nothing can be removed while any exist.
    public let blockers: [String]
    public let createdAt: Date

    public var canProceed: Bool { blockers.isEmpty && items.contains(where: \.isRequired) }
    public var required: RemovalItem? { items.first(where: \.isRequired) }
}

public struct UninstallContext: Sendable {
    public let home: URL
    public let applications: [InstalledApplication]
    public let tools: [CommandLinePackage]
    public let protectedBundleIdentifiers: Set<String>
    public let homebrewPrefixes: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, applications: [InstalledApplication], tools: [CommandLinePackage],
                protectedBundleIdentifiers: Set<String>, homebrewPrefixes: [URL] = UpdateChecker.brewExecutables().map { $0.deletingLastPathComponent().deletingLastPathComponent() }) {
        self.home = home
        self.applications = applications
        self.tools = tools
        self.protectedBundleIdentifiers = protectedBundleIdentifiers
        self.homebrewPrefixes = homebrewPrefixes
    }

    var library: URL { home.appendingPathComponent("Library") }
}
