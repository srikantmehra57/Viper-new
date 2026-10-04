import Foundation

public struct InstallEnvironment: Sendable {
    public let system: SystemProfile
    public let homebrew: [PackageRuntime]
    public let npm: [PackageRuntime]
    public let packages: InstalledPackages
    public let applications: [InstalledApplication]
    /// Catalog command names found in common tool folders, with every matching path.
    public let commands: [String: [String]]
    public let nodeVersions: [String: String]
    public let checks: [SourceCheck]
    public let detectedAt: Date

    public init(system: SystemProfile, homebrew: [PackageRuntime], npm: [PackageRuntime], packages: InstalledPackages, applications: [InstalledApplication],
                commands: [String: [String]], nodeVersions: [String: String], checks: [SourceCheck], detectedAt: Date = Date()) {
        self.system = system
        self.homebrew = homebrew
        self.npm = npm
        self.packages = packages
        self.applications = applications
        self.commands = commands
        self.nodeVersions = nodeVersions
        self.checks = checks
        self.detectedAt = detectedAt
    }

    public var preferredHomebrew: PackageRuntime? { PackageRuntime.preferredHomebrew(homebrew, appleSilicon: system.appleSilicon) }

    /// Folders checked for existing command-line tools, including each detected npm runtime.
    public static func commandFolders(npm: [PackageRuntime], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        var folders = ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".volta/bin").path, home.appendingPathComponent(".bun/bin").path]
        for runtime in npm where !folders.contains(runtime.location) { folders.append(runtime.location) }
        return folders
    }

    public static func findCommands(_ names: Set<String>, in folders: [String]) -> [String: [String]] {
        var found: [String: [String]] = [:]
        for name in names.sorted() {
            for folder in folders {
                let path = URL(fileURLWithPath: folder).appendingPathComponent(name).path
                if FileManager.default.isExecutableFile(atPath: path) { found[name, default: []].append(path) }
            }
        }
        return found
    }
}

public enum CatalogStatus: Equatable, Sendable {
    case available
    case installed(source: String, version: String)
    case installedElsewhere(String, appURL: URL?)
    case needsSetup(PackageManager)
    case unavailable(String)
    case incompatible(String)
    case needsAttention(String)
    case external(InstallMethod)

    public var isSelectable: Bool { self == .available }
    public var isInstalled: Bool {
        switch self {
        case .installed, .installedElsewhere: return true
        default: return false
        }
    }
}

public struct InstallPlanItem: Identifiable, Sendable {
    public enum Decision: Equatable, Sendable {
        case install(PackageRequest)
        case skip(String)
        case blocked(String)
    }
    public var id: String { entry.id }
    public let entry: CatalogEntry
    public let decision: Decision
    public let version: String?
    public let details: [String]
}

