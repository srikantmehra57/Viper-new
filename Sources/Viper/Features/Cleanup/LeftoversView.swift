import SwiftUI
import ViperCore

struct LeftoversView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: CleanupTarget = .junk
    @State private var search = ""

    var body: some View {
        let state = model.cleanupState(tab)
        PageHeading("Junk & Leftovers", subtitle: tab == .junk ? "Caches, logs, old temporary files, and build data." : "Files from apps that are no longer installed.") {
            if state.loading {
                Button("Cancel scan") { model.cancelCleanupScan(tab) }.buttonStyle(GlowButtonStyle(.secondary))
            } else {
                Button { model.scanCleanup(tab) } label: { Label(state.report == nil ? "Scan" : "Scan again", systemImage: "viewfinder") }
                    .buttonStyle(GlowButtonStyle()).disabled(state.working)
            }
        }
        SegmentedTabs(options: [CleanupTarget.junk, .leftovers], title: \.rawValue, selection: Binding(get: { tab }, set: { tab = $0; search = "" }))
        InfoLine(text: tab == .junk ? "Items belonging to apps that are open right now are kept. Safe-to-rebuild items are selected; slower-to-rebuild items are listed for you to choose."
                 : "Caches, logs, and saved state are selected. Settings and app data are listed unselected, because an app on an unmounted drive may still use them.", icon: "shield")
        if state.loading {
            HStack(spacing: 10) { ScanPulse(color: Palette.yellow); Text(tab == .junk ? "Measuring caches, logs, and temporary files…" : "Checking app ownership…").font(.system(size: 13)) }
        }
        if !state.outcomes.isEmpty { CleanupResultCard(target: tab) }
        if let report = state.report {
            if report.items.isEmpty {
                EmptyPanel(icon: "checkmark.seal", title: tab == .junk ? "No junk found." : "No leftovers found.", detail: "This scan covers the locations listed below.")
            } else {
                CleanupActionBar(target: tab, count: state.selection.count, size: state.selectedBytes, warned: state.selectedItems.filter { $0.warning != nil }.count) {
                    model.cleanSelected(tab)
                }
                Card {
                    HStack {
                        Text("\(report.items.count) items · \(bytes(report.totalBytes))").font(.system(size: 20, weight: .semibold)).tracking(-0.4).foregroundStyle(Palette.titleGradient)
                        Spacer()
                        Text(report.completedAt.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    SearchField(placeholder: "Search results", text: $search)
                    CleanupReviewList(target: tab, search: search)
                    Disclosure("Scan coverage") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.locations, id: \.self) { Text(displayPath(URL(fileURLWithPath: $0))) }
                            if !report.unavailable.isEmpty { Text("Couldn’t read: \(report.unavailable.joined(separator: ", "))") }
                            Text(tab == .junk ? "macOS system caches, iCloud data, and Viper’s own cache are skipped. Folders are measured, never opened."
                                 : "Only third-party reverse-DNS identifiers are considered. Apple items, symbolic links, and anything matching an installed or running app are excluded.")
                        }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 6)
                    }.font(.system(size: 12))
                }
            }
        } else if !state.loading {
            EmptyPanel(icon: "tray", title: "Ready when you are.", detail: state.message ?? "Scan to see what can be cleaned. Nothing moves until you confirm.")
        }
    }
}
