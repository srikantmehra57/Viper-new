import Foundation

// MARK: - Updates

/// One reviewed package update, run with the package manager's own upgrade command.
public struct PackageUpgrade: Hashable, Sendable {
    public let runtime: PackageRuntime
    public let kind: PackageUninstall.Kind
    public let package: String
    public let fromVersion: String
    public let toVersion: String
    public let registryURL: URL?

    public init?(_ update: AvailableUpdate) {
        guard let executable = update.executable else { return nil }
        switch update.source {
        case .homebrew:
            kind = update.isCask ? .cask : .formula
            runtime = .init(manager: .homebrew, executable: executable)
        case .npm:
            kind = .npm
            runtime = .init(manager: .npm, executable: executable)
            // npm installs the exact reviewed version only.
            guard update.available.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+(-[A-Za-z0-9.-]+)?(\\+[A-Za-z0-9.-]+)?$", options: .regularExpression) != nil else { return nil }
        case .appStore:
            return nil
        }
        guard PackageRequest.isValidName(update.package, manager: runtime.manager) else { return nil }
        package = update.package
        fromVersion = update.installed
        toVersion = update.available
        registryURL = update.registryURL
    }

    public var arguments: [String] {
        switch kind {
        case .formula: return ["upgrade", "--formula", package]
        case .cask: return ["upgrade", "--cask", package]
        case .npm: return ["install", "--global", package + "@" + toVersion]
        }
    }
    public var displayCommand: String { ([runtime.executable.path] + arguments).joined(separator: " ") }

    /// How much the version changes for plain dotted-number versions; nil when the format can't be classified.
    public var versionDelta: String? { Self.versionDelta(from: fromVersion, to: toVersion) }

    public static func versionDelta(from old: String, to new: String) -> String? {
        let digits = "^[0-9]+(\\.[0-9]+)*$"
        guard old.range(of: digits, options: .regularExpression) != nil, new.range(of: digits, options: .regularExpression) != nil else { return nil }
        let a = old.split(separator: "."), b = new.split(separator: ".")
        if a.first != b.first { return "major update — review release notes" }
        if (a.count > 1 ? a[1] : "0") != (b.count > 1 ? b[1] : "0") { return "minor update" }
        return "patch update"
    }
}

extension PackageProvider {
    public enum UpgradeOutcome: Equatable, Sendable {
        case updated(String)
        case alreadyCurrent(String)
        case skipped(String)
        case failed(String)
    }

    /// The installed version as the provider reports it now; nil if it can't be read or isn't installed.
    public static func currentVersion(_ upgrade: PackageUpgrade) async -> String? {
        switch upgrade.kind {
        case .npm:
            guard let output = try? await CommandRunner.run(upgrade.runtime.executable, arguments: ["ls", "--global", "--depth=0", "--json"]),
                  [0, 1].contains(output.status), let packages = try? parseNpmList(output.data) else { return nil }
            return packages[upgrade.package]
        case .formula, .cask:
            guard let output = try? await CommandRunner.run(upgrade.runtime.executable, arguments: ["list", "--versions", upgrade.kind == .cask ? "--cask" : "--formula", upgrade.package]),
                  output.status == 0 else { return nil }
            return parseBrewList(output.data)[upgrade.package]
        }
    }

