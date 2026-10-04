# Development

## Setup

- macOS 14 or later; Xcode or the Xcode Command Line Tools with the license accepted (`sudo xcodebuild -license accept`).
- Nothing to install: SwiftPM builds the package with zero third-party dependencies.
- Optional: open `Package.swift` in Xcode and run the `Viper` scheme.

## Commands

| Task | Command |
| --- | --- |
| Build / type check | `swift build` |
| Test | `swift test` |
| Run the app | `swift run Viper` |
| Release build | `swift build -c release` |
| Package the app | `bash scripts/build-app.sh [debug\|release] [--skip-build] [--distribution]` |
| Verify a bundle | `codesign --verify --deep --strict dist/Viper.app` and `plutil -lint dist/Viper.app/Contents/Info.plist` |
| Clean | `swift package clean` |

There is no configured linter or formatter. `swift build` is the type check; keep builds warning-free.

CI (`.github/workflows/test.yml`) runs on `macos-14`: `swift test` and `swift build -c release`.

## Build script

`scripts/build-app.sh` compiles (unless `--skip-build`), generates the icon at `.build/Viper.icns`, assembles `dist/Viper.app`, and signs it.

- Default / `debug` / `release`: ad-hoc signature (`-`), arm64, for local use only.
- `release --distribution`: requires `VIPER_SIGN_IDENTITY` and `VIPER_NOTARY_PROFILE`, builds a universal binary, signs with the hardened runtime, notarizes with `notarytool`, staples, and validates. Unknown flags exit 2 with usage.

Icon tooling lives in `scripts/` (`make-icon.swift` renders the app icon, `fetch-catalog-icons.swift` collects catalog icons). `Resources/CatalogIcons/` is committed; `SOURCES.json` records where each icon came from.

## Testing

- XCTest only, all in `Tests/ViperCoreTests/` against `ViperCore`.
- **Always use temporary fixtures.** Every scanner/executor test builds its own directory tree (and a fixture Trash) under a temp folder. Tests must never touch real user files, the real Trash, real Homebrew/npm installs, or the network. Package-provider tests use recorded command output and injected results, not real `brew`/`npm` calls.
- Filesystem effects are injected at the executor boundary (trash closures, command runners). There is no fake filesystem — pass closures or fixture paths, matching existing tests.
- Destructive behavior that fixtures can't cover (real `trashItem` on root-owned apps, real package installs) is verified manually in disposable environments. Note what you did and didn't verify in the PR, as `VALIDATION.md` used to.

## Adding a feature

1. Domain logic goes in `Sources/ViperCore/<Domain>/` — pure Swift, `Foundation`/`Darwin` only, no SwiftUI. If it can change files or run commands, it belongs behind policy checks and a journal.
2. UI goes in `Sources/Viper/Features/<Page>/` — the view plus its `extension AppModel` file holding that page's state and orchestration.
3. Navigation: add a case to `AppModel.Page` and a row in the sidebar in `ViperApp.swift`.
4. On-disk locations: add the path to `AppPaths.swift` — never construct `Application Support`/`Caches` paths inline.
5. Wire the feature into the mutual-exclusion gates on `AppModel` (`maintenanceBusy`, `packageOperationBusy`) if it mutates anything, and into quit handling if it can be mid-flight at termination.
6. Respect the safety model in `docs/ARCHITECTURE.md`: check `reviewedChangesAreAllowed()` per item, fail closed, record outcomes.

## Conventions

- Swift 5.9 language mode, macOS 14 deployment target. Guard newer APIs with `if #available`.
- `@MainActor` for all view-model state; heavy work in `Task.detached(priority: .utility)` or off-actor types, results assigned back on the main actor.
- `extension AppModel` per feature file — follow the existing slices rather than adding a second observable object.
- British spelling is used in user-facing copy and commit history ("Organise"); match the surrounding file.
- No force unwraps or `try!` in production paths; the codebase prefers `guard` and explicit failure values over thrown errors.
- User-facing copy states what is verified, not what is hoped — never claim a batch or uninstall "succeeded" when only part ran.

## Pitfalls

- **Never mutate in tests or dry runs.** Scanning is fine anywhere; cleanup/uninstall/install paths must only ever run against fixtures during development.
- **`CatalogIconStore` finds `Resources/` by walking up from `#filePath` to `Package.swift`** — keep that lookup working if you move files.
- **`CommandRunner` never takes a shell string.** New tools must be a fixed path plus a validated argument array, and must be added to the environment allowlist deliberately.
- **Quitting mid-operation is handled, not ignored.** New long-running operations need a termination path (cancel waiting, finish active, record outcome).
- **The menu-bar item caused a feedback-loop crash once** — guard redundant writes when observing published state.
- **Journals fail closed.** Code that touches `Application Support/Viper` must tolerate quarantined/unreadable files and must not bypass the review gate.
- **Don't preselect anything ambiguous.** Review lists preselect only confidently rebuildable items; ownership heuristics alone never justify preselection.
