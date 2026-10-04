import Foundation

/// What the app knows about one running GUI process, gathered from NSRunningApplication and the window server.
public struct RunningAppInfo: Sendable, Equatable {
    public enum Policy: String, Sendable { case regular, accessory, prohibited }
    public var bundleID: String?
    public var name: String
    public var bundlePath: String?
    public var isActive: Bool
    public var isHidden: Bool
    public var policy: Policy
    /// Normal-layer windows at least 50×50, including minimised and other-Space ones.
    public var windows: Int

    public init(bundleID: String?, name: String, bundlePath: String?, isActive: Bool, isHidden: Bool, policy: Policy, windows: Int) {
        self.bundleID = bundleID
        self.name = name
        self.bundlePath = bundlePath
        self.isActive = isActive
        self.isHidden = isHidden
        self.policy = policy
        self.windows = windows
    }
}

/// A launchd job behind a process, from `launchctl list` and `launchctl print`.
public struct LaunchdJob: Sendable, Equatable {
    public var label: String
    public var keepAlive: Bool

    public init(label: String, keepAlive: Bool) {
        self.label = label
        self.keepAlive = keepAlive
    }
}

/// A stop-worthy group of processes: one app (helpers included) or one CLI tool with its children.
public struct MemoryCandidate: Identifiable, Sendable {
    public enum Kind: Sendable, Equatable { case app(bundleID: String?), process }
    public enum Tier: Sendable, Equatable { case recommended, optional }

    public var id: Int32 { rootPID }
    public var rootPID: Int32
    public var name: String
    public var kind: Kind
    public var bundlePath: String?
    /// Root first. Identities from the scan are re-verified before anything is signalled.
    public var members: [ProcessIdentity]
    public var footprint: UInt64
    /// 100 means one full core, averaged over the sample interval.
    public var cpuPercent: Double
    public var wakeupsPerSecond: Double
    public var listeningPorts: [UInt16]
    public var establishedConnections: Int
    public var age: TimeInterval
    public var hasTerminal: Bool
    public var usage: AppUsage?
    public var tier: Tier
    public var reasons: [String]
    /// The caution or energy note shown under the reasons.
    public var note: String?

    public init(rootPID: Int32, name: String, kind: Kind, bundlePath: String?, members: [ProcessIdentity], footprint: UInt64,
                cpuPercent: Double, wakeupsPerSecond: Double, listeningPorts: [UInt16], establishedConnections: Int,
                age: TimeInterval, hasTerminal: Bool, usage: AppUsage?, tier: Tier, reasons: [String], note: String?) {
        self.rootPID = rootPID
        self.name = name
        self.kind = kind
        self.bundlePath = bundlePath
        self.members = members
        self.footprint = footprint
        self.cpuPercent = cpuPercent
        self.wakeupsPerSecond = wakeupsPerSecond
        self.listeningPorts = listeningPorts
        self.establishedConnections = establishedConnections
        self.age = age
        self.hasTerminal = hasTerminal
        self.usage = usage
        self.tier = tier
        self.reasons = reasons
        self.note = note
    }
}

/// Found but deliberately not offered.
public struct KeptProcess: Sendable, Identifiable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var name: String
    public var footprint: UInt64
    public var reason: String

    public init(pid: Int32, name: String, footprint: UInt64, reason: String) {
        self.pid = pid
        self.name = name
        self.footprint = footprint
        self.reason = reason
    }
}

public struct MemoryReport: Sendable {
    /// Filled by the caller after the advisor returns.
    public var status: MemoryStatus?
    public var candidates: [MemoryCandidate]
    public var kept: [KeptProcess]
    public var smallProcessCount: Int
    public var smallProcessBytes: UInt64
    public var otherUserProcesses: Int
    public var sampledAt: Date

