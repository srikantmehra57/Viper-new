import AppKit
import SwiftUI
import ViperCore

enum InstallState: Equatable {
    case queued, installing, cancelled
    case installed(String)
    case failed(String)
    case needsAttention(String)

    var isFinished: Bool { self != .queued && self != .installing }
    var label: String {
        switch self {
        case .queued: return "WAITING"
        case .installing: return "INSTALLING"
        case .cancelled: return "CANCELLED"
        case .installed: return "INSTALLED"
        case .failed: return "FAILED"
        case .needsAttention: return "NEEDS ATTENTION"
        }
    }
}

struct InstallQueueItem: Identifiable {
    let id = UUID()
    let entry: CatalogEntry
    let request: PackageRequest
    let reviewedVersion: String?
    let reviewedRegistry: URL?
    var state: InstallState = .queued
    var log = ""
    var progress: OperationProgress?
    var startedAt: Date?
}

struct InstallReview: Identifiable {
    let id = UUID()
    let entryIDs: [String]
    var items: [InstallPlanItem]?
    var progress = "Checking what’s already installed…"
    var installable: [InstallPlanItem] {
        (items ?? []).filter { if case .install = $0.decision { return true } else { return false } }
    }
}

extension AppModel {
    private static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Viper")
    }
    private static var journalURL: URL { supportFolder.appendingPathComponent("install-journal.json") }
    private static var metadataURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Viper/catalog-metadata.json")
    }

    var npmRuntime: PackageRuntime? {
        guard let environment = installEnvironment else { return nil }
        // Default to the npm Terminal uses, so installed tools work where the user runs them.
        return environment.npm.first { $0.id == npmRuntimeID } ?? environment.npm.first { $0.isTerminalDefault == true } ?? environment.npm.first
    }

    /// Loads the catalog on demand. Nothing here contacts the network.
    func loadDiscover() {
        if catalog == nil {
            do {
                catalog = try Catalog.builtIn()
                catalogMetadata = CatalogMetadataCache.load(from: Self.metadataURL)
                installJournal = InstallJournal.load(from: Self.journalURL)
            } catch {
                catalogMessage = error.localizedDescription
                return
            }
        }
        if installEnvironment == nil { detectInstallations() }
    }

    /// Cached availability older than a day is shown as stale. Adding stays allowed: review always re-fetches, and only that fresh metadata can authorise an install.
    func catalogAvailabilityIsStale(_ entry: CatalogEntry) -> Bool {
        guard entry.install.method.isDirect, let key = entry.metadataKey, let checked = catalogMetadata.items[key]?.checkedAt else { return false }
        return Date().timeIntervalSince(checked) > 86_400
    }

    func status(for entry: CatalogEntry) -> CatalogStatus? {
        guard let environment = installEnvironment else { return nil }
        return InstallPlanner.status(for: entry, in: environment, metadata: entry.metadataKey.flatMap { catalogMetadata.items[$0] }, npmRuntime: npmRuntime)
    }

    func queueItem(for entry: CatalogEntry) -> InstallQueueItem? { installQueue.last { $0.entry.id == entry.id } }

    func installedAppURL(for entry: CatalogEntry) -> URL? {
        guard let environment = installEnvironment else { return nil }
        return InstallPlanner.matchingApplications(entry, environment: environment, metadata: entry.metadataKey.flatMap { catalogMetadata.items[$0] }).first?.url
    }

    // MARK: Detection

    /// Checks what's installed, then asks Homebrew and npm for current availability. Never installs anything.
    func refreshDiscover() {
        detectInstallations(thenCheckAvailability: true)
    }

    func detectInstallations(thenCheckAvailability: Bool = false) {
        guard !detectingInstalls, !installing, !maintenanceBusy, !checkingUpdates, !refreshingCatalog, reviewTask == nil, let catalog else { return }
        detectingInstalls = true
        catalogMessage = nil
        let task = Task.detached(priority: .utility) { try await Self.detectEnvironment(catalog: catalog) }
        detectionTask = task
        Task {
            do {
                let (environment, inventory) = try await task.value
                installEnvironment = environment
                self.inventory = inventory
                if let id = npmRuntimeID, !environment.npm.contains(where: { $0.id == id }) { npmRuntimeID = nil }
                installSelection.removeAll { id in catalog.entry(id).flatMap { status(for: $0) }?.isSelectable != true }
                detectingInstalls = false
                detectionTask = nil
                if thenCheckAvailability, !environment.homebrew.isEmpty || !environment.npm.isEmpty { refreshCatalogMetadata() }
                return
            } catch is CancellationError {
                catalogMessage = "Check cancelled. Install status may be out of date."
            } catch {
                catalogMessage = "Viper couldn’t check what’s installed. Try again."
            }
            detectingInstalls = false
            detectionTask = nil
        }
    }

    nonisolated private static func detectEnvironment(catalog: Catalog) async throws -> (InstallEnvironment, AppInventoryResult) {
        await ShellEnvironment.refresh()
        let homebrew = PackageRuntime.detect(.homebrew)
        let npm = PackageRuntime.detect(.npm)
        let inventory = try AppInventory.read()
        let (packages, found) = try await PackageProvider.installedPackages(homebrew: homebrew, npm: npm)
        var checks = found
        var nodes: [String: String] = [:]
        for runtime in npm {
            try Task.checkCancellation()
            if let version = await PackageProvider.nodeVersion(for: runtime) { nodes[runtime.id] = version }
        }
        let names = Set(catalog.apps.flatMap { $0.commands ?? [] })
        let commands = InstallEnvironment.findCommands(names, in: InstallEnvironment.commandFolders(npm: npm))
        if homebrew.isEmpty { checks.append(.init(name: "Homebrew", detail: "Not installed in a supported location.", succeeded: false)) }
        if npm.isEmpty { checks.append(.init(name: "npm", detail: "Not found in supported global, Volta, or nvm locations.", succeeded: false)) }
        checks.append(.init(name: "Application folders", detail: inventory.unavailableFolders.isEmpty ? "Checked \(inventory.searchedFolders.joined(separator: ", "))." : "Some folders couldn’t be read, so some installed apps may not be recognised.", succeeded: inventory.unavailableFolders.isEmpty))
        return (InstallEnvironment(system: SystemProfile.current(), homebrew: homebrew, npm: npm, packages: packages, applications: inventory.applications,
                                   commands: commands, nodeVersions: nodes, checks: checks), inventory)
    }

    // MARK: Availability

    /// Asks Homebrew and npm for current metadata. Runs only when the user requests it.
    func refreshCatalogMetadata() {
        guard !refreshingCatalog, !installing, !maintenanceBusy, !checkingUpdates, !detectingInstalls, reviewTask == nil, let catalog, let environment = installEnvironment else { return }
        let npm = npmRuntime
        let routes: [(CatalogEntry, PackageRuntime)] = catalog.apps.compactMap { entry in
            guard entry.install.method.isDirect, let runtime = entry.install.method == .npm ? npm : environment.preferredHomebrew else { return nil }
            return (entry, runtime)
        }
        guard !routes.isEmpty else {
            notice = "Set up Homebrew or npm first. Availability is checked with the package manager that would install each app."
            return
        }
        refreshingCatalog = true
        catalogProgress = "Checking \(routes.count) packages…"
        catalogRefreshTask = Task {
            let (found, failures) = await verify(routes)
            if !Task.isCancelled {
                catalogMetadata.items.merge(found) { _, new in new }
                catalogMetadata.refreshedAt = Date()
                try? catalogMetadata.save(to: Self.metadataURL)
                if failures > 0 { notice = "\(failures) package\(failures == 1 ? "" : "s") couldn’t be checked. Check your connection and try again; their availability is unknown." }
            }
            refreshingCatalog = false
            catalogRefreshTask = nil
        }
    }

    func cancelCatalogRefresh() {
        detectionTask?.cancel()
        catalogRefreshTask?.cancel()
    }

    /// Bounded, read-only metadata lookups. Results arrive incrementally in the progress text.
    private func verify(_ routes: [(CatalogEntry, PackageRuntime)]) async -> ([String: PackageMetadata], Int) {
        var found: [String: PackageMetadata] = [:]
        var failures = 0
        await withTaskGroup(of: (String?, PackageMetadata?).self) { group in
            var pending = routes[...]
            func addNext() {
                guard let (entry, runtime) = pending.popFirst() else { return }
                group.addTask(priority: .utility) {
                    (entry.metadataKey, try? await PackageProvider.metadata(for: entry.install, runtime: runtime))
                }
            }
            for _ in 0..<4 { addNext() }
            var completed = 0
            while let (key, metadata) = await group.next() {
                completed += 1
                if let key, let metadata { found[key] = metadata } else { failures += 1 }
                catalogProgress = "Checked \(completed) of \(routes.count) packages…"
                if Task.isCancelled { group.cancelAll(); break }
                addNext()
            }
        }
        return (found, failures)
    }

    // MARK: Selection and review

    func toggleSelection(_ entry: CatalogEntry) {
        if let index = installSelection.firstIndex(of: entry.id) { installSelection.remove(at: index) }
        else if status(for: entry)?.isSelectable == true { installSelection.append(entry.id) }
    }

    func addCollection(_ collection: StarterCollection) {
        guard let catalog else { return }
        for id in collection.apps where !installSelection.contains(id) {
            if let entry = catalog.entry(id), status(for: entry)?.isSelectable == true { installSelection.append(id) }
        }
    }

    /// Revalidates installed state and package metadata immediately before showing the exact plan.
    func reviewInstall(_ ids: [String]? = nil) {
        guard reviewTask == nil, !installing, !maintenanceBusy, !checkingUpdates, !refreshingCatalog, !detectingInstalls, let catalog else { return }
        let entryIDs = ids ?? installSelection
        let entries = entryIDs.compactMap(catalog.entry)
        guard !entries.isEmpty else { return }
        installReview = InstallReview(entryIDs: entryIDs)
        reviewTask = Task {
            do {
                let detection = Task.detached(priority: .utility) { try await Self.detectEnvironment(catalog: catalog) }
                let (environment, inventory) = try await withTaskCancellationHandler { try await detection.value } onCancel: { detection.cancel() }
                installEnvironment = environment
                self.inventory = inventory
                let npm = npmRuntime
                let routes: [(CatalogEntry, PackageRuntime)] = entries.compactMap { entry in
                    guard entry.install.method.isDirect, let runtime = entry.install.method == .npm ? npm : environment.preferredHomebrew else { return nil }
                    return (entry, runtime)
                }
                installReview?.progress = "Checking \(routes.count) package\(routes.count == 1 ? "" : "s") with Homebrew and npm…"
                let (found, _) = await verify(routes)
                try Task.checkCancellation()
                catalogMetadata.items.merge(found) { _, new in new }
                try? catalogMetadata.save(to: Self.metadataURL)
                // Only metadata fetched during this review can authorise an install.
                installReview?.items = InstallPlanner.plan(selection: entries, environment: environment, metadata: found, npmRuntime: npm)
            } catch is CancellationError {
                installReview = nil
            } catch {
                installReview = nil
                notice = "Viper couldn’t check what’s installed, so nothing was queued. Try again."
            }
            reviewTask = nil
        }
    }

    func cancelReview() {
        reviewTask?.cancel()
        installReview = nil
    }

    func confirmInstall() {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before installing software."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        guard !checkingUpdates, !refreshingCatalog, !detectingInstalls, !installing, !maintenanceBusy, let review = installReview, review.items != nil else { return }
        for item in review.installable {
            guard case .install(let request) = item.decision, !installQueue.contains(where: { $0.entry.id == item.entry.id && !$0.state.isFinished }) else { continue }
            let registry = item.entry.metadataKey.flatMap { catalogMetadata.items[$0]?.registryURL }
            installQueue.append(InstallQueueItem(entry: item.entry, request: request, reviewedVersion: item.version, reviewedRegistry: registry))
        }
        installSelection.removeAll { review.entryIDs.contains($0) }
        installReview = nil
        runInstallQueue()
    }

    // MARK: Queue

    /// Mutating package operations run strictly one at a time.
    private func runInstallQueue() {
        guard !installing, installQueue.contains(where: { $0.state == .queued }) else { return }
        installing = true
        Task {
            while let index = installQueue.firstIndex(where: { $0.state == .queued }) {
                if let reason = ReviewedChangePolicy.waitingWorkBlocked(changesAllowed: settings.allowReviewedChanges, journalNeedsReview: !settings.preservedJournals.isEmpty) {
                    cancelPendingInstalls()
                    notice = reason
                    break
                }
                installQueue[index].state = .installing
                installQueue[index].startedAt = Date()
                installQueue[index].progress = OperationProgress(phase: .preparing, detail: "Rechecking installed apps and the reviewed version…")
                let item = installQueue[index]
                // A queue may wait for minutes. Refresh ownership, compatibility, and version before each mutation.
                let result: (outcome: PackageProvider.InstallOutcome, log: String)
                do {
                    guard let catalog else { throw CommandError.failed }
                    let (environment, _) = try await Self.detectEnvironment(catalog: catalog)
                    let metadata = try await PackageProvider.metadata(for: item.entry.install, runtime: item.request.runtime)
                    let plan = InstallPlanner.plan(selection: [item.entry], environment: environment, metadata: [metadata.key: metadata], npmRuntime: item.request.method == .npm ? item.request.runtime : nil)
                    guard let fresh = plan.first, case .install(let request) = fresh.decision, request == item.request,
                          let version = item.reviewedVersion, metadata.version == version,
                          metadata.registryURL == item.reviewedRegistry else {
                        installQueue[index].state = .needsAttention("Installed state, compatibility, or the available version changed since review. Review this item again before installing.")
                        record(installQueue[index])
                        continue
                    }
                    let report: ProgressHandler = { progress in
                        Task { @MainActor in
                            guard let row = self.installQueue.firstIndex(where: { $0.id == item.id && $0.state == .installing }) else { return }
                            self.installQueue[row].progress = progress
                        }
                    }
                    result = await Task.detached(priority: .utility) { await PackageProvider.install(item.request, reviewedVersion: version, progress: report) }.value
                } catch {
                    result = (.needsAttention("Viper couldn’t revalidate this item immediately before installation. Nothing was started for this item; review it again."), "")
                }
                guard let current = installQueue.firstIndex(where: { $0.id == item.id }) else { continue }
                installQueue[current].log = result.log
                switch result.outcome {
                case .installed(let version): installQueue[current].state = .installed(version)
                case .failed(let reason): installQueue[current].state = .failed(reason)
                case .needsAttention(let reason): installQueue[current].state = .needsAttention(reason)
                }
                guard record(installQueue[current]) else {
                    cancelPendingInstalls()
                    break
                }
            }
            installing = false
            detectInstallations()
            if let settled = onInstallsSettled {
                onInstallsSettled = nil
                settled()
            }
        }
    }

    func cancelPendingInstalls() {
        for index in installQueue.indices where installQueue[index].state == .queued {
            installQueue[index].state = .cancelled
            record(installQueue[index])
        }
    }

    func clearFinishedInstalls() { installQueue.removeAll { $0.state.isFinished } }

    /// Returns false when the journal could not be written. Callers must not start another change.
    @discardableResult
    private func record(_ item: InstallQueueItem) -> Bool {
        let (outcome, version, detail): (String, String?, String) = {
            switch item.state {
            case .installed(let version): return ("Installed", version, "")
            case .failed(let reason): return ("Failed", nil, reason)
            case .needsAttention(let reason): return ("Needs attention", nil, reason)
            case .cancelled: return ("Cancelled", nil, "Cancelled before it started. Nothing was changed.")
            default: return ("Unknown", nil, "")
            }
        }()
        let entry = InstallJournalEntry(appID: item.entry.id, appName: item.entry.name, source: item.request.method.sourceLabel, package: item.request.package,
                                        runtime: item.request.runtime.executable.path, outcome: outcome, version: version, detail: detail)
        do {
            installJournal = try InstallJournal.append(entry, to: Self.journalURL)
            return true
        } catch let error as JournalStore.Unreadable {
            installJournal.append(entry)
            settings.preservedJournals.insert(error.preservedAt.path)
            notice = error.localizedDescription
            return false
        } catch {
            installJournal.append(entry)
            notice = "Viper couldn’t update its install history, so it will not start another change until that succeeds."
            return false
        }
    }

    // MARK: Handoffs

    func openApplication(_ url: URL) {
        guard NSWorkspace.shared.open(url) else {
            notice = "This app couldn’t be opened. Try opening it from Finder."
            return
        }
    }
}
