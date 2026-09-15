# Research Findings

All paths relative to repo root `/Users/vardy/dev/alanvardy-var-997-import-and-export-checklists-as-json`. Line anchors were re-verified by grep during synthesis; researcher-only anchors are marked `~`.

## Q1: `ChecklistCodec` — encode / classify / decode semantics

### Findings
- All core types live in one file: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`.
- `ChecklistEnvelope` (Checklist.swift:238) — `version: Int`, `deviceID: String`, `checklists: [Checklist]`, `tombstones: [ChecklistTombstone]`; CodingKeys `version, deviceID, checklists, tombstones` (:254); decoder (:256-264) uses `decodeIfPresent` for `deviceID`/`checklists`/`tombstones` with defaults `""`/`[]`/`[]` (:255 comment: "v1 payloads have neither deviceID nor tombstones"); encoder (:266-273) writes all four keys unconditionally; `contentEquals` (:277-281) compares version + checklists + tombstones, **ignoring `deviceID`** (used by sync to decide whether reconciled state must be pushed back).
- `ChecklistTombstone` (:222-234) — `checklistID`, `itemID: UUID?` (`nil` = whole-checklist deletion), `deletedAt`, `revision`.
- `ChecklistItem` (:8-73) — fields `id, title, description, modifiedAt, revision, relativeDate` (:43); decoder (:53-64) makes `description`/`modifiedAt`/`revision` optional (defaults `""`/`.distantPast`/`0`); additive fields need no version bump. `Checklist` decoder (:118-140) makes every field optional and re-runs public init so decode self-heals via `normalizedOrder()`.
- `ChecklistCodec.encode` (:304-306) is just `JSONEncoder().encode(envelope)` — bytes are JSON text of the envelope.
- Version probing: `VersionProbe` (:348) decodes **only** the `version` key first, so a future version is never mis-read into the full model. `classify` (:310-338) never crashes: `currentVersion` (4, :283) → `.loaded(JSONDecoder().decode(ChecklistEnvelope.self))` (:314-315); `case 3/2/1` → `.migratable(from:, envelope:)` decoded verbatim (:316-328); `default` → log → `.unsupportedVersion` (:329-332); any throw during probe or full decode → log → `.unreadable` (:334-337).
- `Outcome` enum (:290-301): `loaded(ChecklistEnvelope)` — exact current version; `migratable(from: Int, envelope:)` — known older version, carries the whole envelope (deviceID/tombstones/sync state preserved); `unsupportedVersion` — future version, unknown shape; `unreadable` — cannot be decoded.
- Two consumers interpret the outcomes:
  - Store — `CheckStitch/ChecklistStore.swift:67-97`: `.loaded` → checklists+tombstones, `canOverwriteStoredPayload = true`; `.migratable` (:73-88) `from == 1` → `migrated(at: now())`, `from == 2` → `seededOrder()`, v3+ verbatim, always `canOverwriteStoredPayload = true` ("never stall migration"); `.unsupportedVersion` → empty checklists, `canOverwriteStoredPayload = false` (refuses to overwrite data from a newer app); `.unreadable` → empty, `true` (store replaces the garbage); no stored data → empty, `true`.
  - Sync — `CheckStitch/ChecklistSyncService.swift:123-150`: `.loaded` → remote as-is; `.migratable` v1 → `migrated(at: .distantPast)` with empty deviceID, v2 → `seededOrder()` keeping deviceID and tombstones, v3+ verbatim; `.unsupportedVersion`/`.unreadable` → `finish(.failed("Stored sync data could not be read."))` — never writes over remote bytes it cannot understand.
- Migration helpers (:160-216): `migrated(at:)` (:160-179, v1: stamps revision/modifiedAt, seeds `itemOrder`); `seededOrder()` (:186-196, v2: only order fields, never restamps sync identity); `normalizedOrder()` (:200-216, canonicalises `items` against `itemOrder`, idempotent, runs on decode/merge/item mutations).
- `decode` convenience (:340-350): `.loaded`/`.migratable` → `envelope.checklists`; `unsupportedVersion`/`unreadable` → `[]`.

### Existing codec tests (`CheckStitchTests/ChecklistCodecTests.swift`, XCTest, `@MainActor`)
- Round trip encode → classify → `.loaded`/decode equality, `itemOrder` survives JSON (:7-24); v1 fixture → `.migratable(from: 1)` (:29); v2 → `.migratable(from: 2)` preserving `revision` (:51); v2 with tombstone → tombstones kept verbatim (:69); v3 → `.migratable(from: 3)` (:87); current version → `.loaded` (:82); future version → `.unsupportedVersion` and `decode == []` (:43, :97-100); raw `"not json"` → `.unreadable` (:123-129); missing `description` key → still `.loaded` with `""` (:164-174); `"description": 42` → `.unreadable` (:192-195); order preserved through encode/classify (:102-117); empty envelope → `[]` (:119-121).

## Q2: `ChecklistStore` — read / mutate / persist semantics

### Findings
- `CheckStitch/ChecklistStore.swift: `@Observable final class` (:8) with `private(set) var checklists` (:20), `private(set) var tombstones` (:23, only grows, no GC — :21-22 comment), `onChange: (() -> Void)?` (:31), `isApplyingRemote` (:33), `canOverwriteStoredPayload` (:38), `textEditDelay` (:41), `deviceID` (:47), `now` clock (:48).
- Storage: `UserDefaults` key `"checklists.v1"` (init :53-55, `defaults.data(forKey:)` at :66); `deviceID` persisted under key `"checklist.deviceID"` (const :116, read/or-create in init).
- `var envelope` (:100-105) builds `ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID:, checklists:, tombstones:)` — comment "store is the only encoder". `var canAcceptRemoteChanges` (:114) = `canOverwriteStoredPayload`.
- Name semantics — the import-conflict primitive:
  - `sameName(_ a, _ b)` (:212-215) — trims whitespace, `caseInsensitiveCompare == .orderedSame`: `"Groceries"`, `"groceries"`, `" groceries "` all collide.
  - `uniqueName(basedOn:, taken:)` (:191-197) — tries base, then `base 2`, `base 3`… via `sameName`.
  - `rename` (:158-171) — excludes the renamed checklist itself from the collision check, bumps `revision += 1` + `modifiedAt = now()`, `scheduleSave()`; outcomes `.renamed`/`.nameTaken`/`.notFound` (:12-17).
