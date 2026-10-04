import SwiftUI
import ViperCore

/// Grouped, selectable review of cleanup items. Used by Junk & Leftovers and Storage.
struct CleanupReviewList: View {
    @EnvironmentObject private var model: AppModel
    let target: CleanupTarget
    var search = ""

    var body: some View {
        let state = model.cleanupState(target)
        let removed = Set(state.outcomes.filter { $0.result.succeeded && !$0.restored }.map(\.id))
        let items = (state.report?.items ?? []).filter { !removed.contains($0.id) && (search.isEmpty || $0.url.path.localizedCaseInsensitiveContains(search)) }
        VStack(alignment: .leading, spacing: 18) {
            ForEach(RemovalKind.allCases, id: \.self) { kind in
                let group = items.filter { $0.kind == kind }
                if !group.isEmpty { section(kind, items: group, state: state) }
            }
            if let kept = state.report?.kept, !kept.isEmpty {
                Disclosure("Kept (\(kept.count)) — found, but not offered") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(kept) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(displayPath(item.url)).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                    Text(item.reason).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Button { model.reveal(item.url) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(IconButtonStyle()).help("Reveal in Finder")
                            }
                        }
                    }.padding(.top, 8)
                }.font(.system(size: 12))
            }
        }
    }

    private func section(_ kind: RemovalKind, items: [RemovalItem], state: CleanupState) -> some View {
        let allSelected = items.allSatisfy { state.selection.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(kind.rawValue.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(Palette.ink.opacity(0.9))
                Text("\(items.count) · \(bytes(items.reduce(0) { $0 + ($1.size ?? 0) }))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                Spacer()
                Button(allSelected ? "Clear" : "Select all") { model.setCleanupItems(target, items, selected: !allSelected) }
                    .buttonStyle(LinkButtonStyle()).disabled(state.working)
            }.padding(.bottom, 8)
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    RemovalRow(item: item, selected: state.selection.contains(item.id)) { model.toggleCleanupItem(target, item) } reveal: { model.reveal(item.url) }
                    if item.id != items.last?.id { GlowDivider().padding(.horizontal, 12) }
                }
            }.glassPanel()
        }
    }
}

/// The primary action with its confirmation.
struct CleanupActionBar: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirming = false
    let target: CleanupTarget
    var count: Int
    var size: Int64
    var warned: Int = 0
    var action: () -> Void

    var body: some View {
        let working = model.cleanupState(target).working
        Card(color: Palette.mint) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 18)).frame(width: 44, height: 44).glowTile(Palette.mint, radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(working ? model.cleanupState(target).progress : "\(count) selected · \(bytes(size))").font(.cardTitle)
                        .contentTransition(.numericText()).animation(Motion.snappy, value: count)
                    Text("Items go to the Trash, so you can put them back. Space is freed when the Trash is emptied.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if working { ScanPulse() }
                Button { confirming = true } label: { Label("Move \(count) to Trash", systemImage: "trash") }
                    .buttonStyle(GlowButtonStyle(.danger))
                    .disabled(count == 0 || working || model.maintenanceBusy || model.installing)
            }
        }
        .confirmationDialog("Move \(count) item\(count == 1 ? "" : "s") to the Trash?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(bytes(size)) will move to the Trash. You can put everything back until the Trash is emptied." + (warned > 0 ? " \(warned) selected item\(warned == 1 ? " has" : "s have") a warning." : ""))
        }
    }
}

struct CleanupResultCard: View {
    @EnvironmentObject private var model: AppModel
    let target: CleanupTarget

    var body: some View {
        let state = model.cleanupState(target)
        let removed = state.outcomes.filter { $0.result.succeeded && !$0.restored }
        let restored = state.outcomes.filter(\.restored)
        let problems = state.outcomes.filter { !$0.result.succeeded }
        Card(color: problems.isEmpty ? Palette.mint : Palette.yellow) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(restored.count > 0 && removed.isEmpty ? "Put back \(restored.count) item\(restored.count == 1 ? "" : "s")."
                         : "Moved \(removed.count) item\(removed.count == 1 ? "" : "s") to the Trash · \(bytes(removed.reduce(0) { $0 + ($1.item.size ?? 0) }))")
                        .font(.cardTitle)
                    Text(problems.isEmpty ? "Empty the Trash to free the space." : "\(problems.count) item\(problems.count == 1 ? " was" : "s were") left alone. Details below.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if state.canPutBack {
                    Button { model.putBackCleanup(target) } label: { Label("Put back", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(GlowButtonStyle(.secondary))
                        .disabled(model.maintenanceBusy || model.installing)
                }
                Button("Done") { model.dismissCleanupResult(target) }.buttonStyle(GlowButtonStyle(.secondary))
            }
            if !problems.isEmpty {
                ForEach(problems) { outcome in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.yellow).frame(width: 16)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(outcome.item.url.lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                            if case .skipped(let reason) = outcome.result { Text(reason).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                            if case .failed(let reason) = outcome.result { Text(reason).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        }
                        Spacer()
                        Button { model.reveal(outcome.item.url) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(IconButtonStyle()).help("Reveal in Finder")
                    }
                }
            }
        }
    }
}

