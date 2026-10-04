import Foundation

public enum CommandLineSource: String, Codable, Sendable { case homebrewFormula = "Homebrew formula", homebrewCask = "Homebrew cask", npm = "npm global package" }

/// A package-manager installed tool. Casks that install an app bundle are already covered by AppInventory.
public struct CommandLinePackage: Identifiable, Hashable, Sendable {
    public var id: String { source.rawValue + ":" + runtime.id + ":" + package }
    public let name: String
    /// The package manager's identifier, which can differ from the display name for casks.
    public let package: String
    public let version: String
    public let summary: String?
    public let source: CommandLineSource
    public let runtime: PackageRuntime
    public let commands: [String]
    public let location: URL?
    /// Homebrew installed it only to satisfy another formula.
    public let isDependency: Bool
    /// Ships with the Node.js runtime rather than being installed separately.
    public let isBundledWithRuntime: Bool

    public var sourceLabel: String { "\(source.rawValue) · \(runtime.location)" }

    /// Shown to the user as guidance only; Viper does not run it.
    public var manualRemovalCommand: String {
        switch source {
        case .homebrewFormula: return "\(runtime.executable.path) uninstall --formula \(package)"
        case .homebrewCask: return "\(runtime.executable.path) uninstall --cask \(package)"
        case .npm: return "\(runtime.executable.path) uninstall --global \(package)"
        }
    }
}

public struct CommandLineInventoryResult: Sendable {
    public let packages: [CommandLinePackage]
    public let checks: [SourceCheck]
}

public enum CommandLineInventory {
    static let bundledNpmPackages: Set<String> = ["npm", "corepack"]

    /// Pass nil to detect runtimes. npm detection needs the shell PATH (e.g. an npm in ~/.local/bin), so it is read first.
    public static func read(homebrew: [PackageRuntime]? = nil, npm: [PackageRuntime]? = nil) async throws -> CommandLineInventoryResult {
        if npm == nil { await ShellEnvironment.refresh() }
        let homebrew = homebrew ?? PackageRuntime.detect(.homebrew)
        let npm = npm ?? PackageRuntime.detect(.npm)
        var packages: [CommandLinePackage] = []
        var checks: [SourceCheck] = []
        if homebrew.isEmpty { checks.append(.init(name: "Homebrew", detail: "Not installed in a supported location.", succeeded: true)) }
        for runtime in homebrew {
            try Task.checkCancellation()
            do {
                let output = try await CommandRunner.run(runtime.executable, arguments: ["info", "--json=v2", "--installed"], timeout: 90)
                guard output.status == 0 else { throw CommandError.failed }
                packages += try parseBrewInstalled(output.data, runtime: runtime)
                checks.append(.init(name: runtime.label, detail: "Read installed formulae and casks without an app bundle.", succeeded: true))
            } catch is CancellationError { throw CancellationError() }
            catch { checks.append(.init(name: runtime.label, detail: "Installed formulae couldn’t be read, so they aren’t listed.", succeeded: false)) }
        }
        if npm.isEmpty { checks.append(.init(name: "npm", detail: "Not found in supported global, Volta, or nvm locations.", succeeded: true)) }
        for runtime in npm {
            try Task.checkCancellation()
            do {
                let output = try await CommandRunner.run(runtime.executable, arguments: ["ls", "--global", "--depth=0", "--json", "--long"])
                // npm exits 1 for some tree problems while still printing valid JSON.
                guard [0, 1].contains(output.status) else { throw CommandError.failed }
                packages += try parseNpmInstalled(output.data, runtime: runtime)
                checks.append(.init(name: runtime.label, detail: "Read top-level global packages in this runtime. Project dependencies are excluded.", succeeded: true))
            } catch is CancellationError { throw CancellationError() }
            catch { checks.append(.init(name: runtime.label, detail: "Global packages couldn’t be read, so they aren’t listed.", succeeded: false)) }
        }
        return .init(packages: packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, checks: checks)
    }

    public static func parseBrewInstalled(_ data: Data, runtime: PackageRuntime, fileManager: FileManager = .default) throws -> [CommandLinePackage] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CommandError.failed }
        let prefix = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        var result: [CommandLinePackage] = []
        for item in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = item["name"] as? String, PackageRequest.isValidName(name, manager: .homebrew),
                  let installed = (item["installed"] as? [[String: Any]])?.last else { continue }
            let keg = prefix.appendingPathComponent("opt").appendingPathComponent(name)
            result.append(.init(name: name, package: name, version: installed["version"] as? String ?? "Unknown", summary: item["desc"] as? String, source: .homebrewFormula,
                                runtime: runtime, commands: executables(in: keg.appendingPathComponent("bin"), fileManager: fileManager),
                                location: fileManager.fileExists(atPath: keg.path) ? keg : nil,
                                isDependency: installed["installed_on_request"] as? Bool == false, isBundledWithRuntime: false))
        }
        for item in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = item["token"] as? String, PackageRequest.isValidName(token, manager: .homebrew) else { continue }
            let artifacts = item["artifacts"] as? [[String: Any]] ?? []
            // App-bundle casks already appear as applications.
            guard !artifacts.contains(where: { $0["app"] != nil }) else { continue }
            let binaries = artifacts.flatMap { $0["binary"] as? [Any] ?? [] }.compactMap { value -> String? in
                guard let path = value as? String else { return nil }
                return URL(fileURLWithPath: path).lastPathComponent
            }
            let name = (item["name"] as? [String])?.first ?? token
            result.append(.init(name: name, package: token, version: item["installed"] as? String ?? "Unknown", summary: item["desc"] as? String, source: .homebrewCask,
                                runtime: runtime, commands: binaries, location: nil, isDependency: false, isBundledWithRuntime: false))
        }
        return result
    }

    public static func parseNpmInstalled(_ data: Data, runtime: PackageRuntime) throws -> [CommandLinePackage] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else { throw CommandError.failed }
        let dependencies = root["dependencies"] as? [String: [String: Any]] ?? [:]
        return dependencies.compactMap { name, item in
            guard PackageRequest.isValidName(name, manager: .npm) else { return nil }
            let commands: [String]
            switch item["bin"] {
            case let map as [String: Any]: commands = map.keys.sorted()
            case is String: commands = [String(name.split(separator: "/").last ?? Substring(name))]
            default: commands = []
            }
            return .init(name: name, package: name, version: item["version"] as? String ?? "Unknown", summary: item["description"] as? String, source: .npm, runtime: runtime,
                         commands: commands, location: (item["path"] as? String).map { URL(fileURLWithPath: $0) },
                         isDependency: false, isBundledWithRuntime: bundledNpmPackages.contains(name))
        }
    }

    private static func executables(in folder: URL, fileManager: FileManager) -> [String] {
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }
}