    public var recommended: [MemoryCandidate] { candidates.filter { $0.tier == .recommended } }
    public var optional: [MemoryCandidate] { candidates.filter { $0.tier == .optional } }
    /// Recommended ids preselected only when the machine is actually under memory pressure.
    public var defaultSelection: Set<Int32> {
        (status?.pressure ?? .normal) == .normal ? [] : Set(recommended.map(\.id))
    }
}

/// Pure policy: turns two process samples into a reviewed list. No syscalls — every fact arrives via `Input`.
public enum MemoryAdvisor {
    public struct Input: Sendable {
        /// Two samples taken `interval` seconds apart.
        public var first: [ProcessSample]
        public var second: [ProcessSample]
        public var interval: TimeInterval
        public var apps: [Int32: RunningAppInfo]
        public var usage: [String: AppUsage]
        public var launchdJobs: [Int32: LaunchdJob]
        public var isAppleSigned: @Sendable (String) -> Bool
        public var recentlyStopped: [MemoryJournalEntry]
        public var ownPID: Int32
        public var ownBundleID: String?
        public var ancestorPIDs: Set<Int32>
        /// Processes the sampler could see but not inspect because they belong to other users.
        public var otherUserProcesses: Int
        public var pressure: MemoryPressure
        public var now: Date

        public init(first: [ProcessSample], second: [ProcessSample], interval: TimeInterval, apps: [Int32: RunningAppInfo] = [:],
                    usage: [String: AppUsage] = [:], launchdJobs: [Int32: LaunchdJob] = [:], isAppleSigned: @escaping @Sendable (String) -> Bool = { _ in false },
                    recentlyStopped: [MemoryJournalEntry] = [], ownPID: Int32 = -1, ownBundleID: String? = nil, ancestorPIDs: Set<Int32> = [],
                    otherUserProcesses: Int = 0, pressure: MemoryPressure = .normal, now: Date = Date()) {
            self.first = first
            self.second = second
            self.interval = interval
            self.apps = apps
            self.usage = usage
            self.launchdJobs = launchdJobs
            self.isAppleSigned = isAppleSigned
            self.recentlyStopped = recentlyStopped
            self.ownPID = ownPID
            self.ownBundleID = ownBundleID
            self.ancestorPIDs = ancestorPIDs
            self.otherUserProcesses = otherUserProcesses
            self.pressure = pressure
            self.now = now
        }
    }

