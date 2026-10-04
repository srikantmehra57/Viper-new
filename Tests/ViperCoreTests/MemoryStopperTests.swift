import Darwin
import XCTest
@testable import ViperCore

final class MemoryStopperTests: XCTestCase {
    private func candidate(_ pid: Int32, path: String = "/bin/sleep", footprint: UInt64 = 1_000_000) -> MemoryCandidate {
        let identity = ProcessInventory.identity(of: pid) ?? ProcessIdentity(pid: pid, startSeconds: 0, startMicroseconds: 0, path: path)
        return MemoryCandidate(rootPID: pid, name: "sleep", kind: .process, bundlePath: nil, members: [identity],
                               footprint: footprint, cpuPercent: 0, wakeupsPerSecond: 0, listeningPorts: [],
                               establishedConnections: 0, age: 0, hasTerminal: false, usage: nil,
                               tier: .recommended, reasons: [], note: nil)
    }

    private func sleepProcess() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        return process
    }

    /// A spawned sleep stops gracefully and reports what it freed.
    func testGracefulStopOfRealProcess() async throws {
        let process = try sleepProcess()
        defer { if process.isRunning { process.terminate() } }
        let outcome = await MemoryStopper.stop(candidate(process.processIdentifier), force: false,
                                               quitApp: { _, _ in false }, isAllowed: { _ in nil }, wait: 10)
        guard case .stopped(let freed) = outcome.result else {
            XCTFail("expected .stopped, got \(outcome.result)")
            return
        }
        XCTAssertEqual(freed, 1_000_000)
        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
    }

    /// A recycled pid (same pid, different start time) is skipped and the real process untouched.
    func testChangedIdentityIsSkipped() async throws {
        let process = try sleepProcess()
        defer { if process.isRunning { process.terminate() } }
        var changed = candidate(process.processIdentifier)
        changed.members[0].startSeconds += 120
        let outcome = await MemoryStopper.stop(changed, force: false, quitApp: { _, _ in false }, isAllowed: { _ in nil })
        guard case .skipped = outcome.result else {
            XCTFail("expected .skipped, got \(outcome.result)")
            return
        }
        XCTAssertTrue(process.isRunning)
        XCTAssertNotNil(ProcessInventory.identity(of: process.processIdentifier))
    }

    /// isAllowed has the last word before any signal.
    func testRefusalSkipsWithoutSignalling() async {
        let box = Box<Bool>(false)
        let outcome = await MemoryStopper.stop(candidate(424242), force: false,
                                               quitApp: { _, _ in true }, isAllowed: { _ in "In use right now" },
                                               identityOf: { _ in nil }, isOurs: { _ in true },
                                               signal: { _, _ in box.value = true })
        guard case .skipped(let reason) = outcome.result else {
            XCTFail("expected .skipped, got \(outcome.result)")
            return
        }
        XCTAssertEqual(reason, "In use right now")
        XCTAssertFalse(box.value)
    }

    /// A fake table: members that survive the signal are reported for the force-quit offer.
    func testSurvivorsAreReportedForForceQuit() async {
        let root = ProcessIdentity(pid: 9001, startSeconds: 10, startMicroseconds: 0, path: "/opt/t/t")
        let members = [root, ProcessIdentity(pid: 9002, startSeconds: 10, startMicroseconds: 0, path: "/opt/t/child")]
        var candidate = candidate(9001)
        candidate.members = members
        let dead = Box<Set<Int32>>([])
        let outcome = await MemoryStopper.stop(candidate, force: false, quitApp: { _, _ in true }, isAllowed: { _ in nil }, wait: 0.3,
                                               identityOf: { pid in dead.value.contains(pid) ? nil : members.first { $0.pid == pid } },
                                               isOurs: { _ in true },
                                               signal: { pid, _ in if pid == 9001 { dead.value.insert(pid) } }) // 9002 ignores the signal
        guard case .stillRunning(let remaining) = outcome.result else {
            XCTFail("expected .stillRunning, got \(outcome.result)")
            return
        }
        XCTAssertEqual(remaining.map(\.pid), [9002])
    }

    /// An app object that can't be reached still gets a signal on its verified members.
    func testAppFallsBackToSignalWhenQuitAppFails() async {
        let root = ProcessIdentity(pid: 9100, startSeconds: 10, startMicroseconds: 0, path: "/Applications/Stub.app/Contents/MacOS/Stub")
        var candidate = candidate(9100)
        candidate.kind = .app(bundleID: "com.vendor.stub")
        candidate.members = [root]
        let signals = Box<[(Int32, Int32)]>([])
        let outcome = await MemoryStopper.stop(candidate, force: false, quitApp: { _, _ in false }, isAllowed: { _ in nil }, wait: 0.2,
                                               identityOf: { pid in signals.value.contains { $0.0 == pid } ? nil : root },
                                               isOurs: { _ in true },
                                               signal: { pid, code in signals.value.append((pid, code)) })
        XCTAssertEqual(signals.value.map(\.1), [SIGTERM])
        guard case .stopped = outcome.result else {
            XCTFail("expected .stopped, got \(outcome.result)")
            return
        }
    }
}

private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