- Mutation → save pattern:
  - Immediate `save()`: `create` (:127-136), `addItem` (:209-215), `removeItems` (:263-268), `moveItems` (:285-295), `delete` (:308-315), `duplicate` (:130-149 + `duplicateName` = `"<name> copy"`).
  - Coalesced `scheduleSave()`: `rename`, `setDestination`, `updateItem` family (:218-255); `relativeDate` update no-ops when unchanged (:250-253).
- **Tombstone recording** — both delete paths append `ChecklistTombstone(checklistID:, itemID:, deletedAt: now(), revision: removed.revision + 1)`:
  - Whole-checklist: `delete(id)` (:310-313) with `itemID: nil`; unknown id → no-op (:314).
  - Item: `removeItems(from:, at:)` (:265-268) — one tombstone per removed item, `save()`.
  - `duplicate` makes fresh copies (new item UUIDs, revision 1) and never touches tombstones (:130-149).
- `save()` (:365-377): cancels pending debounce, `guard canOverwriteStoredPayload else return` (logs "Refusing to overwrite checklist payload written by a newer app version"), `defaults.set(try ChecklistCodec.encode(envelope), forKey: key)` (encode failures only log), then `if !isApplyingRemote { onChange?() }` (:376). `scheduleSave()` (:346-356) debounces via `textEditDelay` (nil → immediate, test injection); `flushPendingSave()` (:337-340) cancels and saves.
- `apply(remote: ChecklistEnvelope)` (:320-338): guards `canOverwriteStoredPayload` and `remote.version == ChecklistCodec.currentVersion`, runs `ChecklistMerge.merge(local: envelope, remote: remote)` (:326; merge engine `CheckStitch/ChecklistMerge.swift:11-12`), `normalizedOrder()` self-heal (:329), idempotence guard `merged != envelope else false` (:330), sets `isApplyingRemote`, swaps checklists/tombstones, `save()`, returns whether `merged.checklists != checklists` (visible change).
- `onChange` is suppressed during `apply(remote:)` (test `ChecklistStoreTests.swift:546-561`), so sync pulls never echo a push.

## Q3: `ChecklistSyncService` — observation / push / merge