    private static let neverQuitBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight",
        "com.apple.WindowManager", "com.apple.coreservices.uiagent", "com.apple.TextInputMenuAgent"
    ]
    private static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "login", "tmux", "screen"]
    private static let smallLimit: UInt64 = 50 * 1_000_000

    public static func advise(_ input: Input) -> MemoryReport {
        let second = Dictionary(input.second.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let first = Dictionary(input.first.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        // A group only exists when the same process (not just the same pid) appears in both samples.
        var groups: [String: [ProcessSample]] = [:]
        var roots: [String: Int32] = [:]
        for member in input.second where first[member.pid]?.identity == member.identity {
            let key = groupKey(of: member, in: second)
            groups[key.id, default: []].append(member)
            if let bundle = outermostBundle(member.path) {
                // The NSRunningApplication pid owns the group when its bundle path matches.
                if let app = input.apps.first(where: { $0.value.bundlePath == bundle })?.key, member.pid == app { roots[key.id] = app }
            } else {
                roots[key.id] = key.root
            }
        }
        var candidates: [MemoryCandidate] = []
        var kept: [KeptProcess] = []
        var smallCount = 0
        var smallBytes: UInt64 = 0
        for (key, group) in groups {
            let root = group.first(where: { $0.pid == roots[key] })
                ?? group.filter { member in !group.contains { $0.pid == member.ppid } }.min(by: { $0.pid < $1.pid })
                ?? group.min(by: { $0.pid < $1.pid })!
            let ordered = [root] + group.filter { $0.pid != root.pid }.sorted { $0.footprint > $1.footprint }
            let candidate = build(root: root, members: ordered, first: first, input: input)
            if let reason = protectedReason(of: candidate, input: input) {
                kept.append(KeptProcess(pid: candidate.rootPID, name: candidate.name, footprint: candidate.footprint, reason: reason))
            } else if isFrequentlyUsed(candidate.usage, now: input.now), candidate.footprint < 1_000_000_000 {
                kept.append(KeptProcess(pid: candidate.rootPID, name: candidate.name, footprint: candidate.footprint,
                                        reason: "Used often — relaunching would cost more than it saves"))
            } else if candidate.footprint < smallLimit {
                smallCount += group.count
                smallBytes += candidate.footprint
            } else {
                candidates.append(candidate)
            }
        }
        candidates.sort { ($0.tier == .recommended) != ($1.tier == .recommended) ? $0.tier == .recommended : $0.footprint > $1.footprint }
        kept.sort { $0.footprint > $1.footprint }
        return MemoryReport(status: nil, candidates: candidates, kept: kept,
                            smallProcessCount: smallCount, smallProcessBytes: smallBytes,
                            otherUserProcesses: input.otherUserProcesses, sampledAt: input.now)
    }

    /// Why this candidate must never be offered. Re-evaluated before anything is stopped.
    public static func protectedReason(of candidate: MemoryCandidate, input: Input) -> String? {
        var bundleID: String? = nil
        if case .app(let id) = candidate.kind { bundleID = id }
        if candidate.members.contains(where: { $0.pid == input.ownPID }) { return "Viper itself" }
        if candidate.members.contains(where: { input.ancestorPIDs.contains($0.pid) }) { return "Runs Viper" }
        if let bundleID, neverQuitBundleIDs.contains(bundleID) || bundleID == input.ownBundleID { return "Part of macOS" }
        if let job = candidate.members.lazy.compactMap({ input.launchdJobs[$0.pid] }).first(where: { $0.keepAlive }) {
            return "Restarts automatically (launchd: \(job.label)) — stopping it would just relaunch it and cost more energy."
        }
        // Only a successful stop counts: something Viper skipped or failed to stop can't "come back".
        let processStart = input.now.addingTimeInterval(-candidate.age)
        let cameBack = input.recentlyStopped.first { entry in
            entry.outcome == "stopped" && input.now.timeIntervalSince(entry.date) < 24 * 3600
                && processStart > entry.date
                && (candidate.members.contains { $0.path == entry.path } || (bundleID != nil && bundleID == entry.bundleID))
        }
        if let cameBack {
            let when = cameBack.date.formatted(date: .omitted, time: .shortened)
            if case .app = candidate.kind, input.apps[candidate.rootPID]?.policy == .regular {
                return "You reopened it after Viper quit it at \(when), so it’s kept"
            }
            return "Came back after Viper stopped it at \(when) — something restarts it, so stopping it again wouldn't help."
        }
        if let app = input.apps[candidate.rootPID], app.isActive { return "In use right now" }
        // A regular GUI app is a normal Quit even when Apple made it (Safari, Xcode, Music).
        let regularGUIApp = candidate.bundlePath != nil && input.apps[candidate.rootPID]?.policy == .regular
        if !regularGUIApp, candidate.members.contains(where: { systemPath($0.path) || input.isAppleSigned($0.path) }) {
            return "Part of macOS"
        }
        return nil
    }

    /// Paths that belong to the OS and are never offered.
    private static func systemPath(_ path: String) -> Bool {
        path.hasPrefix("/System/") || path.hasPrefix("/bin/") || path.hasPrefix("/sbin/")
            || path.hasPrefix("/Library/Apple/") || path.hasPrefix("/private/var/") || path.hasPrefix("/Library/Developer/CommandLineTools/")
            || (path.hasPrefix("/usr/") && !path.hasPrefix("/usr/local/"))
    }

    // MARK: Grouping

    private struct GroupKey {
        var id: String
        var root: Int32
    }

    /// The outermost `.app` directory in a path, so helpers and bundled tools roll up into their app.
    static func outermostBundle(_ path: String) -> String? {
        var current = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            current += "/" + component
            if component.hasSuffix(".app") { return current }
        }
        return nil
    }

    private static func groupKey(of process: ProcessSample, in table: [Int32: ProcessSample]) -> GroupKey {
        if let bundle = outermostBundle(process.path) { return GroupKey(id: "app:" + bundle, root: process.pid) }
        // Climb to the nearest non-bundled, non-shell ancestor so tools like node→esbuild stay one group.
        var seen: Set<Int32> = [process.pid]
        var ancestor = table[process.ppid]
        while let next = ancestor, seen.insert(next.pid).inserted {
            if outermostBundle(next.path) == nil, !shells.contains(next.name) {
                return GroupKey(id: "proc:\(next.pid)", root: next.pid)
            }
            ancestor = table[next.ppid]
        }
        return GroupKey(id: "proc:\(process.pid)", root: process.pid)
    }

    // MARK: Candidates

    private static func isFrequentlyUsed(_ usage: AppUsage?, now: Date) -> Bool {
        guard let usage else { return false }
        return usage.recentLaunches.filter { now.timeIntervalSince($0) < 7 * 86_400 }.count >= 3
            || (usage.lastActivated.map { now.timeIntervalSince($0) < 24 * 3600 } ?? false)
            || ((usage.spotlightLastUsed.map { now.timeIntervalSince($0) < 2 * 86_400 } ?? false) && (usage.spotlightUseCount ?? 0) >= 20)
    }

    private static func build(root: ProcessSample, members: [ProcessSample], first: [Int32: ProcessSample], input: Input) -> MemoryCandidate {
        let bundlePath = outermostBundle(root.path)
        let app = members.lazy.compactMap { input.apps[$0.pid] }.first(where: { $0.bundlePath == bundlePath }) ?? input.apps[root.pid]
        let bundleID = app?.bundleID
        var cpuDelta: UInt64 = 0, wakeDelta: UInt64 = 0
        var footprint: UInt64 = 0, ports = Set<UInt16>(), established = 0
        var hasTerminal = false
        for member in members {
            footprint += member.footprint
            if let before = first[member.pid] {
                cpuDelta += member.cpuNanoseconds - min(member.cpuNanoseconds, before.cpuNanoseconds)
                wakeDelta += member.wakeups - min(member.wakeups, before.wakeups)
            }
            ports.formUnion(member.listeningPorts)
            established += member.establishedConnections
            hasTerminal = hasTerminal || member.hasTerminal
        }
        let interval = max(input.interval, 0.001)
        let cpuPercent = Double(cpuDelta) / interval / 1e7 // nanoseconds → percent of one core
        let wakeups = Double(wakeDelta) / interval
        let age = max(0, input.now.timeIntervalSince(root.startDate))
        let usage = bundleID.flatMap { input.usage[$0] }
        let idle = cpuPercent < 2 && wakeups < 20
        // A bundle group only counts as an app when a running app object matches it;
        // agents or updaters living inside an app bundle are plain processes.
        let isApp = app != nil
        let missingApp = bundlePath != nil && app == nil
        let dormantApp = app != nil && (app!.isHidden || app!.windows == 0)
        let backgroundBusy = (cpuPercent >= 5 || wakeups >= 50) && (bundlePath == nil || dormantApp)
        let launches = usage?.recentLaunches ?? []
        let lastOpened = [usage?.lastActivated, usage?.spotlightLastUsed, launches.last].compactMap { $0 }.max()
        let daysUnopened = lastOpened.map { input.now.timeIntervalSince($0) / 86_400 }
        let frequent = isApp && isFrequentlyUsed(usage, now: input.now)
        let usedRecently = !frequent && isApp && (
            (usage?.lastActivated.map { input.now.timeIntervalSince($0) < 7200 } ?? false)
            || (usage?.spotlightLastUsed.map { input.now.timeIntervalSince($0) < 7200 } ?? false))
        let job = members.lazy.compactMap { input.launchdJobs[$0.pid] }.first
        let server = !isApp && !missingApp && !ports.isEmpty && established == 0 && idle

        let sizeLimit: UInt64 = isApp ? 300 * 1_000_000 : 150 * 1_000_000
        let dormant = !isApp || dormantApp
        var tier: MemoryCandidate.Tier = (footprint >= sizeLimit && idle && dormant) || backgroundBusy ? .recommended : .optional
        var note: String? = nil
        if missingApp {
            tier = .optional
            let bundle = bundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "an app"
            note = "Runs from inside \(bundle); Viper couldn't confirm what it does"
        }
        if frequent {
            tier = .optional
            note = "You use this often. Quitting means relaunching it soon, which costs more energy than keeping it — macOS compresses its idle memory."
        } else if usedRecently {
            tier = .optional
            note = "Used in the last couple of hours"
        }
        if isApp, established > 0 {
            tier = .optional
            note = note ?? "Has active network connections — it may be syncing, downloading, or in a call"
        }
        if let app, !app.isHidden, app.windows > 0 {
            tier = .optional
            note = note ?? "Has open windows — you may be working in it"
        }
        if let app, app.policy != .regular {
            tier = .optional
            note = "Background or menu bar app — it may provide a service you rely on (VPN, sync, security, backups)."
        }
        if let job, !job.keepAlive {
            tier = .optional
            note = "Started by launchd (\(job.label)); it may start again at next login."
        }
        if server {
            if age >= 3600 {
                tier = .recommended
            } else {
                tier = .optional
                note = "Started recently — you may still be using it"
            }
        }
        if !server, hasTerminal {
            tier = .optional
            note = note ?? "Running in a terminal window"
        }
        if tier == .recommended, backgroundBusy {
            note = "Busy in the background — stopping it also saves battery"
        }

        var reasons = ["Uses \(memoryString(footprint))"]
        if backgroundBusy {
            reasons.append(wakeups >= 50 ? "Busy in the background · \(Int(wakeups.rounded())) wake-ups/s" : "Busy in the background · \(oneDecimal(cpuPercent))% CPU")
        } else if idle {
            reasons.append("Idle · \(oneDecimal(cpuPercent))% CPU")
        }
        if let port = ports.sorted().first, established == 0 { reasons.append("Listening on :\(port) with no connections") }
        if established > 0 { reasons.append("\(established) connection\(established == 1 ? "" : "s") open") }
        if age >= 3600 { reasons.append("Running for \(ageString(age))") }
        let launches7 = launches.filter { input.now.timeIntervalSince($0) < 7 * 86_400 }.count
        if launches7 >= 3 {
            reasons.append("Opened \(launches7) times recently")
        } else if let days = daysUnopened, days >= 2 {
            reasons.append("Not opened in \(Int(days.rounded())) days")
        }
        if let app, app.windows == 0 { reasons.append("No open windows") }

        let name = app?.name ?? (bundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? root.name)
        return MemoryCandidate(rootPID: root.pid, name: name, kind: isApp ? .app(bundleID: bundleID) : .process,
                               bundlePath: bundlePath, members: members.map(\.identity), footprint: footprint,
                               cpuPercent: cpuPercent, wakeupsPerSecond: wakeups, listeningPorts: ports.sorted(),
                               establishedConnections: established, age: age, hasTerminal: hasTerminal,
                               usage: usage, tier: tier, reasons: reasons, note: note)
    }

    // MARK: Formatting

    static func memoryString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func ageString(_ age: TimeInterval) -> String {
        let hours = age / 3600
        if hours >= 48 { return "\(Int((hours / 24).rounded())) d" }
        return "\(Int(hours.rounded())) h"
    }
}
