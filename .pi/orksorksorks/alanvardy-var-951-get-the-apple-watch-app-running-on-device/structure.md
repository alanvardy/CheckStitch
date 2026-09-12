# Structure Outline

## Approach

Rebase-free: `HEAD` already descends from `main`, so build on the existing
persistence (`ChecklistStore`, `ChecklistCodec`, `AppGroup`) and the
`CheckStitchCore` seam. Add a companion `CheckStitchWatch` target
(`WKWatchOnly = NO`) that is a **pure client** — no EventKit, no writes — and
sync it over WatchConnectivity. **All new logic lands in `CheckStitchCore` as
plain, host-testable types**; the watch target, the `WCSession` adapter and the
pbxproj stay thin and are verified by build/run only.

**Cross-cutting caveat (cannot be built horizontally):** the pbxproj watch
target, the `WCSession` adapter and the SwiftUI watch views only become testable
at the top layer. Mitigation: every one of them is deliberately logic-free —
state, decoding and dispatch live in Core behind injected protocols, so each
risky shell is a compile check plus a manual smoke, never untested behaviour.

**Preconditions**: `git merge-base --is-ancestor main HEAD` true (confirmed);
housekeeping — the worktree `AGENTS.md` gate line omits `make build-mac`
(actual `scripts/test.sh` runs `make build` → `make test` → `make build-mac` →
`shellcheck`).

---

## Stage 1: Shared model in `CheckStitchCore`

Relocate the versioned model out of the app target into the package and merge
the two `ChecklistItem` types. Green tests prove the envelope is still
byte-compatible with what `ChecklistStore` already persists under
`checklists.v1`.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` (new),
`CheckStitchCore/Sources/CheckStitchCore/ChecklistItem.swift` (merge into it),
`CheckStitch/Checklist.swift` (delete), `CheckStitch/ChecklistStore.swift`,
`CheckStitch/ChecklistDetailView.swift`, `CheckStitchCore/Package.swift`

**Key changes**:
- `public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable { id: UUID; title: String; isBlank: Bool }` — merged (app's Codable/Hashable shape + Core's `isBlank`)
- `public struct Checklist: Identifiable, Codable, Hashable, Sendable`, `public struct ChecklistEnvelope: Codable, Sendable` — moved, no wire-format change
- `public enum ChecklistCodec { static func encode(_:) throws -> Data; static func decode(_:) throws -> ChecklistEnvelope }` — moved; still refuses newer schema versions
- `Package.swift`: add `.watchOS("27.0")` alongside iOS/macOS (package stays buildable for all three)
- Consumers switch to `import CheckStitchCore`; no behavioural change

**Tests**: existing `ChecklistCodecTests`, `ChecklistItemTests`,
`ChecklistStoreTests` pass unchanged against Core types; new cases in
`ChecklistItemTests` for `isBlank` (empty **and** whitespace-only = blank;
`"x"` = non-blank) and id-preserving Codable round-trip.
**Verify**: `make test-unit` green; `make build` and `make build-mac` green
(the macOS slice proves the package still compiles off-iOS).

---

## Stage 2: Sync contract + watch state machine (`CheckStitchCore`)

Define the WatchConnectivity wire contract and the watch's observable state as
pure, transport-injected types. Green tests prove both sides agree on the
envelope and that malformed/stale payloads never corrupt watch state.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift` (new)

**Key changes**:
- `enum ChecklistSyncKey { context = "checklists"; runChecklist = "runChecklist"; requestChecklists = "requestChecklists" }`
- `enum ChecklistSyncMessage: Equatable, Sendable { case context(Data) /* encoded ChecklistEnvelope */, runChecklist(UUID), requestChecklists }` with `init?(userInfo: [String: Any])` / `var userInfo: [String: Any]`
- `protocol ChecklistSyncTransport: AnyObject { var onMessage: ((ChecklistSyncMessage) -> Void)? { get set }; func activate(); func sendContext(_ data: Data); func sendUserInfo(_ message: ChecklistSyncMessage) }` — the seam both the watch and phone adapters implement (faked in tests)
- `@MainActor @Observable final class WatchChecklistStore { init(transport:); private(set) var checklists: [Checklist]; private(set) var pendingRunID: UUID?; func start(); func run(_ checklist: Checklist); func requestRefresh() }`

