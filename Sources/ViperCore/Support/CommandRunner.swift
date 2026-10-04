import Foundation
import Darwin

public struct CommandOutput: Sendable {
    public let status: Int32
    public let data: Data
    public var errors = Data()
}

public enum CommandError: LocalizedError {
    case timeout, outputLimit, failed, unsafeExecutable, unsettled
    public var errorDescription: String? {
        switch self {
        case .timeout: return "The source took too long to respond. Try again later."
        case .outputLimit: return "The source returned more data than Viper can safely process."
        case .failed: return "The source could not complete the request. Check your connection and package-manager setup."
        case .unsafeExecutable: return "The package-manager executable changed, is linked unsafely, or is no longer executable. Refresh and review it again."
        case .unsettled: return "Viper tried to stop the operation, but part of it may still be running. Check the package manager before trying again."
        }
    }
}

public enum CommandRunner {
    /// Fixed executable plus argument array; never runs a shell command string.
    /// `includeErrors` captures diagnostic output separately for operations whose result is explained to the user.
    /// `onOutput` receives new output while the command runs, for live progress. It never changes what is returned.
    public static func run(_ executable: URL, arguments: [String], timeout: TimeInterval = 75, includeErrors: Bool = false,
                           environment extra: [String: String] = [:], onOutput: (@Sendable (String) -> Void)? = nil) async throws -> CommandOutput {
        try Task.checkCancellation()
        let manager = FileManager.default
        let resolvedExecutable = executable.resolvingSymlinksInPath().standardizedFileURL
        guard manager.isExecutableFile(atPath: resolvedExecutable.path), let executableIdentity = FileIdentity.read(resolvedExecutable) else {
            throw CommandError.unsafeExecutable
        }
        let folder = manager.temporaryDirectory.appendingPathComponent("viper-process-\(UUID().uuidString)")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: folder) }
        let output = folder.appendingPathComponent("output")
        manager.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let errorOutput = folder.appendingPathComponent("errors")
        manager.createFile(atPath: errorOutput.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let errorHandle = try FileHandle(forWritingTo: errorOutput)
        defer { try? errorHandle.close() }
        let discardedErrors: Int32 = includeErrors ? -1 : open("/dev/null", O_WRONLY)
        defer { if discardedErrors >= 0 { close(discardedErrors) } }
        let stderr = includeErrors ? errorHandle.fileDescriptor : discardedErrors
        guard stderr >= 0 else { throw CommandError.failed }
        let inherited = ProcessInfo.processInfo.environment
        // SSH_AUTH_SOCK is intentionally absent: install scripts must not receive the user's SSH agent.
        let allowedKeys = ["HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TERM",
                           "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy",
                           "SSL_CERT_FILE", "SSL_CERT_DIR"]
        var env = Dictionary(uniqueKeysWithValues: allowedKeys.compactMap { key in inherited[key].map { (key, $0) } })
        env["PATH"] = executable.deletingLastPathComponent().path + ":" + resolvedExecutable.deletingLastPathComponent().path
            + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["npm_config_update_notifier"] = "false"
        env["npm_config_audit"] = "false"
        env["npm_config_fund"] = "false"
        for (key, value) in extra where key.hasPrefix("npm_config_") || key.hasPrefix("HOMEBREW_") { env[key] = value }
        // Pin the exact resolved executable from review through launch.
        guard FileIdentity.read(resolvedExecutable) == executableIdentity else { throw CommandError.unsafeExecutable }
        let child = try spawn(resolvedExecutable, arguments: arguments, environment: env, directory: folder,
                              stdout: handle.fileDescriptor, stderr: stderr)
        let watcher = Task.detached(priority: .userInitiated) {
            while child.status == nil && !Task.isCancelled {
                child.rememberTree()
                try? await Task.sleep(nanoseconds: 15_000_000)
            }
            child.rememberTree()
        }
        let deadline = Date().addingTimeInterval(timeout)
        var offsets = [output: UInt64(0), errorOutput: UInt64(0)]
        func streamNewOutput() {
            guard let onOutput else { return }
            for file in [output, errorOutput] {
                guard let reader = try? FileHandle(forReadingFrom: file) else { continue }
                defer { try? reader.close() }
                let start = offsets[file] ?? 0
                guard (try? reader.seek(toOffset: start)) != nil, let chunk = try? reader.read(upToCount: 256_000), !chunk.isEmpty else { continue }
                offsets[file] = start + UInt64(chunk.count)
                onOutput(String(decoding: chunk, as: UTF8.self))
            }
        }
        do {
            while child.status == nil {
                child.poll()
                if child.status != nil { break }
                streamNewOutput()
                try Task.checkCancellation()
                guard Date() < deadline else { throw CommandError.timeout }
                let size = [output, errorOutput].reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                guard size <= 8_000_000 else { throw CommandError.outputLimit }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        } catch {
            watcher.cancel()
            let settled = await child.stop()
            if !settled { throw CommandError.unsettled }
            throw error
        }
        watcher.cancel()
        streamNewOutput()
        try Task.checkCancellation()
        let data = try Data(contentsOf: output)
        let errors = try Data(contentsOf: errorOutput)
        guard data.count + errors.count <= 8_000_000 else { throw CommandError.outputLimit }
        return .init(status: child.status ?? -1, data: data, errors: errors)
    }

    /// Starts the command in its own process group before it can fork, so a timeout can signal the whole tree.
    private static func spawn(_ executable: URL, arguments: [String], environment: [String: String], directory: URL, stdout: Int32, stderr: Int32) throws -> SpawnedCommand {
        var attr: posix_spawnattr_t?
        guard posix_spawnattr_init(&attr) == 0 else { throw CommandError.failed }
        defer { posix_spawnattr_destroy(&attr) }
        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
        guard posix_spawnattr_setflags(&attr, flags) == 0, posix_spawnattr_setpgroup(&attr, 0) == 0 else { throw CommandError.failed }

        let devnull = open("/dev/null", O_RDONLY)
        guard devnull >= 0 else { throw CommandError.failed }
        defer { close(devnull) }
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw CommandError.failed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_adddup2(&actions, devnull, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stdout, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stderr, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, directory.path) == 0 else { throw CommandError.failed }

        var pid: pid_t = 0
        let code = withCStrings([executable.path] + arguments) { argv in
            withCStrings(environment.map { "\($0.key)=\($0.value)" }) { envp in
                posix_spawn(&pid, executable.path, &actions, &attr, argv, envp)
            }
        }
        guard code == 0, pid > 0 else { throw CommandError.failed }
        return SpawnedCommand(pid: pid, ownsProcessGroup: getpgid(pid) == pid)
    }

    private static func withCStrings<T>(_ strings: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> T) -> T {
        let pointers = strings.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        let buffer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: pointers.count + 1)
        defer { buffer.deallocate() }
        for (index, pointer) in pointers.enumerated() { buffer[index] = pointer }
        buffer[pointers.count] = nil
        return body(buffer)
    }
}

