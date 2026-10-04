import Foundation
import Darwin

public enum RemovalResult: Hashable, Sendable {
    case removed(trashURL: URL?)
    case skipped(String)
    case failed(String)

    public var succeeded: Bool { if case .removed = self { return true } else { return false } }
}

public struct RemovalOutcome: Identifiable, Hashable, Sendable {
    public var id: String { item.id }
    public let item: RemovalItem
    public var result: RemovalResult
    public var restored = false
}

public enum UninstallExecutor {
    public typealias Trasher = @Sendable (URL) throws -> URL?
    public typealias OutcomeRecorder = @Sendable (RemovalOutcome) async -> Bool

    public static let systemTrash: Trasher = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    /// Fails closed: anything that changed since the review is left alone.
    public static func revalidate(_ item: RemovalItem, home: URL, bundleIdentifier: String?) -> String? {
        if case .packageUninstall = item.action, item.kind == .package, item.identity == nil { return nil }
        if let changed = identityChanged(item) { return changed }
        let parent = item.parentPath
        if item.isRequired {
            guard UninstallPlanner.isInApplicationFolder(URL(fileURLWithPath: parent).appendingPathComponent(item.url.lastPathComponent), home: home) else { return "The app is no longer in a supported application folder." }
            if let bundleIdentifier, Bundle(url: item.url)?.bundleIdentifier != bundleIdentifier { return "It changed since the review, so Viper left it alone. Review again to include it." }
        } else {
            guard UninstallPlanner.allowedParents(home: home).contains(parent), !["", ".", ".."].contains(item.url.lastPathComponent) else {
                return "This location isn’t one Viper removes files from."
            }
        }
        return nil
    }

    /// Same file, same place, still not a link. Shared by every removal in Viper.
    public static func identityChanged(_ item: RemovalItem) -> String? {
        let changed = "It changed since the review, so Viper left it alone. Scan again to include it."
        guard let identity = item.identity, let signature = item.signature,
              FileIdentity.read(item.url) == identity,
              (try? RemovalSignature.read(item.url, limit: signature.descendantLimit)) == signature,
              UninstallPlanner.canonicalParent(item.url) == item.parentPath else { return changed }
        return nil
    }

    /// The app or package goes first. If it isn’t removed, its settings and data are kept so a still-installed app keeps working.
    public static func execute(_ plan: UninstallPlan, selected: Set<String>, home: URL,
                               isRunning: @Sendable () async -> Bool,
                               mayContinue: @Sendable () async -> Bool = { true },
                               trash: Trasher = systemTrash,
                               uninstallPackage: @Sendable (PackageUninstall) async -> PackageProvider.UninstallOutcome = { await PackageProvider.uninstall($0) },
                               record: OutcomeRecorder = { _ in true },
                               progress: @Sendable (String) async -> Void = { _ in }) async -> [RemovalOutcome] {
        guard plan.canProceed, let required = plan.required else { return [] }
        let rest = plan.items.filter { !$0.isRequired && selected.contains($0.id) }
        var outcomes: [RemovalOutcome] = []

        await progress("Removing \(plan.name)…")
        let first: RemovalResult
        if !(await mayContinue()) {
            first = .skipped("Reviewed changes were turned off before removal started, so nothing was changed.")
        } else if await isRunning() {
            first = .skipped("\(plan.name) is open. Quit it and try again.")
        } else if let reason = revalidate(required, home: home, bundleIdentifier: plan.bundleIdentifier) {
            first = .skipped(reason)
        } else {
            switch required.action {
            case .trash: first = move(required, trash: trash)
            case .packageUninstall(let request):
                switch await uninstallPackage(request) {
                case .removed:
                    var info = stat()
                    if required.url.pathExtension.lowercased() == "app", lstat(required.url.path, &info) == 0 {
                        first = .failed("The package manager finished, but \(plan.name) is still on disk. Related files were kept.")
                    } else {
                        first = .removed(trashURL: nil)
                    }
                case .failed(let reason): first = .failed(reason)
                }
            }
        }
        let firstOutcome = RemovalOutcome(item: required, result: first)
        outcomes.append(firstOutcome)
        guard await record(firstOutcome) else {
            return outcomes + rest.map { .init(item: $0, result: .skipped("The recovery journal could not be updated, so Viper stopped before changing anything else.")) }
        }
        guard first.succeeded else {
            let skipped = rest.map { RemovalOutcome(item: $0, result: .skipped("Kept because \(plan.name) itself wasn’t removed.")) }
            for outcome in skipped { _ = await record(outcome) }
            return outcomes + skipped
        }
        for (index, item) in rest.enumerated() {
            await progress("Moving related files to the Trash (\(index + 1) of \(rest.count))…")
            let outcome: RemovalOutcome
            if !(await mayContinue()) {
                outcome = .init(item: item, result: .skipped("Reviewed changes were turned off, so this related item was kept."))
            } else if let reason = revalidate(item, home: home, bundleIdentifier: nil) {
                outcome = .init(item: item, result: .skipped(reason))
            } else {
                outcome = .init(item: item, result: move(item, trash: trash))
            }
            outcomes.append(outcome)
            guard await record(outcome) else { break }
        }
        return outcomes
    }

    public static func move(_ item: RemovalItem, trash: Trasher) -> RemovalResult {
        do { return .removed(trashURL: try trash(item.url)) }
        catch {
            let code = (error as NSError).code
            if [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(code) || (error as NSError).domain == NSPOSIXErrorDomain {
                return .failed("macOS didn’t allow this to be moved. Reveal it in Finder and drag it to the Trash; Finder can ask for your password.")
            }
            return .failed("It couldn’t be moved to the Trash: \(error.localizedDescription)")
        }
    }

    /// Puts trashed items back where they were, when both the Trash copy exists and the original spot is still free.
    public static func restore(_ outcomes: [RemovalOutcome], fileManager: FileManager = .default) -> [RemovalOutcome] {
        outcomes.map { outcome in
            var outcome = outcome
            guard case .removed(let trashURL?) = outcome.result, !outcome.restored else { return outcome }
            // lstat sees a symlink even when its target is missing. fileExists would follow it and look empty.
            var info = stat()
            guard lstat(trashURL.path, &info) == 0, lstat(outcome.item.url.path, &info) != 0 else { return outcome }
            do {
                try fileManager.moveItem(at: trashURL, to: outcome.item.url)
                outcome.restored = true
            } catch {}
            return outcome
        }
    }
}
