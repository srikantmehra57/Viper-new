import Foundation

/// The command search path the user's own shell uses, so Viper finds and labels the same tools Terminal runs.
/// Reading it starts the shell once, non-interactively for input, with a short timeout; nothing is changed.
public enum ShellEnvironment {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedPath: [String] = []

    public static var path: [String] { lock.withLock { cachedPath } }

    public static func refresh() async {
        let requested = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shell = ["/bin/zsh", "/bin/bash"].contains(requested) ? requested : "/bin/zsh"
        let marker = "__VIPER_PATH__"
        // -i reads the rc files where PATH is usually extended (~/.zshrc), -l the login profile.
        guard let output = try? await CommandRunner.run(URL(fileURLWithPath: shell),
                                                        arguments: ["-ilc", "printf '\\n\(marker)%s\(marker)\\n' \"$PATH\""], timeout: 8),
              output.status == 0 else { return }
        let parsed = parse(String(decoding: output.data, as: UTF8.self), marker: marker)
        guard !parsed.isEmpty else { return }
        lock.withLock { cachedPath = parsed }
    }

    static func parse(_ text: String, marker: String) -> [String] {
        let parts = text.components(separatedBy: marker)
        guard parts.count >= 3 else { return [] }
        var seen = Set<String>()
        return parts[1].split(separator: ":").map(String.init).filter { entry in
            entry.hasPrefix("/") && entry.count < 1_024 && seen.insert(entry).inserted
        }
    }

    /// The executable Terminal would run for `command`, from the cached shell PATH.
    public static func resolve(_ command: String, in path: [String] = ShellEnvironment.path) -> URL? {
        for folder in path {
            let candidate = URL(fileURLWithPath: folder).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Whether `executable` is the same file Terminal runs for its command name (following symlinks).
    public static func isTerminalDefault(_ executable: URL) -> Bool? {
        guard !path.isEmpty, let resolved = resolve(executable.lastPathComponent) else { return nil }
        return resolved.resolvingSymlinksInPath().standardizedFileURL == executable.resolvingSymlinksInPath().standardizedFileURL
    }
}

extension PackageRuntime {
    /// nil when the shell PATH hasn't been read.
    public var isTerminalDefault: Bool? { ShellEnvironment.isTerminalDefault(executable) }
}
