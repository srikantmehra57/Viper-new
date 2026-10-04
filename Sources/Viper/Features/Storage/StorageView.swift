import SwiftUI
import ViperCore

struct CapacityCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Card(color: Palette.blue) {
            HStack {
                Label(model.capacity?.name ?? "Disk capacity", systemImage: "internaldrive").font(.system(size: 13.5, weight: .medium))
                Spacer()
                Eyebrow(text: "VOLUME")
            }
            if let capacity = model.capacity {
                let used = min(1, max(0, Double(capacity.usedBytes) / Double(max(1, capacity.totalBytes))))
                // Website draws one solid ink for "used"; Space lights it with a blue-to-violet blend.
                let usedColors = Palette.isWebsite ? [Palette.signal] : [Palette.blue, Palette.lavender]
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(bytes(capacity.availableBytes)).font(.system(size: Palette.isWebsite ? 32 : 34, weight: Palette.isWebsite ? .semibold : .light)).tracking(-1.2).monospacedDigit()
                                .contentTransition(.numericText())
                            Text("available of \(bytes(capacity.totalBytes))").font(.system(size: 12)).foregroundStyle(Palette.muted)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        GlowMeter(fraction: used, colors: usedColors, height: 9)
                            .accessibilityLabel("\(bytes(capacity.usedBytes)) used, \(bytes(capacity.availableBytes)) available")
                        HStack(spacing: 14) {
                            HStack(spacing: 5) {
                                Swatch(color: usedColors[0], size: 6)
                                Text("\(bytes(capacity.usedBytes)) used")
                            }
                            HStack(spacing: 5) {
                                Swatch(color: Palette.isWebsite ? Palette.ink.opacity(0.22) : Palette.slate, size: 6)
                                Text("\(bytes(capacity.availableBytes)) available")
                            }
                        }.font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    RingGauge(fraction: used, size: 112, lineWidth: Palette.isWebsite ? 6 : 9, colors: usedColors) {
                        VStack(spacing: 2) {
                            Text("\(Int((used * 100).rounded()))%")
                                .font(.system(size: Palette.isWebsite ? 22 : 24, weight: Palette.isWebsite ? .semibold : .medium)).monospacedDigit()
                            Text("USED").font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1).foregroundStyle(Palette.muted)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Volume space used")
                    .accessibilityValue("\(bytes(capacity.usedBytes)) of \(bytes(capacity.totalBytes))")
                }
                Text(capacity.purgeableBytes > 0
                     ? "Available includes \(bytes(capacity.purgeableBytes)) macOS can free automatically."
                     : "Volume usage includes macOS and data outside the folder you scan.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            } else {
                InfoLine(text: model.capacityError ?? "Capacity is unavailable.")
            }
        }
    }
}

