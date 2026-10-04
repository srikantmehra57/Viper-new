import Foundation
import Security

public struct InstalledApplication: Identifiable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let bundleIdentifier: String?
    public let version: String
    public let url: URL
    public let isSystem: Bool
    public let isAppStore: Bool
    public let teamIdentifier: String?
    public let applicationGroups: Set<String>
    public var sourceLabel: String { isSystem ? "macOS" : (isAppStore ? "App Store receipt" : "Application folder") }

    public init(name: String, bundleIdentifier: String?, version: String, url: URL, isSystem: Bool, isAppStore: Bool,
                teamIdentifier: String? = nil, applicationGroups: Set<String> = []) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.url = url
        self.isSystem = isSystem
        self.isAppStore = isAppStore
        self.teamIdentifier = teamIdentifier
        self.applicationGroups = applicationGroups
    }
}

public struct AppInventoryResult: Sendable {
    public let applications: [InstalledApplication]
    public let searchedFolders: [String]
    public let unavailableFolders: [String]
}

public enum AppInventory {
    public static func read() throws -> AppInventoryResult {
        let manager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var applications: [InstalledApplication] = []
        var searched: [String] = []
        var unavailable: [String] = []
        for root in roots {
            try Task.checkCancellation()
            guard manager.fileExists(atPath: root.path) else { continue }
            guard manager.isReadableFile(atPath: root.path) else { unavailable.append(root.path); continue }
            searched.append(root.path)
            guard let iterator = manager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, _ in unavailable.append(url.path); return true }) else {
                unavailable.append(root.path)
                continue
            }
            for case let url as URL in iterator {
                try Task.checkCancellation()
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    iterator.skipDescendants()
                    continue
                }
                guard url.pathExtension.lowercased() == "app" else { continue }
                iterator.skipDescendants()
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let signing = signingInfo(for: url)
                applications.append(InstalledApplication(
                    name: name, bundleIdentifier: bundle?.bundleIdentifier,
                    version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
                    url: url, isSystem: url.path.hasPrefix("/System/"),
                    isAppStore: manager.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path),
                    teamIdentifier: signing.teamIdentifier, applicationGroups: signing.applicationGroups
                ))
            }
        }
        return AppInventoryResult(applications: applications.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, searchedFolders: searched, unavailableFolders: unavailable)
    }

    private static func signingInfo(for url: URL) -> (teamIdentifier: String?, applicationGroups: Set<String>) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess, let code else { return (nil, []) }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return (nil, []) }
        let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let groups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        return (team, Set(groups.map { $0.lowercased() }))
    }
}
