# Research Findings

All paths relative to `CheckStitchCore/Sources/CheckStitchCore/` unless noted.
Recon note: the `((n))` positional-marker replacement does NOT exist yet — current
title numbering is positional (`:position: title`). Everything below documents what
already exists; the marker resolution is net-new.

## Q1: Mutable scalar fields on `Checklist` / `ChecklistItem` and the mutation convention

### Findings
- `Checklist` (Checklist.swift:147-190, impl 195+) shares ONE coarse clock
  (`revision`/`modifiedAt`, decl ~182-183) across all checklist-level scalar fields:
  `name`, `destinationListIdentifier: String?` (~167), `prefixesReminderNumbers: Bool`
  (~167), `showsOnWatch: Bool` (~173), `folderID: UUID?` (~179). `itemOrder`/
  `orderRevision`/`orderModifiedAt` are a separate ordering clock.
- Doc note (Checklist.swift:132-136): checklist-level clocks describe the record only;
  item member ops do NOT bump the checklist coarse clock.
- `ChecklistItem` (Checklist.swift:25-125) has whole-item clocks (modifiedAt/revision,
  :44-45) plus per-field clocks (`titleRevision/TitleModifiedAt`,
  `description*`, `relativeDate*`, `priority*`, :50-60). Public init seeds each nil
  field clock from the coarse clock (:26-37).
- Each model implements its own Codable `init(from:)`/`encode(to:)` inline in
  Checklist.swift (item :109-166, checklist :229-289).
- Mutation entry points all live in ChecklistStore.swift, following a uniform shape:
  - `rename(id:to:)` (~243-256): guard found → `revision += 1` + `modifiedAt = now()` → `scheduleSave()`.
  - `setDestination(_:for:)` (~295-306): same coarse-clock bump.
  - `setPrefixesReminderNumbers(_:for:id:)` (~311-323): **no-op guard** `guard current != new else { return .updated }` then coarse-clock bump.
  - `setShowsOnWatch(_:for:id:)` (~327-343): **no-op guard** + coarse-clock bump.
  - `moveChecklist(id:toFolder:)` (~486-500): unchanged membership is a no-op.
  - Item setters stamp their own field clock too: `updateItem(…title:)` (~369-381) bumps
    item revision/modifiedAt PLUS `titleRevision/titleModifiedAt`; same for description
    (~386-399), relativeDate (~405-421, no-op guard), priority (~427-440, no-op guard).
  - Item member mutations use debounced `scheduleSave()`; create/remove/move use immediate `save()`.
- Additive readers are computed: `hasDescription` (Checklist.swift:63-67), `isBlank` (:69-72).
- UI bindings call these store mutators directly: ChecklistDetailView.swift:214/227 (rename),
  :267 (`setPrefixesReminderNumbers` as `set:`); ItemEditView.swift:104,117,162.
- **Trio a new checklist scalar must touch**: (1) model declaration (stored `var` + init
  param + CodingKeys in Checklist.swift); (2) codec `init(from:)`/`encode(to:)` +
  `migrated(at:)` seeding; (3) a ChecklistStore `set...` method following no-op-guard +
  coarse-clock bump + `scheduleSave()`.
- `migrated(at:)` (Checklist.swift:291-323) seeds legacy field clocks on upgrade; a new
  scalar must be seeded there to avoid granting a spurious LWW win to pre-upgrade payloads.

## Q2: Persistence codec round-trip and merge

### Findings
- Checklist decode uses `decodeIfPresent(...) ?? default` throughout (Checklist.swift:211-243):
  `name` required (:213); `items ?? []`; `prefixesReminderNumbers ?? false` (:218);
  `showsOnWatch ?? true` (:223 — only default-true); `folderID`/`destinationListIdentifier`
  no default; coarse clocks defaulted; `itemOrder ?? items.map(id)` plus decode-time
  self-heal via `normalizedOrder` (:232-243). Additive optional fields decode to defaults
  with NO version bump.
- Checklist encode (Checklist.swift:245-263) writes every key; `folderID` written
  key-or-Nil (:251-257).
- `ChecklistEnvelope` (Checklist.swift:419-439) is the versioned wire container: fields
  `version, deviceID, checklists, tombstones, folders, folderTombstones`. `contentEquals`
  (:470-473) ignores deviceID.
- Format versioning: `enum ChecklistCodec`, `currentVersion = 5` (Checklist.swift:476-477).
  `classify` probes version via `VersionProbe` (:547) before full decode; outcomes
  loaded / migratable / unsupportedVersion / unreadable (:483-496). Migration branches
  (:508-534): v4 folders verbatim, v3 predates relativeDate, v2 seed ordering, v1 full
  `migrated(at:)` restamp. Store is the only encoder (ChecklistStore.swift:115-120).
