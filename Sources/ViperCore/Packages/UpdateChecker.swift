import Foundation

public enum UpdateSource: String, Sendable { case homebrew = "Homebrew", npm = "npm", appStore = "App Store" }

public struct AvailableUpdate: Identifiable, Sendable {
    public var id: String { source.rawValue + ":" + (executable?.path ?? "") + ":" + package }
    public let name: String
    public let package: String
    public let installed: String
    public let available: String
    public let source: UpdateSource
    public let executable: URL?
    public let isCask: Bool
    public let storeURL: URL?
    public var registryURL: URL? = nil
    /// Packages the new version depends on, for Homebrew items only. Homebrew may install or upgrade these too.
    public var dependencies: [String] = []
}

public struct SourceCheck: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let detail: String
    public let succeeded: Bool

    public init(name: String, detail: String, succeeded: Bool) {
        self.name = name
        self.detail = detail
        self.succeeded = succeeded
    }
}

public struct UpdateReport: Sendable {
    public let updates: [AvailableUpdate]
    public let sources: [SourceCheck]
    public let checkedAt: Date
    /// Third-party apps that are neither App Store receipts nor Homebrew cask apps.
    public let notCovered: [String]
}

public enum UpdateChecker {
    public static func check(homebrew: Bool, npm: Bool, appStore: Bool, applications: [InstalledApplication],
                             progress: @Sendable (String) async -> Void = { _ in }) async throws -> UpdateReport {
        var updates: [AvailableUpdate] = []
        var checks: [SourceCheck] = []
        if homebrew {
            let executables = brewExecutables()
            if executables.isEmpty { checks.append(.init(name: "Homebrew", detail: "Not installed in a supported location.", succeeded: false)) }
            for executable in executables {
                try Task.checkCancellation()
                await progress("Refreshing Homebrew’s package list…")
                do {
                    let refresh = try await CommandRunner.run(executable, arguments: ["update"], timeout: 120)
                    guard refresh.status == 0 else { throw CommandError.failed }
                    await progress("Checking Homebrew apps and tools…")
                    let result = try await CommandRunner.run(executable, arguments: ["outdated", "--json=v2", "--greedy"])
                    guard result.status == 0 else { throw CommandError.failed }
                    let found = try parseBrew(result.data, executable: executable)
                    let dependencies = await brewDependencies(for: found, executable: executable)
                    updates += found.map { var update = $0; update.dependencies = dependencies[$0.package] ?? []; return update }
                    checks.append(.init(name: "Homebrew · \(executable.deletingLastPathComponent().path)", detail: "Checked installed formulae and casks, including apps with their own updater. Pinned formulae are excluded.", succeeded: true))
                } catch is CancellationError { throw CancellationError() }
                catch { checks.append(.init(name: "Homebrew · \(executable.path)", detail: error.localizedDescription, succeeded: false)) }
            }
        }
        if npm {
            await ShellEnvironment.refresh()
            let executables = npmExecutables()
            if executables.isEmpty { checks.append(.init(name: "npm", detail: "Not found in supported global or nvm locations.", succeeded: false)) }
            for executable in executables {
                try Task.checkCancellation()
                await progress("Checking global npm tools…")
                do {
                    let registry = try await PackageProvider.npmRegistry(for: .init(manager: .npm, executable: executable))
                    let output = try await CommandRunner.run(executable, arguments: ["outdated", "--global", "--json", "--depth=0"])
                    // npm exits 1 when updates exist. Validate the JSON as well as the exit status.
                    guard [0, 1].contains(output.status) else { throw CommandError.failed }
                    updates += try parseNpm(output.data, executable: executable, registryURL: registry)
                    checks.append(.init(name: "npm · \(executable.deletingLastPathComponent().path)", detail: "Checked top-level global packages against \(registry.absoluteString). Project dependencies are excluded.", succeeded: true))
                } catch is CancellationError { throw CancellationError() }
                catch { checks.append(.init(name: "npm · \(executable.path)", detail: error.localizedDescription, succeeded: false)) }
            }
        }
        if appStore {
            let apps = applications.filter { $0.isAppStore && !$0.isSystem }
            if apps.isEmpty { checks.append(.init(name: "App Store", detail: "No apps with an App Store receipt were found in the application folders checked.", succeeded: true)) }
            for (index, app) in apps.enumerated() {
                try Task.checkCancellation()
                if index > 0 { try await Task.sleep(nanoseconds: 3_100_000_000) }
                await progress("Checking \(app.name) in Apple’s catalog…")
                do {
                    let found = try await checkStore(app)
                    if let found { updates.append(found) }
                    checks.append(.init(name: app.name + " · App Store", detail: found == nil ? "No newer version in the public catalog for this region." : "A newer catalog version is available. Availability for your account is confirmed in the App Store.", succeeded: true))
                } catch is CancellationError { throw CancellationError() }
                catch { checks.append(.init(name: app.name + " · App Store", detail: "Couldn’t match or reach this app in Apple’s catalog. Its update status is unknown.", succeeded: false)) }
            }
        }
        try Task.checkCancellation()
        let caskApps = UninstallPlanner.homebrewAppNames(prefixes: brewExecutables().map { $0.deletingLastPathComponent().deletingLastPathComponent() })
        let notCovered = applications.filter { app in
            !app.isSystem && !app.isAppStore && app.bundleIdentifier != nil && !caskApps.contains(app.url.lastPathComponent)
        }.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return .init(updates: updates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, sources: checks, checkedAt: Date(), notCovered: notCovered)
    }

