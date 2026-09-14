# Research Findings

VAR-999 research — how `ChecklistItem` data is stored, encoded, merged, mutated, rendered, and mapped to Reminders, on iOS, macOS, and watchOS. Repo root = `~/dev/alanvardy-var-999-add-item-descriptions`. This tree is **pre-VAR-995**: `ChecklistCodec.currentVersion == 2` everywhere here; VAR-995's v3 (itemOrder) is landed on origin/main, not in this working tree.

## Q1: `ChecklistItem` model and its custom Codable

### Findings
- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:8` — `public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable`; the codec is implemented directly on the struct (no separate codec type).
- Fields `Checklist.swift:16-19`: `public let id: UUID` (immutable), `public var title: String`, `public var modifiedAt: Date`, `public var revision: Int`. Primary init `:9-13` defaults `id: UUID()`, `modifiedAt: .distantPast`, `revision: 0`; doc `:1-7` says the stable `id` prevents conflating duplicate titles, and `modifiedAt`/`revision` are optional on decode for v1 payloads.
- `isBlank` `Checklist.swift:22-24` — computed property `title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`. **Not stored, not serialized** — no decode/encode path touches it; derived purely from whatever `title` decodes to.
- CodingKeys `Checklist.swift:27`: `case id, title, modifiedAt, revision` — exactly the four fields.
- Encode `Checklist.swift:37-42` — keyed container, encodes all four keys unconditionally (`try container.encode(value, forKey: .<key>)`).
- Decode `Checklist.swift:29-34` — required (hard `decode`, absence throws): `id` `:31`, `title` `:32`. Optional (`decodeIfPresent` + `??` fallback): `modifiedAt` `:33` → `.distantPast`, `revision` `:34` → `0`. Unknown payload keys are never enumerated by the 4-case keyed container — they are silently ignored (no preservation, no rejection).
- Container `Checklist` `Checklist.swift:52-84` — same pattern: required `id`/`name`, optional `items` (`?? []`), `modifiedAt`, `revision`; encodes all five `:78-84`. Doc `:43-50`: item ops never bump the checklist's `revision`/`modifiedAt`; only create/rename do.
- `migrated(at date:)` `Checklist.swift:91-104` — v1 upgrade stamps `modifiedAt = date` and `revision = max(revision, 1)` per item and per checklist.
- `ChecklistEnvelope` `Checklist.swift:128-164` — `version`, `deviceID`, `checklists`, `tombstones`; decode uses `decodeIfPresent` for `deviceID` (`?? ""`) and `tombstones` (`?? []`) `:140-147` (this is why v1 round-trips through the v2 decoder); `contentEquals` `:160-164`.
- Tests: `CheckStitchTests/ChecklistItemTests.swift:6-12` (duplicate titles → distinct ids), `:14-22` (blank/non-blank `isBlank` boundaries incl. `" "`, `"\t"`, `"\n"`), `:24-28` (JSON round-trip preserves identity).

## Q2: Payload-version classification and the store's load/save handling

### Findings
- `ChecklistCodec` lives in `Checklist.swift:168-227`. `currentVersion = 2` `:169`.
- Outcome enum `:176-187`: `.loaded(ChecklistEnvelope)`, `.migratable(from:checklists:)`, `.unsupportedVersion`, `.unreadable`.
- `encode` `:188-191` — plain `JSONEncoder().encode(envelope)`; the store is the only caller shape.
- `classify` `:194-217` — one `do/catch`, never partial:
  1. Decodes a private `VersionProbe { let version: Int }` first.
  2. `version == currentVersion` → `.loaded(JSONDecoder().decode(ChecklistEnvelope.self, from: data))` `:198-202`.
  3. `version == 1` → decodes same envelope shape, returns `.migratable(from: 1, checklists: legacy.checklists)` `:203-205`.
  4. Any other version → `.unsupportedVersion` + `logger.error("Unsupported checklist payload version …")` `:206-209`.
  5. Any throw → `.unreadable` `:210-214`.
- `decode` convenience `:214-223` — `.loaded`/`.migratable` → checklists; unsupported/unreadable → `[]`.
- **Store load** `CheckStitch/ChecklistStore.swift:44-77`, key `"checklists.v1"` `:43`; reads `defaults.data(forKey: key)` `:61`, switches on `classify`:
  - `.loaded` → checklists/tombstones set, `canOverwriteStoredPayload = true` `:59-63`.
  - `.migratable` → `legacy.map { $0.migrated(at: now()) }`, flag true, comment "never stall migration" `:64-66`.
  - `.unsupportedVersion` → empty state, **`canOverwriteStoredPayload = false`** `:67-69` — the newer-payload guard.
  - `.unreadable` → empty state, flag true (garbage is replaced) `:70-72`.
  - No data → empty, flag true `:74-76`.
- Flag declared `:31`, doc: mutations still work in memory, saving is refused so the newer payload survives.
- **Store save** `save()` `:266-283`: cancels pending coalesced save, then `guard canOverwriteStoredPayload else { logger.error("Refusing to overwrite checklist payload written by a newer app version"); return }` `:278-281`; only then `defaults.set(try ChecklistCodec.encode(envelope), forKey: key)` `:283`; fires `onChange` unless `isApplyingRemote`.
- Envelope getter `:85-90` stamps `version: ChecklistCodec.currentVersion` (i.e. 2).
- `scheduleSave()` (300ms text-edit debounce) `:252-271` routes through `save()`, so the guard applies to coalesced writes too.
- `apply(remote:)` `:224-242`: `guard canOverwriteStoredPayload` then `guard remote.version == ChecklistCodec.currentVersion else { return false }` `:228`; merges and commits only when result differs `:237`.
- Sync side is stricter: `CheckStitch/ChecklistSyncService.swift:126-136` maps remote `.migratable` by stamping `migrated(at: .distantPast)`, but `.unsupportedVersion`/`.unreadable` → `.failed("Stored sync data could not be read.")` — remote bytes are never discarded.
- Tests: `ChecklistCodecTests.swift:25-33` (v1 legacy JSON → `.migratable`), `:50-54` (garbage → `.unreadable`; `{"version":99}` → `.unsupportedVersion`). `ChecklistStoreTests.swift:124-137` (`testUnsupportedVersionPayloadIsNotOverwritten` — version-99 payload survives `create`/writes).

## Q3: Store item operations — what each mutation writes

### Findings
- `ChecklistStore.swift:184-187` `addItem(to id:)` — guards checklist index; appends `ChecklistItem(title: "New item", modifiedAt: now(), revision: 1)` (fresh `UUID()` from initializer default); calls `save()` directly.
- `ChecklistStore.swift:190-198` `updateItem(checklistID:itemID:title:)` — guards index + item (`firstIndex(where: { $0.id == id })` `:191`); sets `title` (keeps id), `revision += 1`, `modifiedAt = now()`; `scheduleSave()` (debounced).
- `ChecklistStore.swift:128-143` `duplicate(id:name:)` — guards source `:129`; name fallback `duplicateName` `:117-120` (`"\(sourceName) copy"`) disambiguated by `uniqueName` `:166-171`; new checklist = `Checklist(name: …, items: source.items.map { ChecklistItem(title: $0.title, modifiedAt: now(), revision: 1) }, modifiedAt: now(), revision: 1)` `:142` — **copies only `title`**; fresh ids (initializer default), fresh timestamps, revision pinned to 1. Exercise: `ChecklistStoreTests.swift:536-539` (ids never reused).
- `ChecklistStore.swift:200-208` `removeItems(from id:, at offsets:)` — guards checklist; iterates offsets sorted descending; per removed item pushes `ChecklistTombstone(checklistID: id, itemID: removed.id, deletedAt: now(), revision: removed.revision + 1)`; the item itself is destroyed. Calls `save()`.
- `ChecklistStore.swift:150-163` `rename(id:to:)` — checklist-level only: `name`, `checklists[index].revision += 1`, `modifiedAt = now()`; `scheduleSave()`. No item field changes.
- `ChecklistStore.swift:107-115` `create(name:)` — fresh `Checklist(name:, items: [], modifiedAt: now(), revision: 1)`.
- `checklist(id:)` lookups `:98-105` — used by UI bindings and re-finds by id each read.

## Q4: Merge winner rules at every level

### Findings
- `CheckStitch/ChecklistMerge.swift:116-131` `wins(revision:date:device:overRevision:overDate:overDevice:)`:
  `revision >` → `date >` → `device <` (lexicographically smaller deviceID). Symmetric — local/remote argument order never changes outcome (doc `:4-10`; `ChecklistMergeTests.swift:31-49`).
- Envelope: `merge(local:remote:)` `:12-35` does **not** pick one winning envelope — it unions. Tombstones unioned by `(checklistID, itemID)` via `wins` (`mergedTombstones` `:42`); `deadChecklists` = tombstones with `itemID == nil` `:14`; tombstoned checklists pruned `:21-22`; tombstoned items pruned from surviving checklists `:23-27`; result rebuilt with `version: ChecklistCodec.currentVersion` and **`deviceID: local.deviceID`** — the local producer always wins envelope identity `:30-31`.
- Checklist: `mergedChecklists` `:64-94`. Remote checklist with new id appends `:70-74`; on id match and remote win, only `name`/`revision`/`modifiedAt` are copied `:79-87` — items are always re-merged independently `:89-92` (consistent with Q1's doc that item ops don't bump checklist revision).
- Item: `mergedItems` `:95-114`. Local items seed the result; on matching `id` and remote win, **whole-struct replacement** `result[index] = remoteItem` `:110` — the losing item's `title`, `modifiedAt`, `revision` are all discarded wholesale; no field-level merge anywhere.
- Tombstone suppression beats everything: a `(checklistID, itemID)` tombstone unconditionally suppresses the live entry `:21-27` (a delete can't be resurrected by an older live copy).
- Wiring: `ChecklistStore.swift:224-242` `apply(remote:)` guards flag + version, calls `ChecklistMerge.merge`, commits only if `merged != envelope` `:237`.
- Tests: `ChecklistMergeTests.swift:111-131` (`itemEditsFromBothDevicesSurvive` — distinct ids union), `:132-153` (`sameItemEditedOnBothDevicesUsesLWW`), `:72-131` (tombstone suppression).

## Q5: Item → Reminder mapping (two paths)

### Findings
- **Path 1 — production (app UI + sync)**: `CheckStitch/ChecklistReminders.swift:9-27` `static func create(from checklist: Checklist) async`. Fresh `EKEventStore()` per call `:11`; `requestFullAccessToReminders()` `:13`, silent return on denial; per item: skip if `item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` `:19`; `reminder.title = item.title` `:22` — **title only**; `reminder.calendar = eventStore.defaultCalendarForNewReminders()` `:23`; `eventStore.save(reminder, commit: true)` `:24`; failures logged, never thrown. Call sites: `CheckStitch/ContentView.swift:249-262` `createReminders(for:)` (per-row button), `CheckStitch/MyApp.swift:58-67` (sync coordinator `createReminders` closure for phone-initiated runs).
- **Path 2 — legacy core flow (tests only)**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift:20-33` `create(from items: [ChecklistItem]) async -> ChecklistCreationOutcome`. `requestAccess()` guard → `.permissionDenied` `:25`; per item where `!item.isBlank` `:27`; `reminders.create(title: item.title)` `:28` — again **title only**; returns `.created(count:)` / `.failed(error)`. Protocol `ReminderCreating.swift:7-11`; live adapter `EventKitReminderCreator` `ReminderCreating.swift:19-37` — one injected long-lived `EKEventStore` `:21-23` (`@MainActor`), `reminder.title = title` `:30`, `defaultCalendarForNewReminders()` `:31`, commit-per-item `:35` under `#if !os(watchOS)` `:33-35`. Orchestrator `ChecklistViewModel.swift:51-68` maps outcome → flags; creator from `environment.reminderCreator` `:13` (`Environment.swift:6-10`).
- **No production view instantiates `ChecklistViewModel`** — consumers are `ChecklistCreatorTests.swift:6-60` and `ChecklistViewModelTests.swift:5-8` only. The app goes through Path 1.
- Both paths read **only `item.title`**; both skip blank/whitespace titles; neither reads `id`/`modifiedAt`/`revision`; created reminders carry no notes, flags, due dates, or priorities.

