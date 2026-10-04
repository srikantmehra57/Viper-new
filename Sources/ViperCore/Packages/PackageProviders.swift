import Foundation
import Darwin

public enum PackageManager: String, Codable, Sendable { case homebrew = "Homebrew", npm = "npm" }

public struct PackageRuntime: Identifiable, Hashable, Codable, Sendable {
    public var id: String { executable.path }
    public let manager: PackageManager
    public let executable: URL
    public var location: String { executable.deletingLastPathComponent().path }
    public var label: String { "\(manager.rawValue) · \(location)" }

    public init(manager: PackageManager, executable: URL) {
        self.manager = manager
        self.executable = executable
    }

    // Update checks live in UpdateChecker; upgrades in Maintenance.swift.
    public static func detect(_ manager: PackageManager) -> [PackageRuntime] {
        (manager == .homebrew ? UpdateChecker.brewExecutables() : UpdateChecker.npmExecutables()).map { .init(manager: manager, executable: $0) }
    }

    /// Only Homebrew's native prefix for this hardware is used for installs. Other prefixes are reported, never chosen silently.
    public static func preferredHomebrew(_ runtimes: [PackageRuntime], appleSilicon: Bool) -> PackageRuntime? {
        runtimes.first { $0.location == (appleSilicon ? "/opt/homebrew/bin" : "/usr/local/bin") }
    }
}

public struct SystemProfile: Sendable, Equatable {
    public let macOSVersion: String
    public let appleSilicon: Bool

    public init(macOSVersion: String, appleSilicon: Bool) {
        self.macOSVersion = macOSVersion
        self.appleSilicon = appleSilicon
    }

    public static func current() -> Self {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        // Reports the hardware, including when Viper itself runs under Rosetta.
        let arm = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
        return .init(macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)", appleSilicon: arm)
    }
}

public struct PackageRequest: Hashable, Codable, Sendable {
    public let method: InstallMethod
    public let package: String
    public let runtime: PackageRuntime

    public init?(method: InstallMethod, package: String, runtime: PackageRuntime) {
        let manager: PackageManager = method == .npm ? .npm : .homebrew
        guard method.isDirect, runtime.manager == manager, Self.isValidName(package, manager: manager) else { return nil }
        self.method = method
        self.package = package
        self.runtime = runtime
    }

    /// Exact reviewed names only: no taps, registries, URLs, paths, flags, or version ranges.
    public static func isValidName(_ name: String, manager: PackageManager) -> Bool {
        guard UpdateChecker.safePackage(name, npm: manager == .npm), name.count <= 214 else { return false }
        return manager == .npm || name.range(of: "^[a-z0-9][a-z0-9+_.@-]*$", options: .regularExpression) != nil
    }

    public var installArguments: [String] {
        switch method {
        case .homebrewCask: return ["install", "--cask", package]
        case .homebrewFormula: return ["install", "--formula", package]
        default: return ["install", "--global", package]
        }
    }
}

public struct PackageMetadata: Codable, Hashable, Sendable {
    public let key: String
    public let found: Bool
    public let canonicalName: String?
    public let version: String?
    public let minimumMacOS: String?
    public let appleSiliconOnly: Bool
    public let appNames: [String]
    public let requiresAdministrator: Bool
    public let deprecated: Bool
    public let disabled: Bool
    public let dependencies: [String]
    public let nodeRequirement: String?
    public let runsInstallScripts: Bool
    public let checkedAt: Date
    /// Exact npm registry origin used for this metadata review. Nil for non-npm providers.
    public var registryURL: URL? = nil

    static func missing(_ key: String, at date: Date = Date()) -> Self {
        .init(key: key, found: false, canonicalName: nil, version: nil, minimumMacOS: nil, appleSiliconOnly: false, appNames: [], requiresAdministrator: false, deprecated: false, disabled: false, dependencies: [], nodeRequirement: nil, runsInstallScripts: false, checkedAt: date)
    }
}

public struct InstalledPackages: Sendable {
    /// Keyed by runtime executable path, then package name, with the installed version.
    public var casks: [String: [String: String]] = [:]
    public var formulae: [String: [String: String]] = [:]
    public var npm: [String: [String: String]] = [:]
    public init() {}
}

public enum PackageProvider {
    // MARK: Inventory