public enum InstallPlanner {
    public static func status(for entry: CatalogEntry, in environment: InstallEnvironment, metadata: PackageMetadata?, npmRuntime: PackageRuntime? = nil) -> CatalogStatus {
        let route = entry.install
        let apps = matchingApplications(entry, environment: environment, metadata: metadata)
        switch route.method {
        case .appStore, .vendor:
            if let app = apps.first { return .installed(source: app.sourceLabel, version: app.version) }
            if let reason = incompatibility(entry, metadata: nil, system: environment.system) { return .incompatible(reason) }
            return .external(route.method)
        case .homebrewCask, .homebrewFormula, .npm:
            guard let package = route.package else { return .unavailable("This catalog entry has no package mapping.") }
            if route.method == .npm {
                for runtime in environment.npm {
                    if let version = environment.packages.npm[runtime.id]?[package] { return .installed(source: runtime.label, version: version) }
                }
            } else {
                let lists = route.method == .homebrewCask ? environment.packages.casks : environment.packages.formulae
                for runtime in environment.homebrew {
                    if let version = lists[runtime.id]?[package] { return .installed(source: runtime.label, version: version) }
                }
            }
            if let app = apps.first {
                return .installedElsewhere("\(app.name) is already installed at \(app.url.path). Viper won’t replace or adopt an installation from another source.", appURL: app.url)
            }
            for command in entry.commands ?? [] {
                if let path = environment.commands[command]?.first {
                    return .installedElsewhere("A “\(command)” command already exists at \(path). Viper won’t replace or adopt a tool installed another way.", appURL: nil)
                }
            }
            if let reason = incompatibility(entry, metadata: metadata, system: environment.system) { return .incompatible(reason) }
            let runtime: PackageRuntime
            if route.method == .npm {
                guard let selected = npmRuntime ?? environment.npm.first else { return .needsSetup(.npm) }
                runtime = selected
                guard environment.packages.npm[runtime.id] != nil else { return .needsAttention("Viper couldn’t read this npm runtime’s global packages. Check again before installing.") }
            } else {
                guard !environment.homebrew.isEmpty else { return .needsSetup(.homebrew) }
                guard let preferred = environment.preferredHomebrew else {
                    return .needsAttention("Homebrew was found at \(environment.homebrew.map(\.location).joined(separator: ", ")), which isn’t the standard location for this Mac. Viper won’t install with it.")
                }
                runtime = preferred
                guard environment.packages.casks[runtime.id] != nil else { return .needsAttention("Viper couldn’t read what Homebrew has installed. Check again before installing.") }
            }
            guard let metadata else { return .available }
            guard metadata.found else { return .unavailable("\(route.method.sourceLabel) doesn’t currently offer “\(package)”. This catalog mapping needs review.") }
            if let canonical = metadata.canonicalName, canonical != package {
                return .unavailable("\(route.method.sourceLabel) now calls this package “\(canonical)”. Viper won’t follow a renamed mapping until the catalog is reviewed.")
            }
            if metadata.disabled { return .unavailable("Homebrew has disabled this package.") }
            if metadata.deprecated { return .needsAttention("Homebrew has deprecated this package. Check the publisher’s website for a supported route.") }
            if metadata.requiresAdministrator { return .needsAttention("This package runs an installer that needs an administrator password. Use the publisher’s website instead.") }
            if let requirement = metadata.nodeRequirement, let node = environment.nodeVersions[runtime.id], nodeSatisfies(requirement, version: node) == false {
                return .incompatible("Requires Node.js \(requirement). The selected runtime has \(node).")
            }
            return .available
        }
    }