## Q6: iOS item editor (`ChecklistDetailView`) and `ContentView`

### Findings
- `CheckStitch/ChecklistDetailView.swift:11-12` — keyed by `checklistID: UUID`; `@Environment(ChecklistStore.self)` `:15`. Body guards `store.checklist(id:)` `:32`; missing → `ContentUnavailableView("Checklist not found", systemImage: "trash")` `:108-110` (suppressed while `isRemoving`).
- Item rows `:42-45`: `Section("Items")` + `ForEach(checklist.items)` with one `TextField("Item", text: titleBinding(...))` per row. `titleBinding(checklistID:itemID:)` `:119-127`: getter re-finds checklist+item by id from the store each read (returns `title` or `""`); setter calls `store.updateItem(checklistID:itemID:title:)` — **per-keystroke live mutation**, no draft buffer for titles (unlike the checklist name, buffered in `@State draftName` `:26`, committed by `commitRename()`/`commitDraftIfChanged()` `:112-117`).
- Row deletion: `.onDelete` `:46-48` → `store.removeItems(from:at:)`.
- Layout: single `Form` `:33` — Section "Checklist name" `:36-39` (`TextField` id `"checklistNameField"`), Section "Items" `:41-48`, unlabeled button section `:49-79` (`addItemButton` → `store.addItem(to:)`; `duplicateChecklistButton` → alert seeding `duplicateDraftName` from `duplicateName`; `removeChecklistButton` → confirmation → `store.delete(id:)` + `dismiss()` `:66-78`).
- Toolbar: `.navigationTitle("Edit checklist")` / `.toolbarTitleDisplayMode(.inline)` `:80-81`; "Done" `.confirmationAction` `:84-90` → `commitRename()`. `.onAppear` seeds `draftName` once `:93-96`; `.onDisappear` commits draft + `store.flushPendingSave()` `:98-101`.
- `CheckStitch/ContentView.swift`: `@State path: [UUID]` in a `NavigationStack` `:24/:57`, `.navigationDestination(for: UUID.self)` → `ChecklistDetailView(checklistID: id)` `:80-82`. Body switches on `store.checklists.isEmpty` `:60-66` → `emptyState` (`ContentUnavailableView` + "Create checklist") or `checklistList`.
- `checklistList` `:167-193`: `GeometryReader > ScrollView > LazyVStack` of `checklistRow(for:)` + `Divider()`, capped by `ChecklistWidth.maxContentWidth` `:177` (= `min(340, viewportWidth * 0.6)` `:319-323`), wrapped in CardPlate styling.
- `checklistRow(for:)` `:220-230`: `HStack(spacing: 12)` — `NavigationLink(checklist.name, value: checklist.id)` + `createRemindersButton` (per-id state: `ProgressView` while creating, green `checkmark.circle.fill` while created, else `play.circle.fill`; `.disabled(creating.contains(id))`; label "Create reminders from checklist").
- `createReminders(for:)` `:249-262`: guards `creating.contains(id)` + `store.checklist(id:)`; spawns a `Task` awaiting `ChecklistReminders.create(from: checklist)` with a 1s minimum spinner, then `created` for 1s. `createChecklist()` `:240-244` appends `store.create().id` to `path`.
- Platform layout: iOS floating 52×52 overlays gated on `path.isEmpty` `:124-142`; macOS toolbar items `:67-76`; `SyncStatusView` in a bottom `safeAreaInset` `:104-107`, defined `:325-351`; `.refreshable { await syncService.refresh() }` on the main `Group` `:108`.