/// One launched command. The process group is created by posix_spawn, before the command can fork.
private final class SpawnedCommand: @unchecked Sendable {
    let pid: pid_t
    let ownsProcessGroup: Bool
    /// Wall-clock second the process was spawned. Recorded children started earlier are not killed.
    let startedAt: UInt64
    private let lock = NSLock()
    private var statusStorage: Int32?
    private var seenPIDs = Set<pid_t>()
    var status: Int32? { lock.withLock { statusStorage } }

    init(pid: pid_t, ownsProcessGroup: Bool) {
        self.pid = pid
        self.ownsProcessGroup = ownsProcessGroup
        startedAt = UInt64(time(nil))
    }

    func poll() {
        rememberTree()
        guard status == nil else { return }
        var raw: Int32 = 0
        let result = waitpid(pid, &raw, WNOHANG)
        if result == pid { lock.withLock { statusStorage = Self.exitCode(raw) } }
    }

    /// Records descendants, including ones that later leave the group, so a later stop can still signal them.
    func rememberTree() {
        var found = ProcessTree.descendants(of: pid)
        let prior = lock.withLock { seenPIDs }
        for old in prior { found.formUnion(ProcessTree.descendants(of: old)) }
        lock.withLock { seenPIDs.formUnion(found) }
    }

