# Research Findings

## Q1: Model, Codable codec, and `ChecklistStore` persistence

### Findings
- All domain entities, encode and decode live in one file: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`.
  - `ChecklistItem` (`Checklist.swift:8`): `Identifiable, Codable, Hashable, Sendable`; fields per-field sync clocks + coarse `modifiedAt`/`revision` + `priority`.
  - `Checklist` (`Checklist.swift:145`): `id`, `name`, `items: [ChecklistItem]`, `destinationListIdentifier: String?`, `prefixesReminderNumbers: Bool`, coarse `modifiedAt`/`revision`, `itemOrder: [UUID]` + `orderRevision`/`orderModifiedAt`.
  - `ChecklistTombstone` (`Checklist.swift:307`): `checklistID`, optional `itemID` (nil = whole-checklist delete), `deletedAt`, `revision`.
  - `ChecklistEnvelope` (`Checklist.swift:323`): `version`, `deviceID`, `checklists`, `tombstones`; v1 had none of `deviceID`/`tombstones` (`:341`). `contentEquals` ignores `deviceID` (`:361-366`).
- `ChecklistCodec` enum (`Checklist.swift:367`), `currentVersion = 4` (`:368`). `encode` = `JSONEncoder().encode(envelope)`; `classify` probes `version` before decoding (`:389-422`). Outcomes: `loaded`, `migratable(from:, envelope:)`, `unsupportedVersion`, `unreadable` (`:382-395`).
- **Additive-field pattern** (what a new optional Folder relationship field would follow):
  - `ChecklistItem.description` precedent: "absent key decodes to …, no version bump" (`:96-98`).
  - Every additive key decodes via `container.decodeIfPresent(...) ?? <default>`; encode writes every key unconditionally (encodeNil for `Int?`). `prefixesReminderNumbers` absent in ≤v4 decodes to `false`, "no version bump" (`:200-201`).
  - Closed-enum caveat: `priority` decodes absent to `.none`, but an unknown raw value throws — adding an enum case later needs a v5 bump → `.unsupportedVersion` which refuses to overwrite (`:113-117`).
- Store: `CheckStitch/ChecklistStore.swift` — `@Observable final class`, `defaults: UserDefaults`, `key = "checklists.v1"`, `textEditDelay` 300ms, `deviceID` from `checklist.deviceID` (`:48-75`).
  - Load (`:79-125`): `defaults.data(forKey:)` → `classify`; `.migratable` per-version (v1 `migrated(at:)`, v2 `seededOrder()`); `.unsupportedVersion` → empty + write-protect; missing/unreadable → empty/overwritable.
  - `envelope` getter is the only thing the store encodes — "store is the only encoder" (`:130-137`).
  - Save (`:483-495`): guards `canOverwriteStoredPayload`, `defaults.set(encode(envelope), forKey:)`; `isApplyingRemote` suppresses `onChange`; text edits coalesce via `scheduleSave`/`pendingSave`; `textEditDelay=nil` saves synchronously (tests).
  - Tombstones additive/grow-only (`:26-29`).
- Migration helpers on `Checklist` (`:277-306`): `migrated(at:)`, `seededOrder()`, `normalizedOrder()` (idempotent, `uniquingKeysWith`).
- Storage: App Group KVS storekit (`AppGroup.entitlements` embeds `com.apple.developer.ubiquity-kvstore-identifier`), `AppGroup.defaults`, key `"checklists.v1"`.

## Q2: `ContentView` main list screen structure

### Findings
- Root `ContentView` (`CheckStitch/ContentView.swift`): `ZStack` + `NavigationStack(path: $path)` (`:28-58`); `@State path: [UUID]` (`:21`); **`@State isEditing`** (`:25`) gates edit-mode rows.
- Empty state vs list: `if listVM.checklists.isEmpty { emptyState } else { checklistList }` (`:31-38`).
- `checklistList` (`:260-305`): `GeometryReader`→`ScrollView`→`VStack`. iOS header row holds the edit toggle (`:264-285`); `LazyVStack` `ForEach(listVM.checklists)` renders `checklistRow(for:)` with a `Divider` (`:286-296`), inside a `CardPlate`.
- `checklistRow(for:)` (`:306-338`) — an `HStack(spacing: 12)` branching on `isEditing`:
  - **Editing** (`:313-329`): leading **minus control** `Button` (`minus.circle.fill`) setting `listVM.checklistPendingRemoval = checklist.id`, `accessibilityIdentifier: "removeChecklist-<id>"`; plain `Text(checklist.name)`; trailing `checklistMoveControls`.
  - **Not editing** (`:330-334`): `NavigationLink(checklist.name, value: checklist.id)` → `ChecklistDetailView`; trailing `createRemindersButton` (play).
- `checklistMoveControls(for:)` (`:340-365`): up/down chevrons → `listVM.moveChecklist(id:up:)`; disabled at first/last.
- **Removal is two-step/staged**: minus sets pending id; `.confirmationDialog("Remove Checklist", isPresented: pending != nil)` (`:271-297`); destructive button clears pending + `withAnimation { listVM.removeChecklist(id:) }`; `.onChange(of: listVM.checklists.isEmpty)` resets `isEditing=false` on last-removal.
- Edit toggle: macOS toolbar item (`#if os(macOS)` `:39-54`, hidden when list empty); iOS edit toggle is an in-content header item (`:264-285`), not a toolbar/canvas item. Shared `editToggleButton` (`:252-258`) text "Edit"/"Done", `withAnimation { isEditing.toggle() }`.
- Create: iOS floating 52×52 `plus` plate `.overlay(topLeading)` guarded by `path.isEmpty` (`:74-90`); macOS `Label("Create checklist", systemImage: "plus")` toolbar item (`:197-198`); both call `createChecklist()` → `path.append(listVM.createChecklist())` (`:523-526`). iOS settings floats `.topTrailing` (`:92-111`).
- **No `.contextMenu`, no `.swipeActions`, no per-row gesture anywhere in `CheckStitch/`** (grep). Row interaction is minus-removal dialog + import/export settings sheet (`requestDataAction`/`perform`, `:579-602`) + import name-conflict dialog (`:230-238`). Minus uses a row-width minus override (`.buttonStyle(.plain)`, red fill), not a native `EditButton`/`onDelete`.

