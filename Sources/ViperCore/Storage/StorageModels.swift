import Foundation

public enum StorageCategory: String, CaseIterable, Identifiable, Sendable {
    case applications = "Applications"
    case documents = "Documents"
    case images = "Images"
    case video = "Video"
    case audio = "Audio"
    case archives = "Archives"
    case development = "Developer files"
    case other = "Other files"

    public var id: String { rawValue }

    public static func classify(_ url: URL, relativePath: String) -> Self {
        if relativePath.split(separator: "/").contains(where: { $0.hasSuffix(".app") }) {
            return .applications
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf", "txt", "rtf", "doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "csv": return .documents
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "raw", "svg", "psd": return .images
        case "mp4", "mov", "mkv", "avi", "m4v", "webm": return .video
        case "mp3", "wav", "flac", "aac", "m4a", "aiff": return .audio
        case "zip", "dmg", "tar", "gz", "bz2", "xz", "7z", "rar", "pkg": return .archives
        case "swift", "js", "jsx", "ts", "tsx", "py", "rs", "go", "c", "h", "cpp", "java", "o", "a": return .development
        default:
            if relativePath.split(separator: "/").contains(where: { ["node_modules", ".git", ".build", "DerivedData"].contains(String($0)) }) {
                return .development
            }
            return .other
        }
    }
}

public struct StorageFile: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let category: StorageCategory
}

public struct ScanProgress: Sendable {
    public let files: Int
    public let allocatedBytes: Int64
    public let currentFolder: String
}

public struct FolderTotal: Sendable, Hashable {
    public let name: String
    public let url: URL
    public let files: Int
    public let allocatedBytes: Int64

    public init(name: String, url: URL, files: Int, allocatedBytes: Int64) {
        self.name = name
        self.url = url
        self.files = files
        self.allocatedBytes = allocatedBytes
    }
}

public struct StorageMapItem: Identifiable, Sendable {
    public enum Kind: Sendable, Equatable { case folder, file, remaining }
    public var id: String { url?.path ?? "remaining" }
    public let name: String
    public let url: URL?
    public let kind: Kind
    public let files: Int
    public let allocatedBytes: Int64
}

public struct ScanResult: Sendable {
    public let root: URL
    public let completedAt: Date
    public let files: Int
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let categories: [StorageCategory: Int64]
    public let largestFiles: [StorageFile]
    public let largestRootFiles: [StorageFile]
    /// Allocated totals for each immediate subfolder of the scan root, largest first.
    public let largestFolders: [FolderTotal]
    public let skippedLinks: Int
    public let skippedCloudItems: Int
    public let duplicateHardLinks: Int
    public let unreadableCount: Int
    public let unreadableExamples: [String]
    public let omittedVolumes: Int

    public var hasLimitedCoverage: Bool {
        unreadableCount > 0 || skippedCloudItems > 0 || omittedVolumes > 0
    }

    public var mapItems: [StorageMapItem] {
        guard allocatedBytes > 0 else { return [] }
        let folders = largestFolders.map { StorageMapItem(name: $0.name, url: $0.url, kind: .folder, files: $0.files, allocatedBytes: $0.allocatedBytes) }
        let looseFiles = largestRootFiles.map { StorageMapItem(name: $0.url.lastPathComponent, url: $0.url, kind: .file, files: 1, allocatedBytes: $0.allocatedBytes) }
        let shown = Array((folders + looseFiles).filter { $0.allocatedBytes > 0 }.sorted {
            $0.allocatedBytes == $1.allocatedBytes ? $0.id < $1.id : $0.allocatedBytes > $1.allocatedBytes
        }.prefix(6))
        var items = shown
        let remainingBytes = max(0, allocatedBytes - shown.reduce(Int64(0)) { $0 + $1.allocatedBytes })
        if remainingBytes > 0 {
            let remainingFiles = max(0, files - shown.reduce(0) { $0 + $1.files })
            items.append(StorageMapItem(name: shown.isEmpty ? "Files in this folder" : "Other files & folders",
                                        url: nil, kind: .remaining, files: remainingFiles, allocatedBytes: remainingBytes))
        }
        return items
    }

    public var summary: StoredScanSummary {
        .init(root: root.path, completedAt: completedAt, files: files, logicalBytes: logicalBytes, allocatedBytes: allocatedBytes,
              categories: Dictionary(uniqueKeysWithValues: categories.map { ($0.key.rawValue, $0.value) }),
              largestFolders: largestFolders.map { .init(name: $0.name, path: $0.url.path, files: $0.files, allocatedBytes: $0.allocatedBytes) },
              hasLimitedCoverage: hasLimitedCoverage)
    }
}

/// The last completed scan, without the file list. Small enough to keep between launches.
public struct StoredScanSummary: Codable, Sendable, Equatable {
    public struct Folder: Codable, Sendable, Equatable {
        public let name: String
        public let path: String
        public let files: Int
        public let allocatedBytes: Int64
    }

    public let root: String
    public let completedAt: Date
    public let files: Int
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let categories: [String: Int64]
    public let largestFolders: [Folder]
    public let hasLimitedCoverage: Bool

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: [.atomic])
    }

    public static func load(from url: URL) -> Self? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Self.self, from: data)
    }
}

public struct VolumeCapacity: Sendable, Equatable {
    public let name: String
    public let totalBytes: Int64
    /// Space available for important files, as Finder and About This Mac report it. Includes purgeable space.
    public let availableBytes: Int64
    /// Space free right now, before macOS reclaims purgeable data such as caches and local snapshots.
    public let freeBytes: Int64
    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    /// Space macOS can reclaim automatically when it's needed.
    public var purgeableBytes: Int64 { max(0, availableBytes - freeBytes) }

    public init(name: String, totalBytes: Int64, availableBytes: Int64, freeBytes: Int64? = nil) {
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.freeBytes = freeBytes ?? availableBytes
    }

    public static func read(at url: URL) throws -> Self {
        let values = try url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                                      .volumeAvailableCapacityForImportantUsageKey])
        guard let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity else {
            throw CocoaError(.fileReadUnknown)
        }
        // Match Finder: its "available" counts purgeable space. Fall back to raw free space if the volume can't say.
        let important = values.volumeAvailableCapacityForImportantUsage.flatMap { $0 > 0 ? $0 : nil } ?? Int64(free)
        return Self(name: values.volumeName ?? "Selected volume", totalBytes: Int64(total),
                    availableBytes: max(Int64(free), important), freeBytes: Int64(free))
    }
}
