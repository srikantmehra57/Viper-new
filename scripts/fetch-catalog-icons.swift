// Catalog review tool: collects one icon per catalog app from official sources and
// writes 128px PNGs plus a SOURCES.json manifest to Resources/CatalogIcons.
// Run manually when the catalog changes: swift scripts/fetch-catalog-icons.swift
// The app never downloads icons at runtime.
import AppKit
import Foundation

struct Entry: Decodable {
    let id: String
    let website: URL
    let bundleIdentifiers: [String]?
    let install: Install
    struct Install: Decodable { let method: String; let url: URL? }
}
struct Catalog: Decodable { let apps: [Entry] }

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let source = try String(contentsOf: root.appendingPathComponent("Sources/ViperCore/Catalog/BuiltInCatalog.swift"), encoding: .utf8)
guard let start = source.range(of: "#\"\"\"\n"), let end = source.range(of: "\n\"\"\"#") else { fatalError("Catalog JSON not found") }
let catalog = try JSONDecoder().decode(Catalog.self, from: Data(source[start.upperBound..<end.lowerBound].utf8))
let output = root.appendingPathComponent("Resources/CatalogIcons")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Reviewed official alternatives, tried first. Used where a product page exposes no usable icon or a parent-company
/// logo. GitHub organisation avatars are the project's own chosen logo; personal avatars are never used.
let overrides: [String: String] = [
    "zed": "https://github.com/zed-industries.png?size=256",
    "git": "https://github.com/git.png?size=256",
    "gh": "https://github.com/cli.png?size=256",
    "node": "https://github.com/nodejs.png?size=256",
    "pnpm": "https://github.com/pnpm.png?size=256",
    "claude-code": "https://github.com/anthropics.png?size=256",
    "chatgpt": "https://openai.com/apple-touch-icon.png",
    "codex": "https://github.com/openai.png?size=256",
    "gemini-cli": "https://github.com/google-gemini.png?size=256",
    "vlc": "https://github.com/videolan.png?size=256",
    "epic-games": "https://github.com/EpicGames.png?size=256",
    "gimp": "https://www.gimp.org/images/frontpage/wilber-big.png",
    "inkscape": "https://github.com/inkscape.png?size=256",
    "libreoffice": "https://github.com/LibreOffice.png?size=256",
    "stats": "https://raw.githubusercontent.com/exelban/stats/master/Stats/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_512x512.png",
    "microsoft-edge": "https://edgecdn-embza6g8cacagcbn.z01.azurefd.net/welcome/static/favicon.png",
    "jq": "https://github.com/jqlang.png?size=256",
    "eza": "https://github.com/eza-community.png?size=256",
    "tmux": "https://github.com/tmux.png?size=256",
    "neovim": "https://github.com/neovim.png?size=256",
    "yt-dlp": "https://github.com/yt-dlp.png?size=256",
    "mas": "https://github.com/mas-cli.png?size=256",
    "serve": "https://github.com/vercel.png?size=256",
    "github-copilot-cli": "https://github.com/github.png?size=256",
    "monitorcontrol": "https://github.com/MonitorControl.png?size=256",
    "aider": "https://github.com/Aider-AI.png?size=256",
    "wrangler": "https://github.com/cloudflare.png?size=256",
    "yarn": "https://github.com/yarnpkg.png?size=256",
    "prettier": "https://github.com/prettier.png?size=256",
    "eslint": "https://github.com/eslint.png?size=256",
    "iterm2": "https://iterm2.com/img/logo2x.jpg",
    "fork": "https://git-fork.com/images/logo.png",
    "ghostty": "https://github.com/ghostty-org.png?size=256",
    "dbeaver-community": "https://github.com/dbeaver.png?size=256",
    "jan": "https://github.com/janhq.png?size=256",
    "mpv": "https://github.com/mpv-player.png?size=256",
    "heroic": "https://github.com/Heroic-Games-Launcher.png?size=256",
    "tor-browser": "https://github.com/torproject.png?size=256",
    "ffmpeg": "https://github.com/FFmpeg.png?size=256",
    "webex": "https://github.com/webex.png?size=256",
    "arc": "https://github.com/thebrowsercompany.png?size=256",
    "eqmac": "https://github.com/bitgapp.png?size=256",
    "appcleaner": "https://github.com/FreeMacSoft.png?size=256"
]

let size = 128
let minimumPixels = 96

