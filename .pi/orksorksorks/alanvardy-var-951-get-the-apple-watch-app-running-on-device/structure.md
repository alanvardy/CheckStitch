# Structure Outline

## Approach

Build bottom-up in dependency order: a shared `CheckStitchCore` package that
owns every piece of **pure, testable** logic, then the iPhone-side
persistence → reminder-writing → WatchConnectivity stack, then the watch
target scaffold and its sync/cache layer, then the watch UI. The watch never
writes EventKit; runs are messages the phone turns into reminders.

### Test strategy (decided)

Tests now ship with the work, so the design's "no tests" stance is superseded:
**`CheckStitchCore` is a Swift package and carries Swift Testing tests run with
`swift test`** — no Xcode test target. To make that cover more than trivia,
every algorithm that can be exercised without EventKit/WatchConnectivity moves
**down** into Core:

- model + Codable/message contract (`Checklist`, `ChecklistItem`, `RunReceipt`, `SyncKey`),
- the blank-skipping/trimming rule (`Checklist.reminderTitles`),
- file-backed persistence (`FileChecklistStore`) used by the iPhone source of
  truth *and* the watch cache.

What remains in the app targets (`ReminderWriter`, `PhoneSyncService`,
`WatchSyncService`, views) is a thin shell over EventKit / `WCSession` and is
verified manually on simulator and the real watch. This expands `design.md`
decision 7 ("model + message contract only") and should get a one-line
amendment — it is the only way to have real tests without an Xcode target.

---

## Stage 1: `CheckStitchCore` package — model, codec, store (+ tests)

Pure, dependency-free types and persistence both targets import. Everything
above assumes them, and this is the only stage with a fully automated suite.

**Files**: `CheckStitchCore/Package.swift`, `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`, `.../SyncContract.swift`, `.../FileChecklistStore.swift`, `CheckStitchCore/Tests/CheckStitchCoreTests/ChecklistTests.swift`, `.../ChecklistCodecTests.swift`, `.../FileChecklistStoreTests.swift`
**Key changes**:
- `public struct Checklist: Identifiable, Codable, Hashable, Sendable { let id: UUID; var name: String; var items: [ChecklistItem] }`
- `public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable { let id: UUID; var title: String }`
- `public struct RunReceipt: Codable, Sendable { let checklistID: UUID; let createdCount: Int; let at: Date }`
- `public enum SyncKey { static let checklists, runChecklistID, runReceipt: String }`
- `public enum ChecklistCodec { static func encode([Checklist]) -> Data; static func decode(Data) -> [Checklist]; encode(RunReceipt)/decode(Data) -> RunReceipt? }`
- `public extension Checklist { var reminderTitles: [String] }` — trimmed, blank titles dropped, order preserved (the rule at `ContentView.swift:94`)
- `public struct FileChecklistStore { init(fileURL: URL); func load() -> [Checklist]; func upsert(_ c: Checklist) throws }` — JSON, atomic write, missing/corrupt file ⇒ `[]`
- `Package.swift` platforms: iOS 18.7, watchOS 27.0, and the app's `MACOSX_DEPLOYMENT_TARGET`

**Tests** (Swift Testing, `@Test` in a `@MainActor`/plain struct):
- `reminderTitles` trims, drops blank/whitespace-only, keeps order — happy + sad (all-blank ⇒ empty)
- `Checklist` / `RunReceipt` Codable round-trip
- `ChecklistCodec` decode of garbage / empty `Data` ⇒ `[]` / `nil`
- `FileChecklistStore` save→load round-trip in a temp dir, `upsert` replaces by id, missing file ⇒ `[]`, corrupt file ⇒ `[]` without throwing

**Verify**: `swift test --package-path CheckStitchCore` green — the only fully automated gate in the ticket.

---

## Stage 2: iPhone persistence wiring

Checklists stop being ephemeral: Create persists `{name, items}` through the
tested `FileChecklistStore` and reloads it on launch.