### Findings
- `CheckStitch/ChecklistSyncService.swift` fields (:22-35): `sync`, `store`, `pushDelay` (default `.milliseconds(500)`), `observation`, `inFlight`/`inFlightID`, `pushTask`.
- `start()` (:44-50) does exactly two wirings: `sync.startObserving { … Task { await self.reconcile() } }` (external KV change → async reconcile) and `store.onChange = { self?.schedulePush() }` (every local save → scheduled push). Called once from `MyApp.swift:29-30`; `syncOnLaunch()` from view `.task`s (`MyApp.swift:46,76`).
- Observer source — `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift:34-42`: `UbiquitousChecklistSync.startObserving` registers NotificationCenter observer for `NSUbiquitousKeyValueStore.didChangeExternallyNotification`, queue `.main`, hops via `MainActor.assumeIsolated`; real read/write/sync are `store.data(forKey:)`/`set`/`synchronize()` on KVS key `"checklists.v1"` (:25, :30-32, :52-59 cancel).
- `schedulePush()` (:91-99): `pushDelay` nil → `return pushNow()` immediately (what tests use, `ChecklistSyncServiceTests.swift:25`); else debounce task. `pushNow()` (:80-89) cancels the debounce and runs `reconcileNow()` synchronously, deliberately skipping the in-flight gate (doc :15-17; merge idempotence makes overlap harmless). Lifecycle callers: `MyApp.swift:53,82` on `scenePhase != .active` (flush + push before background/suspend).
- `reconcileNow()` (:102-171): guard `canAcceptRemoteChanges`; read remote (`sync.read()`, failure → `.unavailable`); seed path (remote nil, local non-empty → write + `.seeded`; empty local → `.synced`, never pushes empty local); classify remote (unsupported/unreadable → `.failed`, local untouched); `store.apply(remote:)`; write back iff `visibleChanged || !store.envelope.contentEquals(remote)` (:148-154) — so a local delete that merges cleanly still pushes because `contentEquals` includes tombstones while the remote has none.
- After a store mutation (delete/add): `save()` → `onChange` → `schedulePush` → `pushNow` → `reconcileNow` reads remote, `apply` merges (tombstone included), `contentEquals` differs → encode + `sync.write` → tombstone pushed to iCloud. No sync test asserts this delete-then-push path end-to-end (noted as a coverage gap by the researcher).
- Separate iOS phone-sync path exists (`MyApp.swift:72-74`, `ChecklistSyncCoordinator` + `PhoneSyncAdapter`) observing `store.checklists` — distinct from this service.

## Q4: Main list screen and checklist-level actions

### Findings
- `CheckStitch/ContentView.swift` is the sole list screen; root `View` with `@Environment(ChecklistStore.self)` / `@Environment(ChecklistSyncService.self)`; body is a `ZStack` with `BackgroundPhotoLayer` and a `NavigationStack(path: $path)` (:37-49).
- Navigation state is a raw `[UUID]` path stack (`path` state); list rows navigate by pushing the checklist's UUID (`navigationDestination(for: UUID.self)` → `ChecklistDetailView(checklistID:)`); `createChecklist()` (:309) pushes `store.create().id` onto the path.
- Row rendering: `checklistList` (declared :224, iterates `store.checklists`) → `checklistRow(for:)` (:262) — an `HStack` of a `NavigationLink(checklist.name)` + a per-row create-reminders button (`createRemindersButton` ~:172-201 with `creating`/`created` `Set<UUID>` spinner state).
- **No selection state exists anywhere** — rows are tap-to-navigate; the only id-state is the path stack, the reminder feedback sets, and `@AppStorage` prefs. No context menus (grep `Menu|FileMenu|EditMenu` in `CheckStitch/*.swift` → no matches). macOS surfaces actions via `.toolbar` items (create + settings, ~:56-63); iOS uses floating `CardPlate` overlays at `.topLeading`/`.topTrailing`, hidden when `path` is non-empty.
- Create-reminders flow (:327-356 per locator, createReminders guarded against double-tap, 1s minimum spinner, `.alert("Couldn't create reminders", …)` on failure). `emptyState` renders `ContentUnavailableView` + create button when no checklists.
- `CheckStitch/ChecklistDetailView.swift` (358 lines) holds the only checklist-level confirm-dialog patterns:
  - Delete: `.destructive` button sets `isRemoveConfirmPresented`; `confirmationDialog("Remove Checklist", …)` → `isRemoving = true`, `store.delete(id:)`, `dismiss()`; `isRemoving` suppresses the "not found" flash on pop.
  - Duplicate: button seeds `duplicateDraftName = ChecklistStore.duplicateName(basedOn:)` and raises a presented flag; alert "Duplicate" calls `store.duplicate(id:, name:)`.
  - Rename: buffered `draftName`; `commitRename()` switches on `store.rename(id:, to:)` — `.nameTaken` → alert "Name already in use"; `.renamed/.notFound` → dismiss; `commitDraftIfChanged()` silently commits on exit; `onDisappear` also runs `store.flushPendingSave()`.
  - `.sheet(isPresented:)` pattern for settings (ContentView) and `Picker` for the destination list (DetailView) are the existing modal/selector primitives.

