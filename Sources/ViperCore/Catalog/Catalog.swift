import Foundation

public enum CatalogCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case developer, ai, audio, video, gaming, browsers, design, utilities, productivity, communication
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .developer: return "IDEs & Developer Tools"
        case .ai: return "AI Agents & Assistants"
        case .audio: return "Music & Audio"
        case .video: return "Video"
        case .gaming: return "Gaming"
        case .browsers: return "Browsers"
        case .design: return "Images & Design"
        case .utilities: return "Utilities"
        case .productivity: return "Productivity"
        case .communication: return "Communication"
        }
    }
}

public enum CatalogKind: String, Codable, Sendable { case app, commandLine }

public enum CatalogPricing: String, Codable, Sendable {
    case free, paid, freemium, unverified
    public var label: String {
        switch self {
        case .free: return "Free"
        case .paid: return "Paid"
        case .freemium: return "Free with paid plans"
        case .unverified: return "Pricing not verified"
        }
    }
}

public enum InstallMethod: String, Codable, Sendable {
    case homebrewCask, homebrewFormula, npm, appStore, vendor
    public var isDirect: Bool { self == .homebrewCask || self == .homebrewFormula || self == .npm }
    public var sourceLabel: String {
        switch self {
        case .homebrewCask, .homebrewFormula: return "Homebrew"
        case .npm: return "npm"
        case .appStore: return "App Store"
        case .vendor: return "Publisher website"
        }
    }
}

public struct InstallRoute: Codable, Hashable, Sendable {
    public let method: InstallMethod
    /// Reviewed Homebrew token or npm package name. Never a command, URL, tap, or version range.
    public let package: String?
    /// External destination for App Store and publisher routes only.
    public let url: URL?
}

public struct CatalogEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let publisher: String
    public let summary: String
    public let category: CatalogCategory
    public let kind: CatalogKind
    public let website: URL
    public let pricing: CatalogPricing
    /// nil means the account requirement has not been verified.
    public let requiresAccount: Bool?
    public let install: InstallRoute
    public let bundleIdentifiers: [String]?
    public let appNames: [String]?
    public let commands: [String]?
    public let minimumMacOS: String?
    public let appleSiliconOnly: Bool?
    public let notes: [String]?

    public var metadataKey: String? { install.package.map { install.method.rawValue + ":" + $0 } }
}

public struct StarterCollection: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let apps: [String]
}

public struct Catalog: Codable, Sendable {
    public static let supportedSchemaVersion = 1
    public let schemaVersion: Int
    public let catalogVersion: String
    public let reviewedAt: String
    public let apps: [CatalogEntry]
    public let collections: [StarterCollection]

    public func entry(_ id: String) -> CatalogEntry? { apps.first { $0.id == id } }

    /// Decodes and validates catalog data. Invalid content is rejected as a whole rather than partially trusted.
    public static func decode(_ data: Data) throws -> Catalog {
        let catalog: Catalog
        do { catalog = try JSONDecoder().decode(Catalog.self, from: data) }
        catch { throw CatalogError.invalid("The catalog format could not be read.") }
        try catalog.validate()
        return catalog
    }

    public func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else { throw CatalogError.invalid("Catalog schema \(schemaVersion) is not supported by this version of Viper.") }
        guard !apps.isEmpty else { throw CatalogError.invalid("The catalog has no apps.") }
        var ids = Set<String>()
        var packages = Set<String>()
        for app in apps {
            guard app.id.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil, ids.insert(app.id).inserted else {
                throw CatalogError.invalid("Catalog identity “\(app.id)” is invalid or duplicated.")
            }
            guard !app.name.trimmingCharacters(in: .whitespaces).isEmpty, !app.publisher.isEmpty, !app.summary.isEmpty else {
                throw CatalogError.invalid("\(app.id) is missing its name, publisher, or description.")
            }
            guard app.website.scheme == "https", app.website.host != nil else { throw CatalogError.invalid("\(app.id) must use a secure official website.") }
            if let minimum = app.minimumMacOS, minimum.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) == nil {
                throw CatalogError.invalid("\(app.id) has an invalid macOS requirement.")
            }
            for identifier in app.bundleIdentifiers ?? [] where identifier.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9_-]+)+$", options: .regularExpression) == nil {
                throw CatalogError.invalid("\(app.id) has an invalid bundle identifier.")
            }
            for name in app.appNames ?? [] where !name.hasSuffix(".app") || name.contains("/") {
                throw CatalogError.invalid("\(app.id) has an invalid app name.")
            }
            for command in app.commands ?? [] where command.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]*$", options: .regularExpression) == nil {
                throw CatalogError.invalid("\(app.id) has an invalid command name.")
            }
            try validateRoute(app)
            if let key = app.metadataKey, !packages.insert(key).inserted {
                throw CatalogError.invalid("\(app.id) duplicates another package mapping.")
            }
        }
        var collectionIDs = Set<String>()
        for collection in collections {
            guard collectionIDs.insert(collection.id).inserted, !collection.apps.isEmpty, collection.apps.allSatisfy(ids.contains) else {
                throw CatalogError.invalid("Collection “\(collection.name)” refers to apps that are not in the catalog.")
            }
        }
    }

    private func validateRoute(_ app: CatalogEntry) throws {
        let route = app.install
        switch route.method {
        case .homebrewCask, .homebrewFormula, .npm:
            let npm = route.method == .npm
            guard route.url == nil, let package = route.package, PackageRequest.isValidName(package, manager: npm ? .npm : .homebrew) else {
                throw CatalogError.invalid("\(app.id) has an unsafe or unsupported package mapping.")
            }
            guard app.kind == (route.method == .homebrewCask ? .app : .commandLine) else {
                throw CatalogError.invalid("\(app.id) mixes app and command-line package types.")
            }
        case .appStore:
            guard route.package == nil, let url = route.url, url.scheme == "macappstore", url.path.range(of: "^/app/id[0-9]+$", options: .regularExpression) != nil else {
                throw CatalogError.invalid("\(app.id) has an invalid App Store link.")
            }
        case .vendor:
            guard route.package == nil, let url = route.url, url.scheme == "https", url.host != nil else {
                throw CatalogError.invalid("\(app.id) has an invalid publisher link.")
            }
        }
    }
}

public enum CatalogError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}
