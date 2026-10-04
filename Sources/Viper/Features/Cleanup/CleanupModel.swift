import AppKit
import SwiftUI
import ViperCore

enum CleanupTarget: String, Hashable { case junk = "Junk files", leftovers = "App leftovers", storage = "Large files" }

struct CleanupState {
    var report: CleanupReport?
    var selection: Set<String> = []
    var loading = false
    var working = false
    var progress = ""
    var message: String?
    var outcomes: [RemovalOutcome] = []

    var selectedItems: [RemovalItem] { (report?.items ?? []).filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + ($1.size ?? 0) } }
    var canPutBack: Bool { outcomes.contains { if case .removed(_?) = $0.result { return !$0.restored } else { return false } } }
}

extension AppModel {
    func cleanupState(_ target: CleanupTarget) -> CleanupState {
        switch target {
        case .junk: return junk
        case .leftovers: return leftovers
        case .storage: return storageCleanup
        }
    }

    private func updateCleanup(_ target: CleanupTarget, _ change: (inout CleanupState) -> Void) {
        switch target {
        case .junk: change(&junk)
        case .leftovers: change(&leftovers)
        case .storage: change(&storageCleanup)
        }
    }

    private var runningApplications: (identifiers: Set<String>, names: Set<String>, displayNames: [String: String]) {
        let running = NSWorkspace.shared.runningApplications
        var aliases = Set<String>()
        var displayNames: [String: String] = [:]
        for app in running {
            let display = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "Running app"
            let bundle = app.bundleURL.flatMap(Bundle.init(url:))
            let values = [app.localizedName, app.bundleURL?.deletingPathExtension().lastPathComponent,
                          bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                          bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
                          app.bundleIdentifier?.split(separator: ".").last.map(String.init)].compactMap { $0?.lowercased() }
            aliases.formUnion(values)
            for value in values { displayNames[value] = display }
            if let identifier = app.bundleIdentifier { displayNames[identifier] = display }
        }
        return (Set(running.compactMap(\.bundleIdentifier) + [Bundle.main.bundleIdentifier].compactMap { $0 }), aliases, displayNames)
    }

