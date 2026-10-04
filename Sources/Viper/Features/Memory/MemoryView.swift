import AppKit
import SwiftUI
import ViperCore

struct MemoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirming = false

    var body: some View {
        let state = model.memory
        PageHeading("Memory", subtitle: "Find apps and background processes holding memory you aren’t using.") {
            if state.loading {
                Button("Cancel scan") { model.cancelMemoryScan(); model.stopLiveMemoryUpdates() }.buttonStyle(GlowButtonStyle(.secondary))
            } else {
                Button { model.scanMemory(); model.startLiveMemoryUpdates() } label: { Label(state.report == nil ? "Scan" : "Scan again", systemImage: "viewfinder") }
                    .buttonStyle(GlowButtonStyle()).disabled(state.working)
            }
        }
        .onAppear { model.startLiveMemoryUpdates() }
        .onDisappear { model.stopLiveMemoryUpdates() }
        InfoLine(text: "macOS processes, anything launchd restarts, the app you’re using, and apps you open often are never offered. Apps quit normally and can ask to save.", icon: "shield")
        if state.loading {
            HStack(spacing: 10) { ScanPulse(color: Palette.teal); Text("Sampling processes twice, two seconds apart…").font(.system(size: 13)) }
        }
        if let status = state.report?.status { MemoryStatusCard(status: status, live: model.memoryRefreshTask != nil) }
        if !state.outcomes.isEmpty { MemoryResultCard() }
        if let report = state.report {
            if report.candidates.isEmpty && !state.loading {
                EmptyPanel(icon: "checkmark.seal", title: "Nothing worth quitting.",
                           detail: "Everything using meaningful memory is either in use, used often, or owned by macOS.")
            } else if !report.candidates.isEmpty {
                actionBar(state)
                sections(state, report: report)
            }
        } else if !state.loading {
            EmptyPanel(icon: "memorychip", title: "Ready when you are.",
                       detail: state.message ?? "Scan to see what’s holding memory. Nothing quits until you confirm.")
        }
    }

    private func actionBar(_ state: MemoryState) -> some View {
        let count = state.selection.count
        return Card(color: Palette.teal) {
            HStack(spacing: 14) {
                Image(systemName: "memorychip").font(.system(size: 18)).frame(width: 44, height: 44).glowTile(Palette.teal, radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.working ? state.progress : "Quit \(count) selected · about \(bytes(Int64(state.selectedFootprint)))")
                        .font(.cardTitle).contentTransition(.numericText())
                    Text(model.settings.allowReviewedChanges
                         ? "Apps quit normally and may ask to save. Background processes get a stop request."
                         : "Read-only safety mode is on — enable reviewed changes in Settings to quit anything.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if state.working { ScanPulse(color: Palette.teal) }
                Button { confirming = true } label: { Label("Quit \(count) selected", systemImage: "power") }
                    .buttonStyle(GlowButtonStyle(.danger))
                    .disabled(count == 0 || state.working || model.maintenanceBusy || model.installing || !model.settings.allowReviewedChanges)
            }
        }
        .confirmationDialog("Quit \(count) item\(count == 1 ? "" : "s")?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Quit", role: .destructive) { model.stopSelectedMemory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apps quit normally and may ask you to save. Background processes get a stop request. Nothing is force quit unless you ask.")
        }
    }

    private func sections(_ state: MemoryState, report: MemoryReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            MemorySection(title: "Recommended", candidates: report.recommended, state: state)
            MemorySection(title: "Your call", candidates: report.optional, state: state)
            if !report.kept.isEmpty {
                Card {
                    Disclosure("Kept (\(report.kept.count)) — found, but not offered") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.kept) { kept in
                                HStack(alignment: .top) {
                                    Text(kept.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                    Spacer()
                                    Text(bytes(Int64(kept.footprint))).font(.system(size: 11, design: .monospaced))
                                    Text(kept.reason).frame(maxWidth: 320, alignment: .trailing)
                                }
                            }
                        }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 8)
                    }.font(.system(size: 12))
                    Text(footer(report)).font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            }
        }
    }

    private func footer(_ report: MemoryReport) -> String {
        var text = "\(report.smallProcessCount) small processes use about \(bytes(Int64(report.smallProcessBytes))) in total and aren’t listed."
        if report.otherUserProcesses > 0 {
            text += " \(report.otherUserProcesses) processes belong to macOS or other users and aren’t shown."
        }
        text += " Updated \(report.sampledAt.formatted(date: .omitted, time: .standard))."
        return text
    }
}