struct StorageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: StorageCategory?
    @State private var search = ""
    var body: some View {
        PageHeading("Storage", subtitle: model.selectedFolder.path) {
            Button("Choose folder") { model.chooseFolder() }.buttonStyle(GlowButtonStyle(.secondary))
                .disabled(model.scanning || model.storageCleanup.working)
            if model.scanning {
                Button("Cancel scan") { model.cancelScan() }.buttonStyle(GlowButtonStyle(.secondary))
            } else {
                Button { filter = nil; search = ""; model.startScan() } label: { Label(model.scan == nil ? "Scan folder" : "Scan again", systemImage: "viewfinder") }
                    .buttonStyle(GlowButtonStyle()).disabled(model.storageCleanup.working)
            }
        }
        .onChange(of: model.selectedFolder) { _, _ in filter = nil; search = "" }
        CapacityCard()
        if model.scanning {
            HStack(spacing: 12) {
                ScanPulse()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Looking through your files…").font(.system(size: 13, weight: .semibold))
                    if let progress = model.progress {
                        Text("\(progress.files.formatted()) files · \(bytes(progress.allocatedBytes)) on disk · \(progress.currentFolder)")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    } else { Text("Preparing the scan. You can cancel at any time.").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                }
            }
        } else if let message = model.scanMessage {
            InfoLine(text: message, icon: model.scan == nil ? "info.circle" : "checkmark.circle")
        } else {
            InfoLine(text: "Scans stay on this volume. Cloud-only files and symbolic links are skipped. Your exclusions and hidden-file preference apply.")
        }
        if let result = model.scan {
            scanSummary(result)
            if !model.storageCleanup.outcomes.isEmpty { CleanupResultCard(target: .storage) }
            if !model.storageSelection.isEmpty || model.storageCleanup.working {
                let selected = result.largestFiles.filter { model.storageSelection.contains($0.id) }
                CleanupActionBar(target: .storage, count: selected.count, size: selected.reduce(0) { $0 + $1.allocatedBytes }) { model.cleanSelected(.storage) }
            }
            fileList(result)
        } else if !model.scanning {
            if let summary = model.scanSummary, summary.root == model.selectedFolder.path {
                savedSummary(summary)
            }
            EmptyPanel(icon: "magnifyingglass", title: "Your files have a story.", detail: "Scan a folder to see its categories and up to \(model.settings.storageResultLimit.formatted()) largest files. Try Downloads for a quick first look.")
        }
    }

    private func savedSummary(_ summary: StoredScanSummary) -> some View {
        Card {
            HStack {
                Text("Last scan").font(.cardTitle)
                Spacer()
                Text(summary.completedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Text("\(summary.files.formatted()) files · \(bytes(summary.allocatedBytes)) allocated. This is an estimate kept from the last scan. Scan again to see the largest files.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if !summary.largestFolders.isEmpty {
                ForEach(summary.largestFolders, id: \.path) { folder in
                    HStack {
                        Text(folder.name).lineLimit(1)
                        Spacer()
                        Text(bytes(folder.allocatedBytes)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                        Button("Look inside") { model.lookInside(URL(fileURLWithPath: folder.path)) }
                            .buttonStyle(GlowButtonStyle(.secondary, compact: true)).disabled(model.storageCleanup.working)
                    }.font(.system(size: 12))
                }
            }
        }
    }

    private func scanSummary(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.storageCleanup.outcomes.isEmpty {
                InfoLine(text: "This scan predates the cleanup results below. Scan again to update the space map and totals.", icon: "arrow.clockwise")
            } else if Date().timeIntervalSince(result.completedAt) > 1_800 {
                InfoLine(text: "This scan is over 30 minutes old. Sizes and contents may have changed; scan again for current numbers.", icon: "clock.badge.exclamationmark")
            }
            StorageMapCard(result: result).disabled(model.storageCleanup.working)
            HStack(spacing: 14) {
                metric("ALLOCATED", value: bytes(result.allocatedBytes), color: Palette.lavender)
                metric("FILES COUNTED", value: result.files.formatted(), color: Palette.mint)
                metric("COVERAGE", value: result.hasLimitedCoverage ? "Partial" : "Accessible files", color: result.hasLimitedCoverage ? Palette.yellow : Palette.blue)
            }
            Card {
                HStack {
                    Text("By file type").font(.cardTitle)
                    Spacer()
                    Text("Scanned \(RelativeDateTimeFormatter().localizedString(for: result.completedAt, relativeTo: Date()))")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).help(result.completedAt.formatted(date: .abbreviated, time: .standard))
                }
                if result.allocatedBytes > 0 {
                    CategoryBar(result: result).accessibilityHidden(true)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(StorageCategory.allCases) { category in
                            if let size = result.categories[category], size > 0 {
                                let selected = filter == category
                                Button { filter = selected ? nil : category } label: {
                                    HStack(spacing: 8) {
                                        Swatch(color: Palette.category(category), size: 8, glow: 4, glowOpacity: 0.8)
                                        Text(category.rawValue).lineLimit(1)
                                        Spacer(minLength: 6)
                                        Text(storageShare(size, of: result.allocatedBytes)).foregroundStyle(Palette.muted)
                                        Text(bytes(size)).foregroundStyle(Palette.ink)
                                    }
                                    .font(.system(size: 11.5, weight: .medium))
                                    .padding(.horizontal, 9).padding(.vertical, 8)
                                    .background {
                                        let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? 7 : 9, style: .continuous)
                                        if Palette.isWebsite {
                                            shape.fill(selected ? Palette.category(category).opacity(0.14) : Palette.surface.opacity(0.7))
                                                .overlay { shape.strokeBorder(selected ? Palette.category(category).opacity(0.7) : Palette.line, lineWidth: 1) }
                                        } else {
                                            shape.fill(selected ? Palette.category(category).opacity(0.14) : Color.white.opacity(0.03))
                                        }
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                                .modifier(FocusHalo(kind: .rounded(9)))
                                .accessibilityLabel("\(category.rawValue), \(bytes(size)), \(storageShare(size, of: result.allocatedBytes)) of this scan")
                                .accessibilityHint("Filter the largest-file list")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                    Text("Select a type to filter the largest-file list. Totals include all files counted in this folder.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                } else {
                    InfoLine(text: "No allocated file space to break down in this folder.")
                }
                Disclosure("How this is counted") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("File contents: \(bytes(result.logicalBytes)). Allocated disk space: \(bytes(result.allocatedBytes)). APFS clones, compression, snapshots, and purgeable storage can make these totals differ from your disk’s used space. These are not reclaimable-space estimates.")
                        Text("Skipped: \(result.skippedLinks) symbolic links, \(result.skippedCloudItems) cloud-only items, \(result.duplicateHardLinks) duplicate hard links, and \(result.omittedVolumes) entries on other volumes.")
                        Text("Unreadable items: \(result.unreadableCount). Categories are estimates based on file extensions and locations; system files are not independently classified.")
                        ForEach(result.unreadableExamples, id: \.self) { Text($0).textSelection(.enabled) }
                    }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 8)
                }.font(.system(size: 12))
                if result.unreadableCount > 0 {
                    HStack {
                        InfoLine(text: "Some locations couldn’t be read. You can allow broader access, then scan again.", icon: "exclamationmark.circle")
                        Spacer()
                        Button("Access settings") { model.openSettings("com.apple.preference.security?Privacy_AllFiles") }.buttonStyle(LinkButtonStyle())
                    }
                }
            }
        }
    }

    private func metric(_ title: String, value: String, color: Color) -> some View {
        Card(color: color) {
            HStack(spacing: 6) {
                Swatch(color: color, size: 6, glow: 4)
                Eyebrow(text: title)
            }
            Text(value).font(.system(size: 24, weight: Palette.isWebsite ? .semibold : .medium)).tracking(-0.6).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(Palette.titleGradient)
            if title == "ALLOCATED" {
                Text("Estimate, not reclaimable space").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
    }

    private func fileList(_ result: ScanResult) -> some View {
        let removed = Set(model.storageCleanup.outcomes.filter { $0.result.succeeded && !$0.restored }.map(\.id))
        let files = result.largestFiles.filter {
            !removed.contains($0.id) && (filter == nil || $0.category == filter) && (search.isEmpty || $0.url.path.localizedCaseInsensitiveContains(search))
        }
        return Card {
            HStack {
                Text("The biggest files").font(.cardTitle)
                Spacer()
                Tag(text: "TOP \(result.largestFiles.count) · ON DISK")
            }
            HStack {
                SearchField(placeholder: "Search largest files", text: $search)
                ViperSelect(title: "Category", selection: $filter, options: [("All categories", Optional<StorageCategory>.none)] + StorageCategory.allCases.map { ($0.rawValue, Optional($0)) }).frame(width: 180)
            }
            if files.isEmpty {
                Text(result.files == 0 ? "No accessible regular files were found in this folder." : "No files match these filters within the \(result.largestFiles.count) retained results.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(files) { file in
                        FileRow(file: file)
                    }
                }
            }
            InfoLine(text: "Large doesn’t mean unnecessary. Select files you’re sure about; each is re-checked (best effort) before it moves to the Trash. Files inside apps and system locations can’t be selected.")
        }
    }
}

private struct FileRow: View {
    @EnvironmentObject private var model: AppModel
    let file: StorageFile
    @State private var hovering = false
    var body: some View {
        let blocked = StorageCleanup.blockedReason(file.url)
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { model.storageSelection.contains(file.id) }, set: { on in
                if on { model.storageSelection.insert(file.id) } else { model.storageSelection.remove(file.id) }
            })) { EmptyView() }
                .toggleStyle(ViperCheckboxStyle()).disabled(blocked != nil || model.storageCleanup.working)
                .help(blocked ?? "Select to move to the Trash").accessibilityLabel("Select \(file.url.lastPathComponent)")
            Image(systemName: "doc.fill").font(.system(size: 15)).frame(width: 36, height: 36)
                .glowTile(Palette.category(file.category), radius: 10, glow: hovering)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.url.lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(blocked.map { "Can’t be removed here · " + $0 } ?? file.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle)
            }.help(file.url.path)
            Spacer(minLength: 8)
            Text(bytes(file.allocatedBytes)).font(.system(size: 12, weight: .semibold, design: .monospaced))
            Button { model.reveal(file.url) } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 15)) }
                .buttonStyle(IconButtonStyle()).help("Reveal in Finder").accessibilityLabel("Reveal \(file.url.lastPathComponent) in Finder")
        }.padding(.vertical, 10).padding(.horizontal, 10)
            .rowHighlight(hovering: hovering, selected: model.storageSelection.contains(file.id))
            .onHover { hovering = $0 }
    }
}

