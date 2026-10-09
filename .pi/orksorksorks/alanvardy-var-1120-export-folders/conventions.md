# Conventions — factual appendix (no source re-reading needed)

## Canonical build / test / lint commands
- **Gate:** `./scripts/test.sh` — full pipeline: `make build` (simulator) → headless pre-boot of
  this worktree's `.simulator_id` → `make test` → `make build-mac` → `make watch-build` →
  `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`, prints `gate: ok`.
- `make build` — simulator build, scheme `CheckStitch`.
- `make build-mac` — unsigned macOS compile leg.
- `make build-mac-signed` — runnable macOS app (needs `-allowProvisioningUpdates`; used by run-devices).
- `make run` — build, boot/install/launch on a simulator.
- `make watch-build` — watchOS simulator compile of `CheckStitchWatch`.
- `make test-unit` — `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO` (no sim/signing).
- `make test-ui` — one `CheckStitchUITests` smoke via build-for-testing → test-without-building on
  this worktree's `.simulator_id`.
- Warnings-as-errors are enforced project-wide (Debug+Release, both `SWIFT_TREAT_WARNINGS_AS_ERRORS`
  and `GCC_TREAT_WARNINGS_AS_ERRORS=YES`) so any Xcode build fails on a compiler warning. The
  `CheckStitchCore` local package is not separately enforced.

## Test-suite inventory (all under `CheckStitchTests/`)
| Suite | Type | Isolation | Folder coverage |
|---|---|---|---|
| `ChecklistExportTests.swift` (173) | XCTest | `@MainActor` | none |
| `ChecklistExportDocumentTests.swift` (12) | Swift Testing | — | none |
| `ChecklistImportSessionTests.swift` (360) | Swift Testing | `@MainActor` | none |
| `ChecklistImportExportViewModelTests.swift` (351) | Swift Testing | `@MainActor` | none |
| `ChecklistCodecTests.swift` (571) | XCTest | `@MainActor` | yes (round-trip :507-517, collapse :465, absent-key :454) |
| `ChecklistStoreTests.swift` (2950, VAR-969) | XCTest | `@MainActor` | yes (CRUD :2675-2797) |
| `ChecklistMergeTests.swift` (1250) | Swift Testing | — | yes (LWW :877-892, unite :859, tombstone :896-912) |
| `ChecklistGroupingTests.swift` (169) | Swift Testing | — | yes (loose/orphan/empty/visibility) |

- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in with
  `@MainActor`. No `#if os(...)`/`#available` guards in any named suite.
- Unit suites are Swift Testing (`@Test`/`#expect`, behaviour-named functions — never
  `test`-prefixed; `@Test(arguments:)` for cases). Store/codec suites are XCTest (`XCTAssert*`).
- Fakes/spies live in `CheckStitchTests/TestFixtures.swift` (`makeItem`, `makeIsolatedDefaults`,
  `sharedTestEventStore`, `SpyReminderCreator`, `InMemoryChecklistSync`,
  `FakeChecklistSyncTransport`, etc.). **No shared folder fixture helper** — folders are built
  inline per suite.

## Fixture construction patterns (per suite)
- Export/import round-trip tests encode via `ChecklistCodec.encode`, decode via
  `ChecklistCodec.classify`, and assert on the decoded envelope semantically — never byte-compare
  JSON (`ChecklistExportTests.swift:24-33,159-173`).
- Import sessions are built with an isolated store:
  `ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)` +
  `ChecklistImportSession`; payloads via `payload(_:version:)` (`ChecklistImportSessionTests.swift:6-18`).
- Filters: `store.activeChecklists` (excludes tombstoned); names collide via case-insensitive
  trimmed `sameName`; import arrives disambiguated `base`→`base 2`… via `uniqueName`
  (`ChecklistStore.swift:407-425`).
- Store suites use a deterministic `Clock` and nil debounce (`ChecklistStoreTests.swift:10-46`).
- Folder cases build `Folder(name:)` and link via `checklist.folderID = folder.id`.

## Build / verify gotchas
- Never leave a bare `name=` destination in a script (selects a shared device, wedges parallel
  agents); use an explicit `SIM=` / `.simulator_id` UDID.
- `scripts/*.sh` are `#!/bin/bash`, `set -euo pipefail`, mode `100755`.
- Import write paths (`freshCopy`/`importInsert`/`importReplace`) drop `folderID`, `itemOrder`,
  archive state, and legacy revisions; imported content always lands active with fresh UUIDs and
  `revision: 1` (`ChecklistStore.swift:274-324`).
- `save()` refuses writes when `!canOverwriteStoredPayload` (newer-app-version guard)
  (`ChecklistStore.swift:784-787`).
- Localization: user-facing strings live in `Localizable.xcstrings` (all 6 languages + a
  `LocalizationFixtures.requiredKeys` entry); run `scripts/l10n-check.sh` first. Not applicable to
  Core (no user-facing strings), but relevant in the app target view-model/error messages
  (`ChecklistImportExportViewModel.swift:122-128`).
- The export payload deliberately sets `deviceID: ""` and ships no tombstones/folders — the design
  must preserve the "no foreign device id, no resurrection" invariant when adding folders.