## Q5: Platform file export/import and share APIs

### Findings
- **Nothing exists in code in either repo.** Grep across CheckStitch and SingleThread (all file types) for `fileExporter|fileImporter|ShareLink|fileExport|fileImport|exportFile|importFile|Attachment` returns zero source matches; SingleThread also has no `ShareService|SavePanel|OpenPanel|FileDocument` usage. The only occurrences of `.fileExporter` / `ShareLink` in this repo are the task-spec documents (`large.md:3`, `task.md:3`) — i.e. the API names are requirements, not an existing pattern.
- The seams the feature builds on already exist and are sync-shaped, not file-shaped: `ChecklistCodec.classify` (`ChecklistStore.swift:67-97`), `ChecklistEnvelope(version: currentVersion, …)` (`ChecklistStore.swift:100-105`), `sameName` (`ChecklistStore.swift:212`), `apply(remote:)` (`ChecklistStore.swift:320-338`), merge (`ChecklistMerge.swift:11-12`).
- `exportOptions.plist` in the SingleThread repo is an app-store-connect **code-signing** export config, unrelated to file export.
- These are first-class SwiftUI platform APIs (verified via web, not in-repo):
  - `.fileImporter(isPresented:, allowedContentTypes:, allowsMultipleSelection:, onCompletion:) -> Result<[URL], Error>` — iOS 14 / macOS 11+; returned URLs are security-scoped — must call `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` (defer) before reading; cancel leaves `isPresented` false without calling the completion.
  - `.fileExporter(isPresented:, document: FileDocument, contentType:, defaultFilename:)` (in-memory files, iOS 14/macOS 11+) or `item/items` + `contentTypes` via `Transferable` (iOS 16/macOS 13+); completion `Result<URL, Error>`; macOS shows a format dropdown for multiple contentTypes, iOS uses the first; attach at root-view level (nesting inside sheets/popovers breaks the macOS panel); needs macOS entitlement `com.apple.security.files.user-selected.read-write`.
  - `ShareLink(item: Transferable)` — iOS 16 / macOS 13+ system share sheet (AirDrop/Mail/Messages/Files-targets); the save-to-disk counterpart of fileExporter.
  - Source: [swiftui-file-export skill](https://lobehub.com/skills/eworthing-agent-skills-swiftui-file-export#1), [Apple docs: fileImporter](https://developer.apple.com/documentation/SwiftUI/View/fileImporter(isPresented:allowedContentTypes:onCompletion:)?language=objc#1), [Apple docs: ShareLink](https://developer.apple.com/documentation/SwiftUI/ShareLink?language=occ#1), [SwiftUI-Agent-Skill macOS views](https://github.com/avdlee/swiftui-agent-skill/blob/main/swiftui-expert-skill/references/macos-views.md#1), [fileExporter pitfalls (Zenn)](https://zenn.dev/kyome/articles/6f11400f47a5f8#1).

## Q6: Test suite structure

### Findings
- Two frameworks coexist. **XCTest classes** (`final class …: XCTestCase`, `@MainActor`): `ChecklistCodecTests.swift:1,6`, `ChecklistStoreTests.swift:1,6`, `CheckStitchUITests/CheckStitchUITests.swift:1,14`. **Swift Testing structs** (`import Testing`, `#expect`, `@Test`): `ChecklistSyncServiceTests.swift:3,7,28`, `ChecklistMergeTests.swift`, `ChecklistSyncMessageTests.swift`, `ChecklistSyncCoordinatorTests.swift`, `UbiquitousChecklistSyncTests.swift:5`, `ChecklistRemindersTests.swift:7`, `WatchChecklistStoreTests.swift:6`, plus view/UI suites (`ViewRenderTests`, `CardPlateTests`, `AboutViewTests`). All import `@testable import CheckStitch` / `CheckStitchCore`.
- Suites opt in per-suite (`Makefile:63` — `SWIFT_DEFAULT_ACTOR_ISOLATION` not set on test targets); anything touching EventKit/store/sync is `@MainActor`.
- Platform gating: whole-file `#if os(macOS)` (`MacWindowFrameTests.swift:1`); inline `#if os(macOS)` (`ViewRenderTests.swift:27`, `ChecklistDetailViewTests.swift:60`, `AboutViewTests.swift:23`); UI smoke has `#if os(iOS)` accessibility-audit branch (`CheckStitchUITests.swift:33-39`); watch suite `WatchChecklistStoreTests.swift` imports `CheckStitchCore`.
- Assertion styles: XCTest `XCTAssertEqual/True/False/Nil` + `XCTUnwrap` forced-optional decode (codec:115, store:770/835) + `guard case … else { XCTFail }` outcome matching (codec:33-35, 55-57); Swift Testing `#expect(expr, "message")` with explanatory messages (sync:40-46, 60-61, 104-105), helper `isFailed(_:)` (sync:261).
- Coverage relevant to this feature already exists: codec round trips and bad-payload rejection (`ChecklistCodecTests.swift:7`, :43, :97-100, :123-129, :192-195); store tombstones (`ChecklistStoreTests.swift:779` delete, :800 removeItems), apply/remote-merge (:824, :837-894 per q6 grep, future-version rejection at :894), sameName collisions (:236, :281, :298), unsupported-version payload not overwritten (:137); sync seeding/migration/merge/failure (`ChecklistSyncServiceTests.swift:28-46, :64-105, :104-167, :186-236`), observer→reconcile (:239-256); fake transport `InMemoryChecklistSync` (`TestFixtures.swift:89-117`).

## Cross-Cutting Observations

- **Single encoder seam**: `ChecklistStore.envelope` (:100-105) is the only place an envelope is constructed; both store save and sync push encode through the same property. An export that wants a *subset* (checklists only) must build its own envelope — nothing today constructs an envelope from a filtered checklist list.
- **`contentEquals` ignores `deviceID`** (`Checklist.swift:277-281`) — sync decides "push needed" on checklists+tombstones only; an import that writes through the store will naturally surface as pushable.
- **Lossless round trip is largely free anyway**: encode of a current-version envelope re-classifies `.loaded` and decodes to an equal envelope (`ChecklistCodecTests.swift:7-24`); the open questions are payload *contents* (checklists only vs tombstones/deviceID) and whether the store's `apply(remote:)` merge (not raw assignment) is the right ingestion path vs store mutations.
- **`unsupportedVersion` vs `unreadable` are already distinct paths** in every consumer: store refuses to overwrite newer-app data but repairs garbage; sync refuses to touch either and fails; the import flow must pick one behavior per outcome.
- **Tombstone LWW semantics are the replace-vs-keep primitive**: `delete` writes `revision + 1` tombstones; `apply(remote:)` merges them; a conflict-replace that routes through `store.delete` + `store.create` (or renames) records tombstones and pushes automatically via `onChange → schedulePush`.
- **No selection, no menus**: multi-select for export is greenfield UI; the closest existing primitives are per-row buttons, toolbar items, `.sheet`, `confirmationDialog`, and `Picker`.
- **Detail-view dialog handlers are the reference for confirm-style interactions** (`isRemoveConfirmPresented`, `confirmationDialog`, `isDuplicatePresented` with drafted name) — `ChecklistDetailView.swift`.

## Open Areas

- Q5's codebase answer is purely negative — platform API availability/entitlements came from web sources, not the repo; exact SwiftUI signatures for this toolchain's SwiftUI version (esp. `fileExporter` FileDocument-vs-Transferable variants and the `com.apple.security.files.user-selected.read-write` entitlement in `AppGroup.entitlements`) need confirmation during design.
- Whether `apply(remote:)`'s merge (LWW, tombstone-aware) or direct store mutations is the ingestion path for imported payloads — both exist, neither is exercised with in-memory envelopes.
- No test currently pushes a delete/tombstone end-to-end through sync; no test covers file import/export paths (nothing to test).
- `ChecklistMerge.swift` interior (union/tombstone-keyed merge, LWW tie-break on deviceID) and the `WatchChecklistStore` suite were summarised, not deep-read.
- xcodeproj scheme test destinations and full `Makefile:64-71` `test-unit` flags were not read (grep hits only).