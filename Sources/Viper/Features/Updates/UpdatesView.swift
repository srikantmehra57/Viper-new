import AppKit
import SwiftUI
import ViperCore

struct UpdatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var pending: [AvailableUpdate] = []
    @State private var confirming = false
    @State private var enablingChanges = false
    @State private var expanded: String?

    private var updates: [AvailableUpdate] { model.updateReport?.updates ?? [] }
    private var direct: [AvailableUpdate] {
        updates.filter { PackageUpgrade($0) != nil && !isDone($0) }
    }
    private var busy: Bool { model.installing || model.detectingInstalls || model.refreshingCatalog || model.reviewTask != nil || model.uninstalling || model.cleaning }

    private var headingSubtitle: String {
        if model.checkingUpdates { return model.updateProgress }
        if let report = model.updateReport { return summary + " · Last checked \(report.checkedAt.formatted(date: .abbreviated, time: .shortened))" }
        return "Check for updates when you’re ready. Nothing updates automatically."
    }

    var body: some View {
        PageHeading("Updates", subtitle: headingSubtitle) {
            if model.checkingUpdates {
                ScanPulse(color: Palette.blue).scaleEffect(0.8)
                Button("Cancel check") { model.cancelUpdateCheck() }.buttonStyle(GlowButtonStyle(.secondary))
            } else {
                Button { model.checkUpdates() } label: { Label(model.updateReport == nil ? "Check for updates" : "Check again", systemImage: "arrow.clockwise") }
                    .buttonStyle(GlowButtonStyle(.secondary)).disabled(busy || model.updating)
                // Hidden while a run is in progress: the queue card below owns that state and its actions.
                if !direct.isEmpty && !model.updating {
                    Button { request(direct) } label: { Label("Update all (\(direct.count))", systemImage: "arrow.down.circle") }
                        .buttonStyle(GlowButtonStyle()).disabled(busy || model.updating)
                }
            }
        }
            // Dialogs must hang off a view that is actually on screen; EmptyView never presents them.
            .confirmationDialog(pending.count == 1 ? "Update \(pending.first?.name ?? "")?" : "Update \(pending.count) packages?", isPresented: $confirming, titleVisibility: .visible) {
                Button(pending.count == 1 ? "Update" : "Update \(pending.count)") { withAnimation(Motion.smooth) { model.applyUpdates(pending) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(pending.compactMap { update -> String? in
                    guard let upgrade = PackageUpgrade(update) else { return nil }
                    var line = "\(upgrade.package): \(upgrade.fromVersion) → \(upgrade.toVersion)" + (upgrade.versionDelta.map { " · \($0)" } ?? "")
                    line += "\n" + upgrade.displayCommand
                    if !update.dependencies.isEmpty { line += "\nMay also install or update: " + update.dependencies.joined(separator: ", ") }
                    if let registry = upgrade.registryURL { line += "\nRegistry: \(registry.absoluteString)" }
                    return line
                }.joined(separator: "\n\n")
                     + "\n\nEach one is rechecked before it starts. Homebrew may also update dependencies, which can change how related tools behave. Updates can’t be rolled back.")
            }
            .confirmationDialog("Updates are off in read-only mode", isPresented: $enablingChanges, titleVisibility: .visible) {
                Button("Turn on reviewed changes") {
                    model.settings.allowReviewedChanges = true
                    // Let the first dialog close before asking to confirm the update itself.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirming = true }
                }
                Button("Cancel", role: .cancel) { pending = [] }
            } message: {
                Text("Viper is in read-only safety mode, so it can check for updates but not install them. Turning on reviewed changes lets Viper run the package manager for updates you confirm. You can switch back in Settings.")
            }
        if model.updating {
            let active = model.updateQueue.filter { $0.state != .cancelled }
            let waiting = active.filter { $0.state == .queued }.count
            Card {
                HStack {
                    HStack(spacing: 10) {
                        ScanPulse(color: Palette.blue)
                        Text(progressTitle).font(.cardTitle).contentTransition(.numericText())
                    }
                    Spacer()
                    if waiting > 0 {
                        Button("Cancel waiting") { model.cancelPendingUpdates() }.buttonStyle(GlowButtonStyle(.secondary))
                    }
                }
                QueueSummaryBar(finished: active.filter { $0.state.isFinished }.count, total: active.count,
                                current: active.first { $0.state == .updating }?.progress, title: "Overall progress")
                InfoLine(text: "Updates run one at a time. The active update finishes even if you quit; waiting ones can be cancelled.")
            }
        }
        if let message = model.updateMessage { InfoLine(text: message) }
        Card {
            HStack {
                Text("Available updates").font(.cardTitle)
                Spacer()
                if model.updateQueue.contains(where: { $0.state.isFinished }) && !model.updating {
                    Button("Clear results") { model.clearFinishedUpdates() }.buttonStyle(LinkButtonStyle())
                }
                Button("Manage sources") { model.page = .settings }.buttonStyle(LinkButtonStyle())
            }
            if !updates.isEmpty {
                SearchField(placeholder: "Search available updates", text: $search)
                ForEach(updates.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { update in
                    row(update)
                    GlowDivider()
                }
            } else if !model.checkingUpdates {
                EmptyPanel(framed: false, icon: model.updateReport == nil ? "arrow.down.circle" : "checkmark.circle", title: model.updateReport == nil ? "Let’s see what’s new." : "No updates reported.", detail: model.updateReport == nil ? "Your available updates will appear here after a check." : "See source coverage below. Sources that failed, aren’t installed, or aren’t supported have an unknown update status.")
            }
            InfoLine(text: "Homebrew and npm updates run with their own package manager. Homebrew may update dependencies too. Updates can’t be rolled back.")
        }
        if let report = model.updateReport {
            Card {
                Text("Source coverage").font(.cardTitle)
                ForEach(report.sources) { source in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: source.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(source.succeeded ? Palette.mint : Palette.yellow)
                            .shadow(color: (source.succeeded ? Palette.mint : Palette.yellow).opacity(Palette.isWebsite ? 0 : 0.6), radius: Palette.isWebsite ? 0 : 5)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(source.name).font(.system(size: 12, weight: .semibold))
                            Text(source.detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
            if !report.notCovered.isEmpty {
                Card {
                    Text("Not checked by Viper").font(.cardTitle)
                    Text("These apps are not App Store receipts and not Homebrew casks. Sparkle, Setapp, and other updaters stay with the app.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    ForEach(report.notCovered.prefix(12), id: \.self) { name in
                        Text(name).font(.system(size: 12))
                    }
                    if report.notCovered.count > 12 {
                        Text("And \(report.notCovered.count - 12) more.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
    }

    private func row(_ update: AvailableUpdate) -> some View {
        let state = model.updateState(for: update)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: update.source == .npm ? "terminal" : (update.source == .appStore ? "bag" : "app.badge")).font(.system(size: 19))
                    .frame(width: 44, height: 44).glowTile(update.source == .npm ? Palette.peach : (update.source == .appStore ? Palette.blue : Palette.yellow), radius: 12, glow: false)
                VStack(alignment: .leading, spacing: 5) {
                    Text(update.name).font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 6) {
                        Text(update.installed).foregroundStyle(Palette.muted)
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.ink)
                        Text(update.available).foregroundStyle(Palette.mint)
                    }.font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text(update.source.rawValue + (update.isCask ? " app" : "") + (update.executable.map { " · " + $0.deletingLastPathComponent().path } ?? "") + (update.registryURL.map { " · " + ($0.host ?? $0.absoluteString) } ?? "") + (update.dependencies.isEmpty ? "" : " · \(update.dependencies.count) dep\(update.dependencies.count == 1 ? "" : "s"): \(update.dependencies.joined(separator: ", "))"))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if PackageUpgrade(update)?.versionDelta?.hasPrefix("major") == true { Tag(text: "MAJOR", color: Palette.peach) }
                if update.source == .npm, let executable = update.executable, ShellEnvironment.isTerminalDefault(executable) == true {
                    Tag(text: "USED BY TERMINAL", color: Palette.blue)
                }
                if let state { Tag(text: state.label, color: tagColor(state), pulse: state == .updating) }
                if update.source == .appStore {
                    Button("Update in App Store") { if let url = update.storeURL { model.openExternal(url.absoluteString) } }
                        .buttonStyle(GlowButtonStyle(.secondary))
                } else if PackageUpgrade(update) == nil {
                    Text("Can’t be updated safely").font(.system(size: 11)).foregroundStyle(Palette.muted)
                } else if state == nil || !(state?.isFinished == false) && !isDone(update) {
                    Button("Update") { request([update]) }
                        .buttonStyle(GlowButtonStyle(.secondary)).disabled(busy || state == .queued || state == .updating)
                }
            }
            if let item = model.updateQueue.last(where: { $0.id == update.id }) {
                if item.state == .updating {
                    OperationProgressView(progress: item.progress ?? OperationProgress(phase: .preparing, detail: "Starting…"), startedAt: item.startedAt)
                        .padding(.leading, 58)
                } else if item.state == .queued {
                    QueueWaitingLine(position: model.updateQueue.filter { $0.state == .queued || $0.state == .updating }.firstIndex { $0.id == item.id } ?? 1)
                        .padding(.leading, 58)
                }
            }
            if let state, let detail = detail(state) {
                Text(detail + (update.executable.map { " In \(displayPath($0.deletingLastPathComponent()))." } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.leading, 58)
            }
            if let note = terminalNote(update, finished: state?.isFinished == true) {
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.isWebsite ? Palette.yellow : Color(hex: 0xFFD89A))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .noticeBackground(Palette.yellow, radius: 12)
                    .padding(.leading, 58)
            }
            if let item = model.updateQueue.last(where: { $0.id == update.id }), !item.log.isEmpty, item.state.isFinished {
                Disclosure("Package manager output", isExpanded: Binding(get: { expanded == update.id }, set: { expanded = $0 ? update.id : nil })) {
                    ScrollView { Text(item.log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
                }.font(.system(size: 11)).padding(.leading, 58)
            }
        }.padding(.vertical, 8)
        .animation(Motion.smooth, value: state)
    }

    /// Explains when an npm update targets a copy that Terminal doesn't run, so `npm -v` there won't change.
    private func terminalNote(_ update: AvailableUpdate, finished: Bool) -> String? {
        guard update.source == .npm, let executable = update.executable, ShellEnvironment.isTerminalDefault(executable) == false,
              let terminal = ShellEnvironment.resolve("npm") else { return nil }
        let here = displayPath(executable.deletingLastPathComponent())
        let there = displayPath(terminal.deletingLastPathComponent())
        return finished
            ? "This updated the npm in \(here). Terminal runs npm from \(there), so commands there still use that copy."
            : "This is the npm in \(here). Terminal runs npm from \(there), so updating this copy won’t change what Terminal uses."
    }

    /// Asks to turn off read-only mode first when needed, so the Update button always responds.
    private func request(_ updates: [AvailableUpdate]) {
        pending = updates
        if model.settings.allowReviewedChanges { confirming = true } else { enablingChanges = true }
    }

    private func isDone(_ update: AvailableUpdate) -> Bool {
        switch model.updateState(for: update) {
        case .updated?, .alreadyCurrent?: return true
        default: return false
        }
    }

    private func detail(_ state: UpdateState) -> String? {
        switch state {
        case .updated(let version): return "Now on \(version)."
        case .alreadyCurrent(let version): return "Already on \(version)."
        case .skipped(let reason), .failed(let reason): return reason
        case .cancelled: return "Cancelled before it started. Nothing changed."
        default: return nil
        }
    }

    private func tagColor(_ state: UpdateState) -> Color {
        switch state {
        case .updated, .alreadyCurrent: return Palette.mint
        case .failed, .skipped: return Palette.peach
        default: return Palette.lavender
        }
    }

    private var progressTitle: String {
        let total = model.updateQueue.filter { $0.state != .cancelled }.count
        let done = model.updateQueue.filter { $0.state.isFinished && $0.state != .cancelled }.count
        return "Updating \(min(done + 1, total)) of \(total)…"
    }

    private var summary: String {
        guard let report = model.updateReport else { return "Ready to check" }
        let remaining = report.updates.filter { !isDone($0) }.count
        if remaining > 0 { return "\(remaining) update\(remaining == 1 ? "" : "s") available" }
        if !report.updates.isEmpty { return "Everything checked is up to date" }
        return report.sources.contains(where: { !$0.succeeded }) ? "Check finished with gaps" : "No updates from checked sources"
    }
}