- `ChecklistMerge` (ChecklistMerge.swift): entry `merge(local,remote)`
  (:24-52), symmetric, tombstones-union-first, emits envelope at `currentVersion`.
  Winner rule `wins()` (:287-303): per-field revision higher wins → tie newer `modifiedAt`
  → tie smaller device id. LWW only picks values when both sides have the record.
- **Checklist scalar fields share ONE coarse clock**: if remote wins the coarse `wins()`
  test, ALL coarses scalars are copied wholesale (:145-157) — no per-field clocks at
  checklist level. So a new `multiple` field would travel with that wholesale copy.
- Item fields ARE per-field (title/description/relativeDate/priority, :172-198); coarse
  item revision/modifiedAt from whole-item winner then raised to max of adopted field
  clocks (:202-207). Ordering decided independently by `orderRevision`/`orderModifiedAt`.
- `ChecklistStore.apply(remote)` (ChecklistStore.swift:584-611): refuses non-current
  versions, merges, re-canonicalises `normalizedOrder`, no-op if equal, saves.

## Q3: Reminder-creation flow and the title resolver

### Findings
- Pure resolver `ChecklistTitleNumbering.title(_:position:numbered:itemCount:)`
  (ChecklistCreator.swift:16-28): if `numbered == false` returns title raw (:23); else
  zero-pads single-digit positions to two digits only when `itemCount > 9 && position < 10`
  (:24) so Reminders lexical sorting works, returns `"\(padded): \(title)"` (:25).
- **Path A (production)** `ChecklistReminders.create(from:targeting:gate:)`
  (ChecklistReminders.swift:26-71): `gate.reserveRun()` first (:35, fails → `.purchaseRequired`);
  reads `checklist.prefixesReminderNumbers` (:32); `requestAccess()` (:38); resolve
  destination (:42-47, `.destinationMissing` if unresolved); `itemCount = items.filter{!isBlank}.count`
  (:50); loops non-blank items with position cursor (:52-54); raw reads `item.title`,
  `item.description`/`hasDescription`, `item.priority`, `item.dueDateComponents(today:)`
  (:58-61); derived title produced at :56-57 via the resolver; **this path also passes
  notes: raw description** (:58-59) — the only path that surfaces descriptions.
  ReminderRunOutcome enum :67-71.
- **Path B (test-only)** `ChecklistCreator.create(from items:)` (ChecklistCreator.swift:46-68):
  same resolver + blank-drop-first position cursor + non-blank itemCount; no descriptions
  passed; returns ChecklistCreationOutcome (:6-10, :66-67). No production consumer
  (only CheckStitchTests/ChecklistCreatorTests.swift).
- Both paths share: same resolver, same blank-drop-first position (no gap after empty
  rows), same non-blank itemCount. Derived text is produced ONLY inside the resolver at
  the two call sites; raw item.title/description are never mutated.
- `RunCounter`/`RunGate` (RunCounter.swift): durable run counter in UserDefaults
  ("runCount.v1", :17), validated read (:21-24), increment/decrement/reset; `RunGate`
  (:42) `freeRunLimit = 20`, `reserveRun()` atomic check+increment (:56-62). RunCounter
  gates runs before any reminder is created — it does not touch titles.
- Call sites: production `CheckStitch/ChecklistRunViewModel.swift:47-48` builds
  `RunGate(counter:,isUnlocked:)` and calls `ChecklistReminders.create(from:targeting:gate:)`;
  `CheckStitch/MyApp.swift:108` phone-sync path `createReminders:`.
- Toggle storage: `Checklist.prefixesReminderNumbers` (Checklist.swift:183, codec :206,218,251),
  set via ChecklistStore.swift:280-281, read in UI ChecklistDetailView.swift:266.

## Q4: Read-only vs editing surfaces across iOS/macOS/watch/widget

### Findings
- iOS and macOS share one set of SwiftUI views under `CheckStitch/`; watchOS and the
  widget are separate targets. No dedicated macOS item/editor view.
- **Read-only row (iOS/macOS)** `ItemRow` (CheckStitch/ChecklistDetailView.swift:305): whole
  row is a `NavigationLink` into ItemEditView (:310-315); title `Text(Self.displayTitle(title))`
  (:331); `displayTitle(_:)` (:362-365) is DERIVED — empty → localized "Item" placeholder,
  non-empty → raw passthrough; description `Text(description)` RAW (:343) shown when non-empty;
  date `DueDateLabel.resource(for:)` DERIVED (CheckStitch/DueDateLabel.swift:16-33); priority
  marker + color derived (:326, :339-349), hidden when marker empty, rendered on title HStack.
- **Editor** `ItemEditView` (CheckStitch/ItemEditView.swift:12, pushed from the row): title/
  description RAW TextFields via `titleBinding`/`descriptionBinding` (:24-32) edited raw;
  priority Menu (:33-52); date via buffered field + `RelativeDateDraft` seam reusing DERIVED
  DueDateLabel phrases (:5-10). Mutations go through per-field store mutators — no editing VM.
