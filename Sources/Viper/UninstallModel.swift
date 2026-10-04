import AppKit
import SwiftUI
import ViperCore

enum UninstallTarget {
    case app(InstalledApplication)
    case tool(CommandLinePackage)

    var name: String {
        switch self {
        case .app(let app): return app.name
        case .tool(let tool): return tool.name
        }
    }
}

struct UninstallSession: Identifiable {
    enum Phase { case scanning, review, removing, finished }
    let id = UUID()
    let target: UninstallTarget
    var plan: UninstallPlan?
    var selection: Set<String> = []
    var phase: Phase = .scanning
    var progress = "Finding related files…"
    var outcomes: [RemovalOutcome] = []
    var failure: String?

    var selectedItems: [RemovalItem] { (plan?.items ?? []).filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + ($1.size ?? 0) } }
    var canPutBack: Bool { outcomes.contains { if case .removed(let trash?) = $0.result { return !$0.restored && trash.path.isEmpty == false } else { return false } } }
}

extension AppModel {
    var packageOperationBusy: Bool { installing || checkingUpdates || detectingInstalls || refreshingCatalog || reviewTask != nil || maintenanceBusy }

    /// Lets a pending quit continue once removals and updates have finished.
    func settleMaintenance() {
        guard !maintenanceBusy, let settled = onMaintenanceSettled else { return }
        onMaintenanceSettled = nil
        settled()
    }

    /// Discover and explain. Reads names and sizes only; nothing is changed until the user confirms.
    func beginUninstall(_ target: UninstallTarget) {
        guard uninstallSession == nil else { return }
        let session = UninstallSession(target: target)
        uninstallSession = session
        let cachedTools = commandLine?.packages
        let protected = Set([Bundle.main.bundleIdentifier].compactMap { $0 })
        uninstallTask = Task {
            do {
                let planning = Task.detached(priority: .userInitiated) {
                    let applications = try AppInventory.read().applications
                    let tools: [CommandLinePackage]
                    if let cachedTools { tools = cachedTools } else { tools = try await CommandLineInventory.read().packages }
                    let context = UninstallContext(applications: applications, tools: tools, protectedBundleIdentifiers: protected)
                    switch target {
                    case .app(let app): return try UninstallPlanner.plan(for: app, context: context)
                    case .tool(let tool): return try UninstallPlanner.plan(for: tool, context: context)
                    }
                }
                let plan = try await withTaskCancellationHandler { try await planning.value } onCancel: { planning.cancel() }
                // The sheet may have been closed and another opened meanwhile.
                guard uninstallSession?.id == session.id, uninstallSession?.phase == .scanning else { return }
                uninstallSession?.plan = plan
                uninstallSession?.selection = Set(plan.items.filter { $0.isRequired || (settings.preselectRebuildableItems && $0.selectedByDefault) }.map(\.id))
                uninstallSession?.phase = .review
            } catch is CancellationError {
            } catch {
                guard uninstallSession?.id == session.id else { return }
                uninstallSession?.failure = "Viper couldn’t finish looking for related files. Nothing was changed."
                uninstallSession?.phase = .review
            }
            uninstallTask = nil
        }
    }

    func toggleUninstallItem(_ item: RemovalItem) {
        guard !item.isRequired, uninstallSession?.phase == .review else { return }
        if uninstallSession?.selection.contains(item.id) == true { uninstallSession?.selection.remove(item.id) }
        else { uninstallSession?.selection.insert(item.id) }
    }

    func setUninstallItems(_ items: [RemovalItem], selected: Bool) {
        guard uninstallSession?.phase == .review else { return }
        for item in items where !item.isRequired {
            if selected { uninstallSession?.selection.insert(item.id) } else { uninstallSession?.selection.remove(item.id) }
        }
    }

    func isRunning(_ target: UninstallTarget) -> Bool {
        guard case .app(let app) = target else { return false }
        return !runningInstances(of: app).isEmpty
    }