## Q7: watchOS item rows and the WCSession context path

### Findings
- `CheckStitchWatch/WatchChecklistDetailView.swift:4-6` — `struct WatchChecklistDetailView: View`, `let checklist: Checklist`, `@Environment(WatchChecklistStore.self)`, `@State sent = false` `:7`.
- `:11-14` `visibleItems` = `checklist.items.filter { !$0.isBlank }` — comment: "Blank rows are never turned into reminders, so the watch hides them too." Row body `:16-18`: `List(visibleItems) { item in Text(item.title) }` — read-only `Text(item.title)` per row. `.navigationTitle(checklist.name)` `:19`. Bottom `.safeAreaInset` `:21-26`: `Button` labeled "Sent…"/"Create reminders…", action `sent = store.run(checklist)`, `.disabled(sent || visibleItems.isEmpty)`.
- `CheckStitchWatch/WatchChecklistListView.swift:14-20` — `List(store.checklists)` of `NavigationLink(checklist.name) { WatchChecklistDetailView(checklist: checklist) }` `:18`; empty state `:10-13`; `.task { store.start(); store.requestRefresh() }` `:31-34`. App entry `CheckStitchWatchApp.swift:5-11` creates and injects the store.
- `WatchChecklistStore` — `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift:64-71`: `@MainActor @Observable final class`, `init(transport: ChecklistSyncTransport)`; holds only decoded `[Checklist]` (`:70`) + `pendingRunID` (`:71`) — **raw context bytes are never retained**.
  - `start()` `:80-86` — `transport.onMessage = receive`, `onActivated = requestRefresh`, then `transport.activate()`.
  - `run(_ checklist:)` `:92-97` — sends `.runChecklist(checklist.id)` via `transport.sendUserInfo`; `pendingRunID = checklist.id` on acceptance.
  - `requestRefresh()` `:100-103` — sends `.requestChecklists`.
  - `receive(_ message:)` `:106-114` — on `.context(let data)`: `if case .loaded(let envelope) = ChecklistCodec.classify(data) { checklists = envelope.checklists }`. **Only `.loaded` is accepted** — `.migratable`/`.unsupportedVersion`/`.unreadable` leave the previous list intact. `.runChecklist`/`.requestChecklists` are ignored (phone-only).
