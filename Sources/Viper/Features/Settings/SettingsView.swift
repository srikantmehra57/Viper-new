import SwiftUI
import ViperCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingChanges = false
    @State private var confirmingReset = false
    private var removalHistory: [RemovalJournalEntry] {
        Array(RemovalJournal.load(from: AppPaths.removalJournal).suffix(8).reversed())
    }
    private var unfinishedTransactions: [RemovalTransaction] {
        RemovalTransactionJournal.load(from: AppPaths.removalTransactions).filter { $0.state == .inProgress }
    }
    var body: some View {
        PageHeading("Settings", subtitle: model.settings.allowReviewedChanges
                    ? "Reviewed changes are enabled — Viper still previews, fingerprints, revalidates, and journals every item."
                    : "Read-only mode: scans and checks work, but nothing changes on disk.") {
            if model.settings.allowReviewedChanges {
                Button("Switch to read-only") { model.settings.allowReviewedChanges = false }
                    .buttonStyle(GlowButtonStyle(.secondary))
            } else {
                Button("Enable reviewed changes…") { confirmingChanges = true }
                    .buttonStyle(GlowButtonStyle(.warning))
            }
        }
        Card {
            Toggle("Preselect clearly rebuildable items after scans", isOn: $model.settings.preselectRebuildableItems)
                .toggleStyle(ViperCheckboxStyle()).disabled(!model.settings.allowReviewedChanges)
            InfoLine(text: "Keep preselection off for maximum control. Required app or package targets remain selected during an uninstall review.")
        }
        .confirmationDialog("Enable file-changing actions?", isPresented: $confirmingChanges, titleVisibility: .visible) {
            Button("Enable reviewed changes") { model.settings.allowReviewedChanges = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Viper will be allowed to run package-manager operations and move only the items you confirm. Every filesystem item is checked again immediately before it moves — a best-effort recheck, not a guarantee.")
        }
        if !model.settings.preservedJournals.isEmpty {
            Card(color: Palette.peach) {
                Label("A journal needs review", systemImage: "exclamationmark.triangle.fill").font(.cardTitle)
                Text("Viper couldn’t read a journal, so it saved a copy and will not change files until you mark it reviewed.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(model.settings.preservedJournals.sorted(), id: \.self) { path in
                    HStack {
                        Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Reveal") { model.reveal(URL(fileURLWithPath: path)) }.buttonStyle(GlowButtonStyle(.secondary, compact: true))
                    }
                }
                Button("Mark as reviewed") { model.markPreservedJournalsReviewed() }.buttonStyle(GlowButtonStyle(.warning, compact: true))
            }
        }
        if !unfinishedTransactions.isEmpty {
            Card(color: Palette.peach) {
                Label("Interrupted removal needs review", systemImage: "exclamationmark.triangle.fill").font(.cardTitle)
                Text("\(unfinishedTransactions.count) removal plan\(unfinishedTransactions.count == 1 ? " was" : "s were") not finalized. Viper or the Mac may have stopped mid-operation. Check the recorded paths and the Trash before retrying.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(unfinishedTransactions.prefix(3)) { transaction in
                    Text("\(transaction.name) · \(transaction.targets.filter { $0.outcome != nil }.count)/\(transaction.targets.count) outcomes · \(transaction.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11, design: .monospaced))
                }
                HStack {
                    Button("Reveal recovery journal") { model.reveal(AppPaths.removalTransactions) }.buttonStyle(GlowButtonStyle(.secondary))
                    Button("Open Trash") { model.openTrash() }.buttonStyle(GlowButtonStyle(.secondary))
                }
            }
        }
        if !removalHistory.isEmpty {
            Card {
                HStack {
                    Text("Removal history").font(.cardTitle)
                    Spacer()
                    Button("Reveal history file") { model.reveal(AppPaths.removalJournal) }.buttonStyle(GlowButtonStyle(.secondary, compact: true))
                }
                InfoLine(text: "Every cleanup and uninstall is recorded locally. Trashed items can be put back until the Trash is emptied in Finder.")
                ForEach(removalHistory) { entry in
                    HStack {
                        Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(entry.items.filter { $0.outcome == "Removed" }.count)/\(entry.items.count) removed · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        Card(color: model.settings.theme == .website ? Palette.orange : Palette.lavender) {
            HStack(spacing: 14) {
                ViperMark(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Appearance").font(.cardTitle)
                    Text(model.settings.theme.detail)
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                SegmentedTabs(options: ThemeChoice.allCases, title: \.rawValue, selection: $model.settings.theme)
                    .accessibilityLabel("App theme")
            }
            InfoLine(text: "The theme changes the complete app, including navigation, cards, controls, sheets, and backgrounds. Motion still follows your Mac’s Reduce Motion setting.")
        }
        Card {
            HStack {
                Text("Saved scan folders").font(.cardTitle)
                Spacer()
                Button { model.addFolder(exclusion: false) } label: { Label("Add folder", systemImage: "plus") }
                    .buttonStyle(GlowButtonStyle(.secondary)).disabled(model.scanning)
            }
            Text("Choose a saved folder as your Storage scan location. Each scan covers one folder and its contents.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            if model.settings.scanFolders.isEmpty { InfoLine(text: "No saved folders. Add one to start scanning.") }
            ForEach(model.settings.scanFolders, id: \.self) { path in
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").font(.system(size: 13)).frame(width: 30, height: 30)
                        .glowTile(model.selectedFolder.path == path ? Palette.mint : Palette.slate, radius: 8, glow: model.selectedFolder.path == path)
                    Text(path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).help(path)
                    Spacer()
                    if model.selectedFolder.path == path {
                        Tag(text: "IN USE", color: Palette.mint)
                    } else {
                        Button("Use folder") { model.selectFolder(URL(fileURLWithPath: path)) }
                            .buttonStyle(GlowButtonStyle(.secondary, compact: true)).disabled(model.scanning)
                    }
                    Button { model.removeFolder(path, exclusion: false) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(IconButtonStyle(tint: Palette.peach)).help("Remove from saved folders").accessibilityLabel("Remove \(path) from saved folders").disabled(model.scanning)
                }.padding(.vertical, 5)
            }
            Toggle("Include hidden files in storage scans", isOn: $model.settings.includeHiddenFiles).toggleStyle(ViperCheckboxStyle()).disabled(model.scanning)
            HStack {
                Text("Largest files retained per scan")
                Spacer()
                Picker("Largest files retained", selection: $model.settings.storageResultLimit) {
                    Text("100").tag(100)
                    Text("500").tag(500)
                    Text("1,000").tag(1_000)
                }.labelsHidden().frame(width: 120).disabled(model.scanning)
            }.font(.system(size: 12))
            InfoLine(text: "Higher limits make search and category filtering more useful, but retain more file metadata in memory until the next scan or app quit.")
        }
        Card {
            HStack {
                Text("Excluded folders").font(.cardTitle)
                Spacer()
                Button { model.addFolder(exclusion: true) } label: { Label("Add exclusion", systemImage: "plus") }
                    .buttonStyle(GlowButtonStyle(.secondary)).disabled(model.scanning)
            }
            InfoLine(text: "Storage scans skip these folders and their contents. Removing an entry here only changes this list; it never removes files.")
            if model.settings.excludedFolders.isEmpty { Text("No folders excluded.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
            ForEach(model.settings.excludedFolders, id: \.self) { path in
                HStack {
                    Text(path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { model.removeFolder(path, exclusion: true) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(IconButtonStyle(tint: Palette.peach)).accessibilityLabel("Remove exclusion \(path)").disabled(model.scanning)
                }
            }
        }
        Card {
            HStack {
                Text("Full Disk Access").font(.cardTitle)
                Spacer()
                Tag(text: model.fullDiskAccess == true ? "GRANTED" : (model.fullDiskAccess == false ? "NOT GRANTED" : "CHECKING"),
                    color: model.fullDiskAccess == true ? Palette.mint : Palette.yellow)
            }
            Text(model.fullDiskAccess == true
                 ? "Viper can read protected folders such as Mail and Messages when you scan them."
                 : "Viper can’t read some protected folders (like Mail) right now. Scans and cleanup still work; unreadable items are counted and skipped. This check is best-effort.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Button("Open Full Disk Access settings") { model.openSettings("com.apple.preference.security?Privacy_AllFiles") }
                .buttonStyle(GlowButtonStyle(.secondary, compact: true))
        }
        Card {
            Text("App behaviour").font(.cardTitle)
            Toggle("Show Viper in the menu bar", isOn: $model.settings.showMenuBar).toggleStyle(ViperCheckboxStyle())
            Toggle("Quit when the last window closes", isOn: $model.settings.quitOnClose).toggleStyle(ViperCheckboxStyle())
            InfoLine(text: "When close-to-quit is off, use the Dock or menu bar to reopen Viper. No scans or update checks run automatically.")
            HStack {
                Text("Reset appearance, folders, exclusions, safety mode, and update sources to defaults.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Reset all settings…") { confirmingReset = true }.buttonStyle(GlowButtonStyle(.secondary, compact: true))
                    .disabled(model.scanning || model.maintenanceBusy || model.installing || model.checkingUpdates)
            }
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset settings") { model.resetSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything on this page returns to its default. File-changing actions switch back to read-only. Removal history is kept.")
        }
        if let environment = model.installEnvironment, environment.npm.count > 1 {
            Card {
                Text("Command-line installs").font(.cardTitle)
                HStack {
                    Text("npm tools install into").font(.system(size: 12))
                    Spacer()
                    ViperSelect(title: "npm runtime", selection: Binding(get: { model.npmRuntime?.id ?? "" }, set: { model.npmRuntimeID = $0 }),
                                options: environment.npm.map { ($0.location + ($0.isTerminalDefault == true ? "  ·  Terminal default" : ""), $0.id) }).frame(width: 340)
                }.disabled(model.installing)
                InfoLine(text: "Viper uses the npm that Terminal runs by default, so installed tools work where you use them. Change this only if you manage several Node.js versions.")
            }
        }
        Card {
            Text("Update sources").font(.cardTitle)
            Toggle("Homebrew apps and tools", isOn: $model.settings.checkHomebrew).toggleStyle(ViperCheckboxStyle())
            Toggle("Global npm tools", isOn: $model.settings.checkNpm).toggleStyle(ViperCheckboxStyle())
            Toggle("App Store catalog", isOn: $model.settings.checkAppStore).toggleStyle(ViperCheckboxStyle())
            InfoLine(text: "Check for updates contacts enabled sources. Homebrew refreshes its local package metadata; npm checks its configured registry; App Store app names are sent to Apple’s public catalog. No software is updated by checking.")
        }
    }
}
