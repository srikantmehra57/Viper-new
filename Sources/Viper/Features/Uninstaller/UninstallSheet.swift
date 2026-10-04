import AppKit
import SwiftUI
import ViperCore

struct UninstallSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirming = false
    let session: UninstallSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(26)
            GlowDivider()
            Group {
                switch session.phase {
                case .scanning: scanning
                case .review: review
                case .removing: removing
                case .finished: finished
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            GlowDivider()
            footer.padding(.horizontal, 26).padding(.vertical, 18)
        }
        .frame(minWidth: 680, idealWidth: 780, maxWidth: 860, minHeight: 520, idealHeight: 680, maxHeight: 760)
        .background(SheetBackground(tint: Palette.lavender)).foregroundStyle(Palette.ink)
        .environment(\.colorScheme, .dark)
        .animation(Motion.smooth, value: session.phase)
        .interactiveDismissDisabled(session.phase == .removing)
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(primaryLabel, role: .destructive) { model.confirmUninstall() }
            Button("Keep \(session.target.name)", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            switch session.target {
            case .app(let app): Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 60, height: 60)
                .shadow(color: Palette.lavender.opacity(Palette.isWebsite ? 0 : 0.45), radius: Palette.isWebsite ? 0 : 16)
            case .tool: ToolIcon(size: 60)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(session.target.name).font(.system(size: 26, weight: .medium)).tracking(-0.6).lineLimit(1).foregroundStyle(Palette.titleGradient)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2).textSelection(.enabled)
            }
            Spacer()
            Tag(text: phaseLabel, color: session.phase == .finished ? Palette.mint : Palette.lavender, pulse: session.phase == .scanning || session.phase == .removing)
                .id(phaseLabel).transition(.scale.combined(with: .opacity))
        }
    }

    private var subtitle: String {
        switch session.target {
        case .app(let app): return ["Version \(app.version)", app.bundleIdentifier, app.url.path].compactMap { $0 }.joined(separator: " · ")
        case .tool(let tool): return ["Version \(tool.version)", tool.sourceLabel, tool.commands.isEmpty ? nil : "Commands: " + tool.commands.prefix(6).joined(separator: ", ")].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var phaseLabel: String {
        switch session.phase {
        case .scanning: return "LOOKING"
        case .review: return "REVIEW"
        case .removing: return "REMOVING"
        case .finished: return "DONE"
        }
    }

    // MARK: Phases

    private var scanning: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) { ScanPulse(color: Palette.lavender); Text(session.progress).font(.system(size: 13)) }
            InfoLine(text: "Viper reads file names and sizes in your Library and home folder. Nothing is changed yet.", icon: "shield")
        }.padding(26)
    }

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let failure = session.failure { banner(failure, icon: "exclamationmark.triangle", color: Palette.peach) }
                if let plan = session.plan {
                    ForEach(plan.blockers, id: \.self) { banner($0, icon: "hand.raised", color: Palette.peach) }
                    if model.isRunning(session.target) {
                        HStack {
                            Label("\(session.target.name) is open. Quit it before uninstalling so it can save its work.", systemImage: "exclamationmark.circle")
                                .font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Quit \(session.target.name)") { model.quitUninstallTarget() }.buttonStyle(GlowButtonStyle(.warning))
                        }.padding(14).noticeBackground(Palette.yellow)
                    }
                    if plan.canProceed {
                        summary(plan)
                        ForEach(RemovalKind.allCases, id: \.self) { kind in
                            let items = plan.items.filter { $0.kind == kind }
                            if !items.isEmpty { section(kind, items: items) }
                        }
                    }
                    if !plan.kept.isEmpty {
                        Disclosure("Kept (\(plan.kept.count)) — found, but not removed") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(plan.kept) { item in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(displayPath(item.url)).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                            Text(item.reason).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                        }
                                        Spacer()
                                        revealButton(item.url)
                                    }
                                }
                            }.padding(.top, 8)
                        }.font(.system(size: 12))
                    }
                    Disclosure("What Viper checks") {
                        Text("Your Library’s Preferences, Application Support, Containers, Group Containers, Application Scripts, Caches, HTTP storage, WebKit, Cookies, Logs, Saved Application State, and LaunchAgents, plus hidden folders in your home named after the app or command. Exact matches use the app’s identifier and are selected. Likely matches use the name and are left for you to decide. System-wide items under /Library are listed as kept. Files in Documents, Desktop, and projects are never included.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 12))
                }
            }.padding(26)
        }
    }

    private func summary(_ plan: UninstallPlan) -> some View {
        let likely = plan.items.filter { $0.confidence == .likely }
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(session.selectedItems.count) of \(plan.items.count) selected · \(bytes(session.selectedBytes))").font(.system(size: 22, weight: .medium)).tracking(-0.4)
                .foregroundStyle(Palette.ink).contentTransition(.numericText())
            Text(likely.isEmpty ? "Everything listed was matched by \(session.target.name)’s identifier."
                 : "\(likely.count) likely match\(likely.count == 1 ? " is" : "es are") listed but not selected. Check them before including.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }

    private func section(_ kind: RemovalKind, items: [RemovalItem]) -> some View {
        let optional = items.filter { !$0.isRequired }
        let allSelected = optional.allSatisfy { session.selection.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(kind.rawValue.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(Palette.ink.opacity(0.9))
                Text("\(items.count) · \(bytes(items.reduce(0) { $0 + ($1.size ?? 0) }))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                Spacer()
                if optional.count > 1 {
                    Button(allSelected ? "Clear" : "Select all") { model.setUninstallItems(optional, selected: !allSelected) }
                        .buttonStyle(LinkButtonStyle())
                }
            }.padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    RemovalRow(item: item, selected: session.selection.contains(item.id)) { model.toggleUninstallItem(item) } reveal: { model.reveal(item.url) }
                    if item.id != items.last?.id { GlowDivider().padding(.horizontal, 12) }
                }
            }.glassPanel()
        }
    }

    private var removing: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) { ScanPulse(color: Palette.peach); Text(session.progress).font(.system(size: 14, weight: .semibold)) }
            InfoLine(text: "Each item is re-checked just before it moves, and anything that changed since the review is left alone. These checks are best-effort: a last-instant change can still slip through.", icon: "shield")
        }.padding(26)
    }

    private var finished: some View {
        let removed = session.outcomes.filter { $0.result.succeeded && !$0.restored }
        let restored = session.outcomes.filter(\.restored)
        let problems = session.outcomes.filter { !$0.result.succeeded }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline(removed: removed.count, problems: problems.count, restored: restored.count)).font(.system(size: 22, weight: .medium)).tracking(-0.4)
                        .foregroundStyle(problems.isEmpty ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.ink))
                    Text("\(bytes(removed.reduce(0) { $0 + ($1.item.size ?? 0) })) moved out. Disk space is freed when you empty the Trash; Viper never empties it.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                VStack(spacing: 0) {
                    ForEach(session.outcomes) { outcome in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(outcome)).font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26)
                                .glowTile(outcome.result.succeeded ? (outcome.restored ? Palette.blue : Palette.mint) : Palette.yellow, radius: 8, glow: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(outcome.item.url.lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                Text(detail(outcome)).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if !outcome.result.succeeded || outcome.restored { revealButton(outcome.item.url) }
                        }.padding(12)
                        if outcome.id != session.outcomes.last?.id { GlowDivider().padding(.horizontal, 12) }
                    }
                }.glassPanel()
            }.padding(26)
        }
    }

    private func headline(removed: Int, problems: Int, restored: Int) -> String {
        if restored > 0 && removed == 0 { return "Put back \(restored) item\(restored == 1 ? "" : "s")." }
        if problems == 0 { return "\(session.target.name) is uninstalled." }
        if removed == 0 { return "Nothing was removed." }
        return "Removed \(removed) item\(removed == 1 ? "" : "s"). \(problems) need\(problems == 1 ? "s" : "") attention."
    }

    private func icon(_ outcome: RemovalOutcome) -> String {
        if outcome.restored { return "arrow.uturn.backward" }
        switch outcome.result {
        case .removed: return "checkmark"
        case .skipped: return "minus.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func detail(_ outcome: RemovalOutcome) -> String {
        if outcome.restored { return "Put back at \(displayPath(outcome.item.url))." }
        switch outcome.result {
        case .removed(let trash): return trash == nil ? "Removed by the package manager." : "Moved to the Trash from \(displayPath(outcome.item.url))."
        case .skipped(let reason), .failed(let reason): return reason
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            switch session.phase {
            case .scanning:
                Spacer()
                Button("Cancel") { model.closeUninstall() }.buttonStyle(GlowButtonStyle(.secondary)).keyboardShortcut(.cancelAction)
            case .review:
                InfoLine(text: "Files go to the Trash, so you can put them back.", icon: "trash")
                Spacer()
                Button("Cancel") { model.closeUninstall() }.buttonStyle(GlowButtonStyle(.secondary)).keyboardShortcut(.cancelAction)
                Button(primaryLabel) { confirming = true }
                    .buttonStyle(GlowButtonStyle(.danger))
                    .disabled(!(session.plan?.canProceed ?? false) || model.isRunning(session.target) || model.packageOperationBusy)
            case .removing:
                InfoLine(text: "Please wait. Viper finishes this before it quits.", icon: "hourglass")
                Spacer()
            case .finished:
                if session.canPutBack {
                    Button { model.putBackUninstalled() } label: { Label("Put everything back", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(GlowButtonStyle(.secondary))
                        .disabled(model.maintenanceBusy || model.installing)
                }
                Spacer()
                Button("Done") { model.closeUninstall() }.buttonStyle(GlowButtonStyle(.primary)).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var isPackage: Bool { if case .packageUninstall = session.plan?.required?.action { return true } else { return false } }
    private var trashCount: Int { session.selectedItems.filter { $0.action == .trash }.count }

    private var primaryLabel: String {
        if isPackage {
            return trashCount == 0 ? "Uninstall \(session.target.name)" : "Uninstall and move \(trashCount) item\(trashCount == 1 ? "" : "s") to Trash"
        }
        return "Move \(trashCount) item\(trashCount == 1 ? "" : "s") to Trash"
    }

    private var confirmTitle: String { "Uninstall \(session.target.name)?" }

    private var confirmMessage: String {
        var lines: [String] = []
        if trashCount > 0 { lines.append("\(trashCount) item\(trashCount == 1 ? "" : "s") (\(bytes(session.selectedBytes))) will move to the Trash. Settings and data in them are gone for good once you empty the Trash.") }
        if isPackage, case .packageUninstall(let request)? = session.plan?.required?.action {
            lines.append("\(request.runtime.manager.rawValue) will run “\(request.displayCommand)”. That part can’t be put back from the Trash; reinstall it instead.")
        }
        let warned = session.selectedItems.filter { $0.warning != nil }.count
        if warned > 0 { lines.append("\(warned) selected item\(warned == 1 ? " has" : "s have") a warning. Review them before continuing.") }
        return lines.joined(separator: "\n\n")
    }

    // MARK: Helpers

    private func banner(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).noticeBackground(color)
    }

    private func revealButton(_ url: URL) -> some View {
        Button { model.reveal(url) } label: { Image(systemName: "arrow.up.right.square") }
            .buttonStyle(IconButtonStyle()).help("Reveal in Finder").accessibilityLabel("Reveal \(url.lastPathComponent) in Finder")
            .disabled(!FileManager.default.fileExists(atPath: url.path))
    }
}

struct RemovalRow: View {
    let item: RemovalItem
    let selected: Bool
    let toggle: () -> Void
    let reveal: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(get: { selected }, set: { _ in toggle() })) { EmptyView() }
                .toggleStyle(ViperCheckboxStyle()).disabled(item.isRequired)
                .accessibilityLabel("Include \(item.url.lastPathComponent)")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.url.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if item.isRequired { Tag(text: "REQUIRED", color: Palette.lavender) }
                    else { Tag(text: item.confidence == .exact ? "EXACT MATCH" : "LIKELY", color: item.confidence == .exact ? Palette.mint : Palette.yellow) }
                }
                Text(displayPath(item.url)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Text(item.reason).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if let warning = item.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.yellow).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(item.size.map(bytes) ?? "—").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            Button(action: reveal) { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(IconButtonStyle()).help("Reveal in Finder").accessibilityLabel("Reveal \(item.url.lastPathComponent) in Finder")
        }
        .padding(12)
        .background(Palette.isWebsite ? Palette.elevated.opacity(selected ? 1 : (hovering ? 0.7 : 0)) : (selected ? Palette.mint.opacity(0.05) : Color.white.opacity(hovering ? 0.04 : 0)))
        .animation(Motion.hover, value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { toggle() }
    }
}

func displayPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
}