**Tests**: new `ChecklistSyncMessageTests` (round-trip each case; unknown key →
`nil`; wrong value type → `nil` — sad path) and `WatchChecklistStoreTests`
(context replaces the list; malformed `Data` leaves the previous list intact and
does not crash; `run` sends exactly one `.runChecklist` and records
`pendingRunID`; `requestRefresh` sends `.requestChecklists`; `start` activates
the transport).
**Verify**: `make test-unit` green (no watch target needed yet — the whole layer
runs on the macOS host).

---

## Stage 3: Watch target + build scaffolding

Stand up the `CheckStitchWatch` target, its shared scheme and `make watch-build`
with a minimal shell app. This is the riskiest layer (hand-edited pbxproj), so
it lands alone; verification is a compile of every affected target.

**Files**: `CheckStitchWatch/CheckStitchWatchApp.swift` (minimal `WindowGroup`
shell), `CheckStitch.xcodeproj/project.pbxproj`,
`CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitchWatch.xcscheme`,
`Makefile`

**Key changes**:
- `PBXNativeTarget "CheckStitchWatch"` (product `CheckStitchWatch.app`) with watch configs per SingleThread: `SDKROOT = watchos`, `SUPPORTED_PLATFORMS = "watchos watchsimulator"`, `TARGETED_DEVICE_FAMILY = 4`, `SKIP_INSTALL = YES`, `WKWatchOnly = NO`, `WKCompanionAppBundleIdentifier = app.alanvardy.CheckStitch`, bundle id `app.alanvardy.CheckStitch.watchkitapp`, **no** `CODE_SIGN_ENTITLEMENTS`
- `PBXFileSystemSynchronizedRootGroup` for `CheckStitchWatch/`; "Embed Watch Content" copy phase (`$(CONTENTS_FOLDER_PATH)/Watch`) + `PBXTargetDependency`; package product link reusing ref `...031`
- `Makefile`: `WATCH_SIM := generic/platform=watchOS Simulator` and a `watch-build` target (`xcodebuild -scheme CheckStitchWatch -destination '$(WATCH_SIM)' … build`)

**Tests**: none (no watch test target by design — decision 9).
**Verify**: `make watch-build` green **and** `make build`, `make build-mac`,
`make test-unit` still green (a malformed pbxproj breaks the whole gate, so all
four run in this checkpoint). Optional manual: install the built `.app` on the
`Apple Watch Series 11 (46mm)` simulator and confirm it launches empty.

---

## Stage 4: Watch UI — list → detail → run

Render the watch surface over the Stage-2 store: a checklist list, a read-only
item detail, and the single **"Create reminders"** action.

**Files**: `CheckStitchWatch/WatchChecklistListView.swift` (new),
`CheckStitchWatch/WatchChecklistDetailView.swift` (new),
`CheckStitchWatch/CheckStitchWatchApp.swift`

**Key changes**:
- Root view switches on `WatchChecklistStore`: empty → "Open CheckStitch on your iPhone"; otherwise a `List` of checklists navigating to detail
- Detail view: read-only `ForEach(checklist.items)` (blank items filtered, using the merged `isBlank`) + one button calling `store.run(checklist)`, which shows a **"Sent"** state only (never "created" — queued `transferUserInfo` is not delivery)
- No `import EventKit`, no Edit/Delete affordances

**Tests**: none directly (watch views are outside any host test target); the
behaviour they expose is already covered by `WatchChecklistStoreTests`.
**Verify**: `make watch-build` green; manual smoke on the watch simulator
(list renders, tapping a checklist shows items and the button).

---