**Files**: `CheckStitch/ContentView.swift` (modified), `CheckStitch/MyApp.swift` (modified)
**Key changes**:
- `let store = FileChecklistStore(fileURL: …Application Support/checklists.json)` owned by `MyApp`, injected into `ContentView`
- `createChecklistReminders()` calls `store.upsert(...)`; initial `@State` seeds from `store.load()`

**Tests**: none at this layer (thin glue) — manual: create two checklists,
relaunch, both survive; re-saving a checklist updates in place.
**Verify**: `make build`; manual simulator relaunch check.

---

## Stage 3: iPhone reminder writer — `ReminderWriter`

Extract the EventKit write out of the view so the view and sync service share
one owner, holding a **single** `EKEventStore` (dodges `EKCADErrorDomain
Code=1021`).

**Files**: `CheckStitch/ReminderWriter.swift` (new), `CheckStitch/ContentView.swift` (modified)
**Key changes**:
- `@MainActor final class ReminderWriter { init(store: EKEventStore = EKEventStore()); func requestAccess() async -> Bool; func write(_ checklist: Checklist) async throws -> Int }`
- `write` iterates `checklist.reminderTitles` (Stage 1, tested) → `EKReminder(eventStore:)` → `calendar = defaultCalendarForNewReminders()` → `save(commit: true)`
- `ContentView` calls the writer instead of owning the store

**Tests**: EventKit cannot run headlessly; the filtering rule is already covered
in Stage 1. Manual: blank item + valid item ⇒ only the valid reminder (happy);
permission denied ⇒ no reminders, no crash (sad).
**Verify**: `make build`; simulator create flow still produces reminders.

---

## Stage 4: iPhone transport — `PhoneSyncService`

Activate `WCSession`, publish the checklist set via `updateApplicationContext`,
consume `transferUserInfo` run triggers, write reminders, send back a
`RunReceipt`.

**Files**: `CheckStitch/PhoneSyncService.swift` (new), `CheckStitch/MyApp.swift` (modified)
**Key changes**:
- `@MainActor final class PhoneSyncService: NSObject, WCSessionDelegate { init(store: FileChecklistStore, writer: ReminderWriter, session: WCSession = .default); func start(); func pushChecklists() }`
- `didReceiveUserInfo` → decode `runChecklistID` → find in store → `writer.write` → `sendReceipt` via `transferUserInfo`; unknown id ignored (sad path)
- `activationDidCompleteWith` / `reachabilityDidChange` → `pushChecklists()`
- ContentView pushes the context after every `upsert`

**Tests**: none (WCSession); payload encode/decode is already covered by Stage 1's codec tests.
**Verify**: `make build`; manual phone↔watch-sim pair — context arrives, bad id ignored (log-based).

---

## Stage 5: Watch target + tooling (deploy risk retired early)

Add `CheckStitchWatch` as a companion target with a hello-world `WindowGroup`,
embed it in `CheckStitch.app`, and install it on the **real** watch before any
watch logic exists, so the `devicectl`/signing unknowns surface now.

**Files**: `CheckStitchWatch/CheckStitchWatchApp.swift` (new), `CheckStitch.xcodeproj/project.pbxproj` (new target, product ref, `PBXFileSystemSynchronizedRootGroup`, "Embed Watch Content" phase, `PBXTargetDependency`, package dependency), `Makefile` (`watch-build`), `scripts/run-watch.sh` (new, `100755`)
**Key changes**:
- Watch configs copy SingleThread's recipe: `SDKROOT = watchos`, `SUPPORTED_PLATFORMS = "watchos watchsimulator"`, `TARGETED_DEVICE_FAMILY = 4`, `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitch.watchkitapp`, `SKIP_INSTALL = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_WKCompanionAppBundleIdentifier = app.alanvardy.CheckStitch`, `INFOPLIST_KEY_WKWatchOnly = NO`, `DEVELOPMENT_TEAM = 6NWX2DHB9Q`; **no** `CODE_SIGN_ENTITLEMENTS`
- iOS target gains the watch dependency + embed phase and links `CheckStitchCore`
- `make watch-build` → `xcodebuild -scheme CheckStitchWatch -destination 'generic/platform=watchOS' … build` (+ `-allowProvisioningUpdates` fallback)
- `scripts/run-watch.sh` → `xcrun devicectl list devices -j` + python filter (physical watch, Developer Mode enabled) → `device install app` → `device process launch --terminate-existing --activate`