    /// Signals the process group and every descendant seen while the command ran.
    /// Returns false when a recorded descendant is still alive after that attempt.
    func stop() async -> Bool {
        rememberTree()
        var known = lock.withLock { seenPIDs }
        func signalTree(_ code: Int32) {
            rememberTree()
            known.formUnion(lock.withLock { seenPIDs })
            let current = ProcessTree.descendants(of: pid)
            for child in known.union(current) where child > 1 && child != pid {
                let orphan = !current.contains(child)
                if orphan && !ProcessTree.born(after: startedAt, pid: child) { continue }
                kill(child, code)
            }
            signal(code)
        }
        signalTree(SIGTERM)
        for _ in 0..<10 {
            poll()
            if finished && ProcessTree.alive(targets(in: known)).isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        signalTree(SIGKILL)
        if status == nil {
            while true {
                var raw: Int32 = 0
                let result = waitpid(pid, &raw, 0)
                if result == pid {
                    lock.withLock { statusStorage = Self.exitCode(raw) }
                    break
                }
                if result == -1 && errno == EINTR { continue }
                break
            }
        }
        for _ in 0..<4 {
            if ProcessTree.alive(targets(in: known)).isEmpty { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
            known.formUnion(ProcessTree.descendants(of: pid))
            signalTree(SIGKILL)
        }
        return ProcessTree.alive(targets(in: known)).isEmpty
    }

    /// Descendants we are willing to signal. Orphans must have started with this command.
    private func targets(in known: Set<pid_t>) -> [pid_t] {
        let current = ProcessTree.descendants(of: pid)
        return known.union(current).filter { child in
            child > 1 && child != pid && (current.contains(child) || ProcessTree.born(after: startedAt, pid: child))
        }
    }

    private var finished: Bool { status != nil }

    private func signal(_ code: Int32) {
        if ownsProcessGroup { kill(-pid, code) } else { kill(pid, code) }
    }

    /// Darwin's wait status macros are function-like and are not visible to Swift.
    private static func exitCode(_ raw: Int32) -> Int32 {
        let waited = raw & 127
        if waited == 0 { return (raw >> 8) & 0xff }
        if waited != 0o177 { return waited }
        return raw
    }
}

/// Child processes of one command. A new session is still a child until its parent exits, so it can be signalled directly.
private enum ProcessTree {
    static func descendants(of root: pid_t) -> Set<pid_t> {
        var result = Set<pid_t>()
        var pending = childPIDs(of: root)
        while let next = pending.popLast() {
            guard next > 1, result.insert(next).inserted else { continue }
            pending.append(contentsOf: childPIDs(of: next))
        }
        return result
    }

    static func alive(_ pids: some Sequence<pid_t>) -> [pid_t] {
        pids.filter { $0 > 1 && kill($0, 0) == 0 }
    }

    /// False when the process is gone or started before this command. Avoids killing a recycled pid.
    static func born(after threshold: UInt64, pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let wrote = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard wrote == MemoryLayout<proc_bsdinfo>.size else { return false }
        return info.pbi_start_tvsec + 2 >= threshold
    }

    /// `proc_listchildpids` reports a pid count on current macOS and a byte count on some older releases.
    private static func childPIDs(of parent: pid_t) -> [pid_t] {
        guard parent > 1 else { return [] }
        var capacity = 32
        while capacity <= 4_096 {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let written = proc_listchildpids(parent, &buffer, Int32(capacity * MemoryLayout<pid_t>.size))
            guard written > 0 else { return [] }
            if written < capacity {
                return Array(buffer.prefix(Int(written))).filter { $0 > 0 }
            }
            let byteCount = Int(written) / MemoryLayout<pid_t>.size
            if byteCount > 0 && byteCount < capacity {
                return Array(buffer.prefix(byteCount)).filter { $0 > 0 }
            }
            capacity *= 2
        }
        return []
    }
}
