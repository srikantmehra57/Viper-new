import Foundation
import SwiftUI

enum ThemeChoice: String, CaseIterable, Codable, Identifiable {
    case space = "Space"
    case website = "Website"

    var id: String { rawValue }
    var detail: String {
        switch self {
        case .space: return "Luminous glass, soft color, and an ambient space backdrop."
        case .website: return "Warm graphite, cream surfaces, and the editorial style from Viper’s website."
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .space
    }
}

struct AppSettings: Codable {
    var theme: ThemeChoice = .space
    var scanFolders: [String] = [FileManager.default.homeDirectoryForCurrentUser.path]
    var excludedFolders: [String] = []
    var includeHiddenFiles = true
    var showMenuBar = true
    var quitOnClose = true
    var checkHomebrew = true
    var checkNpm = true
    var checkAppStore = true
    /// Safe default: scans and reviews work, but no files or packages are changed until explicitly enabled.
    var allowReviewedChanges = false
    /// Automatic selection is separate from permission to change files.
    var preselectRebuildableItems = false
    var storageResultLimit = 500
    /// Recovery transactions already surfaced to the user at launch, so each interruption is reported once.
    var acknowledgedInterruptedRemovals: Set<String> = []
    /// Journals that could not be decoded. Viper keeps the saved copies and will not change anything until these are marked reviewed.
    var preservedJournals: Set<String> = []
    /// True when the stored settings couldn't be decoded and defaults were restored. Never persisted.
    var settingsWereReset = false

    private enum CodingKeys: String, CodingKey {
        case theme, scanFolders, excludedFolders, includeHiddenFiles, showMenuBar, quitOnClose
        case checkHomebrew, checkNpm, checkAppStore, allowReviewedChanges, preselectRebuildableItems, storageResultLimit
        case acknowledgedInterruptedRemovals, preservedJournals
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decodeIfPresent(ThemeChoice.self, forKey: .theme) ?? .space
        scanFolders = try values.decodeIfPresent([String].self, forKey: .scanFolders) ?? [FileManager.default.homeDirectoryForCurrentUser.path]
        excludedFolders = try values.decodeIfPresent([String].self, forKey: .excludedFolders) ?? []
        includeHiddenFiles = try values.decodeIfPresent(Bool.self, forKey: .includeHiddenFiles) ?? true
        showMenuBar = try values.decodeIfPresent(Bool.self, forKey: .showMenuBar) ?? true
        quitOnClose = try values.decodeIfPresent(Bool.self, forKey: .quitOnClose) ?? true
        checkHomebrew = try values.decodeIfPresent(Bool.self, forKey: .checkHomebrew) ?? true
        checkNpm = try values.decodeIfPresent(Bool.self, forKey: .checkNpm) ?? true
        checkAppStore = try values.decodeIfPresent(Bool.self, forKey: .checkAppStore) ?? true
        allowReviewedChanges = try values.decodeIfPresent(Bool.self, forKey: .allowReviewedChanges) ?? false
        preselectRebuildableItems = try values.decodeIfPresent(Bool.self, forKey: .preselectRebuildableItems) ?? false
        let decodedLimit = try values.decodeIfPresent(Int.self, forKey: .storageResultLimit) ?? 500
        storageResultLimit = [100, 500, 1_000].contains(decodedLimit) ? decodedLimit : 500
        acknowledgedInterruptedRemovals = try values.decodeIfPresent(Set<String>.self, forKey: .acknowledgedInterruptedRemovals) ?? []
        preservedJournals = try values.decodeIfPresent(Set<String>.self, forKey: .preservedJournals) ?? []
    }

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "viper.settings") else { return .init() }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch {
            var fresh = Self()
            fresh.settingsWereReset = true
            return fresh
        }
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "viper.settings") }
    }
}
