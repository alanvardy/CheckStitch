# Research Findings

## Q1: ChecklistItem model, Codable codec, per-field sync clocks

### Findings
- `public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable` at
  `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:8`. Doc comment
  (`:4-7`): `modifiedAt`/`revision` carry sync identity, "both optional on
  decode so v1 payloads ... still load" — the stored properties are non-optional,
  only the decode path tolerates absence.
- Fields (`:32-48`): `let id: UUID`, `var title: String`, `var description:
  String`, `var modifiedAt: Date`, `var revision: Int`, `var relativeDate: Int?`
  ("Days from today (0 = today ...); `nil` = no date", `:37-40`), then six
  per-field clocks `titleRevision`/`titleModifiedAt`, `descriptionRevision`/
  `descriptionModifiedAt`, `relativeDateRevision`/`relativeDateModifiedAt`
  (`:41-52`). Design comment: "each editable field carries its own clock so a
  title edit and a description edit from two devices are independent".
- Init (`:9-30`): every clock param defaults `nil`; body seeds each field clock
  from the coarse clock when unspecified (`titleRevision = titleRevision ??
  revision`, `:22-29`). Comment: "A fresh record (or a legacy payload)
  attributes its last whole-item edit to every field".
- Codable: `private enum CodingKeys: String, CodingKey` lists all 13 keys
  (`:67-71`). `init(from decoder:)` (`:73-92`): `id`/`title` required; the rest
  `decodeIfPresent` with fallbacks — `description ?? ""` (comment `:77-78`:
  "Additive optional field: absent key decodes to `""`, matching the
  `destinationListIdentifier` precedent — no version bump"), `modifiedAt ??
  .distantPast`, `revision ?? 0`, `relativeDate` via `decodeIfPresent(Int.self)`
  (absent key and nil both yield nil). Field clocks fall back to the coarse
  clock when their key is absent (`:84-91`).
- `encode(to:)` (`:94-115`): writes **every** key unconditionally. `relativeDate`
  is the special case (`:101-108`): "Write the key unconditionally, matching the
  'encoder writes every key' invariant. `encode` on an `Int?` may omit the key
  depending on overload resolution, so be explicit" — `if let relativeDate {
  encode } else { encodeNil(forKey: .relativeDate) }`.
- Migration restamp: `Checklist.migrated(at:)` (`:200-230`) upgrades v1 items —
  `revision = max(revision, 1)`, every field clock set to that revision/date.
  `seededOrder()` (`:232-240`, v2) never touches item clocks. `normalizedOrder()`
  (`:246`) canonicalises `items`↔`itemOrder`; used on decode, merge, mutation.
- Extension files: `CheckStitchCore/Sources/CheckStitchCore/ChecklistItem+DueDate.swift:3-17`
  is the only `extension ChecklistItem` in the source tree —
  `dueDateComponents(today:calendar:)` derived from `relativeDate`, with
  injectable calendar. `hasDescription`/`isBlank` are computed inline
  (`Checklist.swift:55-65`), not extensions.
- Clock stamping lives in the store (Q2): coarse `revision += 1`/`modifiedAt` plus
  the edited field's own clock, `ChecklistStore.swift:288-296,304-312,324-330`.
  Merge adopts winning field clocks and clamps the coarse clock to the max field
  clock (`ChecklistMerge.swift:137-163`).

## Q2: Item mutators and load/save paths in ChecklistStore.swift

### Findings
- Backing store: `AppGroup.defaults` key `"checklists.v1"`; only the versioned
  `ChecklistEnvelope` is ever encoded, via `ChecklistCodec.encode`
  (`Checklist.swift:371-373`). All mutator line refs below verified by grep.
- `addItem(to id:, title:)` (`:274`): appends `ChecklistItem(title:, modifiedAt:
  now(), revision: 1)`; field clocks seed via init defaults (all = 1/now);
  appends itemOrder; `save()` directly. `addItem(to id:)` (`:282`) delegates
  with title `"New item"`.
- `updateItem(checklistID:itemID:title:)` (`:286`): stamps `revision += 1`,
  `modifiedAt = revisedAt`, `titleRevision = revision`, `titleModifiedAt =
  revisedAt` (`:288-296`); `scheduleSave()` (debounced text path). Item ops
  never touch checklist-level clocks.
- `updateItemDescription` (`:302`): identical pattern on description
  (`:304-312`); `scheduleSave()`.
- `updateItem(checklistID:itemID:relativeDate:)` (`:319`): **no-op guard**
  `item.relativeDate != relativeDate` (`:321`) so re-committing an identical
  parse never wins a spurious LWW round; otherwise same stamp pattern on
  relativeDate clocks (`:324-330`); `scheduleSave()`.
- `removeItems(from id:, at offsets:)` (`:333`): removes items/order entries and
  appends a per-item `ChecklistTombstone(checklistID:, itemID: removed.id,
  deletedAt: now(), revision: removed.revision + 1)`; `save()` direct.
- `moveItems` (`:366`, helper `moved` `:349`): on success regenerates itemOrder
  and stamps **only** the ordering clocks (`orderRevision += 1`, `orderModifiedAt
  = now()`); item revisions untouched — "a pure reorder is never mistaken for an
  item edit".
- `delete(id:)` (`:378`): removes checklist, appends whole-checklist tombstone
  (`itemID: nil`, same `revision + 1`); `save()`. `rename` (`:223`) and
  `setDestination` (`:239`) bump checklist-level `revision`/`modifiedAt`.
- Save plumbing: `save()` (`:435`) cancels `pendingSave`, refuses (logs) when
  `canOverwriteStoredPayload == false`, writes `defaults.set(encoded, forKey:
  key)`, fires `onChange?()` unless `isApplyingRemote`. `scheduleSave()` (`:421`)
  coalesces: `textEditDelay == nil` → synchronous (tests), else 300 ms debounce
  Task. `flushPendingSave()` (`:412`) forces an immediate save. Structural
  mutators call `save()` directly so a queued text save can't land later out of
  order.
- `init` load/classify (`:73-110` region): `ChecklistCodec.classify(data)`
  probes the version first — v1 → `.map { $0.migrated(at: now()) }` (restamps
  all clocks), v2 → `seededOrder()` (seeds ordering only), v3+ loaded verbatim;
  `.unsupportedVersion` → empty checklists and `canOverwriteStoredPayload =
  false` (mutations work in memory, save refused); `.unreadable` → empty, can
  overwrite (replace garbage). deviceID in `UserDefaults` key
  `"checklist.deviceID"`.
- `duplicate(id:name:)` (`:155`): fresh checklist + fresh item UUIDs,
  `revision: 1`, `modifiedAt: now()`, new ids; name via `uniqueName` (`:252`).
  `freshCopy(of:)` (`:175`, private): same remap, keeps source name, drops
  `destinationListIdentifier`. `importInsert(_:as:)` (`:192`): freshCopy + name
  resolution; append + save. `importReplace(id:with:)` (`:206`): removes local,
  records the same whole-checklist tombstone, inserts freshCopy, commits both in
  one `save()` ("a replace is one push").
- `apply(remote:)` (`:390`): refuses when `canOverwriteStoredPayload` false or
  `remote.version != currentVersion`; merges, `normalizedOrder()` self-heal,
  idempotence guard `merged != envelope`; wraps assign+save in
  `isApplyingRemote = true` so `onChange` isn't re-fired; returns whether
  visible state changed.

## Q3: Line-by-line merge in ChecklistMerge.swift and the fold-in

### Findings
- `merge(local: ChecklistEnvelope, remote: ChecklistEnvelope)` at
  `CheckStitch/ChecklistMerge.swift:12` — pure/deterministic (class doc `:4-10`).
  Unions tombstones first, computes `deadChecklists` (itemID == nil) and
  `itemTombstones`, drops dead entries from each surviving checklist's `items`
  and `itemOrder` (`:17-34`), rebuilds a fresh envelope (`:36-41`).
- `mergedTombstones` (`:43-60`): union by `TombstoneKey{checklistID, itemID}`;
  on collision `wins(revision: tombstone.revision, date: deletedAt, ...)` picks
  the winner; sorted for determinism. Tombstones always kill live entries
  (unconditional `removeAll` `:26-34`).
- `mergedChecklists` (`:65-114`): starts from local; remote-only appended via
  `remoteChecklist.normalizedOrder()`. On collision, whole-checklist LWW via
  `wins` on coarse clock (`:77-81`); **order decided separately** by
  `orderRevision`/`orderModifiedAt` (`remoteWinsOrder` `:86-90`).
- `mergedItems` (`:116-171`): for each shared id copies **per axis**:
  - coarse `revision`/`modifiedAt` (`:127-131`);
  - `titleRevision`/`titleModifiedAt` → title (`:133-138`);
  - `descriptionRevision`/`descriptionModifiedAt` → description (`:140-145`);
  - `relativeDateRevision`/`relativeDateModifiedAt` → relativeDate (`:147-152`);
  - high-water guard (comment `:155-159`): `merged.revision = max(merged.revision,
    titleRevision, descriptionRevision, relativeDateRevision)` (`:160-163`) — the
    tombstone invariant (`removed.revision + 1`) relies on the coarse clock being
    the item's high-water mark.
- `wins(revision, date, device, overRevision, overDate, overDevice)` (`:198-203`):
  `revision > overRevision`; tie → `date > overDate`; tie → `device <
  overDevice` (lexicographically smaller id); either device nil → false (no
  spurious reassignment). Symmetric in local/remote roles.
- `reconciledOrder` (`:173-189`) + `reorder` (`:191-196`): winner-order ids that
  survive, deduped, then remaining surviving ids; rebuilds `items` from the
  order via a first-wins Dictionary (duplicate-safe).
- Store fold-in: `ChecklistStore.swift:390` `apply(remote:) -> Bool` — guards,
  merge, `normalizedOrder()` per checklist (`:398`), idempotence guard (`:399`),
  `isApplyingRemote` + `save()` firing `onChange` only when not applying remote.
- Tests: `CheckStitchTests/ChecklistMergeTests.swift` — symmetry `:31-38`,
  field-clock merge `:139-155`, coarse-vs-field skew `:334-364`, tombstone-vs-
  field `:289-295`, order reconciliation `:449-563`, replay no-op `:638-639`.
  `ChecklistStoreTests.swift:992-998,1082-1126,1174-1176` cover `apply`
  idempotence, no-push, newer-version refusal.

## Q4: Codec back-compat test patterns and fixtures

### Findings
- Codec suite is `CheckStitchTests/ChecklistCodecTests.swift` (XCTest). Every
  legacy payload is an inline JSON literal via `Data(#"..."#.utf8)` — **no
  committed fixture files exist anywhere** (no fixtures/, testdata/, golden*
  dirs; only `*.json` files in the repo are Xcode asset-catalog Contents.json).
- Version classification (`classify`: `.loaded` / `.migratable(from:)` /
  `.unsupportedVersion` / `.unreadable`):
  - `:29` `testLegacyV1PayloadIsClassifiedMigratable` (no deviceID/tombstones/
    modifiedAt/revision keys → migratable from 1);
  - `:51` v2 → migratable; `:69` v2 with tombstones "never restamped";
  - `:83` current version → `.loaded`;
  - `:89` `testV3PayloadIsClassifiedMigratable` — v3 predates `relativeDate`,
    still migratable;
  - `:96` future version unsupported; `:43` unknown decodes as empty; `:117`
    distinguishes unsupported from unreadable;
  - `:253` `testV1V2V3ClassificationUnchanged` — regression guard that new field
    keys don't shift classification.
- Additive optional field / absent key:
  - `:140` `testDecodesV2PayloadWithoutDestinationAsNil` (pre-destination v2);
  - `:171` `testItemWithoutDescriptionClassifiesLoadedAsEmpty` — v4 payload with
    no `description` key stays `.loaded` with `""` (the "no version bump" rule);
  - `:187` `testMalformedDescriptionMakesPayloadUnreadable` — only whole-key
    absence is tolerant; wrong-typed value → unreadable.
- Encoder writes every key:
  - `:195` `testDescriptionSurvivesEnvelopeRoundTrip` (raw JSON contains
    `"description"`); `:16` `testEnvelopeRoundTrip` (`"itemOrder"`);
  - `:207` `testFieldClocksSurviveEnvelopeRoundTrip` — loops all six per-field
    clocks asserting each "is written unconditionally";
  - `:235` `testItemWithoutFieldClocksSeedsFromCoarseClock` — v4 lacking the six
    clock keys stays `.loaded`, seeds every field clock from coarse.
- Codable level: `ChecklistItemTests.swift` — `:26` round-trip; `:31`
  relativeDate round-trips (argument-driven, incl. nil); `:42` absent
  `relativeDate` key decodes nil ("A v2 item object"); `:50`
  `encodeAlwaysEmitsRelativeDateKey` (JSONSerialization.jsonObject, asserts key
  written as JSON null); `:59` description defaults to "" on absent key; `:88`
  legacy items list without itemOrder derives order (`orderRevision == 0`,
  orderModifiedAt `.distantPast`).
- Store/import/sync back-compat: `ChecklistStoreTests.swift:41` (persist across
  reload; comment `:54`: "payload on disk is a versioned envelope"), `:125`
  corrupt payload repaired on save, `:137` unsupported version not overwritten
  (seeds `{"version":99,...}`); `ChecklistImportSessionTests.swift:79,57,70`
  (migratable accepted; unsupported/unreadable throw, mutate nothing);
  `ChecklistSyncServiceTests.swift:65` cloud v1 migrated on reconcile, `:90`
  cloud v2 absorbed without restamping/tombstone loss, `:163,:207` persisted
  payloads seeded under `"checklists.v1"`; `ChecklistExportTests.swift:27,45,82`
  exported bytes classify `.loaded`.

## Q5: SwiftUI primitives for pickers, overlays, per-row rendering

### Findings
- `Picker` (3 uses, all inside Form sections):
  - `CheckStitch/SettingsView.swift:21` — appearance mode, `.tag(mode)` rows,
    identifier `"appearancePicker"` (`:32`);
  - `CheckStitch/BackgroundSettingsView.swift:23` — fade percent,
    `"backgroundFadePicker"` (`:33`);
  - `CheckStitch/ChecklistDetailView.swift:50` — destination list,
    `Picker("List", selection: destinationBinding(...))` with
    `Text("Default (Inbox)").tag(String?.none)` plus `ForEach(selectableOptions)`
    `.tag(String?.some(id))`, identifier `"destinationListPicker"` (`:56`),
    staleness/unavailable footnote (`:58-65`), writes via `destinationBinding` →
    `store.setDestination` (`:231-244`). No `.pickerStyle` set anywhere
    (platform-default menu/segmented). No value picker exists inside
    `ItemEditView` — its due date is a plain `TextField`.
- `.overlay` (5 uses): `CheckStitch/ContentView.swift:131,138` — floating chrome
  positioners (`.topLeading`/`.topTrailing`); `:224,261,300` — ring/stroke
  `RoundedRectangle(cornerRadius: CardPlate.cornerRadius)` over chrome/plates;
  `CheckStitch/BackgroundPhotoLayer.swift:18` — scaledToFill photo behind.
- `.sheet` (2 uses, both ContentView): `ContentView.swift:105` settings modal,
  `:165` export modal.
- `CardPlate` (`CheckStitch/CardPlate.swift:8`): `nonisolated static`
  constants — `cornerRadius` 14 (`:21`), `checklistTopMargin` 100 (`:31`),
  `plateFill` (`:39`), `iconPlateFill` (`:49`), `iconForeground` (`:59`);
  consumers `ContentView.swift:218-308`.
- `alert`/`confirmationDialog` small panels:
  `ChecklistDetailView.swift:144` rename-conflict alert
  (`"renameNameConflictButton"` `:146`), `:150` add-item alert (`:152-158` ids),
  `:160` duplicate alert (`:162-168` ids), `:172`
  `.confirmationDialog("Remove Checklist")` (`:174-180` ids);
  `ContentView.swift:85,156,190` alerts, `:181` name-conflict confirmation,
  `:161` `"runErrorMessageButton"`.
- `NavigationLink` row rendering: `CheckStitch/ChecklistDetailView.swift:271-289`
  `ItemRow` — the whole row is the link label (VStack: title + trailing
  secondary due-date + footnote description); pushes `ItemEditView(checklistID:
  itemID:)`; identifier `"itemRow-\(itemID.uuidString)"` (`:289`); rendered from
  `ForEach(checklist.items)` (`:86-88`) with `.onDelete` (`:91`) /
  `.onMove` (`:94`). Also `SettingsView.swift:36` → BackgroundSettingsView,
  `:63` → AboutView; `ContentView.swift:322` value-based list link.
- `ItemEditView` (`CheckStitch/ItemEditView.swift`, 124 lines; refs verified):
  struct `:12`, `@State draftDate`/`didLoadDraft`; body `:20` — Group looks up
  the item live from the store each render; found → `Form` with `Section("Title")`
  (`titleBinding` `:70`), `Section("Description")` (`descriptionBinding` `:83`),
  Section header "Due date" + footer "0 means today, 1 means tomorrow, nothing
  means no date" hosting `dueDateField` (`:102`, `#if os(iOS)` for the iOS-only
  `keyboardType(.numbersAndPunctuation)`); not-found → `ContentUnavailableView`
  (`:52`). `.navigationTitle("Edit item")`, inline toolbar,
  `.settingsSubscreenLayout()`, `.onChange(of: item.relativeDate)` absorbs
  external (iCloud) edits into the draft (`:57-63`), `.onAppear` seeds the
  draft once, `.onDisappear { store.flushPendingSave() }`.
- Reachability: `ItemEditView` is reachable **only** via the `ItemRow`
  NavigationLink from `ChecklistDetailView` — no sheet/dialog path.

## Q6: Build/test gate commands and test-suite inventory

### Findings
- Makefile targets (`Makefile:33-89`): `build` (iOS Simulator xcodebuild, scheme
  `CheckStitch`, `:35-39`), `build-mac` (`CODE_SIGNING_ALLOWED=NO`, `:41-47`),
  `build-mac-signed` (`-allowProvisioningUpdates`, `:51-57`), `watch-build`
  (watchOS, `:61-66`), `run`, `test`, `test-unit`, `test-ui`, `clean`. `make
  test` == `test-unit` + `test-ui` (`:61`).
- `test-unit` (`Makefile:66-70`): `-destination 'platform=macOS'`,
  `CODE_SIGNING_ALLOWED=NO`, `-only-testing:CheckStitchTests`. Test targets do
  not set `SWIFT_DEFAULT_ACTOR_ISOLATION` (comment `:59`); suites opt in per
  suite with `@MainActor`.
- `test-ui` (`Makefile:74-82`): `build-for-testing` then `test-without-building
  -only-testing:CheckStitchUITests` on the worktree-pinned SIM — never a bare
  `name=` destination (precedence `Makefile:5-9`: explicit `SIM=` > worktree
  `.simulator_id` > shared default).
- Gate = `scripts/test.sh`: `make build` → resolve/pre-boot this worktree's
  simulator → `make test` → `make build-mac` → `make watch-build` → `bash
  scripts/tests/run.sh` (skippable `GATE_TESTS_SKIP=1`) → shellcheck (`:124-128`)
  → "gate: ok".
- Test-suite inventory (`CheckStitchTests/`, 36 files): XCTest only 3 files —
  `ChecklistCodecTests.swift:1`, `ChecklistExportTests.swift:1`,
  `ChecklistStoreTests.swift:1` (all `@MainActor` `:5`); everything else Swift
  Testing. `@Suite(.serialized)` only 2: `BackgroundImageStoreTests.swift:8`,
  `SettingsBindingsTests.swift:6` (share `UserDefaults.standard`). `@MainActor`
  on nearly every view/store suite (e.g. `ChecklistDetailViewTests.swift:13`,
  `ChecklistMergeTests.swift:6`, `ViewRenderTests.swift:6`) and fixtures
  (`TestFixtures.swift:22,27,56,88,119,132,165`); per-function `@MainActor` at
  `ChecklistSyncServiceTests.swift:340,347,353`, `ChecklistMergeTests.swift:
  672,677,686,699`.
- Platform gating `#if os(...)`: `MacWindowFrameTests.swift:1` whole-file macOS;
  in-function blocks at `ViewRenderTests.swift:27`,
  `ExportChecklistViewTests.swift:35`, `ChecklistDetailViewTests.swift:72,164,
  202,218`, `AboutViewTests.swift:23`. UI smoke:
  `CheckStitchUITests/CheckStitchUITests.swift:13` single XCTest case
  `testLaunchAndAccessibilitySmoke` (`#if os(iOS)` guard `:34`).
- Gotchas: simulator lock `scripts/test.sh:35-82` (host lock file, LOCK_TIMEOUT,
  stale reap, scoped shutdown of resolved UDID only); destination pinning via
  per-worktree `.simulator_id`; `build-mac-signed` needs the dev-team
  provisioning profile.

## Cross-Cutting Observations
- **The per-field clock is the model's core convention**: every editable,
  persisted item field = value + `fieldRevision` + `fieldModifiedAt`, stamped
  together by a store mutator, compared independently in `mergedItems`, included
  in the high-water `max`, seeded from the coarse clock on decode/init/migration,
  and asserted "written unconditionally" by codec tests. `relativeDate` is the
  canonical precedent for an additive optional field: it was added between v3
  and v4 **without a version bump** — the classify switch has a comment
  (`Checklist.swift:425-445` region) and tests prove a v4 payload with the key
  absent stays `.loaded`.
- Back-compat invariants are test-enforced, not just documented: absent key
  decodes (with default), encoder writes every key, wrong-typed value → unreadable,
  legacy v1/v2/v3 classification unchanged after new keys are added
  (`ChecklistCodecTests.swift:253`).
- The edit-checklist screen (`ItemEditView`) is a bare Form of three text
  fields with a per-keystroke commit pattern (`titleBinding`,
  `descriptionBinding`, `commitDate`) and a debounced store write. The item rows
  themselves live in `ChecklistDetailView` and are whole-row `NavigationLink`s.
- The UI has **no** popover/menu/context-menu primitives; small panels are
  `.alert`/`.confirmationDialog`, modals are `.sheet`, value picking is
  `Picker` inside Form sections, and per-decision styling constants live in
  `CardPlate`. Priority-value pickers elsewhere in the codebase (destinations,
  appearance, fade percent) all follow the `Picker` + `.tag` + accessibility
  identifier pattern.
- Mutators fall into two save cadences: text-field edits
  (`updateItem(title/description/relativeDate)`) debounce via `scheduleSave()`;
  structural ops (add/remove/move/delete/duplicate/import) call `save()`
  directly. New mutations follow whichever cadence their control implies.

## Open Areas
- Exact Merge/Store test line numbers for `apply` were taken from report
  citations (`ChecklistStoreTests.swift:992-1126`) and not re-verified against
  the file.
- `CheckStitch/ChecklistExport.swift` (app target) vs
  `CheckStitchCore/.../ChecklistExport.swift` (core) both exist; the core one
  wraps `ChecklistCodec.encode`. The app-target file's role was not traced.
- The `ChecklistSyncCoordinator`/`ChecklistSyncing` push path was mapped only
  top-level (`pushContext` `:30`, protocol `:9/:30`); its change-propagation
  surface was not traced end to end.
- No legacy fixture files exist, but the exact set of hand-written literal
  payloads (v1/v2/v3 JSON) is worth treating as the compat corpus for any new
  field.