## Stage 5: Phone-side coordinator + `WCSession` adapter

Make the phone push its checklist set on every change and execute run requests
through the **existing** `ChecklistReminders.create(from:)` path.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
(new), `CheckStitch/PhoneSyncAdapter.swift` (new),
`CheckStitch/MyApp.swift`, `CheckStitch/AppDelegate.swift`,
`CheckStitch/ChecklistReminders.swift` (unchanged — passed in as a closure)

**Key changes**:
- `@MainActor final class ChecklistSyncCoordinator { init(transport:, snapshot: @escaping () -> ChecklistEnvelope, createReminders: @escaping (Checklist) async -> Void); func start(); func checklistsDidChange() }` — pushes `updateApplicationContext` on start and on change; answers `.requestChecklists`; on `.runChecklist(UUID)` looks the checklist up by id and calls `createReminders`
- `final class PhoneSyncAdapter: NSObject, WCSessionDelegate, ChecklistSyncTransport` — the only `WatchConnectivity` import; activation, `updateApplicationContext`, `transferUserInfo`, inbound dispatch. Single `EKEventStore` stays where it is (no second instance — `EKCADErrorDomain 1021`)
- `MyApp`/`AppDelegate` own the coordinator and call `checklistsDidChange()` from `ChecklistStore` observation

**Tests**: new `ChecklistSyncCoordinatorTests` with a fake transport and fake
create closure (start pushes the encoded context; a store change pushes again;
`.runChecklist` with a known id calls create **once**; unknown id calls create
**zero** times and does not crash; `.requestChecklists` re-pushes).
**Verify**: `make test-unit` green; `make build` green (the adapter compiles
against `WatchConnectivity`).

---

## Stage 6: Tooling, gate and real-watch run

Wire the watch into the gate and deploy to hardware — the last verifiable step,
and the riskiest deliverable.

**Files**: `scripts/run-watch.sh` (new, `#!/bin/bash`, `set -euo pipefail`,
mode `100755`), `scripts/test.sh`, `Makefile` (destination only if needed)

**Key changes**:
- `run-watch.sh`: build `-destination 'generic/platform=watchOS' -allowProvisioningUpdates`, then `xcrun devicectl device install app` + `device process launch --terminate-existing --activate` against `Alan's Apple Watch` (`00008301-209B793C010BC02E`), resolved to an id — **never** a bare `name=`. Report `devicectl` 4016 (offline/RDS) clearly. Install the iPhone app first if the watch bundle needs its companion
- `test.sh`: add `make watch-build` after `make build-mac`, before shellcheck

**Tests**: shellcheck clean; the whole gate is the regression test for every
earlier stage.
**Verify**: `./scripts/test.sh` prints `gate: ok`; `bash scripts/run-watch.sh`
launches `CheckStitchWatch` on the real watch; then the design's manual checks —
(3) a phone-side checklist edit appears on the watch, (4) "Create reminders"
yields one reminder per non-blank item in Inbox, (5) the watch writes nothing
and reads no EventKit.

---

## Testing Checkpoints

- After Stage 1: `make test-unit` + `make build` + `make build-mac` green before touching sync.
- After Stage 2: `make test-unit` green — the entire sync contract is proven on the host before any watch target exists.
- After Stage 3: `make watch-build` **plus** `make build`/`build-mac`/`test-unit` green (pbxproj edits can break every target).
- After Stage 4: `make watch-build` green; manual watch-simulator smoke.
- After Stage 5: `make test-unit` + `make build` green; no second `EKEventStore` introduced.
- After Stage 6: full `./scripts/test.sh` `gate: ok`, then the real-watch manual checks.

## Open Item for Confirmation

Design decision 6 is unresolved: keep the **item detail screen** (structure
above assumes this — one tap cannot silently write N reminders) or make tapping
a checklist run it directly. If the latter, Stage 4 loses
`WatchChecklistDetailView.swift` and becomes a one-line change; nothing below it
is affected.
