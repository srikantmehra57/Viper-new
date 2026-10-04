import Darwin
import Foundation

/// One outcome of asking a candidate to stop, for the result card and the journal.
public struct MemoryStopOutcome: Identifiable, Sendable {
    public enum Result: Sendable, Equatable {
        case stopped(freedEstimate: UInt64)
        case stillRunning(remaining: [ProcessIdentity])
        case skipped(String)
        case failed(String)

        public var succeeded: Bool {
            if case .stopped = self { return true }
            return false
        }
        public var needsForce: Bool {
            if case .stillRunning = self { return true }
            return false
        }
    }
    public var id = UUID()
    public var candidate: MemoryCandidate
    public var result: Result
    public var date: Date
}

/// Sends the actual stop requests. Graceful first: apps get a normal Quit, processes get SIGTERM.
/// Force (forceTerminate / SIGKILL) happens only when the user explicitly asks for a survivor.
public enum MemoryStopper {
    /// `identityOf` and `signal` are the live process table by default; tests inject a fake one.
    public static func stop(_ candidate: MemoryCandidate, force: Bool,
                            quitApp: @Sendable (Int32, Bool) async -> Bool,
                            isAllowed: @Sendable (MemoryCandidate) async -> String?,
                            wait: TimeInterval = 6,
                            identityOf: @Sendable (Int32) -> ProcessIdentity? = { ProcessInventory.identity(of: $0) },
                            isOurs: @Sendable (Int32) -> Bool = { ProcessInventory.ownedByCurrentUser($0) },
                            signal: @Sendable (Int32, Int32) -> Void = { kill($0, $1) }) async -> MemoryStopOutcome {
        func outcome(_ result: MemoryStopOutcome.Result) -> MemoryStopOutcome {
            MemoryStopOutcome(candidate: candidate, result: result, date: Date())
        }
        if let refusal = await isAllowed(candidate) { return outcome(.skipped(refusal)) }
        // Members that exited on their own are fine; members that no longer match are left alone.
        var verified: [ProcessIdentity] = []
        var rootGone = false
        for member in candidate.members {
            let fresh = identityOf(member.pid)
            if fresh == member, isOurs(member.pid) {
                verified.append(member)
            } else if member.pid == candidate.rootPID, fresh != member {
                rootGone = true
            }
        }
        guard !rootGone else {
            if identityOf(candidate.rootPID) == nil { return outcome(.stopped(freedEstimate: candidate.footprint)) }
            return outcome(.skipped("It changed since the scan, so it was left alone."))
        }
        // An app whose object can't be reached still falls back to a signal on its verified members.
        if case .app = candidate.kind, await quitApp(candidate.rootPID, force) {
        } else {
            for member in verified { signal(member.pid, force ? SIGKILL : SIGTERM) }
        }
        var remaining = verified
        let deadline = Date().addingTimeInterval(wait)
        while !remaining.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
            remaining = remaining.filter { identityOf($0.pid) == $0 && isOurs($0.pid) }
        }
        if remaining.isEmpty { return outcome(.stopped(freedEstimate: candidate.footprint)) }
        return outcome(.stillRunning(remaining: remaining))
    }
}

/// What Viper stopped, and when. Used to notice processes that just come back.
public struct MemoryJournalEntry: Codable, Identifiable, Sendable {
    public var id = UUID()
    public let date: Date
    public let name: String
    public let path: String
    public let bundleID: String?
    public let footprint: UInt64
    public let outcome: String
    public let forced: Bool

    public init(date: Date = Date(), name: String, path: String, bundleID: String?, footprint: UInt64, outcome: String, forced: Bool) {
        self.date = date
        self.name = name
        self.path = path
        self.bundleID = bundleID
        self.footprint = footprint
        self.outcome = outcome
        self.forced = forced
    }
}

/// Outcome log for memory stops, appended like the removal journal.
public enum MemoryJournal {
    public static func load(from url: URL) -> [MemoryJournalEntry] {
        guard let data = try? Data(contentsOf: url), let entries = try? InstallJournal.decoder.decode([MemoryJournalEntry].self, from: data) else { return [] }
        return entries
    }

    /// Keeps the newest entries only, so the journal stays small.
    @discardableResult
    public static func append(_ entry: MemoryJournalEntry, to url: URL, limit: Int = 200) throws -> [MemoryJournalEntry] {
        let entries = Array((try JournalStore.existingArray(MemoryJournalEntry.self, from: url) + [entry]).suffix(limit))
        try InstallJournal.write(entries, to: url)
        return entries
    }
}