    public static func brewExecutables() -> [URL] { existing(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) }
    public static func npmExecutables() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm", home.appendingPathComponent(".volta/bin/npm").path, home.appendingPathComponent(".local/bin/npm").path]
        let versions = home.appendingPathComponent(".nvm/versions/node")
        if let children = try? FileManager.default.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil) {
            paths += children.map { $0.appendingPathComponent("bin/npm").path }
        }
        // Any other npm the user's shell puts on PATH (for example a bundled Node in ~/.local/bin).
        paths += ShellEnvironment.path.map { URL(fileURLWithPath: $0).appendingPathComponent("npm").path }
        return existing(paths)
    }
    private static func existing(_ paths: [String]) -> [URL] {
        var seen = Set<String>()
        return paths.compactMap {
            let url = URL(fileURLWithPath: $0)
            guard FileManager.default.isExecutableFile(atPath: $0), seen.insert(url.resolvingSymlinksInPath().path).inserted else { return nil }
            return url
        }
    }

    /// One batched `brew info` per package kind. A failure only drops the dependency hints, never the update list.
    static func brewDependencies(for updates: [AvailableUpdate], executable: URL) async -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (names, flag) in [(updates.filter { !$0.isCask }.map(\.package), "--formula"), (updates.filter(\.isCask).map(\.package), "--cask")] where !names.isEmpty {
            guard let output = try? await CommandRunner.run(executable, arguments: ["info", "--json=v2", flag] + names, timeout: 90, includeErrors: true),
                  output.status == 0 else { continue }
            for (name, deps) in parseBrewDependencies(output.data) { result[name] = deps }
        }
        return result
    }

    static func parseBrewDependencies(_ data: Data) -> [String: [String]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for item in root["formulae"] as? [[String: Any]] ?? [] {
            if let name = item["name"] as? String { result[name] = item["dependencies"] as? [String] ?? [] }
        }
        for item in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = item["token"] as? String else { continue }
            let dependsOn = item["depends_on"] as? [String: Any] ?? [:]
            result[token] = (dependsOn["formula"] as? [String] ?? []) + (dependsOn["cask"] as? [String] ?? [])
        }
        return result
    }

    public static func parseBrew(_ data: Data, executable: URL) throws -> [AvailableUpdate] {
        struct Item: Decodable { let name: String; let installed_versions: [String]; let current_version: String; let pinned: Bool? }
        struct Payload: Decodable { let formulae: [Item]; let casks: [Item] }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return [(payload.formulae, false), (payload.casks, true)].flatMap { items, cask in
            items.filter { $0.pinned != true && safePackage($0.name, npm: false) }.map {
                .init(name: $0.name, package: $0.name, installed: $0.installed_versions.joined(separator: ", "), available: $0.current_version, source: .homebrew, executable: executable, isCask: cask, storeURL: nil)
            }
        }
    }

    public static func parseNpm(_ data: Data, executable: URL, registryURL: URL? = nil) throws -> [AvailableUpdate] {
        struct Item: Decodable { let current: String; let latest: String }
        let payload = try JSONDecoder().decode([String: Item].self, from: data)
        return payload.filter { safePackage($0.key, npm: true) && $0.value.current != $0.value.latest }.map { name, item in
            .init(name: name, package: name, installed: item.current, available: item.latest, source: .npm, executable: executable, isCask: false, storeURL: nil, registryURL: registryURL)
        }
    }

    public static func safePackage(_ name: String, npm: Bool) -> Bool {
        name.range(of: npm ? "^(@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*$" : "^[a-zA-Z0-9][a-zA-Z0-9+_.@/-]*$", options: .regularExpression) != nil && !name.contains("..")
    }

    private static func checkStore(_ app: InstalledApplication) async throws -> AvailableUpdate? {
        guard let identifier = app.bundleIdentifier else { throw CommandError.failed }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [URLQueryItem(name: "term", value: app.name), URLQueryItem(name: "entity", value: "macSoftware"), URLQueryItem(name: "limit", value: "25"), URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else { throw CommandError.failed }
        struct Item: Decodable { let bundleId: String?; let version: String?; let trackId: Int?; let minimumOsVersion: String? }
        struct Payload: Decodable { let results: [Item] }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let item = payload.results.first(where: { $0.bundleId == identifier }), let version = item.version, let id = item.trackId else { throw CommandError.failed }
        guard isNewer(version, than: app.version) else { return nil }
        return .init(name: app.name, package: identifier, installed: app.version, available: version, source: .appStore, executable: nil, isCask: false, storeURL: URL(string: "macappstore://itunes.apple.com/app/id\(id)"))
    }

    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard candidate.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil,
              installed.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil else { return false }
        var left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        var right = installed.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        left += Array(repeating: 0, count: count - left.count)
        right += Array(repeating: 0, count: count - right.count)
        return right.lexicographicallyPrecedes(left)
    }
}