## Q3: `ChecklistListViewModel` + store mutations

### Findings
- `CheckStitch/ChecklistListViewModel.swift` (45 lines): `@MainActor @Observable final class`, single injected `private let store: ChecklistStore` (`:9-15`).
- Observable state: `var checklists: [Checklist] { store.checklists }` — a forwarding getter straight off the store (`:17`); store mutations that reassign/append propagate because store is `@Observable` (`ChecklistStore.swift:5`). `var checklistPendingRemoval: UUID?` VM-owned (`:27`).
- Mutating actions (all forward to store):
  - `createChecklist() -> UUID` → `store.create().id` (`:23-24`).
  - `removeChecklist(id)` → finds index, `store.removeChecklists(at: IndexSet(integer: index))` (`:33-35`), only from the confirm dialog.
  - `moveChecklist(id, up:)` → `store.moveChecklists(from: IndexSet(integer: index), to: up ? index-1 : index+2)` (`:41-43`; `+2` accounts for removed element, doc `:38-40`).
  - **No `duplicate`/rename on the VM**; store `duplicate(id, name)` exists (`ChecklistStore.swift:156-171`) but is not surfaced on the list screen.
- Store mutations (`ChecklistStore.swift`) all mutate `self.checklists` then `save()` (`:505-518`):
  - `create` (`:134-141`): builds `Checklist(name: uniqueName(...), modifiedAt: now(), revision: 1)`, appends, saves, returns. `uniqueName` disambiguates so create always succeeds.
  - `duplicate` (`:156-171`): copies items to fresh UUIDs, keeps `destinationListIdentifier` + `prefixesReminderNumbers`.
  - `removeChecklists(at:)` (`:390-401`): guards empty, appends one `ChecklistTombstone(checklistID, itemID:nil, deletedAt:now(), revision: +1)` per removed, single `save()`.
  - `moveChecklists(from:to:)` (`:441-444`) via `moved<T>` (`:408-423`) using SwiftUI `move(fromOffsets:toOffset:)`; top-level order IS the persisted order; **reorder is local-first, no revision bump** (unlike `moveItems`).
- Data flow: `ContentView` reads single `listVM.checklists` → VM maps id→index → store mutates canonical array + tombstones + `save()` → `@Observable` propagates.

## Q4: Sync/merge surface

### Findings
- `ChecklistSyncing` (`CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift`): data-only KVS seam (`:9-15`); `UbiquitousChecklistSync` over `NSUbiquitousKeyValueStore` key `"checklists.v1"` (`:22-23`). **Transport is opaque `Data` — field changes never touch it**; already-encoded envelope rides through.
- `ChecklistSyncCoordinator` (`CheckpointSyncCoordinator.swift`-adjacent, `ChecklistSyncCoordinator.swift`): phone→watch push. `pushContext()` (`:30-34`) encodes `snapshot()` into an envelope with `deviceID: ""` and `transport.sendContext`. Triggered on `start()`/`onActivated` (`:40-47`) and `checklistsDidChange()` (`:50-53`). **Not a merge host** — a new field rides inside the encoded envelope (`:30`); coordinator doesn't inspect/copy fields.
- `ChecklistMerge` (`CheckStitch/ChecklistMerge.swift`): pure deterministic LWW; winner `wins` = higher revision → newer date → lexicographically smaller device (`:216-221`).
  - `merge(local:, remote:)` (`:12-44`): unions tombstones, builds `mergedChecklists`, prunes tombstoned, returns envelope wearing `local.deviceID` (`:41`).
  - `mergedChecklists` (`:27-75`): bases on `result = local`, appends remote-only with `normalizedOrder()` (`:57-61`). On conflict only these scalars transfer when remote wins — `name`, `destinationListIdentifier`, `prefixesReminderNumbers`, `revision`, `modifiedAt` (`:64-71`). Order merged independently via `orderRevision`/`orderModifiedAt` (`:72-96`).
