import Foundation

public enum UninstallPlanner {
    struct Scope {
        let folder: String
        let kind: RemovalKind
        var matchesNames = false
        var warning: String?
    }

    static let scopes: [Scope] = [
        .init(folder: "Preferences", kind: .preferences),
        .init(folder: "Preferences/ByHost", kind: .preferences),
        .init(folder: "Application Support", kind: .appData, matchesNames: true),
        .init(folder: "Containers", kind: .appData, warning: "Everything this app saved in its sandbox, which can include documents you created in it."),
        .init(folder: "Group Containers", kind: .appData, warning: "Data an app shares with its extensions or other apps from the same developer."),
        .init(folder: "Application Scripts", kind: .appData),
        .init(folder: "Caches", kind: .caches, matchesNames: true),
        .init(folder: "HTTPStorages", kind: .caches),
        .init(folder: "WebKit", kind: .caches),
        .init(folder: "Cookies", kind: .caches),
        .init(folder: "Logs", kind: .logs, matchesNames: true),
        .init(folder: "Saved Application State", kind: .logs),
        .init(folder: "LaunchAgents", kind: .launchItems, warning: "A background item. If it is running, it stops after you log out or restart.")
    ]
    static let systemScopes = ["/Library/Application Support", "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Preferences"]
    static let genericNames: Set<String> = ["app", "apps", "data", "cache", "caches", "logs", "support", "helper", "updater", "electron", "google", "microsoft", "apple", "adobe", "node", "npm", "config"]
    static let homeWarning = "Settings kept in your home folder. Command-line tools and other apps sometimes share these, and they can hold sign-in details."

    // MARK: Applications

    public static let partialReviewWarning = "This app has too many files to review one by one. Viper rechecks the app and the folders directly inside it. A change there cancels the removal. Files added deeper inside can still be removed with it."