    /// Rechecks the installed version, runs the upgrade, then verifies the new version.
    public static func upgrade(_ upgrade: PackageUpgrade, progress: ProgressHandler? = nil) async -> (outcome: UpgradeOutcome, log: String) {
        let tracker = ProgressTracker(progress, start: .init(phase: .preparing, detail: "Rechecking the installed and reviewed versions…"))
        guard let before = await currentVersion(upgrade) else {
            return (.skipped("It no longer appears installed, or its package manager couldn’t be read. Check for updates again."), "")
        }
        if before == upgrade.toVersion { return (.alreadyCurrent(before), "") }
        guard versionMatches(before, upgrade.fromVersion) else {
            return (.skipped("Version \(before) is installed now, not \(upgrade.fromVersion). Check for updates again."), "")
        }
        // Re-read the provider's metadata so the reviewed version is still what the provider would install.
        let method: InstallMethod = upgrade.kind == .npm ? .npm : (upgrade.kind == .cask ? .homebrewCask : .homebrewFormula)
        let route = InstallRoute(method: method, package: upgrade.package, url: nil)
        let metadata: PackageMetadata
        do { metadata = try await PackageProvider.metadata(for: route, runtime: upgrade.runtime) } catch {
            return (.skipped("The package manager couldn’t confirm what version it would install. Check for updates again."), "")
        }
        guard metadata.found, let offered = metadata.version else {
            return (.skipped("This package is no longer offered by \(upgrade.runtime.manager.rawValue). Check for updates again."), "")
        }
        guard offered == upgrade.toVersion else {
            return (.skipped("The available version changed to \(offered) since this update was reviewed. Check for updates again."), "")
        }
        guard metadata.registryURL == upgrade.registryURL else {
            return (.skipped("The package registry changed since this update was reviewed. Check for updates again before installing from a different source."), "")
        }
        let output: CommandOutput
        do {
            tracker.set(.init(phase: .preparing, detail: "Starting \(upgrade.runtime.manager.rawValue)…"))
            let watcher = upgrade.kind == .npm ? nil : tracker.watchHomebrewDownloads()
            defer { watcher?.cancel() }
            output = try await CommandRunner.run(upgrade.runtime.executable, arguments: upgrade.arguments, timeout: 3_600, includeErrors: true,
                                                 environment: progressEnvironment, onOutput: { tracker.consume($0) })
        } catch CommandError.timeout {
            return (.failed("The update took more than an hour and was stopped. It may be incomplete; check again before retrying."), "")
        } catch CommandError.unsettled {
            return (.failed("Viper tried to stop the update, but part of it may still be running. Check the package manager before trying again."), "")
        } catch {
            return (.failed("The update couldn’t be confirmed and may be incomplete. Check for updates again."), "")
        }
        let log = logTail(output)
        tracker.verifying()
        let after = await currentVersion(upgrade)
        // Only the exact reviewed version, after a successful command, is an update. Anything else is reported honestly.
        if output.status == 0, let after, after == upgrade.toVersion { return (.updated(after), log) }
        if let after, after == before { return (.failed(failureSummary(log).replacingOccurrences(of: "installation", with: "update")), log) }
        let state = after.map { "version \($0) is installed now" } ?? "the installed version couldn’t be confirmed"
        return (.failed("The update didn’t reach the reviewed version: \(state). Check for updates again before retrying."), log)
    }

    /// Homebrew may list several installed versions for one package.
    static func versionMatches(_ current: String, _ reviewed: String) -> Bool {
        current == reviewed || reviewed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(current)
    }
}

// MARK: - Reviewed changes

/// Decides whether a waiting install or update is still allowed to start.
public enum ReviewedChangePolicy {
    public static func waitingWorkBlocked(changesAllowed: Bool, journalNeedsReview: Bool) -> String? {
        if journalNeedsReview {
            return "A journal needs review, so Viper will not start anything else that changes your Mac."
        }
        if !changesAllowed {
            return "Reviewed changes are off, so Viper will not start anything else that changes your Mac."
        }
        return nil
    }
}

// MARK: - Privacy

/// Resets an app's privacy decisions with Apple's tccutil, so macOS asks again next time the app needs access.
public enum PermissionReset {
    public static let tool = URL(fileURLWithPath: "/usr/bin/tccutil")

    public static func arguments(bundleIdentifier: String) -> [String]? {
        guard bundleIdentifier.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9_-]+)+$", options: .regularExpression) != nil else { return nil }
        return ["reset", "All", bundleIdentifier]
    }

    public static func reset(bundleIdentifier: String) async -> Result<Void, CommandError> {
        guard let arguments = arguments(bundleIdentifier: bundleIdentifier), FileManager.default.isExecutableFile(atPath: tool.path) else { return .failure(.failed) }
        guard let output = try? await CommandRunner.run(tool, arguments: arguments, timeout: 30, includeErrors: true), output.status == 0 else { return .failure(.failed) }
        return .success(())
    }
}