    public static func installedPackages(homebrew: [PackageRuntime], npm: [PackageRuntime]) async throws -> (InstalledPackages, [SourceCheck]) {
        var packages = InstalledPackages()
        var checks: [SourceCheck] = []
        for runtime in homebrew {
            try Task.checkCancellation()
            do {
                let casks = try await CommandRunner.run(runtime.executable, arguments: ["list", "--versions", "--cask"])
                let formulae = try await CommandRunner.run(runtime.executable, arguments: ["list", "--versions", "--formula"])
                guard casks.status == 0, formulae.status == 0 else { throw CommandError.failed }
                packages.casks[runtime.id] = parseBrewList(casks.data)
                packages.formulae[runtime.id] = parseBrewList(formulae.data)
                checks.append(.init(name: runtime.label, detail: "Read installed casks and formulae.", succeeded: true))
            } catch is CancellationError { throw CancellationError() }
            catch { checks.append(.init(name: runtime.label, detail: "Installed packages couldn’t be read. Their install status is unknown.", succeeded: false)) }
        }
        for runtime in npm {
            try Task.checkCancellation()
            do {
                let output = try await CommandRunner.run(runtime.executable, arguments: ["ls", "--global", "--depth=0", "--json"])
                // npm exits 1 for some tree problems while still printing valid JSON.
                guard [0, 1].contains(output.status) else { throw CommandError.failed }
                packages.npm[runtime.id] = try parseNpmList(output.data)
                checks.append(.init(name: runtime.label, detail: "Read top-level global packages in this runtime.", succeeded: true))
            } catch is CancellationError { throw CancellationError() }
            catch { checks.append(.init(name: runtime.label, detail: "Global packages couldn’t be read. Their install status is unknown.", succeeded: false)) }
        }
        return (packages, checks)
    }