- **Watch detail (read-only)** WatchChecklistDetailView.swift:57-66 renders `item.title` RAW
  and `item.description` RAW (when `hasDescription`); no displayTitle fallback, no due-date,
  no priority marker; rows are not links into an editor. Watch list labels raw (WatchChecklistListView.swift:30-38).
- **Widget (read-only, checklist-level only)** never renders item text. Pure row model
  ChecklistWidgetDisplayModel.swift:8-19 (name raw); Single/ChecklistWidget.swift:92-129
  (`Text(row.name)` :95); MultiChecklistWidget.swift:77-113 (:85).
- **Summary raw vs derived**: ItemRow title derived (fallback only, raw passthrough), desc
  raw, date derived, priority derived; ItemEditView title/desc raw, date label derived; Watch
  detail title/desc raw; Widget name raw. The only item-text read-only surfaces are ItemRow
  (iOS/macOS) and the Watch detail.

## Q5: App Intents parameter & validation patterns

### Findings
- `RunChecklistIntent` (RunChecklistIntent.swift:15): `static title`, `openAppWhenRun=false`
  (:17); ONE required `@Parameter(title: "Checklist") public var checklist: ChecklistEntity`
  (:20-21); `parameterSummary` (:38-40) composes the chosen checklist into the speech summary.
  Test-seam ctor injects store/targeting/gate/runState (:23-35).
- **Validation shape** `enum RunChecklistIntentError: LocalizedError { case checklistNotFound }`
  (:5-13) with `errorDescription` returning a `LocalizedStringResource(...).resolvedInAppLanguage()`
  (Localizable table, bundle .main). **No `.invalid...` case variants exist yet** — validation
  currently surfaces as a thrown LocalizedError. Test asserts it (CheckStitchTests/RunChecklistIntentTests.swift:65-68,
  expected "That checklist no longer exists.").
- **Validation-before-side-effects ordering in `perform()`** (:48-94): resolve collaborators
  (:49-50) → `guard uuid = UUID(...), stored = store.checklist(...)` else throw
  `checklistNotFound` (:52-55, the only throwing validation, before any side effect) →
  status-only pre-check switch on `targeting.accessStatus()` (:57-66; `.notDetermined`/`.denied`
  return dialogs, no throw, no run) → THEN side effects: `resolveGate()` (:68),
  `runState.beginRun` (:78), `ChecklistReminders.create` (:80), `finishRun` (:85), final
  `IntentDialog` (:86-88). Comment :53-55 documents residual TOCTOU.
- Outcome dialogue mapping factored into separate `RunChecklistDialogue` enum (:91-129) —
  intent body stays text-free.
- **Sibling intents**: `ListChecklistsIntent` (ListChecklistsIntent.swift:8-18) has no
  `@Parameter` fields, only a private `ChecklistEntityQuery`, `perform()` calls
  `suggestedEntities()`, no validation. `ChecklistConfigurationIntent`
  (ChecklistConfigurationIntent.swift:8-9) `WidgetConfigurationIntent` with ONE optional
  `@Parameter public var checklist: ChecklistEntity?` (nullable → optional). `MultiChecklistConfigurationIntent`
  (:8-9) optional collection `[ChecklistEntity]?` (custom array-of-entity parameter).
- Entity: `ChecklistEntity: AppEntity` (ChecklistEntity.swift:6-15), `id: String` =
  `Checklist.id.uuidString` (rename-proof), `displayRepresentation = DisplayRepresentation(title)`.
  `ChecklistEntityQuery: EntityStringQuery` (:17-38), fresh store per call, `suggestedEntities()`
  is the default for List/Run intents.
- **Pattern summary**: optional = `T?` nullable, multi = `[T]?`; each throwing intent
  declares its own `enum: LocalizedError`; all validation precedes any side effect; dialogues
  factored into separate enums.

## Q6: Export / share / import / duplicate + localization baseline

### Findings
- **Export** uses the SAME full codec path as persistence — ChecklistExport.swift:11-15
  `envelope(checklists:)` (version `currentVersion`, empty deviceID, no tombstones; valid
  codec payload, never resurrects deletions); `data(checklists:)` :17-19 = `ChecklistCodec.encode`.
  filename :22-27 "CheckStitch-<yyyy-MM-dd>". Because encode writes every key, a new scalar
  field flows through export/share automatically. ChecklistExportDocument.swift:12-26
  `FileDocument`, `.json`.
- **Share**: ChecklistShare.swift:11-29 captures only the document `Data` into an
  `NSItemProvider` under `UTType.json`, `visibility .all`, `suggestedName=filename`
  (:16); `ShareSheet` UIViewControllerRepresentable :33-54 (iOS-only, iPad popover anchor).
  ChecklistImportExportViewModel.swift:15-16,30,70-75 → `shareSelected()` builds the document,
  deferred to sheet onDismiss.