    public static func plan(for app: InstalledApplication, context: UninstallContext, signatureLimit: Int = RemovalSignature.defaultLimit) throws -> UninstallPlan {
        var blockers: [String] = []
        let bundlePath = app.url.standardizedFileURL.path
        if app.isSystem || bundlePath.hasPrefix("/System/") { blockers.append("\(app.name) is part of macOS. Viper doesn’t remove protected system apps.") }
        if let id = app.bundleIdentifier, context.protectedBundleIdentifiers.contains(id) { blockers.append("Viper can’t uninstall itself.") }
        guard isInApplicationFolder(app.url, home: context.home) else {
            return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: [], kept: [], blockers: blockers + ["\(app.name) isn’t in a supported application folder."], createdAt: Date())
        }
        guard let identity = FileIdentity.read(app.url) else {
            return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: [], kept: [], blockers: blockers + ["\(app.name) couldn’t be read, or it is a link to an app stored elsewhere."], createdAt: Date())
        }
        guard let signature = try RemovalSignature.read(app.url, limit: signatureLimit) else {
            return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: [], kept: [], blockers: blockers + ["\(app.name) couldn’t be completely reviewed. Viper won’t offer a partial removal."], createdAt: Date())
        }
        let reviewWarning = signature.coversDescendants ? nil : partialReviewWarning

        var items: [RemovalItem] = []
        var kept: [KeptItem] = []
        let parent = canonicalParent(app.url)
        switch homebrewCaskOwnership(for: app.url, prefixes: context.homebrewPrefixes) {
        case .ambiguous(let tokens):
            let list = tokens.sorted().joined(separator: ", ")
            blockers.append("More than one Homebrew cask claims \(app.name) (\(list)). Viper won’t choose one. Remove the right cask with Homebrew, then review again.")
            return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: [], kept: [], blockers: blockers, createdAt: Date())
        case .unique(let cask):
            items.append(.init(url: app.url, kind: .package, confidence: .exact, reason: "Installed by Homebrew as the “\(cask.package)” cask, so Homebrew removes it.",
                               warning: reviewWarning, size: try allocatedSize(app.url), identity: identity, signature: signature, parentPath: parent, action: .packageUninstall(cask), isRequired: true))
        case .none:
            let writable = access(app.url.path, W_OK) == 0 && access(app.url.deletingLastPathComponent().path, W_OK) == 0
            let ownership = writable ? nil : "This app is owned by the system. macOS may ask for your password, or you can drag it to the Trash in Finder."
            let warning = [ownership, reviewWarning].compactMap { $0 }.joined(separator: " ")
            items.append(.init(url: app.url, kind: .application, confidence: .exact, reason: "The app itself.",
                               warning: warning.isEmpty ? nil : warning, size: try allocatedSize(app.url), identity: identity, signature: signature, parentPath: parent, action: .trash, isRequired: true))
        }

        let others = context.applications.filter { $0.url.standardizedFileURL.path != bundlePath }
        if let id = app.bundleIdentifier, let copy = others.first(where: { $0.bundleIdentifier?.lowercased() == id.lowercased() }) {
            // Another copy shares every setting. Only the selected bundle is offered.
            return .init(name: app.name, bundleIdentifier: id, items: items, kept: [.init(url: copy.url, reason: "Another copy of \(app.name) is installed here and uses the same settings, so related files are kept.")],
                         blockers: blockers, createdAt: Date())
        }
        let names = appNames(app)
        let otherNames = Set(others.flatMap(appNames)).union(context.tools.flatMap(toolNames))
        var seen = Set<String>()

        for scope in scopes {
            try Task.checkCancellation()
            let folder = context.library.appendingPathComponent(scope.folder)
            for entry in children(of: folder) {
                try Task.checkCancellation()
                let name = entry.lastPathComponent
                var confidence: MatchConfidence?
                var reason = ""
                if scope.folder == "Group Containers" {
                    let group = name.lowercased()
                    if let owner = others.first(where: { $0.applicationGroups.contains(group) }) {
                        kept.append(.init(url: entry, reason: "\(owner.name)’s signed entitlement uses this exact shared container."))
                        continue
                    }
                    if app.applicationGroups.contains(group) {
                        confidence = .exact
                        reason = "\(app.name)’s signed application-group entitlement names this exact shared container."
                    }
                }
                if let id = app.bundleIdentifier {
                    let (base, grouped) = identifierBase(name)
                    if confidence == nil, belongs(base, to: id) {
                        if let owner = others.first(where: { other in other.bundleIdentifier.map { $0.count > id.count && belongs(base, to: $0) } ?? false }) {
                            kept.append(.init(url: entry, reason: "Belongs to \(owner.name), which is still installed."))
                            continue
                        }
                        confidence = grouped ? .likely : .exact
                        reason = grouped ? "Shared group named after \(app.name)’s identifier (\(id))." : "Named with \(app.name)’s identifier (\(id))."
                    }
                }
                if confidence == nil, scope.matchesNames, names.contains(name.lowercased()) {
                    if otherNames.contains(name.lowercased()) {
                        kept.append(.init(url: entry, reason: "The name also matches another installed app or tool."))
                        continue
                    }
                    confidence = .likely
                    reason = "Folder has the same name as the app. Other software from the same developer can use it too."
                }
                guard let confidence, seen.insert(entry.path).inserted, let item = try makeItem(entry, kind: scope.kind, confidence: confidence, reason: reason, warning: scope.warning) else { continue }
                items.append(item)
            }
        }
        for variant in names.flatMap(dotVariants) {
            let entry = context.home.appendingPathComponent("." + variant)
            guard FileIdentity.read(entry) != nil, seen.insert(entry.path).inserted else { continue }
            if otherNames.contains(variant) {
                kept.append(.init(url: entry, reason: "The name also matches another installed app or tool."))
                continue
            }
            if let item = try makeItem(entry, kind: .homeSettings, confidence: .likely, reason: "Hidden folder in your home named after the app.", warning: homeWarning) { items.append(item) }
        }
        kept += systemItems(identifier: app.bundleIdentifier, names: names)
        return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: items, kept: kept, blockers: blockers, createdAt: Date())
    }

    // MARK: Command-line tools

    public static func plan(for tool: CommandLinePackage, context: UninstallContext) throws -> UninstallPlan {
        var blockers: [String] = []
        if tool.isBundledWithRuntime { blockers.append("\(tool.name) ships with Node.js. Remove Node.js instead if you no longer need it.") }
        if tool.isDependency { blockers.append("Homebrew installed \(tool.name) for other formulae. Remove those first; Homebrew can then clean it up with “brew autoremove”.") }
        let kind: PackageUninstall.Kind = tool.source == .npm ? .npm : (tool.source == .homebrewCask ? .cask : .formula)
        guard let request = PackageUninstall(runtime: tool.runtime, kind: kind, package: tool.package) else {
            return .init(name: tool.name, bundleIdentifier: nil, items: [], kept: [], blockers: blockers + ["This package name can’t be passed safely to its package manager."], createdAt: Date())
        }
        let target = tool.location ?? tool.runtime.executable
        let prefix = tool.runtime.executable.deletingLastPathComponent().deletingLastPathComponent().path + "/"
        let npmTools = context.tools.filter { $0.source == .npm && !$0.isBundledWithRuntime && $0.runtime.executable.path.hasPrefix(prefix) }
        let runtimeWarning = tool.source == .homebrewFormula && (tool.package == "node" || tool.package.hasPrefix("node@")) && !npmTools.isEmpty
            ? "Global npm tools installed with this Node.js stop working: \(npmTools.map(\.name).joined(separator: ", "))." : nil
        var items = [RemovalItem(url: target, kind: .package, confidence: .exact, reason: "Removed by \(tool.runtime.manager.rawValue) with “\(request.displayCommand)”.",
                                 warning: runtimeWarning, size: tool.location.flatMap { try? allocatedSize($0) }, identity: nil, parentPath: canonicalParent(target),
                                 action: .packageUninstall(request), isRequired: true)]
        var kept: [KeptItem] = []
        let names = Set(toolNames(tool))
        let otherTools = context.tools.filter { $0.id != tool.id }
        let otherNames = Set(otherTools.flatMap(toolNames)).union(context.applications.flatMap(appNames))
        let candidates = names.flatMap { name -> [(URL, RemovalKind)] in
            [(context.home.appendingPathComponent("." + name), .homeSettings), (context.home.appendingPathComponent(".config/" + name), .homeSettings),
             (context.library.appendingPathComponent("Application Support/" + name), .appData), (context.library.appendingPathComponent("Caches/" + name), .caches),
             (context.library.appendingPathComponent("Logs/" + name), .logs)]
        }
        var seen = Set<String>()
        for (url, kind) in candidates where seen.insert(url.path).inserted {
            try Task.checkCancellation()
            guard FileIdentity.read(url) != nil else { continue }
            if otherNames.contains(url.lastPathComponent.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
                kept.append(.init(url: url, reason: "The name also matches another installed app or tool."))
                continue
            }
            if let item = try makeItem(url, kind: kind, confidence: .likely, reason: "Named after the “\(url.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: ".")))” command.", warning: homeWarning) {
                items.append(item)
            }
        }
        return .init(name: tool.name, bundleIdentifier: nil, items: items, kept: kept, blockers: blockers, createdAt: Date())
    }

    // MARK: Matching helpers

    public static func identifierBase(_ name: String) -> (base: String, grouped: Bool) {
        var base = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where base.hasSuffix(suffix) {
            base.removeLast(suffix.count)
            break
        }
        if base.hasPrefix("group.") { return (String(base.dropFirst(6)), true) }
        // Team-identifier prefix, e.g. 2DC432GLL2.com.vendor.app
        if base.range(of: "^[A-Z0-9]{10}\\.", options: .regularExpression) != nil { return (String(base.dropFirst(11)), true) }
        return (base, false)
    }

    public static func belongs(_ base: String, to identifier: String) -> Bool {
        let base = base.lowercased(), identifier = identifier.lowercased()
        guard identifier.split(separator: ".").count >= 2 else { return false }
        return base == identifier || base.hasPrefix(identifier + ".")
    }

    static func appNames(_ app: InstalledApplication) -> [String] {
        let bundle = Bundle(url: app.url)
        let values = [app.name, app.url.deletingPathExtension().lastPathComponent, bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                      bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String].compactMap { $0.map(cleanName) }
        return Array(Set(values.filter { $0.count >= 3 && !genericNames.contains($0) && !$0.contains("/") }))
    }

    /// Some bundles pad their names with invisible direction marks.
    static func cleanName(_ name: String) -> String {
        String(String.UnicodeScalarView(name.unicodeScalars.filter { $0.properties.generalCategory != .format })).trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func toolNames(_ tool: CommandLinePackage) -> [String] {
        let values = tool.commands + [String(tool.package.split(separator: "/").last ?? Substring(tool.package))]
        return Array(Set(values.map { $0.lowercased() }.filter { $0.count >= 2 && !genericNames.contains($0) && !$0.contains("/") && !$0.hasPrefix(".") }))
    }

    static func dotVariants(_ name: String) -> [String] {
        Array(Set([name, name.replacingOccurrences(of: " ", with: "-"), name.replacingOccurrences(of: " ", with: "")]))
    }

    static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    public static func makeItem(_ url: URL, kind: RemovalKind, confidence: MatchConfidence, reason: String, warning: String?) throws -> RemovalItem? {
        guard let identity = FileIdentity.read(url), let signature = try RemovalSignature.read(url), signature.coversDescendants else { return nil }
        let secrets = credentialHint(url)
        let combined = [warning, secrets].compactMap { $0 }.joined(separator: " ")
        return .init(url: url, kind: kind, confidence: confidence, reason: reason, warning: combined.isEmpty ? nil : combined,
                     size: try allocatedSize(url), identity: identity, signature: signature, parentPath: canonicalParent(url), action: .trash, isRequired: false)
    }

    /// Names only, one level deep. File contents are never read.
    static func credentialHint(_ url: URL) -> String? {
        let pattern = "(?i)(credential|token|secret|password|oauth|auth\\.json|\\.pem$|\\.key$|\\.env$)"
        let names = [url.lastPathComponent] + ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).prefix(300)
        guard let match = names.first(where: { $0.range(of: pattern, options: .regularExpression) != nil }) else { return nil }
        return "Contains “\(match)”, which looks like saved sign-in details."
    }

    static func systemItems(identifier: String?, names: [String]) -> [KeptItem] {
        systemScopes.flatMap { folder in
            children(of: URL(fileURLWithPath: folder)).filter { entry in
                let name = entry.lastPathComponent
                if let identifier, belongs(identifierBase(name).base, to: identifier) { return true }
                return folder == "/Library/Application Support" && names.contains(name.lowercased())
            }.map { KeptItem(url: $0, reason: "System-wide item. Removing it needs an administrator, which Viper doesn’t do yet.") }
        }
    }

    static func isInApplicationFolder(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard url.pathExtension.lowercased() == "app" else { return false }
        return applicationRoots(home: home).contains { path.hasPrefix($0 + "/") }
    }

    static func applicationRoots(home: URL) -> [String] { ["/Applications", home.standardizedFileURL.path + "/Applications"] }

    public static func canonicalParent(_ url: URL) -> String { url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path }

    /// Folders whose direct children may be moved to the Trash.
    static func allowedParents(home: URL) -> Set<String> {
        let home = home.resolvingSymlinksInPath().standardizedFileURL
        let library = scopes.map { home.appendingPathComponent("Library").appendingPathComponent($0.folder).resolvingSymlinksInPath().path }
        return Set(library + [home.path, home.appendingPathComponent(".config").resolvingSymlinksInPath().path])
    }

    public static func allocatedSize(_ url: URL, limit: Int = 200_000) throws -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        if values.isSymbolicLink == true { return 0 }
        var total = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return total }
        var count = 0
        for case let child as URL in enumerator {
            count += 1
            if count % 2_000 == 0 { try Task.checkCancellation() }
            guard count <= limit else { return nil }
            let values = try? child.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    enum CaskOwnership: Equatable {
        case unique(PackageUninstall)
        case ambiguous([String])
        case none
    }

    /// A cask owns the app only when its declared `app` artifact is exactly the bundle filename.
    /// Mentions in caveats or conflicts do not count. More than one declaring cask is left for the user to choose.
    static func homebrewCaskOwnership(for app: URL, prefixes: [URL]) -> CaskOwnership {
        let bundleName = app.lastPathComponent
        var matches: [(brew: URL, token: String)] = []
        for prefix in prefixes {
            let brew = prefix.appendingPathComponent("bin/brew")
            guard FileManager.default.isExecutableFile(atPath: brew.path) else { continue }
            for cask in children(of: prefix.appendingPathComponent("Caskroom")) {
                let metadata = cask.appendingPathComponent(".metadata")
                guard let files = FileManager.default.enumerator(at: metadata, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
                var declared = Set<String>()
                for case let file as URL in files where ["json", "rb"].contains(file.pathExtension) {
                    guard (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max < 2_000_000,
                          let data = try? Data(contentsOf: file) else { continue }
                    declared.formUnion(declaredAppNames(in: data, pathExtension: file.pathExtension))
                }
                if declared.contains(bundleName) { matches.append((brew, cask.lastPathComponent)) }
            }
        }
        let tokens = Array(Set(matches.map(\.token))).sorted()
        guard let first = matches.first, tokens.count == 1, let request = PackageUninstall(runtime: .init(manager: .homebrew, executable: first.brew), kind: .cask, package: tokens[0]) else {
            return tokens.count > 1 ? .ambiguous(tokens) : .none
        }
        return .unique(request)
    }

    /// Bundle filenames declared by installed Homebrew casks. Used to tell those apps apart from software Viper cannot update.
    public static func homebrewAppNames(prefixes: [URL]) -> Set<String> {
        var names = Set<String>()
        for prefix in prefixes {
            for cask in children(of: prefix.appendingPathComponent("Caskroom")) {
                let metadata = cask.appendingPathComponent(".metadata")
                guard let files = FileManager.default.enumerator(at: metadata, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
                for case let file as URL in files where ["json", "rb"].contains(file.pathExtension) {
                    guard (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max < 2_000_000,
                          let data = try? Data(contentsOf: file) else { continue }
                    names.formUnion(declaredAppNames(in: data, pathExtension: file.pathExtension))
                }
            }
        }
        return names
    }

    /// App names from a cask artifact, not from caveats, conflicts, or other prose.
    static func declaredAppNames(in data: Data, pathExtension: String) -> Set<String> {
        switch pathExtension.lowercased() {
        case "json":
            guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
            var names = Set<String>()
            collectDeclaredApps(object, into: &names)
            return names
        case "rb":
            return rubyAppDirectives(String(decoding: data, as: UTF8.self))
        default:
            return []
        }
    }

    private static func collectDeclaredApps(_ value: Any, into names: inout Set<String>) {
        if let dict = value as? [String: Any] {
            if let apps = dict["app"] { names.formUnion(appTokens(apps)) }
            for (key, child) in dict where key == "artifacts" || child is [Any] {
                collectDeclaredApps(child, into: &names)
            }
        } else if let array = value as? [Any] {
            for child in array { collectDeclaredApps(child, into: &names) }
        }
    }

    private static func appTokens(_ value: Any) -> Set<String> {
        switch value {
        case let name as String where name.hasSuffix(".app") && !name.contains("/") && !name.contains("\\"):
            return [name]
        case let array as [Any]:
            return Set(array.flatMap { appTokens($0) })
        default:
            return []
        }
    }

    private static func rubyAppDirectives(_ source: String) -> Set<String> {
        let pattern = #"^\s*app\s+["']([^"']+\.app)["']"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var names = Set<String>()
        for line in source.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard !text.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[capture])
            if !name.contains("/") && !name.contains("\\") { names.insert(name) }
        }
        return names
    }
}