- **Propagation of a new relationship scalar (folder id)**: sits on `Checklist` as a plain `String?` (like `destinationListIdentifier` `:172`) and must be added **explicitly** to the winner-copy block in `mergedChecklists` (as `destinationListIdentifier`/`prefixesReminderNumbers` are today, `ChecklistMerge.swift:65-67`). No generic field reflection — every merged scalar is listed by name. If the field needs its own clock it would follow the `itemOrder`/`orderRevision` pattern (`:72-96`, `:185-187`).
- Change-propagation chain: `ChecklistStore.apply(remote:)` is the sole caller of `ChecklistMerge.merge` (idempotence guard `merged != envelope`). A new checklist scalar needs: model field + codec encode/decode default (`Checklist.swift`) + explicit copy line in `mergedChecklists` (`ChecklistMerge.swift:64-71`). Transport/coordinator unchanged unless the field carries its own clock.

## Q5: Test patterns and localization requirements

### Findings
- Store tests — `CheckStitchTests/ChecklistStoreTests.swift`: XCTest `@MainActor` (`:4`, `@testable import CheckStitch`). Fresh isolated `UserDefaults` per test via `makeDefaults()` (`:11-15`), `defer { removePersistentDomain }` cleanup (`:51-52`). `textEditDelay: nil` for synchronous asserts (`:24-30`). Smallest-fixture factories `makeItemStore`/`makeChecklistStore` (`:33-46`); deterministic `Clock` at `Date(timeIntervalSince1970: 0)` (`:48`). Persistence pattern: create→mutate→reload, assert shape (`:50-59`).
- VM tests — `CheckStitchTests/CheckListListViewModelTests.swift` (note casing): Swift Testing `struct` + `@Test`, `@MainActor` (`:1-4`). `makeViewModel()` builds real store on `TestFixtures.makeIsolatedDefaults()` with `textEditDelay: nil`, wrapped in real `ChecklistListViewModel` (`:8-11`). Asserts shape via observable state (`:13-40`).
- `TestFixtures.swift`: `makeItem`, `makeIsolatedDefaults()` UUID-named wiped `UserDefaults` (`:17-26`); `@MainActor sharedTestEventStore` global must outlive reminders (weak store ref → SIGTRAP if deallocated) (`:33-36`). Doubles: `SpyReminderCreator`/`SpyReminderDestination`, `InMemoryChecklistSync`, `FakeChecklistSyncTransport`, `SpyChecklistRunner`, `SpyPurchaseProvider` (`:151-246`), `TestError.boom`, `InMemoryObservation` (`:144-148`).
- Localization — new user-facing key needs BOTH:
  - `CheckStitch/Localizable.xcstrings` JSON with all six languages en/de/es/fr/ja/zh-Hans (`:1-40`).
  - `CheckStitchTests/LocalizationFixtures.swift` `requiredKeys` per catalog (`:12-121`); `languages = ["en","de","es","fr","ja","zh-Hans"]` (`:23-25`).
  - `LocalizationTests.swift`: `catalogsHaveAllSixLanguages` (`:32-41`) fails if any key is missing/empty in any language; `everyRequiredKeyIsPresent` (`:43-51`); **non-English-differs canary** (`:68-83`) forces non-English to differ from English (`guardedCatalogs` App/Core/Watch, `excludedIdentities` allow-list `:151-165`).
  - Plist keys in `infoPlistTargets` (`:125-148`); helpers in `LocalizationTestHelpers.swift`.

## Cross-Cutting Observations
- **One model file, two surfaces**: `Checklist.swift` (core) is the single source of truth for entities + codec; the app `ChecklistStore` is the sole encoder/persister; `ContentView` + `ChecklistListViewModel` are the sole iOS list UI; `CheckStitchWatch` renders the same core model with its own list view.
- **Additive/optional fields are cheap but deliberate**: an optional `String?` on `Checklist` needs no version bump, but every merged scalar must be explicitly listed in `ChecklistMerge.mergedChecklists`, and the closed-enum caveat means values must stay open-ended (plain string id, not enum).
- **Everything funnels through `save()`**: create/duplicate/remove/move all mutate `self.checklists` + tombstones then `save()` → single encode + sync write per batch.
- **Reorder is local-first**: top-level `move` doesn't bump revision — relevant to how folder membership/order might be persisted.
- **No context menus or swipe actions exist**; the current screen's only edited-state interactions are the row minus control and row move chevrons (all gated on `isEditing`).

## Open Areas
- Exact current line numbers of `ChecklistStore.apply(remote:)` and the `merged != envelope` idempotence guard (not re-read first-hand in this phase; cited from prior recon).
- Whether folder persistence should own a separate envelope/key vs riding on the checklist envelope — the codebase today has a single `checklists.v1` key; no folder entity exists to copy.
- Watch list screen (`WatchChecklistListView`) renders the model directly; whether folders change its surface is an open product question, not a codebase fact.