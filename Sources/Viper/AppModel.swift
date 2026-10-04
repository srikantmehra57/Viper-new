import AppKit
import SwiftUI
import ViperCore

enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview", storage = "Storage", uninstaller = "Uninstaller"
    case leftovers = "Junk & Leftovers", memory = "Memory", updates = "Updates", privacy = "Privacy", discover = "Discover & Install", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .storage: return "internaldrive"
        case .uninstaller: return "app.badge"
        case .leftovers: return "tray"
        case .memory: return "memorychip"
        case .updates: return "arrow.down.circle"
        case .privacy: return "hand.raised"
        case .discover: return "plus.app"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    /// Prevents settings side effects from re-entering while they update journals or notices.
    private var applyingSettingEffects = false
    @Published var settings = AppSettings.load() {
        didSet {
            settings.save()
            if settings.theme != oldValue.theme { applyAppearance() }
            guard !applyingSettingEffects else { return }
            let turnedOff = oldValue.allowReviewedChanges && !settings.allowReviewedChanges
            let journalBlocked = settings.preservedJournals.count > oldValue.preservedJournals.count
            guard turnedOff || journalBlocked else { return }
            applyingSettingEffects = true
            defer { applyingSettingEffects = false }
            let hadWaiting = installQueue.contains { $0.state == .queued } || updateQueue.contains { $0.state == .queued }
            cancelPendingInstalls()
            cancelPendingUpdates()
            if hadWaiting && settings.preservedJournals.count == oldValue.preservedJournals.count {
                notice = "Waiting installs and updates were cancelled. Anything already running will finish."
            }
        }
    }
    @Published var page: Page = .overview
    // Cleanup, updates, and privacy actions. Logic lives in CleanupModel.swift and MaintenanceModel.swift.
    @Published var leftovers = CleanupState()
    @Published var junk = CleanupState()
    @Published var storageSelection: Set<String> = []
    @Published var storageCleanup = CleanupState()
    @Published var cleaning = false
    @Published var updateQueue: [UpdateQueueItem] = []
    @Published var updating = false
    var cleanupTasks: [CleanupTarget: Task<Void, Never>] = [:]
    @Published var updateReport: UpdateReport?
    @Published var checkingUpdates = false
    @Published var updateProgress = ""
    @Published var updateMessage: String?
    private var updateCheckTask: Task<UpdateReport, Error>?
    /// Lets a pending quit continue once an in-flight update check has unwound.
    var onUpdateCheckSettled: (() -> Void)?
    @Published var capacity: VolumeCapacity?
    @Published var capacityError: String?
    /// Result of a best-effort probe of a TCC-protected folder; nil while checking.
    @Published var fullDiskAccess: Bool?
    @Published var selectedFolder: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var scan: ScanResult?
    @Published var scanSummary: StoredScanSummary?
    @Published var progress: ScanProgress?
    @Published var scanning = false
    @Published var scanMessage: String?
    @Published var inventory: AppInventoryResult?
    @Published var inventoryLoading = false
    @Published var inventoryMessage: String?
    @Published var commandLine: CommandLineInventoryResult?
    @Published var commandLineLoading = false
    @Published var commandLineMessage: String?
    @Published var notice: String?
    private var scanTask: Task<ScanResult, Error>?
    private var inventoryTask: Task<AppInventoryResult, Error>?
    private var commandLineTask: Task<CommandLineInventoryResult, Error>?
    // Uninstaller. Logic lives in UninstallModel.swift.
    @Published var uninstallSession: UninstallSession?
    @Published var uninstalling = false
    var uninstallTask: Task<Void, Never>?
    var onMaintenanceSettled: (() -> Void)?
    // Memory. Logic lives in MemoryModel.swift.
    @Published var memory = MemoryState()
    @Published var freeingMemory = false
    var memoryScanTask: Task<Void, Never>?
    /// The five-second refresh loop behind the Memory page; non-nil while it runs.
    @Published var memoryRefreshTask: Task<Void, Never>?
    /// The previous scan's second sample, so a refresh tick can measure CPU% across the gap.
    var lastMemorySample: (taken: Date, processes: [ProcessSample])?
    /// Apple-signature verdicts shared across scans; helpers in one bundle cost one check.
    let signatureCache = SignatureCache()
    /// The facts the last memory scan was built on, kept so stops can recheck protection.
    var memoryInput: MemoryAdvisor.Input?
    /// Local launch/activation history used by the memory advisor. Never leaves this Mac.
    var usageHistory = UsageHistory.load(from: AppModel.appUsageURL)
    private var usageHistorySaveTask: Task<Void, Never>?
    var maintenanceBusy: Bool { uninstalling || cleaning || updating || freeingMemory }
    /// Shown in the sidebar only while Viper is changing something.
    var activityLabel: String? {
        if uninstalling { return "UNINSTALLING" }
        if cleaning { return "CLEANING" }
        if updating { return "UPDATING" }
        if installing { return "INSTALLING" }
        if freeingMemory { return "FREEING MEMORY" }
        return nil
    }
    // Discover & Install. Logic lives in InstallModel.swift.
    @Published var catalog: Catalog?
    @Published var catalogMessage: String?
    @Published var installEnvironment: InstallEnvironment?
    @Published var detectingInstalls = false
    @Published var catalogMetadata = CatalogMetadataCache()
    @Published var refreshingCatalog = false
    @Published var catalogProgress = ""
    @Published var installSelection: [String] = []
    @Published var npmRuntimeID: String?
    @Published var installReview: InstallReview?
    @Published var prerequisite: PackageManager?
    @Published var installQueue: [InstallQueueItem] = []
    @Published var installing = false
    @Published var installJournal: [InstallJournalEntry] = []
    var detectionTask: Task<(InstallEnvironment, AppInventoryResult), Error>?
    var catalogRefreshTask: Task<Void, Never>?
    var reviewTask: Task<Void, Never>?
    var onInstallsSettled: (() -> Void)?

    init() {
        if let path = settings.scanFolders.first { selectedFolder = URL(fileURLWithPath: path) }
        refreshCapacity()
        applyAppearance()
        reconcileUnfinishedTransactions()
        preserveUnreadableJournals()
        scanSummary = StoredScanSummary.load(from: Self.scanSummaryURL)
        if settings.settingsWereReset {
            notice = (notice.map { $0 + " " } ?? "") + "Your saved settings couldn’t be read, so defaults were restored. Nothing else was changed."
        }
        probeFullDiskAccess()
        observeAppUsage()
    }

    /// Launch and activation events feed the memory feature's usage history. No timers, no polling.
    private func observeAppUsage() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier else { return }
            Task { @MainActor in
                self?.usageHistory.recordLaunch(id)
                self?.scheduleUsageHistorySave()
            }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier else { return }
            Task { @MainActor in
                self?.usageHistory.recordActivation(id)
                self?.scheduleUsageHistorySave()
            }
        }
    }

    /// Usage history is a cache: it writes at most once every 30 seconds and once on quit.
    private func scheduleUsageHistorySave() {
        guard usageHistorySaveTask == nil else { return }
        usageHistorySaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled else { return }
            usageHistorySaveTask = nil
            try? usageHistory.save(to: Self.appUsageURL)
        }
    }

    /// Flushes any pending usage history; called on terminate via cancelWork.
    func saveUsageHistoryNow() {
        usageHistorySaveTask?.cancel()
        usageHistorySaveTask = nil
        try? usageHistory.save(to: Self.appUsageURL)
    }

    /// Reads a folder macOS only exposes with Full Disk Access; the result is informational, never used to change behavior.
    private func probeFullDiskAccess() {
        Task.detached(priority: .utility) {
            let probe = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC")
            let granted = (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
            await MainActor.run { self.fullDiskAccess = granted }
        }
    }

    /// Viper's interface is designed dark-only, so AppKit chrome (alerts, popovers, menus) is kept dark to match.
    func applyAppearance() {
        Palette.activate(settings.theme)
        let appearance = NSAppearance(named: .darkAqua)
        NSApplication.shared.appearance = appearance
        for window in NSApplication.shared.windows { window.appearance = appearance }
    }

    private static var scanSummaryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Viper/scan-summary.json")
    }

    /// Scans a subfolder from the current results. The folder is remembered with the other saved scan locations.
    func lookInside(_ url: URL) {
        guard !scanning else { return }
        let path = url.standardizedFileURL.path
        if !settings.scanFolders.contains(path) { settings.scanFolders.append(path) }
        selectFolder(url)
        startScan()
    }

    func selectFolder(_ url: URL) {
        guard !scanning else { return }
        selectedFolder = url
        scan = nil
        scanMessage = nil
        refreshCapacity()
    }

    func addFolder(exclusion: Bool) {
        guard !scanning else { return }
        let panel = NSOpenPanel()
        panel.title = exclusion ? "Exclude a folder from storage scans" : "Add a scan folder"
        panel.prompt = exclusion ? "Exclude folder" : "Add folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                let path = url.standardizedFileURL.path
                if exclusion {
                    if !settings.excludedFolders.contains(path) { settings.excludedFolders.append(path) }
                } else if !settings.scanFolders.contains(path) { settings.scanFolders.append(path) }
            }
            if !exclusion, let first = panel.urls.first { selectFolder(first) }
        }
    }

    func removeFolder(_ path: String, exclusion: Bool) {
        guard !scanning else { return }
        if exclusion { settings.excludedFolders.removeAll { $0 == path } }
        else {
            settings.scanFolders.removeAll { $0 == path }
            if selectedFolder.path == path {
                scan = nil
                scanMessage = "Choose a saved folder or add a new one to scan."
                if let next = settings.scanFolders.first { selectFolder(URL(fileURLWithPath: next)) }
            }
        }
    }

    func refreshCapacity() {
        do {
            let fresh = try VolumeCapacity.read(at: selectedFolder)
            if fresh != capacity { capacity = fresh }
            if capacityError != nil { capacityError = nil }
        } catch {
            capacity = nil
            capacityError = "Storage capacity is unavailable for this location. Try another folder."
        }
    }

    func chooseFolder() {
        guard !scanning else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to analyse"
        panel.prompt = "Choose folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedFolder
        if panel.runModal() == .OK, let url = panel.url {
            if !settings.scanFolders.contains(url.path) { settings.scanFolders.append(url.path) }
            selectFolder(url)
        }
    }

    func startScan() {
        guard !scanning else { return }
        guard settings.scanFolders.contains(selectedFolder.path) else {
            notice = "Choose a folder before scanning. You can manage saved locations in Settings."
            return
        }
        guard !settings.excludedFolders.contains(where: { selectedFolder.path == $0 || selectedFolder.path.hasPrefix($0 + "/") }) else {
            notice = "This folder is excluded in Settings. Remove that exclusion or choose another folder."
            return
        }
        scanning = true
        scan = nil
        storageSelection = []
        storageCleanup = CleanupState()
        progress = nil
        scanMessage = nil
        let root = selectedFolder
        let exclusions = settings.excludedFolders.map { URL(fileURLWithPath: $0) }
        let includeHidden = settings.includeHiddenFiles
        let largestFileLimit = settings.storageResultLimit
        let progressHandler: @Sendable (ScanProgress) async -> Void = { [weak self] update in
            await self?.receiveProgress(update)
        }
        let task = Task.detached(priority: .utility) {
            try await StorageScanner.scan(root: root, excluding: exclusions, includeHiddenFiles: includeHidden,
                                          largestFileLimit: largestFileLimit, onProgress: progressHandler)
        }
        scanTask = task
        Task {
            do {
                let result = try await task.value
                scan = result
                let summary = result.summary
                scanSummary = summary
                try? summary.save(to: Self.scanSummaryURL)
                scanMessage = "Scan finished. Your files have not been changed."
            } catch is CancellationError {
                scanMessage = "Scan cancelled. No files were changed. Start another scan whenever you’re ready."
            } catch {
                scanMessage = "This folder could not be scanned. Check access in System Settings or choose a different folder."
            }
            scanning = false
            progress = nil
            scanTask = nil
            refreshCapacity()
        }
    }

    private func receiveProgress(_ value: ScanProgress) { progress = value }
    func cancelScan() { scanTask?.cancel() }

    func loadApplications() {
        guard !inventoryLoading else { return }
        inventoryLoading = true
        inventoryMessage = nil
        let task = Task.detached(priority: .utility) { try AppInventory.read() }
        inventoryTask = task
        Task {
            do { inventory = try await task.value }
            catch is CancellationError { inventoryMessage = "App search cancelled." }
            catch { inventoryMessage = "Viper couldn’t read your application folders. Try refreshing the list." }
            inventoryLoading = false
            inventoryTask = nil
        }
        loadCommandLineTools()
    }

    /// Lists Homebrew and global npm tools alongside apps. Read-only; waits for package installs so it never races them.
    func loadCommandLineTools() {
        guard !commandLineLoading else { return }
        guard !installing, !uninstalling, !updating else {
            commandLineMessage = "Command-line tools will be listed after the current installs finish. Refresh then."
            return
        }
        commandLineLoading = true
        commandLineMessage = nil
        let task = Task.detached(priority: .utility) { try await CommandLineInventory.read() }
        commandLineTask = task
        Task {
            do { commandLine = try await task.value }
            catch is CancellationError { commandLineMessage = "Command-line tool search cancelled." }
            catch { commandLineMessage = "Viper couldn’t read Homebrew or npm packages. Try refreshing the list." }
            commandLineLoading = false
            commandLineTask = nil
        }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func openSettings(_ suffix: String) {
        guard let url = ExternalLink.systemSettings(suffix), NSWorkspace.shared.open(url) else {
            notice = "Open System Settings and choose Privacy & Security. This Mac did not accept the shortcut."
            return
        }
    }

    /// Live safety switch read from background work. Fails closed if Viper is going away.
    func reviewedChangesAreAllowed() -> Bool {
        settings.allowReviewedChanges && settings.preservedJournals.isEmpty
    }

    func openExternal(_ address: String) {
        guard let url = ExternalLink.webOrAppStore(address), NSWorkspace.shared.open(url) else {
            notice = "This link couldn’t be opened. Viper only opens secure web and App Store links."
            return
        }
    }

    /// Returns folders, exclusions, and safety mode to defaults without forgetting an unreadable journal.
    func resetSettings() {
        guard !scanning, !maintenanceBusy, !installing, !checkingUpdates, !refreshingCatalog, reviewTask == nil else {
            notice = "Wait for the current scan or change to finish before resetting settings."
            return
        }
        let preserved = settings.preservedJournals
        let acknowledged = settings.acknowledgedInterruptedRemovals
        settings = AppSettings()
        settings.preservedJournals = preserved
        settings.acknowledgedInterruptedRemovals = acknowledged
        storageSelection = []
        storageCleanup = CleanupState()
        if let path = settings.scanFolders.first { selectFolder(URL(fileURLWithPath: path)) }
    }

    func checkUpdates() {
        guard !checkingUpdates else { return }
        guard !installing, !detectingInstalls, !refreshingCatalog, reviewTask == nil, !maintenanceBusy else {
            notice = "Wait for the current package operation to finish before checking for updates."
            return
        }
        guard settings.checkHomebrew || settings.checkNpm || settings.checkAppStore else {
            notice = "Enable at least one update source in Settings."
            return
        }
        checkingUpdates = true
        updateQueue.removeAll { $0.state.isFinished }
        updateReport = nil
        updateMessage = nil
        updateProgress = "Finding installed apps and package managers…"
        let sources = settings
        let progress: @Sendable (String) async -> Void = { [weak self] message in await self?.setUpdateProgress(message) }
        let task = Task.detached(priority: .utility) {
            let applications = try AppInventory.read().applications
            return try await UpdateChecker.check(homebrew: sources.checkHomebrew, npm: sources.checkNpm, appStore: sources.checkAppStore, applications: applications, progress: progress)
        }
        updateCheckTask = task
        Task {
            do { updateReport = try await task.value }
            catch is CancellationError { updateMessage = "Check cancelled. No software was updated." }
            catch {
                updateMessage = (error as? LocalizedError)?.errorDescription ?? "Update checking failed. Your software has not been changed."
            }
            checkingUpdates = false
            updateCheckTask = nil
            if let settled = onUpdateCheckSettled {
                onUpdateCheckSettled = nil
                settled()
            }
        }
    }
    private func setUpdateProgress(_ message: String) { updateProgress = message }
    func cancelUpdateCheck() { updateCheckTask?.cancel() }

    /// Cancels scans and checks. Installs, updates, and removals in progress finish first; see AppDelegate.applicationShouldTerminate.
    func cancelWork() {
        cleanupTasks.values.forEach { $0.cancel() }
        memoryScanTask?.cancel()
        memoryRefreshTask?.cancel()
        memoryRefreshTask = nil
        saveUsageHistoryNow()
        scanTask?.cancel(); inventoryTask?.cancel(); commandLineTask?.cancel(); updateCheckTask?.cancel()
        detectionTask?.cancel(); catalogRefreshTask?.cancel(); reviewTask?.cancel()
    }
}

func bytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}
