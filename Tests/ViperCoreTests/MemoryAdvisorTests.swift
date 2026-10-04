import Darwin
import XCTest
@testable import ViperCore

final class MemoryAdvisorTests: XCTestCase {
    private let now = Date()
    private var pid: Int32 = 5000

    /// A fixture process. `pair` returns it in both samples; cpu/wakeups are the delta between them.
    private func proc(name: String = "tool", path: String = "/opt/homebrew/bin/tool", ppid: Int32 = 1,
                      footprint: UInt64 = 200_000_000, cpuDelta: UInt64 = 0, wakeDelta: UInt64 = 0,
                      terminal: Bool = false, ports: [UInt16] = [], connections: Int = 0,
                      age: TimeInterval = 7200) -> (first: ProcessSample, second: ProcessSample) {
        pid += 1
        let identity = ProcessIdentity(pid: pid, startSeconds: UInt64(now.addingTimeInterval(-age).timeIntervalSince1970),
                                       startMicroseconds: 0, path: path)
        func make(_ cpu: UInt64, _ wake: UInt64) -> ProcessSample {
            ProcessSample(identity: identity, ppid: ppid, uid: getuid(), name: name, path: path,
                          startDate: now.addingTimeInterval(-age), footprint: footprint, cpuNanoseconds: cpu,
                          wakeups: wake, hasTerminal: terminal, listeningPorts: ports, establishedConnections: connections)
        }
        return (make(0, 0), make(cpuDelta, wakeDelta))
    }

    private func input(_ pairs: [(first: ProcessSample, second: ProcessSample)],
                       apps: [Int32: RunningAppInfo] = [:], usage: [String: AppUsage] = [:],
                       jobs: [Int32: LaunchdJob] = [:], apple: @escaping @Sendable (String) -> Bool = { _ in false },
                       stopped: [MemoryJournalEntry] = [], ownPID: Int32 = -1, ancestors: Set<Int32> = [],
                       pressure: MemoryPressure = .normal, others: Int = 0) -> MemoryAdvisor.Input {
        MemoryAdvisor.Input(first: pairs.map(\.first), second: pairs.map(\.second), interval: 2,
                            apps: apps, usage: usage, launchdJobs: jobs, isAppleSigned: apple,
                            recentlyStopped: stopped, ownPID: ownPID, ancestorPIDs: ancestors,
                            otherUserProcesses: others, pressure: pressure, now: now)
    }

    private func app(_ pid: Int32, id: String = "com.vendor.app", name: String = "App", path: String = "/Applications/App.app",
                     active: Bool = false, hidden: Bool = true, policy: RunningAppInfo.Policy = .regular,
                     windows: Int = 0) -> RunningAppInfo {
        RunningAppInfo(bundleID: id, name: name, bundlePath: path, isActive: active, isHidden: hidden, policy: policy, windows: windows)
    }

    func testSystemPathsAndAppleSignedDaemonsAreKept() {
        let daemon = proc(name: "fooagent", path: "/opt/agent/bin/fooagent")
        let usrBin = proc(name: "helperd", path: "/usr/libexec/helperd")
        let report = MemoryAdvisor.advise(input([daemon, usrBin], apple: { $0 == "/opt/agent/bin/fooagent" }))
        XCTAssertTrue(report.candidates.isEmpty)
        XCTAssertEqual(report.kept.count, 2)
        XCTAssertTrue(report.kept.allSatisfy { $0.reason == "Part of macOS" })
    }

    func testUsrLocalNodeIsNotProtected() {
        let node = proc(name: "node", path: "/usr/local/bin/node", footprint: 300_000_000)
        let report = MemoryAdvisor.advise(input([node]))
        XCTAssertEqual(report.candidates.count, 1)
        XCTAssertEqual(report.candidates[0].name, "node")
    }

