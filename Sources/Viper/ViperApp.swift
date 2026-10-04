import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { AppSettings.load().quitOnClose }
    func applicationWillTerminate(_ notification: Notification) { model?.cancelWork() }
    /// Waiting items are cancelled, but an install already in progress finishes before Viper quits.
    /// An in-flight update check is cancelled; quit resumes once it has unwound.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.maintenanceBusy {
            // Removals and updates in progress finish and record their outcome before Viper quits. Waiting updates are cancelled.
            model.cancelPendingUpdates()
            model.onMaintenanceSettled = { sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
        if model.checkingUpdates {
            model.cancelUpdateCheck()
            model.onUpdateCheckSettled = { sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
        guard model.installing else { return .terminateNow }
        model.cancelPendingInstalls()
        model.onInstallsSettled = { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Viper" }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

@main
struct ViperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Viper", id: "main") {
            RootView().environmentObject(model)
                .frame(minWidth: 960, minHeight: 680)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.page = .settings; showMainWindow() }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit Viper") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
            CommandMenu("Scan") {
                Button("Choose Folder…") { model.chooseFolder() }.keyboardShortcut("o").disabled(model.scanning)
                Button("Scan Selected Folder") { model.page = .storage; model.startScan() }.keyboardShortcut("r").disabled(model.scanning)
                Button("Cancel Scan") { model.cancelScan() }.disabled(!model.scanning)
            }
        }
        MenuBarExtra(isInserted: Binding(get: { model.settings.showMenuBar }, set: { value in
            if model.settings.showMenuBar != value { model.settings.showMenuBar = value }
        })) {
            ViperMenu().environmentObject(model)
        } label: {
            Label("Viper", systemImage: "v.square.fill")
        }
    }
    private func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Viper" })?.makeKeyAndOrderFront(nil)
    }
}

private struct ViperMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.uninstalling ? "Viper · Uninstalling" : model.cleaning ? "Viper · Cleaning" : model.updating ? "Viper · Updating" : model.installing ? "Viper · Installing apps" : model.freeingMemory ? "Viper · Freeing memory" : (model.scanning ? "Viper · Scanning storage" : (model.checkingUpdates ? "Viper · Checking updates" : (model.memory.loading ? "Viper · Scanning memory" : (model.leftovers.loading || model.junk.loading ? "Viper · Scanning for junk" : "Viper · Running, idle")))))
        Text(model.settings.allowReviewedChanges ? "Reviewed changes are on" : "Read-only — scans only")
        if let summary = model.scanSummary {
            Text("Last scan · \(summary.files.formatted()) files · \(bytes(summary.allocatedBytes)) allocated")
        }
        Divider()
        Button("Open Viper") { show(.overview) }
        Button(model.scanning ? "Scanning…" : "Scan \(model.selectedFolder.lastPathComponent)") { show(.storage); model.startScan() }
            .disabled(model.scanning)
        if model.settings.allowReviewedChanges {
            Button("Switch to read-only") { model.settings.allowReviewedChanges = false }
        } else {
            Button("Safety mode…") { show(.settings) }
        }
        Button("Settings…") { show(.settings) }
        Divider()
        Button("Quit Viper") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
    private func show(_ page: Page) {
        model.page = page
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            AmbientBackground(page: model.page)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: model.page)
            HStack(spacing: 0) {
                Sidebar().ignoresSafeArea(.container, edges: .top)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            Color.clear.frame(height: 0).id("top")
                            VStack(alignment: .leading, spacing: 22) {
                                switch model.page {
                                case .overview: OverviewView()
                                case .storage: StorageView()
                                case .uninstaller: ApplicationsView()
                                case .leftovers: LeftoversView()
                                case .memory: MemoryView()
                                case .updates: UpdatesView()
                                case .privacy: PrivacyView()
                                case .discover: DiscoverView()
                                case .settings: SettingsView()
                                }
                            }
                            .id(model.page)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 16)),
                                removal: .opacity))
                        }.padding(.horizontal, 34).padding(.top, -2).padding(.bottom, 36)
                            .frame(maxWidth: 1240, alignment: .leading).frame(maxWidth: .infinity)
                            .background(NoElasticScroll())
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: model.page) { proxy.scrollTo("top", anchor: .top) }
                }
                .animation(reduceMotion ? nil : Motion.smooth, value: model.page)
            }
        }
        .background(Palette.paper)
        // Disk space changes outside Viper, so re-read it at natural moments instead of polling.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshCapacity() }
        .onChange(of: model.page) { model.refreshCapacity() }
        .onChange(of: model.maintenanceBusy) { if !model.maintenanceBusy { model.refreshCapacity() } }
        .onChange(of: model.installing) { if !model.installing { model.refreshCapacity() } }
        .foregroundStyle(Palette.ink)
        .tint(Palette.lavender)
        .environment(\.colorScheme, .dark)
        .id(model.settings.theme)
        .alert("Viper", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }

}

