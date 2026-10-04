import AppKit
import Security
import SwiftUI
import ViperCore

struct MemoryState {
    var report: MemoryReport?
    var selection: Set<Int32> = []
    var loading = false
    var working = false
    var progress = ""
    var message: String?
    var outcomes: [MemoryStopOutcome] = []

    var selectedCandidates: [MemoryCandidate] { (report?.candidates ?? []).filter { selection.contains($0.id) } }
    var selectedFootprint: UInt64 { selectedCandidates.reduce(0) { $0 + $1.footprint } }
}

extension AppModel {
    // MARK: Scanning

    /// Two process samples two seconds apart, joined with app state, usage, and launchd jobs. Read-only.
    /// A refresh tick reuses the previous sample so CPU% stays a true average between ticks; it keeps
    /// the current selection, outcomes, and message instead of resetting them.
    func scanMemory(refreshing: Bool = false) {
        guard !memory.loading, !memory.working, memoryScanTask == nil else { return }
        if !refreshing {
            memory = MemoryState(loading: true)
            memory.progress = "Reading running processes…"
        }
        let running = NSWorkspace.shared.runningApplications
        let windows = Self.windowCounts()
        var apps: [Int32: RunningAppInfo] = [:]
        var appUsage: [String: AppUsage] = [:]
        for app in running {
            guard app.processIdentifier > 0 else { continue }
            let policy: RunningAppInfo.Policy
            switch app.activationPolicy {
            case .accessory: policy = .accessory
            case .prohibited: policy = .prohibited
            default: policy = .regular
            }
            apps[app.processIdentifier] = RunningAppInfo(
                bundleID: app.bundleIdentifier, name: app.localizedName ?? "App",
                bundlePath: app.bundleURL?.path, isActive: app.isActive, isHidden: app.isHidden,
                policy: policy, windows: windows[app.processIdentifier] ?? 0)
            if let id = app.bundleIdentifier, let url = app.bundleURL {
                let spotlight = SpotlightUsage.read(url)
                var merged = usageHistory.usage(of: id)
                merged.spotlightUseCount = spotlight.useCount
                merged.spotlightLastUsed = spotlight.lastUsed
                appUsage[id] = merged
            }
        }
        var ancestors: Set<Int32> = []
        var ancestor = getppid()
        while ancestor > 1, ancestors.insert(ancestor).inserted {
            var info = proc_bsdinfo()
            guard proc_pidinfo(ancestor, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { break }
            ancestor = Int32(bitPattern: info.pbi_ppid)
        }
        let ownPID = getpid()
        let ownBundleID = Bundle.main.bundleIdentifier
        let stopped = MemoryJournal.load(from: AppPaths.memoryJournal)
        let signatures = signatureCache
        let prior = lastMemorySample
        let scan = Task {
            do {
                let sampled = Task.detached(priority: .utility) { () throws -> (MemoryReport, [ProcessSample], MemoryAdvisor.Input) in
                    let first: [ProcessSample]
                    let second: (processes: [ProcessSample], skippedOtherUsers: Int)
                    let interval: TimeInterval
                    if refreshing, let prior, Date().timeIntervalSince(prior.taken) < 30 {
                        // One fresh sample measured against the last tick's — CPU% averages the whole gap.
                        first = prior.processes
                        second = ProcessInventory.sample()
                        interval = Date().timeIntervalSince(prior.taken)
                    } else {
                        let opening = ProcessInventory.sample()
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        try Task.checkCancellation()
                        first = opening.processes
                        second = ProcessInventory.sample()
                        interval = 2
                    }
                    var input = MemoryAdvisor.Input(first: first, second: second.processes, interval: interval,
                                                    apps: apps, usage: appUsage, launchdJobs: [:],
                                                    isAppleSigned: signatures.check, recentlyStopped: stopped,
                                                    ownPID: ownPID, ownBundleID: ownBundleID, ancestorPIDs: ancestors,
                                                    otherUserProcesses: second.skippedOtherUsers)
                    // launchd jobs are only read for groups big enough to matter.
                    input.launchdJobs = await Self.launchdJobs(for: MemoryAdvisor.advise(input).allMemberPIDs)
                    var report = MemoryAdvisor.advise(input)
                    report.status = SystemMemory.read()
                    return (report, second.processes, input)
                }
                let (report, processes, input) = try await withTaskCancellationHandler { try await sampled.value } onCancel: { sampled.cancel() }
                memoryInput = input
                lastMemorySample = (Date(), processes)
                memory.report = report
                if refreshing {
                    // Keep the user's picks; drop ids that left the report since the last tick.
                    memory.selection.formIntersection(report.candidates.map(\.id) + report.kept.map(\.pid))
                } else {
                    memory.selection = report.defaultSelection
                    memory.message = "Scan finished. Nothing was stopped."
                }
            } catch is CancellationError {
                if !refreshing { memory.message = "Scan cancelled. Nothing was stopped." }
            } catch {
                if !refreshing { memory.message = "The scan couldn’t finish. Nothing was stopped." }
            }
            memory.loading = false
            memoryScanTask = nil
        }
        memoryScanTask = scan
    }

    func cancelMemoryScan() { memoryScanTask?.cancel() }

    // MARK: Live updates

    /// While the Memory page is up, re-advises every five seconds. Skips a tick while the app is
    /// in the background, another page is showing, or a scan or stop is already in flight.
    func startLiveMemoryUpdates() {
        guard memoryRefreshTask == nil else { return }
        if memory.report == nil { scanMemory() }
        memoryRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                guard page == .memory, NSApplication.shared.isActive, !memory.loading, !memory.working else { continue }
                scanMemory(refreshing: true)
            }
        }
    }

    func stopLiveMemoryUpdates() {
        memoryRefreshTask?.cancel()
        memoryRefreshTask = nil
    }

    func toggleMemoryCandidate(_ candidate: MemoryCandidate) {
        guard !memory.working else { return }
        if memory.selection.contains(candidate.id) { memory.selection.remove(candidate.id) }
        else { memory.selection.insert(candidate.id) }
    }

    func setMemoryCandidates(_ candidates: [MemoryCandidate], selected: Bool) {
        guard !memory.working else { return }
        for candidate in candidates {
            if selected { memory.selection.insert(candidate.id) } else { memory.selection.remove(candidate.id) }
        }
    }

    // MARK: Stopping

    /// Quits the reviewed selection one at a time. Apps get a normal Quit, processes get SIGTERM.
    func stopSelectedMemory() {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before quitting apps and processes."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        guard !packageOperationBusy else {
            notice = "Wait for the current install, update check, catalog check, or removal to finish first."
            return
        }
        let selected = memory.selectedCandidates
        guard !selected.isEmpty else { return }
        freeingMemory = true
        memory.working = true
        memory.outcomes = []
        Task { await stop(candidate: selected, force: false) }
    }

    /// Force quit is offered only for candidates that refused a graceful stop.
    func forceQuitMemory(_ outcome: MemoryStopOutcome) {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before force quitting."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        guard !maintenanceBusy, !installing else {
            notice = "Wait for the current change to finish before force quitting."
            return
        }
        guard case .stillRunning = outcome.result else { return }
        freeingMemory = true
        memory.working = true
        Task {
            memory.outcomes.removeAll { $0.id == outcome.id }
            await stop(candidate: [outcome.candidate], force: true)
        }
    }

    private func stop(candidate: [MemoryCandidate], force: Bool) async {
        for item in candidate {
            memory.progress = (force ? "Force quitting " : "Quitting ") + item.name + "…"
            let outcome = await MemoryStopper.stop(item, force: force, quitApp: Self.quitApp,
                                                   isAllowed: { [weak self] item in await self?.memoryBlocker(item) ?? "Viper can’t verify it is safe, so it was left alone." })
            memory.outcomes.append(outcome)
            journalMemory(outcome, forced: force)
        }
        memory.report?.status = SystemMemory.read()
        let stopped = Set(memory.outcomes.filter { $0.result.succeeded }.map { $0.candidate.id })
        memory.report?.candidates.removeAll { stopped.contains($0.id) }
        memory.selection.subtract(stopped)
        memory.working = false
        memory.progress = ""
        freeingMemory = false
        settleMaintenance()
    }

    /// Rechecked right before any signal: reviewed changes on, journals reviewed, not frontmost now, still not protected.
    private func memoryBlocker(_ item: MemoryCandidate) -> String? {
        guard reviewedChangesAreAllowed() else {
            return "Viper is in read-only safety mode, so it was left alone."
        }
        if case .app = item.kind, NSRunningApplication(processIdentifier: item.rootPID)?.isActive == true {
            return "It is in use right now, so it was left alone."
        }
        if let input = memoryInput, let reason = MemoryAdvisor.protectedReason(of: item, input: input) {
            return reason
        }
        return nil
    }

    private func journalMemory(_ outcome: MemoryStopOutcome, forced: Bool) {
        var bundleID: String? = nil
        if case .app(let id) = outcome.candidate.kind { bundleID = id }
        let text: String
        switch outcome.result {
        case .stopped: text = "stopped"
        case .stillRunning: text = "still running"
        case .skipped(let reason), .failed(let reason): text = reason
        }
        do {
            try MemoryJournal.append(.init(name: outcome.candidate.name, path: outcome.candidate.members.first?.path ?? "",
                                           bundleID: bundleID, footprint: outcome.candidate.footprint,
                                           outcome: text, forced: forced),
                                     to: AppPaths.memoryJournal)
        } catch let error as JournalStore.Unreadable {
            settings.preservedJournals.insert(error.preservedAt.path)
            notice = error.localizedDescription
        } catch {
            notice = "The stop finished, but Viper couldn’t update its memory journal. Nothing else was affected."
        }
    }

    // MARK: Gathering

    /// Normal-layer windows per process, counted once per scan. `.optionAll` keeps minimised and other-Space windows.
    nonisolated static func windowCounts() -> [Int32: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var counts: [Int32: Int] = [:]
        for window in list {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  (bounds["Width"] as? CGFloat ?? 0) >= 50, (bounds["Height"] as? CGFloat ?? 0) >= 50 else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }

    /// launchctl list labels per pid; keepalive is only read for the pids that matter.
    nonisolated static func launchdJobs(for pids: Set<Int32>) async -> [Int32: LaunchdJob] {
        let launchctl = URL(fileURLWithPath: "/bin/launchctl")
        guard let output = try? await CommandRunner.run(launchctl, arguments: ["list"], timeout: 20),
              output.status == 0 else { return [:] }
        var jobs: [Int32: LaunchdJob] = [:]
        for line in String(decoding: output.data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3, let pid = Int32(parts[0]), pids.contains(pid) else { continue }
            let label = String(parts[2])
            guard !label.hasPrefix("application.") else { continue }
            jobs[pid] = LaunchdJob(label: label, keepAlive: false)
        }
        for (pid, job) in jobs {
            let printed = try? await CommandRunner.run(launchctl, arguments: ["print", "gui/\(getuid())/\(job.label)"], timeout: 10)
            let text = printed.map { String(decoding: $0.data, as: UTF8.self) } ?? ""
            if text.split(separator: "\n").contains(where: { $0.contains("properties") && $0.contains("keepalive") }) {
                jobs[pid] = LaunchdJob(label: job.label, keepAlive: true)
            }
        }
        return jobs
    }

    /// terminate() / forceTerminate() against the live app object. False when the app object is gone.
    nonisolated static func quitApp(_ pid: Int32, _ force: Bool) async -> Bool {
        await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
            return force ? app.forceTerminate() : app.terminate()
        }
    }
}

/// SecStaticCode "anchor apple" checks, cached per path so helpers in one bundle cost one check.
/// Kept across scans so refresh ticks reuse verdicts; cleared when it grows past ~400 paths.
final class SignatureCache: @unchecked Sendable {
    private var cache: [String: Bool] = [:]
    private let lock = NSLock()

    func check(_ path: String) -> Bool {
        lock.withLock {
            if let hit = cache[path] { return hit }
            var code: SecStaticCode?
            var apple = false
            if SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code {
                var requirement: SecRequirement?
                if SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess, let requirement {
                    apple = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), requirement) == errSecSuccess
                }
            }
            if cache.count > 400 { cache.removeAll() }
            cache[path] = apple
            return apple
        }
    }
}

extension MemoryReport {
    /// Every member pid of every offered or kept group, for the launchd keep-alive probe.
    var allMemberPIDs: Set<Int32> {
        Set(candidates.flatMap { $0.members.map(\.pid) } + kept.map(\.pid))
    }
}