    /// Launch Services knows apps on every mounted volume. Apps sitting in the Trash don't count.
    nonisolated static func appExists(_ identifier: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return false }
        return !url.path.contains("/.Trash/")
    }

    // MARK: Scanning

    func scanCleanup(_ target: CleanupTarget) {
        guard target != .storage, !cleanupState(target).loading, !cleanupState(target).working else { return }
        updateCleanup(target) { $0 = CleanupState(loading: true) }
        let running = runningApplications
        let home = FileManager.default.homeDirectoryForCurrentUser
        cleanupTasks[target] = Task {
            do {
                let scanning = Task.detached(priority: .utility) { () throws -> CleanupReport in
                    switch target {
                    case .junk:
                        return try JunkScanner.scan(.init(home: home, runningIdentifiers: running.identifiers, runningNames: running.names, displayNames: running.displayNames))
                    default:
                        let inventory = try AppInventory.read()
                        let installed = Set(inventory.applications.compactMap(\.bundleIdentifier)).union(running.identifiers)
                        return try LeftoverScanner.scan(library: home.appendingPathComponent("Library"), installedIdentifiers: installed,
                                                        installedApplicationGroups: Set(inventory.applications.flatMap(\.applicationGroups)),
                                                        inventoryIncomplete: !inventory.unavailableFolders.isEmpty, isKnownApp: Self.appExists)
                    }
                }
                let report = try await withTaskCancellationHandler { try await scanning.value } onCancel: { scanning.cancel() }
                updateCleanup(target) {
                    $0.report = report
                    $0.selection = settings.preselectRebuildableItems ? Set(report.items.filter(\.selectedByDefault).map(\.id)) : []
                }
            } catch is CancellationError {
                updateCleanup(target) { $0.message = "Scan cancelled. Nothing was changed." }
            } catch {
                updateCleanup(target) { $0.message = "The scan couldn’t finish. Check that Viper can read your Library folder." }
            }
            updateCleanup(target) { $0.loading = false }
            cleanupTasks[target] = nil
        }
    }

    func cancelCleanupScan(_ target: CleanupTarget) { cleanupTasks[target]?.cancel() }

    func toggleCleanupItem(_ target: CleanupTarget, _ item: RemovalItem) {
        guard !cleanupState(target).working else { return }
        updateCleanup(target) { state in
            if state.selection.contains(item.id) { state.selection.remove(item.id) } else { state.selection.insert(item.id) }
        }
    }

    func setCleanupItems(_ target: CleanupTarget, _ items: [RemovalItem], selected: Bool) {
        guard !cleanupState(target).working else { return }
        updateCleanup(target) { state in
            for item in items { if selected { state.selection.insert(item.id) } else { state.selection.remove(item.id) } }
        }
    }

    // MARK: Cleaning

    /// Moves the reviewed selection to the Trash. Ownership, running apps, location, and file identity are rechecked first.
    func cleanSelected(_ target: CleanupTarget) {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before moving files to the Trash."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        guard !packageOperationBusy else {
            notice = "Wait for the current install, update check, catalog check, or removal to finish first."
            return
        }
        let items: [RemovalItem]
        if target == .storage {
            guard let scan else { return }
            items = scan.largestFiles.filter { storageSelection.contains($0.id) }.compactMap { StorageCleanup.item(for: $0) }
            let changed = storageSelection.count - items.count
            storageCleanup = CleanupState(report: CleanupReport(items: items, kept: [], locations: [scan.root.path], unavailable: [], completedAt: Date()),
                                          selection: Set(items.map(\.id)))
            if changed > 0 { notice = "\(changed) file\(changed == 1 ? "" : "s") changed since the scan or can’t be removed here, so \(changed == 1 ? "it was" : "they were") left alone." }
        } else {
            items = cleanupState(target).selectedItems
        }
        guard !items.isEmpty else { return }
        let recorder: RemovalTransactionRecorder
        do {
            recorder = try RemovalTransactionRecorder(name: target.rawValue + " cleanup", items: items, url: AppPaths.removalTransactions)
        } catch let error as JournalStore.Unreadable {
            settings.preservedJournals.insert(error.preservedAt.path)
            notice = error.localizedDescription
            return
        } catch {
            notice = "Viper couldn’t create its recovery journal, so no files were changed. Check that its Application Support folder is writable."
            return
        }
        cleaning = true
        updateCleanup(target) {
            $0.working = true
            $0.progress = "Checking each item again…"
            $0.outcomes = []
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let temporary = FileManager.default.temporaryDirectory
        let mayContinue: @Sendable () async -> Bool = { [weak self] in await self?.reviewedChangesAreAllowed() ?? false }
        let progress: @Sendable (String) async -> Void = { [weak self] text in await self?.setCleanupProgress(target, text) }
        let record: UninstallExecutor.OutcomeRecorder = { outcome in
            do { try await recorder.record(outcome); return true }
            catch { return false }
        }
        Task {
            let outcomes = await Task.detached(priority: .userInitiated) { () -> [RemovalOutcome] in
                return await CleanupExecutor.trash(items, isAllowed: { item in
                    let running = await MainActor.run { [weak self] in self?.runningApplications }
                    guard let running else { return "Viper could not verify which apps are open, so it left this item alone." }
                    let applications = target == .leftovers ? ((try? AppInventory.read().applications) ?? []) : []
                    let installed = Set(applications.compactMap(\.bundleIdentifier)).union(running.identifiers)
                    let groups = Set(applications.flatMap(\.applicationGroups))
                    return Self.cleanupBlocker(item, target: target, home: home, temporary: temporary, running: running, installed: installed, installedGroups: groups)
                }, mayContinue: mayContinue, record: record, progress: progress)
            }.value
            updateCleanup(target) {
                $0.outcomes = outcomes
                $0.working = false
                let removed = Set(outcomes.filter { $0.result.succeeded }.map(\.id))
                $0.selection.subtract(removed)
            }
            do {
                guard outcomes.count == items.count else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try await recorder.complete()
                try RemovalJournal.append(.init(name: target.rawValue + " cleanup", outcomes: outcomes), to: AppPaths.removalJournal)
            } catch let error as JournalStore.Unreadable {
                settings.preservedJournals.insert(error.preservedAt.path)
                notice = error.localizedDescription
            } catch {
                notice = "The operation stopped safely, but its recovery journal could not be finalized. Review the Trash and the removal history before trying again."
            }
            if target == .storage {
                let removed = Set(outcomes.filter { $0.result.succeeded }.map(\.id))
                storageSelection.subtract(removed)
            }
            cleaning = false
            refreshCapacity()
            settleMaintenance()
        }
    }

    nonisolated private static func cleanupBlocker(_ item: RemovalItem, target: CleanupTarget, home: URL, temporary: URL,
                                                   running: (identifiers: Set<String>, names: Set<String>, displayNames: [String: String]), installed: Set<String>,
                                                   installedGroups: Set<String>) -> String? {
        let outside = "This location isn’t one Viper cleans."
        switch target {
        case .junk:
            guard JunkScanner.allowedParents(home: home, temporaryDirectory: temporary).contains(item.parentPath) else { return outside }
            if let owner = JunkScanner.runningOwner(name: item.url.lastPathComponent, identifiers: running.identifiers, names: running.names, displayNames: running.displayNames) {
                return "\(owner) is open and uses this. Quit it and scan again."
            }
            if OpenFiles.isInUse(item.url) { return "An open app is using this. Quit it and scan again." }
            if item.parentPath.hasSuffix("/DerivedData"), running.identifiers.contains("com.apple.dt.Xcode") { return "Xcode is open now. Quit it and scan again." }
        case .leftovers:
            guard LeftoverScanner.isAllowed(item, library: home.appendingPathComponent("Library")) else { return outside }
            let (base, grouped) = UninstallPlanner.identifierBase(item.url.lastPathComponent)
            guard LeftoverScanner.isCandidate(base, installedIdentifiers: installed), !LeftoverScanner.prefixes(of: base).contains(where: appExists),
                  !(grouped && installedGroups.contains(item.url.lastPathComponent.lowercased())) else {
                return "An app that uses this is installed now, so it was kept."
            }
        case .storage:
            if let reason = StorageCleanup.blockedReason(item.url, home: home) { return reason }
        }
        return nil
    }

    private func setCleanupProgress(_ target: CleanupTarget, _ text: String) { updateCleanup(target) { $0.progress = text } }

    func putBackCleanup(_ target: CleanupTarget) {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before restoring files from the Trash."
            return
        }
        guard !maintenanceBusy, !installing else {
            notice = "Wait for the current change to finish before putting files back."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        let restored = UninstallExecutor.restore(cleanupState(target).outcomes)
        updateCleanup(target) { $0.outcomes = restored }
        let missed = restored.filter { if case .removed(_?) = $0.result { return !$0.restored } else { return false } }
        do { try RemovalJournal.append(.init(name: target.rawValue + " (put back)", outcomes: restored.filter(\.restored)), to: AppPaths.removalJournal) }
        catch let error as JournalStore.Unreadable {
            settings.preservedJournals.insert(error.preservedAt.path)
            notice = error.localizedDescription
        } catch { notice = "Files were put back, but Viper couldn’t update its removal history. Review the original locations before making another change." }
        if !missed.isEmpty { notice = "\(missed.count) item\(missed.count == 1 ? "" : "s") couldn’t be put back. The Trash copy may be gone, or something now exists at the original location." }
        refreshCapacity()
    }

    func dismissCleanupResult(_ target: CleanupTarget) {
        updateCleanup(target) { $0.outcomes = [] }
        if target != .storage, cleanupState(target).report != nil { scanCleanup(target) }
    }

    /// Permanent deletion stays in Finder, where macOS owns confirmation and volume-specific behavior.
    func openTrash() {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard NSWorkspace.shared.open(trash) else {
            notice = "The Trash couldn’t be opened. Open it from the Dock before permanently deleting anything."
            return
        }
    }
}
