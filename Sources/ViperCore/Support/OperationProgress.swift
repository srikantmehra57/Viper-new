import Foundation

/// Live progress for a package-manager install or update, derived from the manager's own output.
public struct OperationProgress: Equatable, Sendable {
    public enum Phase: Int, CaseIterable, Comparable, Sendable {
        case preparing, downloading, installing, verifying

        public var title: String {
            switch self {
            case .preparing: return "Preparing"
            case .downloading: return "Downloading"
            case .installing: return "Installing"
            case .verifying: return "Verifying"
            }
        }
        public static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var phase: Phase
    /// Download completion reported by the package manager, when it reports one. Nil means unknown, never zero.
    public var downloadFraction: Double?
    /// The most recent meaningful line of output, for display.
    public var detail: String
    /// Bytes written so far to the package manager's in-progress download, when Viper can observe it.
    public var downloadedBytes: Int64?

    public init(phase: Phase, downloadFraction: Double? = nil, detail: String = "", downloadedBytes: Int64? = nil) {
        self.phase = phase
        self.downloadFraction = downloadFraction
        self.detail = detail
        self.downloadedBytes = downloadedBytes
    }

    /// An estimate of overall completion that only moves forward. Download percentages refine it when available.
    public var overallFraction: Double {
        switch phase {
        case .preparing: return 0.06
        case .downloading: return 0.14 + 0.5 * (downloadFraction ?? 0.2)
        case .installing: return 0.72
        case .verifying: return 0.92
        }
    }
}

/// Turns Homebrew and npm output into progress. Unknown lines never move progress backwards.
public struct ProgressParser: Sendable {
    public private(set) var progress: OperationProgress
    private var buffer = ""

    public init(start: OperationProgress = .init(phase: .preparing, detail: "Starting the package manager…")) {
        progress = start
    }

    /// Feeds raw output. Returns true when the visible progress changed.
    public mutating func consume(_ text: String) -> Bool {
        let before = progress
        buffer += text
        // curl progress bars redraw with carriage returns, so treat them as line breaks too.
        var lines = buffer.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        buffer = lines.removeLast()
        for line in lines { apply(line) }
        // A partially drawn progress bar still carries a useful percentage.
        if let percent = Self.percentage(in: buffer) { applyPercent(percent) }
        return progress != before
    }

    private mutating func apply(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        if let percent = Self.percentage(in: line), line.contains("#") || line.hasSuffix("%") {
            applyPercent(percent)
            return
        }
        let lower = line.lowercased()
        let text = line.hasPrefix("==> ") ? String(line.dropFirst(4)) : line
        if lower.hasPrefix("==> fetching") || lower.hasPrefix("==> downloading") || lower.contains("http fetch get") {
            advance(to: .downloading, detail: Self.shorten(text))
        } else if lower.hasPrefix("==> pouring") || lower.hasPrefix("==> installing") || lower.hasPrefix("==> upgrading")
                    || lower.hasPrefix("==> moving") || lower.hasPrefix("==> linking") || lower.hasPrefix("==> purging")
                    || lower.hasPrefix("==> uninstalling") || lower.hasPrefix("==> backing") || lower.contains("reify:")
                    || lower.hasPrefix("npm http cache") {
            advance(to: .installing, detail: Self.shorten(text))
        } else if lower.hasPrefix("==> summary") || lower.hasPrefix("==> caveats") || lower.hasPrefix("added ") || lower.hasPrefix("changed ")
                    || lower.hasPrefix("up to date") || lower.contains("🍺") {
            advance(to: .installing, detail: Self.shorten(text))
        }
    }

    private mutating func applyPercent(_ percent: Double) {
        if progress.phase < .downloading { progress.phase = .downloading }
        guard progress.phase == .downloading else { return }
        let fraction = min(1, max(0, percent / 100))
        progress.downloadFraction = max(progress.downloadFraction ?? 0, fraction)
    }

    private mutating func advance(to phase: Phase, detail: String) {
        guard phase >= progress.phase else { return }
        if phase == .downloading && progress.phase == .downloading && detail != progress.detail {
            // A new file started downloading; its own percentage starts fresh.
            progress.downloadFraction = nil
        }
        if phase > progress.phase { progress.downloadFraction = phase == .downloading ? nil : progress.downloadFraction }
        progress.phase = phase
        progress.detail = detail
    }

    public mutating func observeDownload(bytes: Int64) {
        guard progress.phase <= .downloading, bytes > (progress.downloadedBytes ?? 0) else { return }
        progress.phase = .downloading
        progress.downloadedBytes = bytes
    }

    public mutating func markVerifying() {
        progress.phase = .verifying
        progress.detail = "Confirming the installed version…"
    }

    typealias Phase = OperationProgress.Phase

    static func percentage(in line: String) -> Double? {
        guard let range = line.range(of: "([0-9]{1,3}(\\.[0-9])?)%", options: [.regularExpression, .backwards]) else { return nil }
        let value = Double(line[range].dropLast())
        return value.flatMap { $0 <= 100 ? $0 : nil }
    }

    static func shorten(_ text: String) -> String {
        // Hide long URLs and hashes; keep the file or package being handled.
        let words = text.split(separator: " ").map { word -> Substring in
            guard word.contains("://") else { return word }
            return word.split(separator: "/").last ?? word
        }
        let joined = words.joined(separator: " ")
        return joined.count > 90 ? String(joined.prefix(87)) + "…" : joined
    }
}

/// Delivers progress from a background package operation. Called on an arbitrary thread.
public typealias ProgressHandler = @Sendable (OperationProgress) -> Void

/// Thread-safe bridge from streamed output to a progress handler.
final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: ProgressParser
    private let handler: ProgressHandler?

    init(_ handler: ProgressHandler?, start: OperationProgress = .init(phase: .preparing, detail: "Starting the package manager…")) {
        self.handler = handler
        parser = ProgressParser(start: start)
        handler?(start)
    }

    func consume(_ text: String) {
        lock.lock()
        let changed = parser.consume(text)
        let snapshot = parser.progress
        lock.unlock()
        if changed { handler?(snapshot) }
    }

    func set(_ progress: OperationProgress) {
        lock.lock()
        parser = ProgressParser(start: progress)
        lock.unlock()
        handler?(progress)
    }

    func observeDownload(bytes: Int64) {
        lock.lock()
        let before = parser.progress
        parser.observeDownload(bytes: bytes)
        let snapshot = parser.progress
        lock.unlock()
        if snapshot != before { handler?(snapshot) }
    }

    /// Watches Homebrew's download cache for the file being fetched and reports how much has arrived.
    /// Read-only: it only lists file sizes and never touches the cache.
    func watchHomebrewDownloads(since start: Date = Date()) -> Task<Void, Never>? {
        guard handler != nil else { return nil }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Homebrew/downloads")
        return Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
                let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
                let active = files.compactMap { url -> (Date, Int64)? in
                    guard url.pathExtension == "incomplete", let values = try? url.resourceValues(forKeys: Set(keys)),
                          let modified = values.contentModificationDate, modified >= start.addingTimeInterval(-2) else { return nil }
                    return (modified, Int64(values.fileSize ?? 0))
                }.max { $0.0 < $1.0 }
                if let active { self?.observeDownload(bytes: active.1) }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    func verifying() {
        lock.lock()
        parser.markVerifying()
        let snapshot = parser.progress
        lock.unlock()
        handler?(snapshot)
    }
}