private func storageShare(_ count: Int64, of total: Int64) -> String {
    guard count > 0 else { return "0%" }
    let percent = 100 * Double(count) / Double(max(1, total))
    if percent < 0.1 { return "<0.1%" }
    if percent < 1 { return String(format: "%.1f%%", percent) }
    return "\(Int(percent.rounded()))%"
}

private func mapColor(_ item: StorageMapItem, index: Int) -> Color {
    if item.kind == .remaining { return Palette.seriesRest }
    // Space keeps its original tile order; the Website theme leads with the site's orange.
    let order = Palette.isWebsite ? [0, 1, 3, 2, 4, 7] : [3, 0, 1, 2, 4, 7]
    return Palette.series[order[index % order.count]]
}

private func mapDescription(_ item: StorageMapItem, total: Int64) -> String {
    let kind = item.kind == .folder ? "folder" : item.kind == .file ? "file" : "group"
    return "\(item.name) \(kind), \(bytes(item.allocatedBytes)), \(storageShare(item.allocatedBytes, of: total)) of this scan, \(item.files.formatted()) \(item.files == 1 ? "file" : "files")"
}

private struct StorageMapCard: View {
    @EnvironmentObject private var model: AppModel
    let result: ScanResult

    var body: some View {
        let items = result.mapItems
        let shownFolders = Set(items.filter { $0.kind == .folder }.compactMap(\.url))
        let moreFolders = result.largestFolders.filter { !shownFolders.contains($0.url) }
        Card(color: Palette.blue) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Space map").font(.cardTitle)
                    Text("Area compares \(bytes(result.allocatedBytes)) counted inside \(result.root.lastPathComponent), not the whole volume.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Tag(text: result.hasLimitedCoverage ? "PARTIAL SCAN" : "FOLDER SCAN", color: result.hasLimitedCoverage ? Palette.yellow : Palette.blue)
            }
            if items.isEmpty {
                InfoLine(text: "There’s no allocated file space to map in this folder. Try scanning a different folder.")
            } else {
                StorageTreemap(items: items, total: result.allocatedBytes, activate: activate)
                    .frame(height: 270).padding(3).glassPanel(radius: 16)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Space map for \(result.root.lastPathComponent)")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 8) {
                    ForEach(items.indices, id: \.self) { index in
                        StorageMapLegend(item: items[index], color: mapColor(items[index], index: index),
                                         total: result.allocatedBytes, activate: activate)
                    }
                }
                if !moreFolders.isEmpty {
                    Disclosure("More folders (\(moreFolders.count))") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(moreFolders, id: \.url) { folder in
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill").foregroundStyle(Palette.muted)
                                    Text(folder.name).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text("\(bytes(folder.allocatedBytes)) · \(folder.files.formatted()) files")
                                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                                    Button("Look inside") { model.lookInside(folder.url) }
                                        .buttonStyle(GlowButtonStyle(.secondary, compact: true))
                                }
                            }
                        }.padding(.top, 8)
                    }.font(.system(size: 12))
                }
                Text("Click a folder to scan inside or a file to reveal in Finder. Smaller items are grouped as Other; excluded and unreadable locations are omitted.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func activate(_ item: StorageMapItem) {
        guard let url = item.url else { return }
        switch item.kind {
        case .folder: model.lookInside(url)
        case .file: model.reveal(url)
        case .remaining: break
        }
    }
}

