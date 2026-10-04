import ViperCore

extension AppModel {
    func resetPermissions(for app: InstalledApplication) {
        guard settings.allowReviewedChanges else {
            notice = "Viper is in read-only safety mode. Enable reviewed changes in Settings before resetting permissions."
            return
        }
        guard !refuseUntilJournalReviewed() else { return }
        guard !isRunning(.app(app)) else {
            notice = "\(app.name) is open. Quit it before resetting permissions, so macOS can ask again cleanly."
            return
        }
        guard let identifier = app.bundleIdentifier else {
            notice = "\(app.name) has no bundle identifier, so its permissions can’t be reset."
            return
        }
        Task {
            switch await PermissionReset.reset(bundleIdentifier: identifier) {
            case .success: notice = "\(app.name)’s privacy permissions were reset. macOS will ask again the next time it needs access."
            case .failure: notice = "macOS didn’t reset \(app.name)’s permissions. You can remove its access in System Settings › Privacy & Security."
            }
        }
    }
}