    /// Builds the reviewed batch. Every install requires fresh provider metadata; nothing is inferred from names.
    public static func plan(selection: [CatalogEntry], environment: InstallEnvironment, metadata: [String: PackageMetadata], npmRuntime: PackageRuntime?) -> [InstallPlanItem] {
        var seenIDs = Set<String>()
        var seenPackages = Set<String>()
        var items: [InstallPlanItem] = []
        for entry in selection where seenIDs.insert(entry.id).inserted {
            guard let key = entry.metadataKey, entry.install.method.isDirect else {
                items.append(.init(entry: entry, decision: .skip("Available from the \(entry.install.method.sourceLabel). Viper opens it there instead."), version: nil, details: []))
                continue
            }
            guard seenPackages.insert(key).inserted else {
                items.append(.init(entry: entry, decision: .skip("Already included in this batch."), version: nil, details: []))
                continue
            }
            let data = metadata[key]
            let status = status(for: entry, in: environment, metadata: data, npmRuntime: npmRuntime)
            let decision: InstallPlanItem.Decision
            switch status {
            case .available:
                let runtime = entry.install.method == .npm ? (npmRuntime ?? environment.npm.first) : environment.preferredHomebrew
                if data == nil {
                    decision = .blocked("Viper couldn’t verify this package with \(entry.install.method.sourceLabel) just now. Check your connection and try again.")
                } else if let runtime, let package = entry.install.package, let request = PackageRequest(method: entry.install.method, package: package, runtime: runtime) {
                    decision = .install(request)
                } else {
                    decision = .blocked("This package mapping couldn’t be validated.")
                }
            case .installed(let source, let version): decision = .skip("Already installed (\(version.isEmpty ? "version unknown" : version)) from \(source). Newer versions appear in Updates.")
            case .installedElsewhere(let reason, _): decision = .skip(reason)
            case .needsSetup(let manager): decision = .blocked("\(manager.rawValue) isn’t set up on this Mac yet.")
            case .unavailable(let reason), .incompatible(let reason), .needsAttention(let reason): decision = .blocked(reason)
            case .external(let method): decision = .skip("Available from the \(method.sourceLabel).")
            }
            items.append(.init(entry: entry, decision: decision, version: data?.version, details: disclosures(entry, metadata: data, decision: decision, environment: environment)))
        }
        // Homebrew formulae first so shared tools settle before apps, then casks, then npm packages.
        let rank: [InstallMethod: Int] = [.homebrewFormula: 0, .homebrewCask: 1, .npm: 2, .appStore: 3, .vendor: 3]
        return items.enumerated().sorted {
            let left = rank[$0.element.entry.install.method] ?? 3, right = rank[$1.element.entry.install.method] ?? 3
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }

    static func disclosures(_ entry: CatalogEntry, metadata: PackageMetadata?, decision: InstallPlanItem.Decision, environment: InstallEnvironment) -> [String] {
        guard case .install(let request) = decision else { return [] }
        var details: [String] = []
        switch request.method {
        case .homebrewCask:
            details.append("Homebrew cask “\(request.package)” using \(request.runtime.location). Installs the app into your Applications folder and may add command-line helpers.")
        case .homebrewFormula:
            details.append("Homebrew formula “\(request.package)” using \(request.runtime.location).")
        default:
            details.append("Global npm package “\(request.package)” in \(request.runtime.location).")
        }
        if let metadata {
            if let registry = metadata.registryURL {
                details.append("Downloads npm metadata and the package from \(registry.absoluteString). A registry change requires a new review.")
            }
            let installed = Set((environment.packages.formulae[request.runtime.id] ?? [:]).keys).union((environment.packages.casks[request.runtime.id] ?? [:]).keys)
            let missing = metadata.dependencies.filter { !installed.contains($0) }
            if !missing.isEmpty { details.append("Also installs \(missing.count) Homebrew dependenc\(missing.count == 1 ? "y" : "ies"): \(missing.joined(separator: ", ")).") }
            if metadata.runsInstallScripts { details.append("This package runs its own install scripts while installing. Those scripts run as you and can read your home folder. Viper does not pass your SSH agent to them.") }
            if let requirement = metadata.nodeRequirement {
                details.append("Requires Node.js \(requirement). This runtime has \(environment.nodeVersions[request.runtime.id] ?? "an unknown version").")
            }
        }
        if entry.requiresAccount == true { details.append("Needs an account to use after installing.") }
        if entry.pricing == .paid || entry.pricing == .freemium { details.append("Price: \(entry.pricing.label.lowercased()).") }
        details += entry.notes ?? []
        details.append("Download size unavailable before installing.")
        return details
    }

    public static func matchingApplications(_ entry: CatalogEntry, environment: InstallEnvironment, metadata: PackageMetadata?) -> [InstalledApplication] {
        guard entry.kind == .app else { return [] }
        let identifiers = Set((entry.bundleIdentifiers ?? []).map { $0.lowercased() })
        let names = Set((entry.appNames ?? []) + (metadata?.appNames ?? []))
        return environment.applications.filter {
            !$0.isSystem && (($0.bundleIdentifier.map { identifiers.contains($0.lowercased()) } ?? false) || names.contains($0.url.lastPathComponent))
        }
    }

    static func incompatibility(_ entry: CatalogEntry, metadata: PackageMetadata?, system: SystemProfile) -> String? {
        if (entry.appleSiliconOnly == true || metadata?.appleSiliconOnly == true) && !system.appleSilicon { return "Requires a Mac with Apple silicon." }
        for minimum in [entry.minimumMacOS, metadata?.minimumMacOS].compactMap({ $0 }) where UpdateChecker.isNewer(minimum, than: system.macOSVersion) {
            return "Requires macOS \(minimum) or later."
        }
        return nil
    }

    /// Supports the common “>=x.y.z” form. Other ranges return nil and are disclosed rather than guessed.
    public static func nodeSatisfies(_ requirement: String, version: String) -> Bool? {
        let trimmed = requirement.replacingOccurrences(of: " ", with: "")
        guard trimmed.hasPrefix(">="), !trimmed.contains("||"), !trimmed.contains("<") else { return nil }
        let minimum = String(trimmed.dropFirst(2))
        guard minimum.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil,
              version.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil else { return nil }
        return !UpdateChecker.isNewer(minimum, than: version)
    }
}