    public static func parseBrewList(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            guard let name = parts.first, PackageRequest.isValidName(String(name), manager: .homebrew) else { continue }
            result[String(name)] = parts.dropFirst().last.map(String.init) ?? ""
        }
        return result
    }

    public static func parseNpmList(_ data: Data) throws -> [String: String] {
        struct Item: Decodable { let version: String? }
        struct Payload: Decodable { let dependencies: [String: Item]? }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] == nil,
              (object["problems"] as? [String] ?? []).isEmpty else { throw CommandError.failed }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return (payload.dependencies ?? [:]).reduce(into: [:]) { result, item in
            if PackageRequest.isValidName(item.key, manager: .npm) { result[item.key] = item.value.version ?? "" }
        }
    }

    // MARK: Verification

    /// Reads the provider's current metadata for one reviewed mapping. Contacts the network only when the provider needs to.
    public static func metadata(for route: InstallRoute, runtime: PackageRuntime) async throws -> PackageMetadata {
        guard let package = route.package, let request = PackageRequest(method: route.method, package: package, runtime: runtime) else { throw CommandError.failed }
        let key = route.method.rawValue + ":" + package
        switch route.method {
        case .npm:
            let registry = try await npmRegistry(for: runtime)
            let output = try await CommandRunner.run(runtime.executable, arguments: ["view", request.package, "name", "version", "engines", "scripts", "--json"], timeout: 45)
            return try parseNpmView(output.data, key: key, registryURL: registry)
        default:
            let output = try await CommandRunner.run(runtime.executable, arguments: ["info", "--json=v2", route.method == .homebrewCask ? "--cask" : "--formula", request.package], timeout: 90, includeErrors: true)
            guard output.status == 0 else {
                let message = String(decoding: output.errors, as: UTF8.self)
                if message.contains("No Cask with this name exists") || message.contains("No available formula") { return .missing(key) }
                throw CommandError.failed
            }
            return try parseBrewInfo(output.data, key: key, cask: route.method == .homebrewCask)
        }
    }

    public static func parseBrewInfo(_ data: Data, key: String, cask: Bool, checkedAt: Date = Date()) throws -> PackageMetadata {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = (root[cask ? "casks" : "formulae"] as? [[String: Any]])?.first else { throw CommandError.failed }
        let name = (cask ? item["token"] : item["name"]) as? String
        let version = cask ? item["version"] as? String : (item["versions"] as? [String: Any])?["stable"] as? String
        var minimum: String?
        var arm = false
        var dependencies: [String] = []
        var admin = false
        var apps: [String] = []
        if cask {
            let dependsOn = item["depends_on"] as? [String: Any] ?? [:]
            if let macos = dependsOn["macos"] as? [String: Any], let values = macos[">="] as? [String] {
                minimum = values.first { $0.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil }
            }
            if let archs = dependsOn["arch"] as? [[String: Any]] {
                arm = !archs.isEmpty && archs.allSatisfy { $0["type"] as? String == "arm" }
            }
            dependencies = (dependsOn["formula"] as? [String] ?? []) + (dependsOn["cask"] as? [String] ?? [])
            for artifact in item["artifacts"] as? [[String: Any]] ?? [] {
                // Installer packages run with administrator rights and can't be completed without a password prompt.
                if artifact["pkg"] != nil || artifact["installer"] != nil { admin = true }
                for value in artifact["app"] as? [Any] ?? [] {
                    if let app = value as? String, app.hasSuffix(".app"), !app.contains("/") { apps.append(app) }
                }
            }
        } else {
            dependencies = item["dependencies"] as? [String] ?? []
        }
        return .init(key: key, found: true, canonicalName: name, version: version, minimumMacOS: minimum, appleSiliconOnly: arm, appNames: apps,
                     requiresAdministrator: admin, deprecated: item["deprecated"] as? Bool ?? false, disabled: item["disabled"] as? Bool ?? false,
                     dependencies: dependencies, nodeRequirement: nil, runsInstallScripts: false, checkedAt: checkedAt)
    }

    public static func parseNpmView(_ data: Data, key: String, checkedAt: Date = Date(), registryURL: URL? = nil) throws -> PackageMetadata {
        struct NpmError: Decodable { let code: String? }
        struct Payload: Decodable {
            let name: String?; let version: String?; let engines: [String: String]?
            let scripts: [String: String]?; let error: NpmError?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        if let error = payload.error {
            guard error.code == "E404" else { throw CommandError.failed }
            return .missing(key, at: checkedAt)
        }
        guard payload.name != nil, payload.version != nil else { throw CommandError.failed }
        let scripts = Set((payload.scripts ?? [:]).keys)
        return PackageMetadata(key: key, found: true, canonicalName: payload.name, version: payload.version, minimumMacOS: nil, appleSiliconOnly: false, appNames: [],
                     requiresAdministrator: false, deprecated: false, disabled: false, dependencies: [], nodeRequirement: payload.engines?["node"],
                     runsInstallScripts: !scripts.isDisjoint(with: ["preinstall", "install", "postinstall"]), checkedAt: checkedAt, registryURL: registryURL)
    }

    /// Reads and validates the registry npm will actually contact. Credentials and insecure remote origins are rejected.
    public static func npmRegistry(for runtime: PackageRuntime) async throws -> URL {
        guard runtime.manager == .npm else { throw CommandError.failed }
        let output = try await CommandRunner.run(runtime.executable, arguments: ["config", "get", "registry"], timeout: 20)
        let value = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.status == 0, value.count <= 2_048, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw CommandError.failed
        }
        return url
    }

    public static func nodeVersion(for runtime: PackageRuntime) async -> String? {
        let node = runtime.executable.deletingLastPathComponent().appendingPathComponent("node")
        guard FileManager.default.isExecutableFile(atPath: node.path),
              let output = try? await CommandRunner.run(node, arguments: ["--version"], timeout: 15), output.status == 0 else { return nil }
        let version = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    // MARK: Installation

    public enum InstallOutcome: Equatable, Sendable {
        case installed(version: String)
        case failed(String)
        case needsAttention(String)
    }

    /// Runs one serialized install and verifies the result with the provider's own inventory.
    /// The active process is not cancelled here: stopping a package manager mid-transaction can leave partial state.
    public static func install(_ request: PackageRequest, reviewedVersion: String, progress: ProgressHandler? = nil) async -> (outcome: InstallOutcome, log: String) {
        let output: CommandOutput
        let tracker = ProgressTracker(progress)
        do {
            let arguments = try installArguments(request, reviewedVersion: reviewedVersion)
            let watcher = request.method == .npm ? nil : tracker.watchHomebrewDownloads()
            defer { watcher?.cancel() }
            output = try await CommandRunner.run(request.runtime.executable, arguments: arguments, timeout: 3_600, includeErrors: true,
                                                 environment: progressEnvironment, onOutput: { tracker.consume($0) })
        } catch CommandError.timeout {
            return (.needsAttention("The installation took more than an hour and was stopped. It may be incomplete; check its status before retrying."), "")
        } catch CommandError.unsettled {
            return (.needsAttention("Viper tried to stop the installation, but part of it may still be running. Check Homebrew or npm before retrying."), "")
        } catch {
            return (.needsAttention("The installation could not be confirmed. It may have started or left partial changes; check its state before retrying."), error.localizedDescription)
        }
        let log = logTail(output)
        tracker.verifying()
        let version = await installedVersion(request)
        if output.status == 0 {
            if let version { return (.installed(version: version), log) }
            return (.needsAttention("The package manager reported success, but Viper couldn’t confirm the installation. Check again before retrying."), log)
        }
        if let version { return (.needsAttention("The package manager reported a problem, but version \(version) now appears installed. Review the details."), log) }
        return (.failed(failureSummary(log)), log)
    }

    /// npm only reports downloads at the http log level; this affects output detail, not what is installed.
    static let progressEnvironment = ["npm_config_loglevel": "http", "npm_config_progress": "false"]

    public static func installArguments(_ request: PackageRequest, reviewedVersion: String) throws -> [String] {
        if request.method == .npm {
            guard reviewedVersion.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+(-[A-Za-z0-9.-]+)?(\\+[A-Za-z0-9.-]+)?$", options: .regularExpression) != nil else { throw CommandError.failed }
            return ["install", "--global", request.package + "@" + reviewedVersion]
        }
        return request.installArguments
    }

    public static func installedVersion(_ request: PackageRequest) async -> String? {
        switch request.method {
        case .npm:
            guard let output = try? await CommandRunner.run(request.runtime.executable, arguments: ["ls", "--global", "--depth=0", "--json"]),
                  let packages = try? parseNpmList(output.data) else { return nil }
            return packages[request.package]
        default:
            guard let output = try? await CommandRunner.run(request.runtime.executable, arguments: ["list", "--versions", request.method == .homebrewCask ? "--cask" : "--formula", request.package]),
                  output.status == 0 else { return nil }
            return parseBrewList(output.data)[request.package]
        }
    }

    // MARK: Removal

    public enum UninstallOutcome: Equatable, Sendable {
        case removed
        case failed(String)
    }

    /// Runs the package manager's own uninstall without force flags, then confirms with its inventory.
    public static func uninstall(_ request: PackageUninstall) async -> UninstallOutcome {
        let output: CommandOutput
        do {
            output = try await CommandRunner.run(request.runtime.executable, arguments: request.arguments, timeout: 1_800, includeErrors: true)
        } catch CommandError.unsettled {
            return .failed("Viper tried to stop the uninstall, but part of it may still be running. Refresh the list and check the package manager before trying again.")
        } catch {
            return .failed("The uninstall couldn’t be confirmed and may be incomplete. Refresh the list to check its state.")
        }
        let stillInstalled = await isInstalled(request)
        // A failed uninstall command, or an inventory that can't be read, is never evidence of removal.
        if output.status == 0, stillInstalled == false { return .removed }
        return .failed(uninstallFailureSummary(logTail(output), status: output.status, unknown: stillInstalled == nil))
    }

    /// nil when the provider's inventory can't be read. A failed read must not be read as “not installed”.
    static func isInstalled(_ request: PackageUninstall) async -> Bool? {
        switch request.kind {
        case .npm:
            guard let output = try? await CommandRunner.run(request.runtime.executable, arguments: ["ls", "--global", "--depth=0", "--json"]),
                  [0, 1].contains(output.status), let packages = try? parseNpmList(output.data) else { return nil }
            return packages[request.package] != nil
        case .formula, .cask:
            guard let output = try? await CommandRunner.run(request.runtime.executable, arguments: ["list", "--versions", request.kind == .cask ? "--cask" : "--formula"], includeErrors: true),
                  output.status == 0 else { return nil }
            if parseBrewList(output.data)[request.package] == nil {
                // Homebrew's definitive answer that nothing is installed under this name.
                return false
            }
            return true
        }
    }

    public static func uninstallFailureSummary(_ log: String, status: Int32, unknown: Bool) -> String {
        let text = log.lowercased()
        if text.contains("because it is required by") || text.contains("refusing to uninstall") { return "Other Homebrew packages still need this. Viper doesn’t force removal; remove those first." }
        if text.contains("eacces") || text.contains("permission denied") { return "The package manager couldn’t write to its install location. Viper won’t change folder permissions for you." }
        if text.contains("sudo") || text.contains("password") { return "This uninstall asked for an administrator password, which Viper can’t provide." }
        if unknown { return "The package manager finished, but Viper couldn’t confirm the result. Refresh the list to check." }
        return status == 0 ? "The package manager reported success, but the package still appears installed." : "The uninstall didn’t complete. The package is still installed."
    }

    public static func failureSummary(_ log: String) -> String {
        let text = log.lowercased()
        if text.contains("already an app at") { return "An app with the same name already exists. Viper didn’t replace or adopt it." }
        if text.contains("eacces") || text.contains("permission denied") { return "The package manager couldn’t write to its install location. Viper won’t change folder permissions for you." }
        if text.contains("sudo") || text.contains("password") { return "This installer asked for an administrator password, which Viper can’t provide. Use the publisher’s installer instead." }
        if text.contains("could not resolve host") || text.contains("enotfound") || text.contains("curl: (") || text.contains("etimedout") { return "The download didn’t complete. Check your connection and try again." }
        if text.contains("requires macos") || text.contains("unsupported") { return "The package manager reports that this Mac isn’t supported." }
        return "The installation didn’t complete. See details for the package manager’s output."
    }

    static func logTail(_ output: CommandOutput) -> String {
        let text = String(decoding: output.data, as: UTF8.self) + String(decoding: output.errors, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).suffix(40)
        return lines.joined(separator: "\n")
    }
}
