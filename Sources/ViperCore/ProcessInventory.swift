import Darwin
import Foundation

/// A pid plus its start time and path. Pids are recycled, so anything that signals a process
/// must confirm all three still match the sampled process.
public struct ProcessIdentity: Codable, Hashable, Sendable {
    public var pid: Int32
    public var startSeconds: UInt64
    public var startMicroseconds: UInt64
    public var path: String

    public init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, path: String) {
        self.pid = pid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
        self.path = path
    }
}

/// One point-in-time reading of a process owned by the current user.
public struct ProcessSample: Sendable {
    public var identity: ProcessIdentity
    public var pid: Int32 { identity.pid }
    public var ppid: Int32
    public var uid: uid_t
    public var name: String
    public var path: String
    public var startDate: Date
    /// Physical memory footprint, like Activity Monitor's Memory column.
    public var footprint: UInt64
    /// User + system time in nanoseconds. Delta over an interval gives CPU%.
    public var cpuNanoseconds: UInt64
    /// Idle package wake-ups + interrupt wake-ups; a proxy for energy cost while idle.
    public var wakeups: UInt64
    /// True when the process owns a controlling terminal.
    public var hasTerminal: Bool
    public var listeningPorts: [UInt16]
    public var establishedConnections: Int

    public init(identity: ProcessIdentity, ppid: Int32, uid: uid_t, name: String, path: String, startDate: Date,
                footprint: UInt64, cpuNanoseconds: UInt64, wakeups: UInt64, hasTerminal: Bool,
                listeningPorts: [UInt16], establishedConnections: Int) {
        self.identity = identity
        self.ppid = ppid
        self.uid = uid
        self.name = name
        self.path = path
        self.startDate = startDate
        self.footprint = footprint
        self.cpuNanoseconds = cpuNanoseconds
        self.wakeups = wakeups
        self.hasTerminal = hasTerminal
        self.listeningPorts = listeningPorts
        self.establishedConnections = establishedConnections
    }
}

/// Live process table for the memory feature. Read-only; other users' processes are counted, never read.
public enum ProcessInventory {
    /// Processes owned by `uid`. `skippedOtherUsers` counts processes we were allowed to see but not inspect.
    public static func sample(uid: uid_t = getuid()) -> (processes: [ProcessSample], skippedOtherUsers: Int) {
        var processes: [ProcessSample] = []
        var skipped = 0
        for pid in OpenFiles.allPIDs() {
            var info = proc_bsdinfo()
            let wrote = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            guard wrote == MemoryLayout<proc_bsdinfo>.size else { continue }
            guard info.pbi_uid == uid else { skipped += 1; continue }
            let path = self.path(of: pid)
            let name = withUnsafePointer(to: info.pbi_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: info.pbi_name)) { String(cString: $0) }
            }
            var usage = rusage_info_v4()
            var footprint: UInt64 = 0, cpu: UInt64 = 0, wakeups: UInt64 = 0
            let read = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            if read == 0 {
                footprint = usage.ri_phys_footprint
                // On Apple Silicon these are mach absolute time units, not nanoseconds.
                #if arch(arm64)
                cpu = (usage.ri_user_time + usage.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom)
                #else
                cpu = usage.ri_user_time + usage.ri_system_time
                #endif
                wakeups = usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups
            }
            let sockets = self.sockets(of: pid)
            processes.append(ProcessSample(
                identity: ProcessIdentity(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec, path: path),
                ppid: Int32(bitPattern: info.pbi_ppid), uid: info.pbi_uid,
                name: name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name, path: path,
                startDate: Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000),
                footprint: footprint, cpuNanoseconds: cpu, wakeups: wakeups,
                hasTerminal: info.e_tdev != UInt32.max, listeningPorts: sockets.listening, establishedConnections: sockets.established))
        }
        return (processes, skipped)
    }

    /// Fresh identity for a pid-reuse check right before a signal is sent.
    public static func identity(of pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let wrote = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard wrote == MemoryLayout<proc_bsdinfo>.size else { return nil }
        return ProcessIdentity(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec, path: self.path(of: pid))
    }

    /// True while the pid is still owned by the current user; part of the pre-signal identity check.
    public static func ownedByCurrentUser(_ pid: Int32, uid: uid_t = getuid()) -> Bool {
        var info = proc_bsdinfo()
        let wrote = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return wrote == MemoryLayout<proc_bsdinfo>.size && info.pbi_uid == uid
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func path(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    /// Listening TCP ports and established TCP connections, from the process's socket descriptors.
    private static func sockets(of pid: Int32) -> (listening: [UInt16], established: Int) {
        var capacity = 128
        var descriptors: [proc_fdinfo] = []
        while capacity <= 4_096 {
            descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
            let wrote = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(capacity * MemoryLayout<proc_fdinfo>.size))
            guard wrote > 0 else { return ([], 0) }
            let count = Int(wrote) / MemoryLayout<proc_fdinfo>.size
            if count < capacity { descriptors = Array(descriptors.prefix(count)); break }
            capacity *= 2
        }
        var listening: [UInt16] = []
        var established = 0
        for descriptor in descriptors where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let got = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard got == MemoryLayout<socket_fdinfo>.size, info.psi.soi_kind == SOCKINFO_TCP else { continue }
            let tcp = info.psi.soi_proto.pri_tcp
            if tcp.tcpsi_state == TSI_S_LISTEN {
                let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
                if port > 0 { listening.append(port) }
            } else if tcp.tcpsi_state == TSI_S_ESTABLISHED {
                established += 1
            }
        }
        return (listening, established)
    }
}