private struct MemorySection: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let candidates: [MemoryCandidate]
    let state: MemoryState

    var body: some View {
        if !candidates.isEmpty {
            let allSelected = candidates.allSatisfy { state.selection.contains($0.id) }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(Palette.ink.opacity(0.9))
                    Text("\(candidates.count) · \(bytes(Int64(candidates.reduce(0) { $0 + $1.footprint })))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button(allSelected ? "Clear" : "Select all") { model.setMemoryCandidates(candidates, selected: !allSelected) }
                        .buttonStyle(LinkButtonStyle()).disabled(state.working)
                }.padding(.bottom, 8)
                LazyVStack(spacing: 0) {
                    ForEach(candidates) { candidate in
                        MemoryRow(candidate: candidate, selected: state.selection.contains(candidate.id)) { model.toggleMemoryCandidate(candidate) }
                        if candidate.id != candidates.last?.id { GlowDivider().padding(.horizontal, 12) }
                    }
                }.glassPanel()
            }
        }
    }
}

private struct MemoryRow: View {
    let candidate: MemoryCandidate
    let selected: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(get: { selected }, set: { _ in toggle() })) { EmptyView() }
                .toggleStyle(ViperCheckboxStyle()).accessibilityLabel("Include \(candidate.name)")
            icon.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(candidate.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    ForEach(candidate.listeningPorts, id: \.self) { Tag(text: ":\($0)", color: Palette.teal) }
                    if isBackground { Tag(text: "BACKGROUND", color: Palette.yellow) }
                    if candidate.hasTerminal { Tag(text: "TERMINAL", color: Palette.blue) }
                }
                Text(candidate.reasons.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = candidate.note {
                    Text(note).font(.system(size: 11)).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(bytes(Int64(candidate.footprint))).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
        }
        .padding(12)
        .background(Palette.isWebsite ? Palette.elevated.opacity(selected ? 1 : (hovering ? 0.7 : 0)) : (selected ? Palette.teal.opacity(0.05) : Color.white.opacity(hovering ? 0.04 : 0)))
        .animation(Motion.hover, value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { toggle() }
    }

    private var isBackground: Bool {
        guard case .app = candidate.kind else { return true }
        return candidate.cpuPercent >= 5 || candidate.wakeupsPerSecond >= 50
    }

    @ViewBuilder private var icon: some View {
        if let bundle = candidate.bundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundle)).resizable()
        } else {
            Image(systemName: "terminal").font(.system(size: 15, weight: .regular)).foregroundStyle(Palette.muted)
        }
    }
}

/// Whole-machine memory: segmented bar plus pressure, and a LIVE marker while ticks refresh the page.
private struct MemoryStatusCard: View {
    let status: MemoryStatus
    var live = false