- Transport `CheckStitchWatch/WatchSyncAdapter.swift`: `:8-10` `@MainActor final class WatchSyncAdapter: NSObject, ChecklistSyncTransport`, `init(session: WCSession = .default)`; `activate()` `:15-17` (guard `WCSession.isSupported()`, set delegate, `session.activate()`); `sendContext` deliberately `false` `:22-24` — the watch never pushes payloads; `sendUserInfo` `:26-30` guards `activationState == .activated`, then `session.transferUserInfo(message.userInfo)`.
- Delegate `WatchSyncAdapter.swift:36-50`: on activation, builds `ChecklistSyncMessage(userInfo: session.receivedApplicationContext)` — so a cold watch launch still gets the phone's last pushed context.
- Phone push origin: `CheckStitch/ChecklistSyncCoordinator.swift:33-38` `pushContext` encodes `ChecklistEnvelope(version: currentVersion, …)` (so **v2 today**) → `PhoneSyncAdapter.swift:29-37` `updateApplicationContext` → WCSession context key `"checklists"` (`ChecklistSync.swift:12-17`, core). On `.requestChecklists` the phone re-pushes `ChecklistSyncCoordinator.swift:37-38`.

## Cross-Cutting Observations
- **Optional-field idiom is established**: v1→v2 back-compat works because every sync field decodes via `decodeIfPresent` + `??` defaults (`Checklist.swift:33-34`, `:73-75`, `:140-147`). A new optional item field would follow the identical pattern (add CodingKey + encode + `decodeIfPresent ?? default`).
- **Whole-item LWW replacement** (`ChecklistMerge.swift:110`) means any new mutable field rides the winner struct wholesale — no field-level reconciliation exists anywhere.
- **`duplicate` copies only `title`** (`ChecklistStore.swift:142`) — every new item field needs an explicit copy there.
- **`isBlank` is title-derived, not a stored field** (`Checklist.swift:22-24`) — a description must not affect blankness.
- **Two create-reminders paths exist and both map title only**; the production one is `ChecklistReminders` (app layer); the core `ChecklistCreator` is test-only. The watch never creates reminders (its button goes through `WatchChecklistStore.run` → user-info round trip back to the phone).
- **Version collision context**: this tree classifies any `version != 1,2` payload as `.unsupportedVersion` (store refuses to overwrite it; the watch ignores it). origin/main has VAR-995's v3 landed (adds `itemOrder`/`orderRevision`/`orderModifiedAt` to `Checklist`, `currentVersion = 3`); this branch's v3 numbering decision must account for that in-flight migration (large.md flags this as the versioning risk).
- **Envelope identity**: `deviceID` in merged payloads is always the local producer's (`ChecklistMerge.swift:30-31`); version is always re-stamped to current on save and on merge.
- **Revision semantics**: item-level `revision`/`modifiedAt` track item edits only; checklist `revision`/`modifiedAt` track create/rename only (`Checklist.swift:43-50`).

## Open Areas
- **EventKit surface**: whether `EKReminder` supports body/notes text (relevant to the open product question of description→reminder flow) was not verified — `ChecklistReminders.swift:22` sets only `.title`.
- **`decodeIfPresent` library semantics** (whether an absent-but-required key vs. a malformed optional value behaves differently) was not fully pinned down; tests only cover whole-key presence (`ChecklistCodecTests.swift:25-54`).
- **Localization**: an editor placeholder/label for a new description field would need lproj/xcstrings entries; the current key inventory for item rows ("Item" label, title) was not enumerated.
- **Cold-start collisions**: how `ContentView`'s per-id `creating`/`created` state interacts with a description editor (which would add per-item state) was not traced.