- **Import**: ChecklistImportSession.swift (29-46 session; state pending/candidates/summary);
  `stage(data:)` :55-70 decode-only → `ChecklistImportCandidate(id:fileUUID, checklist,
  conflicting:)` via `store.conflictingChecklist`; `commit(selectedIDs:)` :75-95 re-runs
  authoritative conflict check, collision → pending FIFO, else `store.importInsert`;
  `decoded(_:)` :107-125 via `ChecklistCodec.classify` (.loaded → checklists; v1 → `migrated`,
  v2 → `seededOrder`); `decide(_:for:)` :129-139 replace→`importReplace`, keepBoth→`importInsert`,
  keepExisting→count. ChecklistImportError :9-23.
- **Duplicate / freshCopy** (ChecklistStore.swift:156-244): `duplicate(id:name:)` :156-189
  guards source existence, disambiguates name, rebuilds fresh items copying
  title/description/relativeDate/priority, and **carries `destinationListIdentifier`,
  `prefixesReminderNumbers`, `showsOnWatch`, `modifiedAt: now()`, `revision: 1`**. `freshCopy`
  :195-213 (private, shared by import) stamps new checklist+item UUIDs, revision 1, now(),
  carries the same three scalars, keeps name. `importInsert` :216-227 / `importReplace` :230-244.
  Convention: duplicate/freshCopy never re-enter LWW merge; scalars carried untouched so the
  user's Reminders target survives. **A new `multiple` scalar must be added to these carry lists.**
- **Localization baseline**: 4 catalogs — CheckStitch/Localizable.xcstrings (App),
  CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings (Core),
  CheckStitchWatch/Localizable.xcstrings (Watch), CheckStitchWidget/Localizable.xcstrings
  (Widget). Apple xcstrings JSON, `sourceLanguage "en"`, strings keyed by UI key,
  `extractionState "manual"`, each key needs localizations for the 6 languages
  en/fr/es/de/ja/zh-Hans (stringUnit state:translated). `.lproj` holds only InfoPlist.strings.
  Fixtures: CheckStitchTests/LocalizationFixtures.swift:12-152 `requiredKeys:[(catalog,[String])]`
  (:8 `guardedCatalogs=["App","Core","Watch","Widget"]`). A new key must exist in its catalog
  across all 6 languages AND be added to that catalog's `requiredKeys` entry (:157-207 handle
  InfoPlist.strings + identical non-English spellings). AGENTS.md: run `scripts/l10n-check.sh`
  first.

## Cross-Cutting Observations

- A new checklist-level `multiple: Int` scalar is a close clone of the existing
  `prefixesReminderNumbers`/`showsOnWatch` path: checklist-level stored field sharing the
  coarse clock, no-op-guard setter in ChecklistStore, `decodeIfPresent ?? 1` (no envelope
  version bump — additive fields decode to defaults), wholesale coarse-LWW copy in merge,
  carried in duplicate/freshCopy/import/export (encode writes every key), and a
  LocalizationFixtures.requiredKeys + 6-language entry.
- The resolution function (a net-new `((n))` scaler) is a sibling of
  `ChecklistTitleNumbering.title`, which already lives in ChecklistCreator.swift and is called
  at exactly two run-path sites (ChecklistReminders.swift:56-57 production, ChecklistCreator.swift:60-61
  test-only). "scale-then-prefix" implies scaling resolves before the numbering prefix is
  applied at those sites.
- Read-only item-text rendering happens in only two places: ItemRow (iOS/macOS) and the Watch
  detail; editors (ItemEditView) stay raw. A factor badge ("×N") would follow the priority
  marker's HStack-badge pattern (ChecklistDetailView.swift:326,339-349).
- Intents: no `.invalid...` case exists yet — `.invalidMultiple` is the first; the pattern to
  follow is the LocalizedError enum with resolved-in-app-language message and validation
  before side effects (RunChecklistIntent.perform :52-66). Optional parameter = `T?` nullable
  `@Parameter`.

## Open Areas

- `((n))` marker grammar, case-sensitivity, and whether it applies to title and/or description,
  and the exact scaling arithmetic (`n × multiple`) are not in the codebase (net-new design).
- Which surfaces must render scaled text is partly a design decision: ItemRow title and Watch
  detail title are the only read-only item-text renderers found; the widget surfaces no items.
- Whether `multiple` clamps `≤0 → 1` at decode and/or in `setMultiple` (spec says clamp; mechanics
  across the codec vs setter is a design choice the research cannot answer).
- The detail-screen Scaling Stepper (1...99) section and "scale-then-prefix" ordering interplay
  with `prefixesReminderNumbers` is design; both current run paths apply numbering independently.