    var body: some View {
        Card(color: pressureColor) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(bytes(Int64(status.used))) used of \(bytes(Int64(status.total)))").font(.system(size: 20, weight: .semibold)).tracking(-0.4).foregroundStyle(Palette.titleGradient)
                    Text(interpretation).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if live { Tag(text: "LIVE", color: Palette.mint, pulse: true) }
                Tag(text: status.pressure.rawValue.uppercased(), color: pressureColor)
            }
            MemoryBar(status: status)
            HStack(spacing: 14) {
                legend("App", MemoryBar.appColor)
                legend("Wired", MemoryBar.wiredColor)
                legend("Compressed", MemoryBar.compressedColor)
                legend("Cached", MemoryBar.cachedColor)
                Spacer()
                if status.swapUsed > 0 {
                    Text("Swap \(bytes(Int64(status.swapUsed)))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private var pressureColor: Color {
        switch status.pressure {
        case .normal: return Palette.mint
        case .warning: return Palette.yellow
        case .critical: return Palette.rose
        }
    }

    private var interpretation: String {
        status.pressure == .normal
            ? "Memory pressure is normal. macOS uses spare memory as cache, so quitting apps now is optional."
            : "Your Mac is short on memory and is compressing or swapping. Freeing the items below will help."
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Swatch(color: color, size: Palette.isWebsite ? 6 : 5)
            Text(name).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }
}

/// One track segmented into app / wired / compressed / cached, in the spirit of GlowMeter.
private struct MemoryBar: View {
    static var appColor: Color { Palette.isWebsite ? Palette.series[0] : Palette.lavender }
    static var wiredColor: Color { Palette.isWebsite ? Palette.series[4] : Palette.yellow }
    static var compressedColor: Color { Palette.isWebsite ? Palette.series[3] : Palette.blue }
    static var cachedColor: Color { Palette.isWebsite ? Palette.seriesRest : Palette.slate }
    let status: MemoryStatus
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let total = max(status.total, 1)
            let app = max(status.used - status.wired - status.compressed, 0)
            let segments: [(bytes: UInt64, color: Color)] = [
                (app, Self.appColor), (status.wired, Self.wiredColor),
                (status.compressed, Self.compressedColor), (status.cached, Self.cachedColor)
            ]
            ZStack(alignment: .leading) {
                if Palette.isWebsite {
                    FlatTrack(radius: 2)
                } else {
                    Capsule().fill(Color.black.opacity(0.3))
                        .overlay { Capsule().strokeBorder(LinearGradient(colors: [Color.black.opacity(0.3), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                }
                HStack(spacing: Palette.isWebsite ? 2 : 1) {
                    ForEach(segments.indices, id: \.self) { index in
                        let width = shown ? geometry.size.width * CGFloat(segments[index].bytes) / CGFloat(total) : 0
                        if Palette.isWebsite {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(segments[index].color).frame(width: width)
                        } else {
                            Capsule().fill(segments[index].color.opacity(0.85)).frame(width: width)
                        }
                    }
                }
            }
        }
        .frame(height: Palette.isWebsite ? 12 : 10)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(response: 1.1, dampingFraction: 0.86).delay(0.15)) { shown = true } }
        }
    }
}

/// What happened: stopped count + freed estimate, survivors with a force-quit offer, and reasons for skips.
private struct MemoryResultCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var forcing: MemoryStopOutcome?

    var body: some View {
        let outcomes = model.memory.outcomes
        let stopped = outcomes.filter { $0.result.succeeded }
        let survivors = outcomes.filter { $0.result.needsForce }
        let problems = outcomes.filter { !$0.result.succeeded && !$0.result.needsForce }
        let freed = stopped.reduce(Int64(0)) { sum, outcome in
            if case .stopped(let estimate) = outcome.result { return sum + Int64(estimate) }
            return sum
        }
        Card(color: problems.isEmpty && survivors.isEmpty ? Palette.mint : Palette.yellow) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Stopped \(stopped.count) item\(stopped.count == 1 ? "" : "s") · freed about \(bytes(freed))").font(.cardTitle)
                    Text(problems.isEmpty && survivors.isEmpty ? "Everything asked to stop has stopped."
                         : "\(survivors.count + problems.count) item\(survivors.count + problems.count == 1 ? "" : "s") need a decision. Details below.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Done") { model.memory.outcomes = [] }.buttonStyle(GlowButtonStyle(.secondary))
            }
            ForEach(survivors) { outcome in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.yellow).frame(width: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(outcome.candidate.name).font(.system(size: 12, weight: .semibold))
                        Text("Still running — it may be waiting for you to save, or it ignored the stop request.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button { forcing = outcome } label: { Label("Force quit", systemImage: "bolt") }
                        .buttonStyle(GlowButtonStyle(.danger, compact: true))
                }
            }
            ForEach(problems) { outcome in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.yellow).frame(width: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(outcome.candidate.name).font(.system(size: 12, weight: .semibold))
                        if case .skipped(let reason) = outcome.result { Text(reason).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        if case .failed(let reason) = outcome.result { Text(reason).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    }
                }
            }
        }
        .confirmationDialog("Force quit \(forcing?.candidate.name ?? "")?", isPresented: Binding(get: { forcing != nil }, set: { if !$0 { forcing = nil } }), titleVisibility: .visible) {
            if let forcing {
                Button("Force quit", role: .destructive) { model.forceQuitMemory(forcing); self.forcing = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Force quitting can lose unsaved work.")
        }
    }
}
