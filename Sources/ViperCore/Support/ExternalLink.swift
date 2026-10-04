import Foundation

/// Links Viper is willing to hand to macOS. Catalog and update data are validated earlier; this is the last check before `NSWorkspace.open`.
public enum ExternalLink {
    /// HTTPS pages and App Store product links. Userinfo, other schemes, and loose App Store paths are rejected.
    public static func webOrAppStore(_ address: String) -> URL? {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), url.user == nil else { return nil }
        switch scheme {
        case "https":
            guard let host = url.host, !host.isEmpty, !host.contains(" ") else { return nil }
            return url
        case "macappstore":
            let host = url.host?.lowercased()
            guard host == "itunes.apple.com" || host == "apps.apple.com" else { return nil }
            guard url.path.range(of: "^/app/id[0-9]+$", options: .regularExpression) != nil else { return nil }
            return url
        default:
            return nil
        }
    }

    /// Privacy & Security destinations compiled into the app. The suffix is not a general URL.
    public static func systemSettings(_ suffix: String) -> URL? {
        guard suffix.range(of: #"^com\.apple\.[A-Za-z0-9.-]+(\?Privacy_[A-Za-z0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "x-apple.systempreferences:" + suffix)
    }
}
