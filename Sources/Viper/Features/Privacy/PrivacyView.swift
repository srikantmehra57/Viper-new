import AppKit
import SwiftUI
import ViperCore

struct PrivacyCategory: Identifiable {
    let name: String
    let icon: String
    let detail: String
    let destination: String
    var id: String { name }

    static let all: [Self] = [
        .init(name: "Camera", icon: "camera", detail: "Which apps can use your camera.", destination: "com.apple.preference.security?Privacy_Camera"),
        .init(name: "Microphone", icon: "mic", detail: "Which apps can listen through your microphone.", destination: "com.apple.preference.security?Privacy_Microphone"),
        .init(name: "Location Services", icon: "location", detail: "Which apps can use your location.", destination: "com.apple.preference.security?Privacy_LocationServices"),
        .init(name: "Screen & System Audio Recording", icon: "rectangle.dashed.badge.record", detail: "Access to record your screen and system audio.", destination: "com.apple.preference.security?Privacy_ScreenCapture"),
        .init(name: "Accessibility", icon: "accessibility", detail: "Apps that can control parts of your Mac.", destination: "com.apple.preference.security?Privacy_Accessibility"),
        .init(name: "Input Monitoring", icon: "keyboard", detail: "Apps that can monitor keyboard and other input.", destination: "com.apple.preference.security?Privacy_ListenEvent"),
        .init(name: "Full Disk Access", icon: "internaldrive", detail: "Access to protected files and app data.", destination: "com.apple.preference.security?Privacy_AllFiles"),
        .init(name: "Files & Folders", icon: "folder", detail: "Access to locations such as Documents and Downloads.", destination: "com.apple.preference.security?Privacy_FilesAndFolders"),
        .init(name: "Automation", icon: "gearshape.2", detail: "Apps that can ask other apps to perform actions.", destination: "com.apple.preference.security?Privacy_Automation"),
        .init(name: "Notifications", icon: "bell", detail: "Banners, sounds, and notification previews.", destination: "com.apple.Notifications-Settings.extension"),
        .init(name: "Contacts", icon: "person.crop.rectangle", detail: "Access to your address book.", destination: "com.apple.preference.security?Privacy_Contacts"),
        .init(name: "Calendars", icon: "calendar", detail: "Access to your calendar events.", destination: "com.apple.preference.security?Privacy_Calendars"),
        .init(name: "Reminders", icon: "checklist", detail: "Access to your lists and reminders.", destination: "com.apple.preference.security?Privacy_Reminders"),
        .init(name: "Photos", icon: "photo", detail: "Access to your photo library.", destination: "com.apple.preference.security?Privacy_Photos"),
        .init(name: "Bluetooth", icon: "antenna.radiowaves.left.and.right", detail: "Apps that communicate with Bluetooth devices.", destination: "com.apple.preference.security?Privacy_Bluetooth"),
        .init(name: "All Privacy Settings", icon: "hand.raised", detail: "More categories available on your macOS version.", destination: "com.apple.preference.security")
    ]
}

struct PrivacyView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    private func privacyTint(_ category: PrivacyCategory) -> Color {
        let tints = [Palette.peach, Palette.lavender, Palette.blue, Palette.mint, Palette.yellow, Palette.teal]
        return tints[(PrivacyCategory.all.firstIndex { $0.id == category.id } ?? 0) % tints.count]
    }
    var body: some View {
        PageHeading("Privacy", subtitle: "macOS grants access in System Settings — Viper opens the right page, or resets an app’s choices.")
        InfoLine(text: "If a shortcut opens the general page, choose the category in Privacy & Security. Names and available categories vary by macOS version.")
        PermissionResetCard()
        SearchField(placeholder: "Find a permission", text: $search)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            ForEach(PrivacyCategory.all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { category in
                Card {
                    HStack {
                        Image(systemName: category.icon).font(.system(size: 18)).frame(width: 44, height: 44).glowTile(privacyTint(category), radius: 12, glow: false)
                        Spacer()
                        Tag(text: "SYSTEM SETTINGS")
                    }
                    Text(category.name).font(.system(size: 15, weight: .semibold)).frame(minHeight: 36, alignment: .topLeading)
                    Text(category.detail).font(.system(size: 12)).foregroundStyle(Palette.muted).frame(minHeight: 32, alignment: .topLeading)
                    Button { model.openSettings(category.destination) } label: { Label("Open settings", systemImage: "arrow.up.right") }
                        .buttonStyle(GlowButtonStyle(.secondary))
                }
            }
        }
        if !search.isEmpty && !PrivacyCategory.all.contains(where: { $0.name.localizedCaseInsensitiveContains(search) }) {
            EmptyPanel(icon: "magnifyingglass", title: "No matching permission.", detail: "Try a different name, or clear your search to see all shortcuts.")
        }
    }
}

private struct PermissionResetCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var pending: InstalledApplication?
    private var apps: [InstalledApplication] {
        (model.inventory?.applications ?? []).filter { !$0.isSystem && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Reset an app’s permissions").font(.cardTitle)
                    Text("Removes every privacy decision for the app — camera, microphone, files, screen recording, and more. macOS asks again the next time the app needs access.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            SearchField(placeholder: "Find an app", text: $search)
            if model.inventoryLoading {
                HStack(spacing: 10) { ScanPulse(color: Palette.peach); Text("Reading application folders…").font(.system(size: 12)) }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(apps) { app in
                            ResetRow {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).font(.system(size: 12, weight: .semibold))
                                    Text(app.bundleIdentifier ?? "").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Button("Reset…") { pending = app }.buttonStyle(GlowButtonStyle(.secondary, compact: true))
                            }
                        }
                    }
                }.frame(maxHeight: 260)
            }
        }
        .task { if model.inventory == nil { model.loadApplications() } }
        .confirmationDialog("Reset \(pending?.name ?? "")’s permissions?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Reset permissions", role: .destructive) { if let app = pending { model.resetPermissions(for: app) }; pending = nil }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("All access \(pending?.name ?? "this app") was given or denied is cleared. Quit the app first; it may need to ask for access again to keep working.")
        }
    }
}

private struct ResetRow<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.vertical, 7).padding(.horizontal, 10)
            .rowHighlight(hovering: hovering)
            .onHover { hovering = $0 }
    }
}
