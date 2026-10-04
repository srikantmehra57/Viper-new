import SwiftUI
import ViperCore

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        PageHeading("Overview")
        if let capacity = model.capacity {
            let used = Double(capacity.usedBytes) / Double(max(1, capacity.totalBytes))
            Card {
                HStack(alignment: .center, spacing: 20) {
                    stat("Available", value: bytes(capacity.availableBytes),
                         caption: capacity.purgeableBytes > 0 ? "Includes \(bytes(capacity.purgeableBytes)) purgeable" : "Ready for new files")
                    stat("Used", value: bytes(capacity.usedBytes), caption: "Includes macOS and apps")
                    stat("Volume", value: capacity.name, caption: "\(bytes(capacity.totalBytes)) total")
                    HStack(spacing: 10) {
                        RingGauge(fraction: used, size: 56, lineWidth: 6) { EmptyView() }
                        Text("\(Int((used * 100).rounded()))% used").font(.system(size: 13, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Int((used * 100).rounded())) percent of disk used")
                }
            }
        }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Tools").font(.system(size: 20, weight: .medium)).tracking(-0.4)
            Text("Everything is reviewed before it changes.").font(.system(size: 12.5)).foregroundStyle(Palette.muted)
        }.padding(.top, 6)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            OverviewTile(index: 1, title: "Remove apps carefully", detail: "Review evidence-backed app, settings, cache, and package matches before removal.", icon: "app.badge", color: Palette.lavender, page: .uninstaller)
            OverviewTile(index: 2, title: "Clean junk and leftovers", detail: "Clear caches, logs, temporary files, and files from removed apps.", icon: "tray", color: Palette.yellow, page: .leftovers)
            OverviewTile(index: 3, title: "Set up your apps", detail: "Pick popular apps and install them together, with a clear review first.", icon: "plus.app", color: Palette.blue, page: .discover)
            OverviewTile(index: 4, title: "Stay up to date", detail: "See available app and tool updates, then choose what to update.", icon: "arrow.down.circle", color: Palette.mint, page: .updates)
            OverviewTile(index: 5, title: "Your privacy, clearly", detail: "Open the right permission setting, or reset an app’s permissions.", icon: "hand.raised", color: Palette.peach, page: .privacy)
            OverviewTile(index: 6, title: "Make space", detail: "See which folders and files take up space, then review anything you choose to move to the Trash.", icon: "internaldrive", color: Palette.teal, page: .storage)
        }
        InfoLine(text: "Every change is shown to you first. Removed files go to the Trash so you can put them back.", icon: "hand.thumbsup")
    }

    private func stat(_ label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: Palette.isWebsite ? 25 : 26, weight: Palette.isWebsite ? .semibold : .light)).tracking(-0.8).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OverviewTile: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let title: String
    let detail: String
    let icon: String
    let color: Color
    let page: Page
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { model.page = page } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: icon).font(.system(size: 17, weight: .regular)).frame(width: 42, height: 42)
                        .glowTile(color, radius: 12, glow: hovering)
                    Spacer()
                    Text(String(format: Palette.isWebsite ? "%03d" : "%02d", index)).font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 16.5, weight: Palette.isWebsite ? .semibold : .medium)).tracking(-0.2).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hovering ? Palette.ink : Palette.faint)
                        .offset(x: hovering && !reduceMotion ? 2 : 0, y: hovering && !reduceMotion ? -2 : 0)
                }
                Text(detail).font(Palette.isWebsite ? .system(size: 12.5, design: .serif) : .system(size: 12.5)).foregroundStyle(Palette.muted).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background(GlassBackground(tint: hovering ? color : nil, radius: 22, selected: hovering))
            .glassAura(color, color, intensity: hovering ? 0.35 : 0)
            .offset(y: hovering && !reduceMotion ? -3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Motion.smooth, value: hovering)
        .riseIn(delay: 0.04 * Double(index))
        .accessibilityLabel("\(title). \(detail)")
    }
}