private struct StorageTreemap: View {
    let items: [StorageMapItem]
    let total: Int64
    let activate: (StorageMapItem) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(StorageMapLayout.tiles(items, in: CGRect(origin: .zero, size: geometry.size))) { tile in
                    StorageMapTile(item: tile.item, color: mapColor(tile.item, index: tile.index),
                                   total: total, activate: activate)
                        .frame(width: max(0, tile.rect.width - 6), height: max(0, tile.rect.height - 6))
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                }
            }
        }
    }
}

private struct StorageMapTile: View {
    let item: StorageMapItem
    let color: Color
    let total: Int64
    let activate: (StorageMapItem) -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if item.url != nil {
                Button { activate(item) } label: { surface }
                    .buttonStyle(.plain)
                    .modifier(FocusHalo(kind: .rounded(12)))
                    .onHover { hovering = $0 }
                    .animation(reduceMotion ? nil : Motion.hover, value: hovering)
                    .accessibilityLabel(mapDescription(item, total: total))
                    .accessibilityHint(item.kind == .folder ? "Scan inside this folder" : "Reveal this file in Finder")
            } else {
                surface.accessibilityElement(children: .ignore).accessibilityLabel(mapDescription(item, total: total))
            }
        }
        .help(item.url?.path ?? mapDescription(item, total: total))
    }

    private var surface: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? 6 : 12, style: .continuous)
            ZStack(alignment: .topLeading) {
                if Palette.isWebsite {
                    // Flat ink wash in the tile's series colour, with a solid rule along the top edge.
                    shape.fill(Palette.surface)
                    shape.fill(color.opacity(hovering ? 0.26 : 0.15))
                    Rectangle().fill(color).frame(height: 2).frame(maxHeight: .infinity, alignment: .top)
                    shape.strokeBorder(color.opacity(hovering ? 0.9 : 0.4), lineWidth: 1)
                } else {
                    shape.fill(Color.white.opacity(0.035))
                    shape.fill(RadialGradient(colors: [color.opacity(hovering ? 0.52 : 0.38), color.opacity(0.12), .clear],
                                              center: .topLeading, startRadius: 0, endRadius: max(geometry.size.width, geometry.size.height)))
                    shape.strokeBorder(color.opacity(hovering ? 0.7 : 0.35), lineWidth: 1)
                }
                if geometry.size.width >= 90 && geometry.size.height >= 48 {
                    VStack(alignment: .leading, spacing: 4) {
                        if geometry.size.height >= 98 {
                            HStack {
                                Swatch(color: color, size: 7, glow: 5)
                                Spacer()
                                if item.url != nil {
                                    Image(systemName: item.kind == .folder ? "arrow.up.right" : "arrow.up.right.square")
                                        .font(.system(size: 10)).foregroundStyle(Palette.isWebsite ? Palette.ink.opacity(0.7) : Palette.muted)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        Text(item.name).font(.system(size: geometry.size.width < 140 ? 11 : 13, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        if geometry.size.width >= 140 && geometry.size.height >= 100 {
                            Text("\(bytes(item.allocatedBytes)) · \(storageShare(item.allocatedBytes, of: total))")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.ink.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
        }
    }
}

private struct StorageMapLegend: View {
    let item: StorageMapItem
    let color: Color
    let total: Int64
    let activate: (StorageMapItem) -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if item.url != nil {
                Button { activate(item) } label: { content }
                    .buttonStyle(.plain)
                    .modifier(FocusHalo(kind: .rounded(9)))
                    .onHover { hovering = $0 }
                    .animation(reduceMotion ? nil : Motion.hover, value: hovering)
                    .accessibilityLabel(mapDescription(item, total: total))
                    .accessibilityHint(item.kind == .folder ? "Scan inside this folder" : "Reveal this file in Finder")
            } else {
                content.accessibilityElement(children: .ignore).accessibilityLabel(mapDescription(item, total: total))
            }
        }
        .help(item.url?.path ?? mapDescription(item, total: total))
    }

    private var content: some View {
        HStack(spacing: 8) {
            Swatch(color: color, size: 7, glow: 4, glowOpacity: 0.65)
            Text(item.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text(bytes(item.allocatedBytes)).font(.system(size: 11, weight: .medium, design: .monospaced))
            Text(storageShare(item.allocatedBytes, of: total)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
            if item.url != nil {
                Image(systemName: item.kind == .folder ? "arrow.up.right" : "arrow.up.right.square")
                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 9)
        .background {
            let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? 7 : 9, style: .continuous)
            if Palette.isWebsite {
                shape.fill(Palette.elevated.opacity(hovering ? 1 : 0.55))
                    .overlay { shape.strokeBorder(hovering ? color.opacity(0.7) : Palette.line, lineWidth: 1) }
            } else {
                shape.fill(Color.white.opacity(hovering ? 0.08 : 0.03))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct StorageMapLayout {
    struct Tile: Identifiable {
        let index: Int
        let item: StorageMapItem
        let rect: CGRect
        var id: String { item.id }
    }

    static func tiles(_ items: [StorageMapItem], in rect: CGRect) -> [Tile] {
        place(items.enumerated().map { (index: $0.offset, item: $0.element) }, in: rect)
    }

    private static func place(_ items: [(index: Int, item: StorageMapItem)], in rect: CGRect) -> [Tile] {
        guard let first = items.first else { return [] }
        guard items.count > 1 else { return [Tile(index: first.index, item: first.item, rect: rect)] }
        let total = items.reduce(0.0) { $0 + Double($1.item.allocatedBytes) }
        let middle = total / 2
        var firstTotal = Double(first.item.allocatedBytes)
        var split = 1
        while split < items.count - 1 {
            let next = Double(items[split].item.allocatedBytes)
            if abs(firstTotal - middle) <= abs(firstTotal + next - middle) { break }
            firstTotal += next
            split += 1
        }
        let fraction = CGFloat(firstTotal / total)
        let leading: CGRect
        let trailing: CGRect
        if rect.width >= rect.height {
            let x = rect.minX + rect.width * fraction
            leading = CGRect(x: rect.minX, y: rect.minY, width: x - rect.minX, height: rect.height)
            trailing = CGRect(x: x, y: rect.minY, width: rect.maxX - x, height: rect.height)
        } else {
            let y = rect.minY + rect.height * fraction
            leading = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: y - rect.minY)
            trailing = CGRect(x: rect.minX, y: y, width: rect.width, height: rect.maxY - y)
        }
        return place(Array(items[..<split]), in: leading) + place(Array(items[split...]), in: trailing)
    }
}

private struct CategoryBar: View {
    let result: ScanResult
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let visible = StorageCategory.allCases.filter { (result.categories[$0] ?? 0) > 0 }
        let gap: CGFloat = Palette.isWebsite ? 2 : 3
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - CGFloat(max(0, visible.count - 1)) * gap)
            HStack(spacing: gap) {
                ForEach(visible) { category in
                    let size = result.categories[category] ?? 0
                    let color = Palette.category(category)
                    let segment = width * CGFloat(size) / CGFloat(max(1, result.allocatedBytes)) * (shown ? 1 : 0)
                    if Palette.isWebsite {
                        // Flat, square-ended blocks, like a printed stacked bar.
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(color).frame(width: segment)
                    } else {
                        Capsule().fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                            .frame(width: segment)
                            .shadow(color: color.opacity(0.55), radius: 6)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Palette.isWebsite ? 12 : 14)
        .background {
            if Palette.isWebsite { FlatTrack(radius: 2) }
            else { Capsule().fill(Color.black.opacity(0.25)).overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1)) }
        }
        .onAppear { if reduceMotion { shown = true } else { withAnimation(.spring(response: 1, dampingFraction: 0.85).delay(0.1)) { shown = true } } }
    }
}
