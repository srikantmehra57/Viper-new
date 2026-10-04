# Decisions

Lightweight record of architectural decisions. Add an entry when a choice would surprise a new contributor or is expensive to reverse. Dates are when the decision was made, not necessarily documented.

## Read-only by default; every mutation is reviewed

**Date:** 2026-09-15
**Context:** A maintenance tool that deletes files is one mistake away from destroying user data.
**Decision:** Ship with `allowReviewedChanges = false`. Each flow is discover → explain → select → preview → journal → revalidate → execute → report. The safety switch is re-checked before every item, not just at confirmation.
**Reason:** A gate checked once at confirmation still executes stale work if the user turns it off mid-queue (fixed in AUD-001).
**Consequences:** No feature may bypass `reviewedChangesAreAllowed()`. Unreadable journals quarantine and block all mutations until reviewed.

## Two targets: `ViperCore` library + `Viper` app

**Date:** 2026-09-15
**Context:** Safety-critical logic needs fixture tests; SwiftUI views can't be unit-tested usefully.
**Decision:** All domain logic lives in `ViperCore` with no UI imports. The app target holds views and the `AppModel` coordinator only.
**Consequences:** New logic lands in the core where it can be tested; the UI layer stays thin. Tests cover planners, scanners, executors, journals, and command construction — the seams where data loss would occur.

## No third-party dependencies

**Date:** 2026-09-15
**Context:** A tool that runs package managers and inspects the filesystem is a supply-chain target; nothing needed was missing from the system frameworks.
**Consequences:** No dependency upgrades to manage. Add a dependency only for a real gap, and justify it in this file.

## Trash-only file removal

**Date:** 2026-09-15
**Context:** Early builds considered permanent deletion and an "Empty Trash" action.
**Decision:** All file removal goes through `FileManager.trashItem`, with put-back support where Finder allows it. Viper never empties the Trash (AUD: an Empty Trash button would delete unrelated user data).
**Consequences:** Space is not reclaimed until the user empties Trash — the UI says so. Items that can't be trashed (root-owned, system) are reported, never forced.

## No privileged helper, daemon, or login item

**Date:** 2026-09-15
**Context:** Root access would widen both capability and attack surface; nothing in the feature set requires it.
**Decision:** Operations needing admin rights are reported or handed to the OS/vendor flow instead. No background processes, no telemetry, no scheduled scans.
**Consequences:** `/Library` system items, root-owned apps, and `pkg`-based casks stay out of scope. If a narrowly scoped helper is ever added, it needs its own threat model and a decision entry here.

## Write-ahead removal journal, fail closed

**Date:** 2026-09-16
**Context:** An earlier audit found removals had no crash recovery — a killed process left half-moved data with no record.
**Decision:** `RemovalTransactionRecorder` persists the full plan before the first mutation and each outcome after. Journals are atomic + fsynced, mode 0600 in a 0700 folder. Unreadable journals quarantine and block changes.
**Consequences:** Interrupted transactions are surfaced in Settings on next launch. Journal writes failing mid-queue stop the queue rather than continuing unrecorded.

## Commands run without a shell, on validated arguments

**Date:** 2026-09-15
**Context:** `brew`, `npm`, `tccutil`, `launchctl` are invoked with user-influenced names.
**Decision:** `CommandRunner` uses `posix_spawn` with a fixed executable path, a validated argument array, an allowlisted environment (`SSH_AUTH_SOCK` excluded), its own process group, and descendant tracking for cancellation.
**Consequences:** Catalog data can never supply a command — only package identifiers that pass validation. A timeout reports `unsettled` rather than claiming a stopped tree (a pre-snapshot double-fork can still escape; documented limitation).

## Catalog is compiled in, not remote

**Date:** 2026-09-15
**Context:** A remotely refreshed catalog would let network content influence installs.
**Decision:** The catalog ships in the binary, validated at load (canonical brew tokens, npm names without versions/URLs, HTTPS sites only). Provider metadata fetched at review time may authorize an install; a disk cache never does.
**Consequences:** Adding apps means a code change and review. Remote refresh is a possible future feature — it must keep the same validation and provenance rules.

## One `AppModel` coordinator, per-feature extensions

**Date:** 2026-09-22 (retained after audit)
**Context:** `AppModel` grew into a large coordinator with boolean mutual-exclusion gates.
**Decision:** Keep it. Each feature's state/orchestration lives in an `extension AppModel` file beside its views, which keeps the file sizes navigable and the published state in one observable object.
**Consequences:** Known debt: the gates are several booleans rather than one operation state machine, and filesystem effects are static functions injected at executor boundaries rather than through a protocol. Revisit only if a second mutation source appears — don't refactor speculatively.

## Local builds are ad-hoc signed; distribution is opt-in

**Date:** 2026-09-16
**Context:** Local builds shouldn't require credentials, but releases must be properly signed and notarized.
**Decision:** `build-app.sh` signs ad-hoc by default. `--distribution` requires release mode plus `VIPER_SIGN_IDENTITY` and `VIPER_NOTARY_PROFILE`, then builds universal, signs hardened runtime, notarizes, and staples.
**Consequences:** `dist/Viper.app` from a default build is a dev artifact — Gatekeeper will not treat it as a normal download. Distribution remains untested until run with real credentials.