    func testRegularAppleAppIsAllowed() {
        let xcode = proc(name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", footprint: 2_000_000_000)
        var info = input([xcode], apple: { _ in true })
        info.apps[xcode.second.pid] = app(xcode.second.pid, id: "com.apple.dt.Xcode", name: "Xcode", path: "/Applications/Xcode.app")
        let report = MemoryAdvisor.advise(info)
        XCTAssertEqual(report.candidates.count, 1, "A regular Apple GUI app is a normal Quit")
        XCTAssertEqual(report.candidates[0].kind, .app(bundleID: "com.apple.dt.Xcode"))
    }

    func testFinderAndDockAreNeverOffered() {
        let finder = proc(name: "Finder", path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder")
        var info = input([finder])
        info.apps[finder.second.pid] = app(finder.second.pid, id: "com.apple.finder", name: "Finder",
                                           path: "/System/Library/CoreServices/Finder.app", active: false, windows: 2)
        XCTAssertTrue(MemoryAdvisor.advise(info).candidates.isEmpty)
    }

    func testSelfAndAncestorsAreKept() {
        let us = proc(name: "Viper", path: "/Applications/Viper.app/Contents/MacOS/Viper")
        let parent = proc(name: "tool", path: "/opt/tool/bin/tool")
        let report = MemoryAdvisor.advise(input([us, parent], ownPID: us.second.pid, ancestors: [parent.second.pid]))
        XCTAssertTrue(report.candidates.isEmpty)
        XCTAssertEqual(Set(report.kept.map(\.reason)), ["Viper itself", "Runs Viper"])
    }

    func testHelpersRollUpIntoTheirApp() {
        let main = proc(name: "Foo", path: "/Applications/Foo.app/Contents/MacOS/Foo", footprint: 200_000_000)
        let helper = proc(name: "Foo Helper", path: "/Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper",
                          ppid: main.second.pid, footprint: 600_000_000)
        var info = input([main, helper])
        info.apps[main.second.pid] = app(main.second.pid, id: "com.vendor.foo", name: "Foo", path: "/Applications/Foo.app")
        let report = MemoryAdvisor.advise(info)
        XCTAssertEqual(report.candidates.count, 1)
        XCTAssertEqual(report.candidates[0].rootPID, main.second.pid)
        XCTAssertEqual(report.candidates[0].footprint, 800_000_000)
        XCTAssertEqual(report.candidates[0].members.count, 2)
    }

    func testChildProcessGroupsWithParentTool() {
        let zsh = proc(name: "zsh", path: "/bin/zsh", footprint: 10_000_000)
        let node = proc(name: "node", path: "/usr/local/bin/node", ppid: zsh.second.pid, footprint: 300_000_000)
        let esbuild = proc(name: "esbuild", path: "/opt/tools/esbuild", ppid: node.second.pid, footprint: 60_000_000)
        let report = MemoryAdvisor.advise(input([zsh, node, esbuild]))
        XCTAssertEqual(report.candidates.count, 1)
        XCTAssertEqual(report.candidates[0].rootPID, node.second.pid)
        XCTAssertEqual(report.candidates[0].footprint, 360_000_000)
        XCTAssertTrue(report.kept.contains { $0.name == "zsh" }, "The shell is system code and stays kept")
    }

    func testIdleLocalhostServerIsRecommended() {
        let server = proc(name: "node", path: "/usr/local/bin/node", ports: [3000], age: 3 * 3600)
        let report = MemoryAdvisor.advise(input([server]))
        XCTAssertEqual(report.candidates[0].tier, .recommended)
        XCTAssertTrue(report.candidates[0].reasons.contains("Listening on :3000 with no connections"))
    }

    func testConnectedServerIsNotAnIdleServer() {
        let server = proc(name: "node", path: "/usr/local/bin/node", footprint: 100_000_000, ports: [3000], connections: 1, age: 3 * 3600)
        let report = MemoryAdvisor.advise(input([server]))
        XCTAssertEqual(report.candidates[0].tier, .optional)
        XCTAssertFalse(report.candidates[0].reasons.contains { $0.contains("Listening on :3000") })
    }

    func testYoungIdleServerIsOptional() {
        let server = proc(name: "node", path: "/usr/local/bin/node", footprint: 300_000_000, ports: [3000], age: 600)
        let report = MemoryAdvisor.advise(input([server]))
        XCTAssertEqual(report.candidates[0].tier, .optional)
        XCTAssertEqual(report.candidates[0].note, "Started recently — you may still be using it")
    }

    func testFrequentlyUsedAppSmallKeptLargeOptional() {
        let small = proc(name: "Slack", path: "/Applications/Slack.app/Contents/MacOS/Slack", footprint: 600_000_000)
        let large = proc(name: "Teams", path: "/Applications/Teams.app/Contents/MacOS/Teams", footprint: 1_500_000_000)
        var info = input([small, large])
        info.apps[small.second.pid] = app(small.second.pid, id: "com.vendor.slack", name: "Slack", path: "/Applications/Slack.app")
        info.apps[large.second.pid] = app(large.second.pid, id: "com.vendor.teams", name: "Teams", path: "/Applications/Teams.app")
        let launches = (0..<4).map { now.addingTimeInterval(-Double($0) * 86_400) }
        info.usage["com.vendor.slack"] = AppUsage(recentLaunches: launches, lastActivated: now.addingTimeInterval(-3600))
        info.usage["com.vendor.teams"] = AppUsage(spotlightUseCount: 60, spotlightLastUsed: now.addingTimeInterval(-86_400),
                                                  recentLaunches: launches)
        let report = MemoryAdvisor.advise(info)
        XCTAssertEqual(report.candidates.count, 1)
        XCTAssertEqual(report.candidates[0].name, "Teams")
        XCTAssertEqual(report.candidates[0].tier, .optional)
        XCTAssertEqual(report.candidates[0].note,
                       "You use this often. Quitting means relaunching it soon, which costs more energy than keeping it — macOS compresses its idle memory.")
        XCTAssertTrue(report.kept.contains { $0.name == "Slack" && $0.reason.hasPrefix("Used often") })
    }

    func testRarelyUsedIdleHiddenAppIsRecommended() {
        let appProc = proc(name: "Board", path: "/Applications/Board.app/Contents/MacOS/Board", footprint: 800_000_000)
        var info = input([appProc])
        info.apps[appProc.second.pid] = app(appProc.second.pid, id: "com.vendor.board", name: "Board", path: "/Applications/Board.app")
        info.usage["com.vendor.board"] = AppUsage(spotlightUseCount: 3, spotlightLastUsed: now.addingTimeInterval(-9 * 86_400))
        let report = MemoryAdvisor.advise(info)
        XCTAssertEqual(report.candidates[0].tier, .recommended)
        XCTAssertTrue(report.candidates[0].reasons.contains("Not opened in 9 days"))
    }

    func testAccessoryAppIsNeverRecommended() {
        let menubar = proc(name: "VPN", path: "/Applications/VPN.app/Contents/MacOS/VPN", footprint: 2_000_000_000)
        var info = input([menubar])
        info.apps[menubar.second.pid] = app(menubar.second.pid, id: "com.vendor.vpn", name: "VPN", path: "/Applications/VPN.app", policy: .accessory)
        let candidate = MemoryAdvisor.advise(info).candidates[0]
        XCTAssertEqual(candidate.tier, .optional)
        XCTAssertTrue(candidate.note?.contains("menu bar") == true)
    }

    func testLaunchdJobsKeepAliveKeptPlainOptional() {
        let alive = proc(name: "agent", path: "/opt/agent/bin/agent", footprint: 300_000_000)
        let plain = proc(name: "worker", path: "/opt/worker/bin/worker", footprint: 300_000_000)
        var info = input([alive, plain])
        info.launchdJobs[alive.second.pid] = LaunchdJob(label: "com.vendor.agent", keepAlive: true)
        info.launchdJobs[plain.second.pid] = LaunchdJob(label: "com.vendor.worker", keepAlive: false)
        let report = MemoryAdvisor.advise(info)
        XCTAssertTrue(report.kept.contains { $0.name == "agent" && $0.reason.contains("Restarts automatically") })
        XCTAssertEqual(report.candidates[0].name, "worker")
        XCTAssertEqual(report.candidates[0].tier, .optional)
        XCTAssertTrue(report.candidates[0].note?.contains("launchd") == true)
    }

    func testRecentlyStoppedAndBackAgainIsKept() {
        let tool = proc(name: "tool", path: "/opt/tool/bin/tool", footprint: 300_000_000, age: 600)
        let entry = MemoryJournalEntry(date: now.addingTimeInterval(-3600), name: "tool", path: "/opt/tool/bin/tool",
                                     bundleID: nil, footprint: 300_000_000, outcome: "stopped", forced: false)
        let report = MemoryAdvisor.advise(input([tool], stopped: [entry]))
        XCTAssertTrue(report.kept.contains { $0.reason.contains("Came back") })
        XCTAssertTrue(report.candidates.isEmpty)
    }

    func testFrontmostAppIsKept() {
        let front = proc(name: "Editor", path: "/Applications/Editor.app/Contents/MacOS/Editor", footprint: 2_000_000_000)
        var info = input([front])
        info.apps[front.second.pid] = app(front.second.pid, name: "Editor", path: "/Applications/Editor.app", active: true, windows: 3)
        let report = MemoryAdvisor.advise(info)
        XCTAssertTrue(report.candidates.isEmpty)
        XCTAssertEqual(report.kept[0].reason, "In use right now")
    }

    func testSmallProcessesRollIntoCount() {
        let tiny = proc(name: "tiny", footprint: 20_000_000)
        let big = proc(name: "big", footprint: 200_000_000)
        let report = MemoryAdvisor.advise(input([tiny, big]))
        XCTAssertEqual(report.candidates.count, 1)
        XCTAssertEqual(report.smallProcessCount, 1)
        XCTAssertEqual(report.smallProcessBytes, 20_000_000)
    }

    func testProcessesMustMatchInBothSamples() {
        let stable = proc(name: "stable", footprint: 300_000_000)
        let gone = proc(name: "gone", path: "/opt/x/gone", footprint: 300_000_000)
        var reborn = proc(name: "reborn", path: "/opt/x/reborn", footprint: 300_000_000)
        reborn.first.identity.startSeconds += 30 // same pid, different process: excluded
        var info = input([stable, gone])
        info.second.removeAll { $0.pid == gone.second.pid } // exited between samples: excluded
        info.second.append(reborn.second)
        info.first.append(reborn.first)
        let report = MemoryAdvisor.advise(info)
        XCTAssertEqual(report.candidates.map(\.name), ["stable"])
    }

    func testBackgroundBusyIsRecommendedWithEnergyNote() {
        let busy = proc(name: "Sync", path: "/Applications/Sync.app/Contents/MacOS/Sync",
                        footprint: 100_000_000, cpuDelta: 200_000_000) // 10% of a core over 2 s
        var info = input([busy])
        info.apps[busy.second.pid] = app(busy.second.pid, id: "com.vendor.sync", name: "Sync", path: "/Applications/Sync.app", windows: 0)
        let candidate = MemoryAdvisor.advise(info).candidates[0]
        XCTAssertEqual(candidate.tier, .recommended)
        XCTAssertEqual(candidate.note, "Busy in the background — stopping it also saves battery")
        XCTAssertEqual(candidate.cpuPercent, 10, accuracy: 0.01)
    }

    func testDefaultSelectionDependsOnPressure() {
        let idle = proc(name: "tool", footprint: 300_000_000, age: 10 * 86_400)
        var normal = MemoryAdvisor.advise(input([idle], pressure: .normal))
        XCTAssertTrue(normal.defaultSelection.isEmpty)
        normal.status = MemoryStatus(total: 1, used: 1, wired: 0, compressed: 0, cached: 0, free: 0, swapUsed: 0, pressure: .normal)
        XCTAssertTrue(normal.defaultSelection.isEmpty)
        var warning = MemoryAdvisor.advise(input([idle], pressure: .warning))
        warning.status = MemoryStatus(total: 1, used: 1, wired: 0, compressed: 0, cached: 0, free: 0, swapUsed: 0, pressure: .warning)
        XCTAssertEqual(warning.defaultSelection, [idle.second.pid])
    }

    func testCpuAndWakeupRatesComeFromDeltas() {
        let pair = proc(cpuDelta: 400_000_000, wakeDelta: 120) // 20% of a core, 60 wake-ups/s over 2 s
        let candidate = MemoryAdvisor.advise(input([pair])).candidates[0]
        XCTAssertEqual(candidate.cpuPercent, 20, accuracy: 0.01)
        XCTAssertEqual(candidate.wakeupsPerSecond, 60, accuracy: 0.01)
        XCTAssertEqual(candidate.tier, .recommended, "20% CPU with no windows is background-busy")
    }

    func testBusyVisibleAppIsOnlyOptional() {
        let busy = proc(name: "Browser", path: "/Applications/Browser.app/Contents/MacOS/Browser",
                        footprint: 2_000_000_000, cpuDelta: 200_000_000)
        var info = input([busy])
        info.apps[busy.second.pid] = app(busy.second.pid, id: "com.vendor.browser", name: "Browser",
                                         path: "/Applications/Browser.app", active: false, hidden: false, windows: 2)
        let candidate = MemoryAdvisor.advise(info).candidates[0]
        XCTAssertEqual(candidate.tier, .optional, "Busy or not, an app with visible windows is never recommended")
        XCTAssertEqual(candidate.note, "Has open windows — you may be working in it")
    }

    func testBusyDormantAppIsRecommended() {
        let busy = proc(name: "Sync", path: "/Applications/Sync.app/Contents/MacOS/Sync",
                        footprint: 400_000_000, cpuDelta: 400_000_000, connections: 0)
        var info = input([busy])
        info.apps[busy.second.pid] = app(busy.second.pid, id: "com.vendor.sync2", name: "Sync",
                                         path: "/Applications/Sync.app", hidden: true, windows: 0)
        let candidate = MemoryAdvisor.advise(info).candidates[0]
        XCTAssertEqual(candidate.tier, .recommended)
        XCTAssertEqual(candidate.note, "Busy in the background — stopping it also saves battery")
    }

    func testAppWithConnectionsIsOnlyOptional() {
        let busy = proc(name: "Call", path: "/Applications/Call.app/Contents/MacOS/Call",
                        footprint: 400_000_000, cpuDelta: 400_000_000, connections: 2)
        var info = input([busy])
        info.apps[busy.second.pid] = app(busy.second.pid, id: "com.vendor.call", name: "Call",
                                         path: "/Applications/Call.app", hidden: true, windows: 0)
        let candidate = MemoryAdvisor.advise(info).candidates[0]
        XCTAssertEqual(candidate.tier, .optional)
        XCTAssertEqual(candidate.note, "Has active network connections — it may be syncing, downloading, or in a call")
    }

    func testBundleGroupWithoutRunningAppIsAProcess() {
        let updater = proc(name: "updater", path: "/Applications/Foo.app/Contents/Library/updater", footprint: 300_000_000)
        let report = MemoryAdvisor.advise(input([updater]))
        let candidate = report.candidates[0]
        XCTAssertEqual(candidate.kind, .process)
        XCTAssertEqual(candidate.tier, .optional)
        XCTAssertEqual(candidate.note, "Runs from inside Foo; Viper couldn't confirm what it does")
    }

    func testSkippedJournalEntryDoesNotSuppress() {
        let tool = proc(name: "tool", path: "/opt/tool/bin/tool", footprint: 300_000_000)
        let entry = MemoryJournalEntry(date: now.addingTimeInterval(-3600), name: "tool", path: "/opt/tool/bin/tool",
                                     bundleID: nil, footprint: 300_000_000, outcome: "skipped", forced: false)
        let report = MemoryAdvisor.advise(input([tool], stopped: [entry]))
        XCTAssertEqual(report.candidates.count, 1)
    }

    func testStoppedEntrySuppressesOnlyIfProcessRestarted() {
        let entry = MemoryJournalEntry(date: now.addingTimeInterval(-3600), name: "tool", path: "/opt/tool/bin/tool",
                                     bundleID: nil, footprint: 300_000_000, outcome: "stopped", forced: false)
        let restarted = proc(name: "tool", path: "/opt/tool/bin/tool", footprint: 300_000_000, age: 600)
        let stillSame = proc(name: "tool", path: "/opt/tool/bin/tool", footprint: 300_000_000, age: 7200)
        let restartedApp = proc(name: "App", path: "/Applications/App.app/Contents/MacOS/App", footprint: 300_000_000, age: 600)

        let back = input([restarted], stopped: [entry])
        XCTAssertTrue(MemoryAdvisor.advise(back).kept.contains { $0.reason.contains("something restarts it") })

        var appInfo = input([restartedApp], stopped: [
            MemoryJournalEntry(date: now.addingTimeInterval(-3600), name: "App", path: "/Applications/App.app/Contents/MacOS/App",
                               bundleID: "com.vendor.app", footprint: 300_000_000, outcome: "stopped", forced: false)])
        appInfo.apps[restartedApp.second.pid] = app(restartedApp.second.pid, name: "App", path: "/Applications/App.app")
        XCTAssertTrue(MemoryAdvisor.advise(appInfo).kept.contains { $0.reason.hasPrefix("You reopened it after Viper quit it") })

        // Started before the stop was logged: it never died, so it isn't "back".
        let report = MemoryAdvisor.advise(input([stillSame], stopped: [entry]))
        XCTAssertEqual(report.candidates.count, 1, "A stop logged after this process started can't be its resurrection")
    }

    func testLiveSampleOnlyReturnsOwnProcesses() {
        let (processes, _) = ProcessInventory.sample()
        XCTAssertFalse(processes.isEmpty)
        XCTAssertTrue(processes.allSatisfy { $0.uid == getuid() })
        XCTAssertNotNil(ProcessInventory.identity(of: getpid()))
    }
}