/// Turns off elastic overscroll, which drags the content column away from the sidebar and exposes the seam between them.
private struct NoElasticScroll: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            var node = view.superview
            while let current = node {
                if let scrollView = current as? NSScrollView {
                    scrollView.verticalScrollElasticity = .none
                    scrollView.horizontalScrollElasticity = .none
                    break
                }
                node = current.superview
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A floating pane of frosted glass that holds navigation.
private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ViperMark(size: 36, active: model.activityLabel != nil)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Viper").font(.system(size: 19, weight: .semibold)).tracking(-0.5)
                    Text("Mac care").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(.top, 38).padding(.bottom, 26).padding(.leading, 6)
            ForEach(Page.allCases.filter { $0 != .settings }) { page in
                NavRow(page: page, selected: model.page == page, namespace: selection) { model.page = page }.padding(.bottom, 2)
            }
            GlowDivider().padding(.vertical, 12).padding(.horizontal, 6)
            NavRow(page: .settings, selected: model.page == .settings, namespace: selection) { model.page = .settings }
            Spacer(minLength: 18)
            // Viper-wide activity lives here, not over the page, so it never floats on top of headings or buttons.
            if let activity = model.activityLabel {
                Tag(text: activity, color: Palette.isWebsite ? Palette.signal : Palette.mint, pulse: true)
                    .padding(.leading, 6)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .accessibilityLabel("Viper is \(activity.lowercased())")
            }
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.system(size: 10)).foregroundStyle(Palette.faint).padding(.top, 12).padding(.bottom, 4).padding(.leading, 6)
        }
        .padding(12)
        .frame(width: 226).frame(maxHeight: .infinity)
        .background(GlassBackground(radius: 0, bordered: false))
        .overlay(alignment: .trailing) { if Palette.isWebsite { Rectangle().fill(Palette.line).frame(width: 1) } }
        .animation(reduceMotion ? nil : Motion.snappy, value: model.page)
        .animation(reduceMotion ? nil : Motion.smooth, value: model.activityLabel)
    }
}

/// Viper's mark: a small pane of glass with light passing through it. It breathes while Viper is changing something.
struct ViperMark: View {
    var size: CGFloat = 40
    var active = false
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * (Palette.isWebsite ? 0.24 : 0.3), style: .continuous)
        ZStack {
            Text("V").font(.system(size: size * 0.5, weight: Palette.isWebsite ? .bold : .semibold, design: .rounded))
                .foregroundStyle(Palette.isWebsite ? Palette.onAccent : Color.white)
            if Palette.isWebsite {
                // The orange square blinks while Viper is changing something, where Space breathes a glow.
                RoundedRectangle(cornerRadius: size * 0.045, style: .continuous).fill(Palette.orange)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .blink(active && !reduceMotion)
                    .offset(x: size * 0.33, y: size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .background {
            if Palette.isWebsite {
                shape.fill(Palette.cream)
            } else {
                shape.fill(Color.white.opacity(0.08))
                    .overlay { shape.fill(RadialGradient(colors: [Palette.ember.opacity(0.75), .clear], center: .bottomTrailing, startRadius: 0, endRadius: size)) }
                    .overlay { shape.fill(RadialGradient(colors: [Palette.violet.opacity(0.9), .clear], center: .topLeading, startRadius: 0, endRadius: size)) }
                    .overlay { GrainLayer(opacity: 0.14).clipShape(shape) }
                    .overlay { shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
            }
        }
        .shadow(color: Palette.violet.opacity(Palette.isWebsite ? 0 : (active && breathe ? 0.7 : 0.3)), radius: Palette.isWebsite ? 0 : (active && breathe ? 16 : 10), y: Palette.isWebsite ? 0 : 4)
        .onChange(of: active, initial: true) { _, isActive in
            guard !reduceMotion, !Palette.isWebsite else { return }
            if isActive {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathe = true }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { breathe = false }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct NavRow: View {
    let page: Page
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @State private var bounce = 0
    var body: some View {
        let activeInk = Palette.isWebsite && selected ? Palette.onAccent : Palette.ink
        let dot = Palette.isWebsite ? Palette.orange : page.aura[0]
        Button {
            bounce += 1
            action()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: page.icon).font(.system(size: 13.5, weight: .regular)).frame(width: 20)
                    .foregroundStyle(selected || hovering ? activeInk : Palette.muted)
                    .symbolEffect(.bounce, value: bounce)
                Text(page.rawValue).font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected || hovering ? activeInk : Palette.ink.opacity(0.68))
                Spacer(minLength: 0)
                if selected {
                    Swatch(color: dot, size: Palette.isWebsite ? 6 : 5, glow: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background {
                if selected {
                    GlassThumb(radius: Palette.isWebsite ? 9 : 11).matchedGeometryEffect(id: "nav-selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Palette.isWebsite ? 9 : 11, style: .continuous)
                        .fill(Palette.isWebsite ? Palette.elevated : Color.white.opacity(0.045))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .modifier(FocusHalo(kind: .rounded(Palette.isWebsite ? 9 : 11)))
        .animation(Motion.hover, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
