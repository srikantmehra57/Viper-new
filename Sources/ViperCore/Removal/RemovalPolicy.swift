import Foundation

/// Preliminary review policy only. No deletion executor is included in this build.
/// An eligible result is not authorization and must never be used without execution-time identity checks.
public enum RemovalAssessment: Equatable, Sendable {
    case protected(String)
    case reviewRequired(String)
}

public enum RemovalPolicy {
    public static func assess(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> RemovalAssessment {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path
        let protected = ["/System", "/bin", "/sbin", "/usr", "/private", "/Library", "/Volumes", "/dev"]
        if path == "/" || path == homePath || protected.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .protected("This location may be required by macOS, installed tools, or other apps.")
        }
        guard path.hasPrefix(homePath + "/") else {
            return .protected("This location is outside the supported personal-file scope.")
        }
        let sensitive = ["Library", ".ssh", ".gnupg", ".aws", ".config"]
        if sensitive.contains(where: { path == homePath + "/" + $0 || path.hasPrefix(homePath + "/" + $0 + "/") }) {
            return .protected("Settings, shared app data, and credentials need an app-specific ownership review.")
        }
        return .reviewRequired("This may be a personal file. Review its contents and keep a backup before removing it.")
    }
}