    private func runningInstances(of app: InstalledApplication) -> [NSRunningApplication] {
        let path = app.url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL.path == path }
    }

    /// Asks the app to quit normally, so it can save its work. Never force-quits.
    func quitUninstallTarget() {
        guard let session = uninstallSession, case .app(let app) = session.target else { return }
        runningInstances(of: app).forEach { $0.terminate() }
        Task {
            for _ in 0..<20 where isRunning(session.target) { try? await Task.sleep(nanoseconds: 250_000_000) }
            objectWillChange.send()
            if isRunning(session.target) { notice = "\(app.name) is still open. It may be waiting for you to save something." }
        }
    }

    /// Revalidate and execute. The executor rechecks every item immediately before it moves.
    func confirmUninstall() {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before uninstalling anything."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        guard var session = uninstallSession, session.phase == .review, let plan = session.plan, plan.canProceed else { return }
        guard !packageOperationBusy else {
            notice = "Wait for the current install, update check, or uninstall to finish first."
            return
        }
        uninstalling = true
        session.phase = .removing
        session.progress = "Starting…"
        uninstallSession = session
        let selection = session.selection
        let target = session.target
        let home = FileManager.default.homeDirectoryForCurrentUser
        let attempted = plan.items.filter { $0.isRequired || selection.contains($0.id) }
        let recorder: RemovalTransactionRecorder
        do {
            recorder = try RemovalTransactionRecorder(name: plan.name, items: attempted, url: AppPaths.removalTransactions)
        } catch let error as JournalStore.Unreadable {
            settings.preservedJournals.insert(error.preservedAt.path)
            notice = error.localizedDescription
            session.phase = .review
            uninstallSession = session
            uninstalling = false
            return
        } catch {
            notice = "Viper couldn’t create its recovery journal, so nothing was removed. Check that its Application Support folder is writable."
            session.phase = .review
            uninstallSession = session
            uninstalling = false
            return
        }
        let running: @Sendable () async -> Bool = { [weak self] in await self?.isRunning(target) ?? true }
        let mayContinue: @Sendable () async -> Bool = { [weak self] in await self?.reviewedChangesAreAllowed() ?? false }
        let progress: @Sendable (String) async -> Void = { [weak self] text in await self?.setUninstallProgress(text) }
        let record: UninstallExecutor.OutcomeRecorder = { outcome in
            do { try await recorder.record(outcome); return true }
            catch { return false }
        }
        Task {
            let outcomes = await Task.detached(priority: .userInitiated) {
                await UninstallExecutor.execute(plan, selected: selection, home: home, isRunning: running, mayContinue: mayContinue, record: record, progress: progress)
            }.value
            uninstallSession?.outcomes = outcomes
            uninstallSession?.phase = .finished
            do {
                guard !outcomes.contains(where: {
                    if case .skipped(let reason) = $0.result { return reason.contains("recovery journal could not be updated") }
                    return false
                }) else { throw CocoaError(.fileWriteUnknown) }
                try await recorder.complete()
                try RemovalJournal.append(.init(name: plan.name, outcomes: outcomes), to: AppPaths.removalJournal)
            } catch let error as JournalStore.Unreadable {
                settings.preservedJournals.insert(error.preservedAt.path)
                notice = error.localizedDescription
            } catch {
                notice = "The removal stopped safely, but its recovery journal could not be finalized. Review the Trash and removal history before trying again."
            }
            uninstalling = false
            if outcomes.contains(where: { $0.result.succeeded }) { refreshAfterRemoval() }
            settleMaintenance()
        }
    }

    private func setUninstallProgress(_ text: String) { uninstallSession?.progress = text }

    func putBackUninstalled() {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before restoring files from the Trash."
            return
        }
        guard !maintenanceBusy, !installing else {
            notice = "Wait for the current change to finish before putting files back."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        guard let session = uninstallSession, session.phase == .finished else { return }
        let restored = UninstallExecutor.restore(session.outcomes)
        uninstallSession?.outcomes = restored
        let missed = restored.filter { if case .removed(let trash?) = $0.result { return !$0.restored && !trash.path.isEmpty } else { return false } }
        do { try RemovalJournal.append(.init(name: session.target.name + " (put back)", outcomes: restored.filter(\.restored)), to: AppPaths.removalJournal) }
        catch let error as JournalStore.Unreadable {
            settings.preservedJournals.insert(error.preservedAt.path)
            notice = error.localizedDescription
        } catch { notice = "Files were put back, but Viper couldn’t update its removal history. Review the original locations before making another change." }
        if !missed.isEmpty { notice = "\(missed.count) item\(missed.count == 1 ? "" : "s") couldn’t be put back, because the Trash copy is gone or something now exists at the original location. Check the Trash in Finder." }
        refreshAfterRemoval()
    }

    func closeUninstall() {
        guard uninstallSession?.phase != .removing else { return }
        uninstallTask?.cancel()
        uninstallTask = nil
        uninstallSession = nil
    }

    /// Surfaces removals that never finished recording, so a crash or forced quit can't be silently forgotten.
    /// Each interrupted transaction is reported once; Settings keeps the full list.
    /// True when a journal was unreadable. Callers stop before changing files.
    func refuseUntilJournalReviewed() -> Bool {
        guard !settings.preservedJournals.isEmpty else { return false }
        notice = "A journal couldn’t be read and was saved aside. Open Settings and mark it reviewed before Viper changes anything."
        return true
    }

    func preserveUnreadableJournals() {
        let found = [
            JournalStore.quarantineIfUnreadable(AppPaths.removalTransactions, as: [RemovalTransaction].self),
            JournalStore.quarantineIfUnreadable(AppPaths.removalJournal, as: [RemovalJournalEntry].self),
            JournalStore.quarantineIfUnreadable(AppPaths.installJournal, as: [InstallJournalEntry].self)
        ].compactMap { $0?.path }
        guard !found.isEmpty else { return }
        settings.preservedJournals.formUnion(found)
        notice = "A journal couldn’t be read and was saved aside. Open Settings and mark it reviewed before Viper changes anything."
    }

    func markPreservedJournalsReviewed() { settings.preservedJournals = [] }

    func reconcileUnfinishedTransactions() {
        let unfinished = RemovalTransactionJournal.load(from: AppPaths.removalTransactions)
            .filter { $0.state == .inProgress && !settings.acknowledgedInterruptedRemovals.contains($0.id.uuidString) }
        guard !unfinished.isEmpty else { return }
        settings.acknowledgedInterruptedRemovals.formUnion(unfinished.map { $0.id.uuidString })
        let names = unfinished.map(\.name).joined(separator: ", ")
        notice = "\(unfinished.count) removal\(unfinished.count == 1 ? "" : "s") didn’t finish recording (\(names)). Viper or the Mac may have stopped mid-operation. Check the Trash, then open Settings to review the recovery journal."
    }

    func refreshAfterRemoval() {
        commandLine = nil
        loadApplications()
        if catalog != nil { installEnvironment = nil }
    }
}
