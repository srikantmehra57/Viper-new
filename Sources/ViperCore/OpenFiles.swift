import Darwin
import Foundation

/// Paths currently held open by processes on this Mac. Used so cleanup will not take a file an app is using.
public enum OpenFiles {
    /// True when any process has this file open, or has something open inside this folder.
    public static func isInUse(_ url: URL) -> Bool {
        let prefix = canonical(url.path)
        for path in openPaths() {
            if path == prefix || path.hasPrefix(prefix + "/") { return true }
        }
        return false
    }

    private static func openPaths() -> [String] {
        var paths: [String] = []
        for pid in allPIDs() {
            var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: 512)
            let wrote = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(descriptors.count * MemoryLayout<proc_fdinfo>.size))
            guard wrote > 0 else { continue }
            let count = min(descriptors.count, Int(wrote) / MemoryLayout<proc_fdinfo>.size)
            for descriptor in descriptors.prefix(count) where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
                var info = vnode_fdinfowithpath()
                let got = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, Int32(MemoryLayout<vnode_fdinfowithpath>.size))
                guard got > 0 else { continue }
                let path = withUnsafePointer(to: &info.pvip.vip_path) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                }
                if !path.isEmpty { paths.append(canonical(path)) }
            }
        }
        return paths
    }

    static func allPIDs() -> [pid_t] {
        var capacity = 512
        while capacity <= 16_384 {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let wrote = proc_listallpids(&buffer, Int32(capacity * MemoryLayout<pid_t>.size))
            guard wrote > 0 else { return [] }
            // Unlike proc_listpids, proc_listallpids returns a pid count, not a byte count.
            if Int(wrote) < capacity { return Array(buffer.prefix(Int(wrote))).filter { $0 > 1 } }
            capacity *= 2
        }
        return []
    }

    private static func canonical(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return path }
        return String(cString: buffer)
    }
}