**Tests**: manual — scaffold launches on `Alan's Apple Watch`; `shellcheck scripts/run-watch.sh` clean (sad: watch unreachable ⇒ loud failure, no bare `name=` destination).
**Verify**: `make watch-build` and `make build` both pass; `bash scripts/run-watch.sh` installs/launches; `shellcheck scripts/*.sh`.

---

## Stage 6: Watch sync + cache

The watch keeps a cached checklist set in its own container (tested
`FileChecklistStore`) and exchanges messages with the phone; run state is
`idle → queued → accepted`.

**Files**: `CheckStitchWatch/WatchSyncService.swift` (new), `CheckStitchWatch/CheckStitchWatchApp.swift` (modified)
**Key changes**:
- `@MainActor @Observable final class WatchSyncService: NSObject, WCSessionDelegate { enum RunState { case idle, queued, accepted(RunReceipt), failed }; init(cache: FileChecklistStore); func start(); func requestChecklists(); func run(_ c: Checklist); private(set) var runState }`
- `didReceiveApplicationContext` → decode `checklists` → cache.upsert/replace; `didReceiveUserInfo` → `runReceipt` → `.accepted`; `reachabilityDidChange` → re-request

**Tests**: cache persistence is Stage 1's tested store. Manual on a paired
sim pair: context populates the cache, `run()` then receipt flips state; run
while the phone is unreachable stays `.queued` (never shown as success).
**Verify**: `make watch-build`; manual paired-simulator sync check.

---

## Stage 7: Watch UI — list → items → Run

Two screens: pick a checklist, see its items read-only, tap Run (the only
action).

**Files**: `CheckStitchWatch/CheckStitchWatchApp.swift` (modified), `CheckStitchWatch/ChecklistListView.swift`, `CheckStitchWatch/ChecklistDetailView.swift`, `CheckStitchWatch/WatchChecklistViewModel.swift` (new)
**Key changes**:
- `@main struct CheckStitchWatchApp: App { WindowGroup { ChecklistListView() } }`; view model owns the cache + `WatchSyncService`, `.task { sync.start(); sync.requestChecklists() }`
- `ChecklistListView`: `NavigationStack` + `List`, empty state ("No checklists yet"), `.navigationDestination`
- `ChecklistDetailView`: item names + `Button("Run")` → `sync.run(checklist)`, rendering `runState` (`.queued` → "Queued", `.accepted` → "Added N reminders")

**Tests**: manual on the real watch — create on iPhone, appears in list, Run
produces one reminder per item on both devices; empty cache and unreachable
phone are the sad paths.
**Verify**: `make watch-build`; `bash scripts/run-watch.sh`; end-to-end acceptance checks 3 and 4 from `design.md`.

---

## Stage 8: Gate + docs

Make the automated tests part of the single gate and record the new commands.
`AGENTS.md` has already been corrected in this step.

**Files**: `scripts/test.sh` (modified), `Makefile` (if needed)
**Key changes**: `scripts/test.sh` = `make build` + `make watch-build` +
`swift test --package-path CheckStitchCore` + `shellcheck scripts/*.sh`.

**Tests**: none beyond the gate itself.
**Verify**: `./scripts/test.sh` passes end to end.

---

## Testing Checkpoints

- After **S1**: `swift test --package-path CheckStitchCore` green before anything imports Core.
- After **S2**: `make build` + persistence survives relaunch.
- After **S3**: `make build` + manual create still writes reminders.
- After **S4**: `make build` + manual paired-sim context/receipt exchange.
- After **S5**: `make watch-build` **and** `make build` green, and the scaffold installs on the real watch.
- After **S6**: `make watch-build` + manual cached-set/run-state sync.
- After **S7**: real-watch acceptance checks 3 & 4.
- After **S8**: `./scripts/test.sh` green.

If any checkpoint fails, fix within that stage — do not start the next layer.