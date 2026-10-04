import AppKit
import SwiftUI
import ViperCore

enum UninstallerFilter: String, CaseIterable { case all = "All", apps = "Apps", tools = "Command-line tools" }

private enum UninstallerItem: Identifiable {
    case app(InstalledApplication)
    case tool(CommandLinePackage)
    var id: String {
        switch self {
        case .app(let app): return "app:" + app.id
        case .tool(let tool): return "tool:" + tool.id
        }
    }
    var name: String {
        switch self {
        case .app(let app): return app.name
        case .tool(let tool): return tool.name
        }
    }
}

struct ApplicationsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var showSystem = false
    @State private var showDependencies = false
    @State private var filter: UninstallerFilter = .all
    private var applications: [InstalledApplication] {
        guard filter != .tools else { return [] }
        return (model.inventory?.applications ?? []).filter {
            (showSystem || !$0.isSystem) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }
    private var tools: [CommandLinePackage] {
        guard filter != .apps else { return [] }
        return (model.commandLine?.packages ?? []).filter { tool in
            (showDependencies || (!tool.isDependency && !tool.isBundledWithRuntime))
                && (search.isEmpty || tool.name.localizedCaseInsensitiveContains(search) || tool.package.localizedCaseInsensitiveContains(search) || tool.commands.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    private var items: [UninstallerItem] {
        (applications.map(UninstallerItem.app) + tools.map(UninstallerItem.tool)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        PageHeading("Uninstaller", subtitle: "Files go to the Trash; packages go through their package manager.") {
            Button { model.loadApplications() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(GlowButtonStyle(.secondary)).disabled(model.inventoryLoading || model.commandLineLoading)
        }
        Card {
            SearchField(placeholder: "Find an app or tool", text: $search)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(UninstallerFilter.allCases, id: \.self) { option in
                    FilterChip(title: option.rawValue, selected: filter == option) { filter = option }
                }
                Toggle("Include macOS apps", isOn: $showSystem).toggleStyle(ViperCheckboxStyle()).font(.system(size: 12)).padding(.leading, 8)
                Toggle("Include dependencies and bundled tools", isOn: $showDependencies).toggleStyle(ViperCheckboxStyle()).font(.system(size: 12))
            }
            if model.inventoryLoading && filter != .tools {
                HStack(spacing: 10) { ScanPulse(color: Palette.lavender); Text("Reading application folders…").font(.system(size: 13)) }.padding(.vertical, 20)
            } else if let message = model.inventoryMessage, filter != .tools {
                InfoLine(text: message)
            }
            if filter != .apps {
                if model.commandLineLoading {
                    HStack(spacing: 10) { ScanPulse(color: Palette.blue); Text("Reading Homebrew and npm packages…").font(.system(size: 13)) }.padding(.vertical, 8)
                } else if let message = model.commandLineMessage {
                    InfoLine(text: message)
                }
            }
            if !model.inventoryLoading && items.isEmpty && !(filter == .tools && model.commandLineLoading) {
                EmptyPanel(framed: false, icon: "app.dashed", title: "Nothing matches.", detail: "Try another search or filter. Viper reads standard application folders plus Homebrew and global npm packages.")
            } else if !items.isEmpty {
                HStack {
                    Eyebrow(text: "\(applications.count) APPS · \(tools.count) TOOLS")
                    Spacer()
                    Text("Select an item to review and uninstall").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        switch item {
                        case .app(let app): ApplicationRow(app: app) { model.beginUninstall(.app(app)) }
                        case .tool(let tool): ToolRow(tool: tool) { model.beginUninstall(.tool(tool)) }
                        }
                    }
                }
            }
            if model.inventory != nil || model.commandLine != nil {
                Disclosure("Where Viper looked") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.inventory?.searchedFolders ?? [], id: \.self) { Text($0) }
                        ForEach(model.commandLine?.checks ?? []) { check in
                            Text("\(check.name): \(check.detail)").foregroundStyle(check.succeeded ? Palette.muted : Palette.ink)
                        }
                        Text("Apps elsewhere, tools installed without Homebrew or npm, and unmounted drives are not included. An App Store receipt is a source hint; it does not verify an app’s authenticity.")
                        if let unavailable = model.inventory?.unavailableFolders, !unavailable.isEmpty {
                            Text("Unavailable locations: \(unavailable.joined(separator: ", "))")
                        }
                    }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 8)
                }.font(.system(size: 12))
            }
        }
        .task {
            if model.inventory == nil { model.loadApplications() }
            else if model.commandLine == nil { model.loadCommandLineTools() }
        }
        .sheet(item: Binding(get: { model.uninstallSession }, set: { if $0 == nil { model.closeUninstall() } })) { session in
            UninstallSheet(session: session).environmentObject(model)
        }
    }
}

private struct ToolRow: View {
    let tool: CommandLinePackage
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ToolIcon(size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.name).font(.system(size: 13, weight: .semibold))
                    Text(tool.commands.isEmpty ? tool.sourceLabel : "\(tool.sourceLabel) · \(tool.commands.prefix(4).joined(separator: ", "))")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                if tool.isBundledWithRuntime { Tag(text: "WITH NODE.JS", color: Palette.yellow) }
                else if tool.isDependency { Tag(text: "DEPENDENCY", color: Palette.yellow) }
                Tag(text: "CLI", color: Palette.blue)
                Text(tool.version).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).frame(maxWidth: 140, alignment: .trailing)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Palette.lavender : Palette.faint)
                    .offset(x: hovering ? 3 : 0)
            }.padding(.vertical, 10).padding(.horizontal, 10)
                .rowHighlight(hovering: hovering)
                .contentShape(Rectangle())
                .animation(Motion.snappy, value: hovering)
        }.buttonStyle(.plain).onHover { hovering = $0 }.accessibilityLabel("\(tool.name), \(tool.source.rawValue), version \(tool.version). Review and uninstall.")
    }
}

struct ToolIcon: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "terminal").font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: size, height: size).glowTile(Palette.blue, radius: size * 0.26, glow: false)
    }
}

private struct ApplicationRow: View {
    let app: InstalledApplication
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(Palette.isWebsite ? 0 : 0.4), radius: Palette.isWebsite ? 0 : 4, y: Palette.isWebsite ? 0 : 2)
                    .scaleEffect(hovering ? 1.08 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.system(size: 13, weight: .semibold))
                    Text(app.sourceLabel).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if app.isSystem { Tag(text: "PROTECTED", color: Palette.yellow) }
                Text(app.version).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).frame(maxWidth: 140, alignment: .trailing)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Palette.lavender : Palette.faint)
                    .offset(x: hovering ? 3 : 0)
            }.padding(.vertical, 10).padding(.horizontal, 10)
                .rowHighlight(hovering: hovering)
                .contentShape(Rectangle())
                .animation(Motion.snappy, value: hovering)
        }.buttonStyle(.plain).onHover { hovering = $0 }.accessibilityLabel("\(app.name), version \(app.version). Review and uninstall.")
    }
}
