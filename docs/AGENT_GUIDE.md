# Agent guide

Orientation for AI coding agents and new contributors. Read `docs/ARCHITECTURE.md` for the system design and `docs/DECISIONS.md` for why it is built this way.

## What this project is

Viper is a native macOS 14+ maintenance app (SwiftUI + SwiftPM, no dependencies). It scans storage, uninstalls apps and Homebrew/npm packages, finds junk and app leftovers, reviews memory use, checks package updates, navigates Privacy settings, and installs curated software — all review-first, all journaled. It starts read-only; users opt in to changes.

**Product direction:** a trustworthy, boring maintenance tool. It explains what it found, asks before it acts, re-validates before it touches anything, and reports honestly — including partial failure. It is not trying to be an optimizer, a black-box "cleaner", or a background service.

## Architecture rules to preserve

- **Safety gates are sacred.** `reviewedChangesAreAllowed()` is checked before every mutating item. Unreadable journals block mutations. Never bypass, weaken, or "temporarily" skip these — not even in a test helper that ships.
- **ViperCore has no UI.** All logic that scans, plans, executes, or journals lives in the library and is fixture-tested. SwiftUI stays in the app target.
- **No shell strings.** New external tools go through `CommandRunner` as a fixed path + validated args. Catalog/network data must never become a command.
- **Trash only.** No permanent delete, no emptying the Trash.
- **No background activity.** No daemon, timers, polling, or telemetry. The only repeating work is Memory's visible-page refresh.
- **All `Application Support`/`Caches` paths come from `AppPaths.swift`.**
- **Mutations join the mutual-exclusion gates** (`maintenanceBusy`, `packageOperationBusy`) and get a quit path.
- **Fail closed and report honestly.** "Possibly partial" beats "done". Never claim success for a queue that only partly ran.

## Where things live

| Need | Location |
| --- | --- |
| Add a page | `Sources/Viper/Features/<Page>/` + `AppModel.Page` + sidebar in `ViperApp.swift` |
| Add domain logic | `Sources/ViperCore/<Domain>/` (see ARCHITECTURE module map) |
| Change app state | The feature's `extension AppModel` file |
| New on-disk file | `AppPaths.swift` |
| New external tool | `CommandRunner` call site in `ViperCore`; validate args |
| Theme/control styling | `Sources/Viper/DesignSystem/` |
| Tests | `Tests/ViperCoreTests/`, temp fixtures only |
| Catalog entries | `Sources/ViperCore/Catalog/BuiltInCatalog.swift` (icons in `Resources/CatalogIcons/`) |

## Engineering style

- Match the file you're in. No formatter is configured; don't reformat code you aren't changing.
- Prefer the existing pattern over a new abstraction. Check whether a responsibility already exists before creating a file.
- Boring and explicit beats clever: `guard`, plain `Result`-style returns, no force unwraps, no suppressions.
- Keep diffs focused — a feature change and a restructure are separate commits.
- Update docs only when architecture or workflow actually changes; keep comments for non-obvious rationale only.

## Before you implement

1. Inspect the existing implementation and its tests — the safety invariants live there.
2. Identify which gate, journal, and quit path your change interacts with.
3. Reuse existing primitives (scanners, `FileIdentity`, `RemovalSignature`, `CommandRunner`, journal stores) before writing new ones.
4. Validate: `swift build` warning-free, `swift test` green, and if the app bundle or script changed, `bash scripts/build-app.sh` plus `codesign --verify`.
5. If you couldn't run a real destructive operation (you usually can't — fixtures only), say so explicitly rather than implying coverage.

## Never

- Run cleanup/uninstall/install/update/permission-reset code against the real system — tests use temp fixtures and a fixture Trash, always.
- Preselect or auto-execute anything ambiguous.
- Add dependencies, daemons, telemetry, or network calls that aren't user-initiated.
- Use `Any`, `as!`, `@unchecked Sendable`, `try!`, or warning suppressions to make errors go away.
- Leave commented-out code, scratch files, or root-level notes/reports.
- Commit credentials, certificates, `.env` files, or signing identities.
- Delete code just because search found no reference — check `AppPaths`, catalog keys, settings keys, `Page` cases, script references, and `UserDefaults` keys first.
- Promise removal completeness or rollback that the mechanism can't deliver, in code or in copy.

## Known debt (don't "fix" unprompted)

- `AppModel` is a large coordinator; mutual exclusion is booleans, not a state machine.
- Filesystem effects are static functions; tests inject at executor boundaries, not through a fake FS.
- `AppSettings` still decodes a legacy `theme` key harmlessly.
- No UI/VoiceOver tests; real package operations are untested end-to-end (needs a disposable machine).
