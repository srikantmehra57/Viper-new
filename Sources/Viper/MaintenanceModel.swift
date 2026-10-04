import AppKit
import SwiftUI
import ViperCore

enum UpdateState: Equatable {
    case queued, updating, cancelled
    case updated(String)
    case alreadyCurrent(String)
    case skipped(String)
    case failed(String)

    var isFinished: Bool { self != .queued && self != .updating }
    var label: String {
        switch self {
        case .queued: return "WAITING"
        case .updating: return "UPDATING"
        case .cancelled: return "CANCELLED"
        case .updated: return "UPDATED"
        case .alreadyCurrent: return "UP TO DATE"
        case .skipped: return "SKIPPED"
        case .failed: return "FAILED"
        }
    }
}

struct UpdateQueueItem: Identifiable {
    var id: String { update.id }
    let update: AvailableUpdate
    let upgrade: PackageUpgrade
    var state: UpdateState = .queued
    var log = ""
    var progress: OperationProgress?
    var startedAt: Date?
}

extension AppModel {
    func updateState(for update: AvailableUpdate) -> UpdateState? { updateQueue.last { $0.id == update.id }?.state }

    /// Queues reviewed Homebrew and npm updates. They run one at a time, each rechecked immediately before it starts.
    func applyUpdates(_ updates: [AvailableUpdate]) {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before updating software."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        guard !installing, !uninstalling, !cleaning, !checkingUpdates, !detectingInstalls, !refreshingCatalog, reviewTask == nil else {
            notice = "Wait for the current install, check, or removal to finish first."
            return
        }
        for update in updates {
            guard let upgrade = PackageUpgrade(update), !updateQueue.contains(where: { $0.id == update.id && !$0.state.isFinished }) else { continue }
            updateQueue.removeAll { $0.id == update.id }
            updateQueue.append(UpdateQueueItem(update: update, upgrade: upgrade))
        }
        runUpdateQueue()
    }

    private func runUpdateQueue() {
        guard !updating, updateQueue.contains(where: { $0.state == .queued }) else { return }
        updating = true
        Task {
            while let index = updateQueue.firstIndex(where: { $0.state == .queued }) {
                if let reason = ReviewedChangePolicy.waitingWorkBlocked(changesAllowed: settings.allowReviewedChanges, journalNeedsReview: !settings.preservedJournals.isEmpty) {
                    cancelPendingUpdates()
                    notice = reason
                    break
                }
                updateQueue[index].state = .updating
                updateQueue[index].startedAt = Date()
                let item = updateQueue[index]
                let report: ProgressHandler = { progress in
                    Task { @MainActor in
                        guard let row = self.updateQueue.firstIndex(where: { $0.id == item.id && $0.state == .updating }) else { return }
                        self.updateQueue[row].progress = progress
                    }
                }
                let result = await Task.detached(priority: .utility) { await PackageProvider.upgrade(item.upgrade, progress: report) }.value
                guard let current = updateQueue.firstIndex(where: { $0.id == item.id }) else { continue }
                updateQueue[current].log = result.log
                switch result.outcome {
                case .updated(let version): updateQueue[current].state = .updated(version)
                case .alreadyCurrent(let version): updateQueue[current].state = .alreadyCurrent(version)
                case .skipped(let reason): updateQueue[current].state = .skipped(reason)
                case .failed(let reason): updateQueue[current].state = .failed(reason)
                }
                guard record(updateQueue[current]) else {
                    cancelPendingUpdates()
                    break
                }
            }
            updating = false
            commandLine = nil
            settleMaintenance()
        }
    }

    func cancelPendingUpdates() {
        for index in updateQueue.indices where updateQueue[index].state == .queued {
            updateQueue[index].state = .cancelled
            _ = record(updateQueue[index])
        }
    }

    func clearFinishedUpdates() { updateQueue.removeAll { $0.state.isFinished } }

    /// Returns false when the journal could not be written. Callers must not start another change.
    @discardableResult
    private func record(_ item: UpdateQueueItem) -> Bool {
        let (outcome, version, detail): (String, String?, String) = {
            switch item.state {
            case .updated(let version): return ("Updated", version, "From \(item.upgrade.fromVersion).")
            case .alreadyCurrent(let version): return ("Already up to date", version, "")
            case .skipped(let reason): return ("Skipped", nil, reason)
            case .failed(let reason): return ("Update failed", nil, reason)
            case .cancelled: return ("Cancelled", nil, "Cancelled before it started. Nothing was changed.")
            default: return ("Unknown", nil, "")
            }
        }()
        let entry = InstallJournalEntry(appID: "update:" + item.upgrade.package, appName: item.update.name, source: item.update.source.rawValue, package: item.upgrade.package,
                                        runtime: item.upgrade.runtime.executable.path, outcome: outcome, version: version, detail: detail)
        do {
            installJournal = try InstallJournal.append(entry, to: AppPaths.installJournal)
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

    // MARK: Privacy

    func resetPermissions(for app: InstalledApplication) {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before resetting permissions."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        guard !isRunning(.app(app)) else {
            notice = "\(app.name) is open. Quit it before resetting permissions, so macOS can ask again cleanly."
            return
        }
        guard let identifier = app.bundleIdentifier else {
            notice = "\(app.name) has no bundle identifier, so its permissions can’t be reset."
            return
        }
        Task {
            switch await PermissionReset.reset(bundleIdentifier: identifier) {
            case .success: notice = "\(app.name)’s privacy permissions were reset. macOS will ask again the next time it needs access."
            case .failure: notice = "macOS didn’t reset \(app.name)’s permissions. You can remove its access in System Settings › Privacy & Security."
            }
        }
    }
}
