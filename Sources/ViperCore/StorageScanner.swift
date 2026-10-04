import Foundation
import Darwin

/// Read-only traversal. The UI owns cancellation and invokes this off the main actor.
public enum StorageScanner {
    public static func scan(
        root: URL,
        excluding excludedFolders: [URL] = [],
        includeHiddenFiles: Bool = true,
        largestFileLimit: Int = 100,
        onProgress: @Sendable (ScanProgress) async -> Void = { _ in }
    ) async throws -> ScanResult {
        let input = root.standardizedFileURL
        let manager = FileManager.default
        let rootValues = try input.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        // The enumerator yields fully resolved paths (/var → /private/var via firmlink), so the root is canonicalized the same way.
        let root = URL(fileURLWithPath: Self.canonicalPath(of: input))
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0 else { throw CocoaError(.fileReadNoPermission) }

        // Error handlers run synchronously on this traversal's executor.
        let errors = ScanErrors()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .fileAllocatedSizeKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let iterator = manager.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: includeHiddenFiles ? [] : [.skipsHiddenFiles],
            errorHandler: { url, _ in errors.record(url.path); return true }
        ) else { throw CocoaError(.fileReadNoPermission) }

        var files = 0
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var categories: [StorageCategory: Int64] = [:]
        var folderTotals: [String: (files: Int, allocated: Int64)] = [:]
        var largest: [StorageFile] = []
        var rootLargest: [StorageFile] = []
        var links = 0
        var cloud = 0
        var duplicates = 0
        var volumes = 0
        var identities = Set<HardLinkIdentity>()
        let excludedPaths = excludedFolders.map { Self.canonicalPath(of: $0.standardizedFileURL) }
        var lastUpdate = ContinuousClock.now

        while let url = iterator.nextObject() as? URL {
            try Task.checkCancellation()
            if excludedPaths.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) {
                iterator.skipDescendants()
                continue
            }
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    links += 1
                    iterator.skipDescendants()
                    continue
                }
                if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded {
                    cloud += 1
                    iterator.skipDescendants()
                    continue
                }
                var info = stat()
                guard lstat(url.path, &info) == 0 else { errors.record(url.path); continue }
                // A second link check handles entries changed after resource-value lookup.
                if (info.st_mode & S_IFMT) == S_IFLNK {
                    links += 1
                    iterator.skipDescendants()
                    continue
                }
                if info.st_dev != rootInfo.st_dev {
                    volumes += 1
                    iterator.skipDescendants()
                    continue
                }
                // lstat is authoritative. Resource values can be missing for a file that is still a regular file.
                guard (info.st_mode & S_IFMT) == S_IFREG else { continue }
                if info.st_nlink > 1 {
                    guard identities.insert(HardLinkIdentity(device: info.st_dev, inode: info.st_ino)).inserted else {
                        duplicates += 1
                        continue
                    }
                }
                let logicalSize = max(0, Int64(info.st_size))
                let allocatedSize = max(0, Int64(info.st_blocks) * 512)
                let prefix = root.path == "/" ? "/" : root.path + "/"
                let relative = String(url.path.dropFirst(prefix.count))
                let category = StorageCategory.classify(url, relativePath: relative)
                files += 1
                logical += logicalSize
                allocated += allocatedSize
                categories[category, default: 0] += allocatedSize
                if relative.contains("/"), let top = relative.split(separator: "/", maxSplits: 1).first {
                    var total = folderTotals[String(top)] ?? (0, 0)
                    total.files += 1
                    total.allocated += allocatedSize
                    folderTotals[String(top)] = total
                }
                let file = StorageFile(url: url, logicalBytes: logicalSize, allocatedBytes: allocatedSize, category: category)
                let resultLimit = min(max(largestFileLimit, 1), 5_000)
                insertLargest(file, into: &largest, limit: resultLimit)
                if !relative.contains("/") { insertLargest(file, into: &rootLargest, limit: 6) }
                if lastUpdate.duration(to: .now) >= .milliseconds(150) {
                    await onProgress(ScanProgress(files: files, allocatedBytes: allocated, currentFolder: url.deletingLastPathComponent().lastPathComponent))
                    lastUpdate = .now
                }
            } catch {
                errors.record(url.path)
            }
        }
        try Task.checkCancellation()
        let folders = folderTotals.map { FolderTotal(name: $0.key, url: root.appendingPathComponent($0.key), files: $0.value.files, allocatedBytes: $0.value.allocated) }
            .sorted { $0.allocatedBytes == $1.allocatedBytes ? $0.name < $1.name : $0.allocatedBytes > $1.allocatedBytes }
        return ScanResult(
            root: root, completedAt: Date(), files: files, logicalBytes: logical,
            allocatedBytes: allocated, categories: categories, largestFiles: largest,
            largestRootFiles: rootLargest, largestFolders: Array(folders.prefix(12)),
            skippedLinks: links, skippedCloudItems: cloud, duplicateHardLinks: duplicates,
            unreadableCount: errors.count, unreadableExamples: errors.examples, omittedVolumes: volumes
        )
    }

    /// Keeps the largest files in order without sorting the whole list on every hit.
    static func insertLargest(_ file: StorageFile, into largest: inout [StorageFile], limit: Int) {
        let belongsBefore: (StorageFile) -> Bool = { existing in
            file.allocatedBytes > existing.allocatedBytes || (file.allocatedBytes == existing.allocatedBytes && file.url.path < existing.url.path)
        }
        guard largest.count < limit || belongsBefore(largest[largest.count - 1]) else { return }
        let index = largest.firstIndex(where: belongsBefore) ?? largest.count
        largest.insert(file, at: index)
        if largest.count > limit { largest.removeLast() }
    }

    /// The resolved form the enumerator yields, including firmlinks like /var → /private/var that `resolvingSymlinksInPath` leaves alone.
    static func canonicalPath(of url: URL) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &buffer) != nil else { return url.path }
        return String(cString: buffer)
    }
}

private struct HardLinkIdentity: Hashable {
    let device: dev_t
    let inode: ino_t
}

private final class ScanErrors {
    var count = 0
    var examples: [String] = []
    func record(_ path: String) {
        count += 1
        if examples.count < 8 { examples.append(path) }
    }
}