func fetch(_ url: URL) -> Data? {
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.setValue("Mozilla/5.0 (Macintosh) Viper catalog icon review", forHTTPHeaderField: "User-Agent")
    let semaphore = DispatchSemaphore(value: 0)
    var result: Data?
    URLSession.shared.dataTask(with: request) { data, response, _ in
        if (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count < 5_000_000 { result = data }
        semaphore.signal()
    }.resume()
    semaphore.wait()
    return result
}

func largestRepresentation(_ data: Data) -> (NSImage, Int)? {
    guard let image = NSImage(data: data) else { return nil }
    let pixels = image.representations.map { max($0.pixelsWide, $0.pixelsHigh) }.max() ?? 0
    // Vector images report zero pixels and render cleanly at any size.
    return (image, pixels == 0 ? size * 2 : pixels)
}

func png(_ image: NSImage) -> Data? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let original = image.size
    let scale = min(Double(size) / max(original.width, 1), Double(size) / max(original.height, 1))
    let drawn = NSSize(width: original.width * scale, height: original.height * scale)
    image.draw(in: NSRect(x: (Double(size) - drawn.width) / 2, y: (Double(size) - drawn.height) / 2, width: drawn.width, height: drawn.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func installedIcon(_ entry: Entry) -> NSImage? {
    for identifier in entry.bundleIdentifiers ?? [] {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier), !url.path.hasPrefix("/System/") {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }
    return nil
}

func appStoreIcon(_ entry: Entry) -> (URL, Data)? {
    var identifiers = entry.bundleIdentifiers ?? []
    if entry.install.method == "appStore", let id = entry.install.url?.lastPathComponent.replacingOccurrences(of: "id", with: "") { identifiers.insert("id:" + id, at: 0) }
    for identifier in identifiers {
        let query = identifier.hasPrefix("id:") ? "id=\(identifier.dropFirst(3))" : "bundleId=\(identifier)"
        guard let lookup = URL(string: "https://itunes.apple.com/lookup?\(query)&entity=macSoftware"), let data = fetch(lookup),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first(where: { $0["kind"] as? String == "mac-software" }),
              let artwork = (result["artworkUrl512"] as? String).flatMap(URL.init(string:)), let image = fetch(artwork) else { continue }
        return (artwork, image)
    }
    return nil
}

func websiteIcons(_ entry: Entry) -> [URL] {
    // GitHub pages only expose GitHub's own logo, which would misidentify the app.
    guard entry.website.host != "github.com", let data = fetch(entry.website), let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
    var candidates: [(URL, Int)] = []
    let links = html.matches(of: #/<link\b[^>]*>/#.ignoresCase())
    for match in links {
        let tag = String(match.output)
        guard let rel = tag.firstMatch(of: #/rel\s*=\s*["']([^"']+)["']/#.ignoresCase())?.1.lowercased(), rel.contains("icon"), !rel.contains("mask"),
              let href = tag.firstMatch(of: #/href\s*=\s*["']([^"']+)["']/#.ignoresCase())?.1,
              let url = URL(string: String(href).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: entry.website)?.absoluteURL else { continue }
        let declared = tag.firstMatch(of: #/sizes\s*=\s*["'](\d+)x\d+/#.ignoresCase()).flatMap { Int($0.1) } ?? (rel.contains("apple-touch") ? 180 : 32)
        candidates.append((url, declared))
    }
    var urls = candidates.sorted { $0.1 > $1.1 }.map(\.0)
    // Domain-root icons identify the product only when it owns the whole site, not e.g. microsoft.com/edge.
    guard entry.website.path.isEmpty || entry.website.path == "/" else { return urls }
    for fallback in ["/apple-touch-icon.png", "/favicon.ico"] {
        if let url = URL(string: fallback, relativeTo: entry.website)?.absoluteURL { urls.append(url) }
    }
    return urls
}

var manifest: [String: [String: String]] = [:]
for entry in catalog.apps {
    var chosen: (NSImage, String, Int)?
    if let override = overrides[entry.id].flatMap(URL.init(string:)), let data = fetch(override), let decoded = largestRepresentation(data) {
        chosen = (decoded.0, override.absoluteString, decoded.1)
    }
    if chosen == nil, let icon = installedIcon(entry) { chosen = (icon, "Installed app bundle on the review Mac", 1024) }
    if chosen == nil, let found = appStoreIcon(entry), let decoded = largestRepresentation(found.1) { chosen = (decoded.0, found.0.absoluteString, decoded.1) }
    if chosen == nil {
        for url in websiteIcons(entry) {
            guard let data = fetch(url), let decoded = largestRepresentation(data) else { continue }
            if decoded.1 >= minimumPixels, decoded.1 > (chosen?.2 ?? 0) { chosen = (decoded.0, url.absoluteString, decoded.1) }
            if decoded.1 >= 180 { break }
        }
    }
    let file = output.appendingPathComponent(entry.id + ".png")
    if let chosen, chosen.2 >= minimumPixels, let data = png(chosen.0) {
        try data.write(to: file)
        manifest[entry.id] = ["source": chosen.1, "pixels": String(chosen.2)]
        print("✓", entry.id, chosen.2, chosen.1)
    } else {
        try? FileManager.default.removeItem(at: file)
        print("–", entry.id, "no official icon of sufficient size; the app shows its letter tile")
    }
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(manifest).write(to: output.appendingPathComponent("SOURCES.json"))
print("\(manifest.count) of \(catalog.apps.count) icons written")
