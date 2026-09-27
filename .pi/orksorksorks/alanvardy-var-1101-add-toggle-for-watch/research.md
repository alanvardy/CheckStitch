# Research Findings

## Q1: How does the versioned `ChecklistEnvelope` codec store boolean fields, their decode defaults, and when does it bump `currentVersion`?

### Findings
- **No stored boolean on `ChecklistItem`** — `ChecklistItem.hasDescription` and `.isBlank` are computed predicates (`Checklist.swift:66-75`), not CodingKeys. The only stored booleans in the model are on `Checklist` and `Folder`. (`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`)
- **`Checklist.prefixesReminderNumbers: Bool`** — default `false` (`Checklist.swift:222`); CodingKey `:234`; decode `decodeIfPresent(Bool.self, ...) ?? false` (`:254-255`, comment: absent in v4-and-earlier payloads decodes to `false`, no version bump); encode **unconditionally** writes the key (`:269`). Shares the checklist's coarse `revision`/`modifiedAt` clock (`:225-231`).
- **`Folder.isCollapsed: Bool`** — default `false` (`Checklist.swift:284`); CodingKey `:294`; decode `decodeIfPresent ?? false` with the same "absent in pre-collapse payloads, no version bump" comment (`:300-301`); encode unconditional (`:306`). Shares folder coarse clock (`:286-290`).
- Envelope-level arrays use the same additive pattern: `deviceID ?? ""`, `checklists`/`tombstones ?? []`, `folders`/`folderTombstones ?? []` (`:454-460`); encode writes all keys unconditionally (`:462-471`).
- **`currentVersion = 5`** (`Checklist.swift:465`). `classify` (`:483-521`) probes only the `version` key via `VersionProbe`; `case currentVersion` → `.loaded(JSONDecoder(...))` (`:490-492`); `case 4/3/2/1` → `.migratable(from:, envelope:)` decoding the **whole envelope verbatim** (`:493-517`); `default` → `.unsupportedVersion` (`:518-520`); any throw → `.unreadable` (`:521-523`).
- **Version-bump rule**: the envelope bumps `currentVersion` only when the wire shape or a closed domain changes so an absent key / `decodeIfPresent` default can no longer represent it. Additive boolean/optional fields land as `decodeIfPresent ?? default` with **no** bump. Closed domain warning for `priority` enum (`:135-139`).
- **`migrated(at:)` / `seededOrder()`** fire only for old-version (`migratable`) payloads to fabricate sync identity v1/v2 lack — not for the absent-boolean case. `Checklist.swift:326-365` (restamp), `:369-382` (seed ordering only). Consumers: `ChecklistStore.swift:80-91` (`case 1 → migrated(at:)`, `case 2 → seededOrder()`, v3+ verbatim; `canOverwriteStoredPayload = true` always for migratable `:89`, `false` only for `.unsupportedVersion` `:96`); `ChecklistSyncService.swift:129-145` (v1 → `migrated(at: .distantPast)`, v2 → `seededOrder()`).

## Q2: What toggle patterns exist in the iOS edit-checklist screens, and how do they bind to the store?

### Findings
- The edit-checklist screen is `ChecklistDetailView.swift`. **Number Reminders** `Toggle` at `ChecklistDetailView.swift:70`: `Toggle(isOn: numberingBinding(checklistID:)) { Label("Number Reminders", systemImage: "textformat.123") }` in a Form/Section, `.accessibilityIdentifier("checklistPrefixNumbersToggle")` (`:73`), behavior footer (`:75`).
- View is keyed by id, not a parent binding: `let checklistID: UUID` (`ChecklistDetailView.swift:3-4`), `@Environment(ChecklistStore.self)` (`:6`), reads via `store.checklist(id:)` (`:53`).
- **Binding pattern**: `numberingBinding(checklistID:)` (`ChecklistDetailView.swift:256-261`) returns `Binding(get: { store.checklist(id:)?.prefixesReminderNumbers ?? false }, set: { store.setPrefixesReminderNumbers($0, for: checklistID) })`. Doc comment (`:253-255`) notes the getter re-reads the store so a synced value updates the toggle. Mirrors `destinationBinding` (`:263-281`).
- **Store mutation method**: `setPrefixesReminderNumbers(_ enabled: Bool, for id:) -> SetDestinationOutcome` (`ChecklistStore.swift:277-283`): guards `notFound`, no-ops if unchanged, mutates the field, bumps `revision += 1` and `modifiedAt = now()`, calls `scheduleSave()`, returns `.updated`.
- Consumption (not part of the toggle): `ChecklistReminders.swift:33,58` reads `prefixesReminderNumbers`.
- Other booleans use `@State`/`$` view-local bindings instead: `InterfaceSettingsView.swift:53` (`$allowsLandscape`, `allowLandscapeToggle`), `BackgroundSettingsView.swift:11,36` — these differ from the store-backed edit-checklist toggle.

## Q3: How does data flow from phone to watch and how do the watch views resolve/render it?

### Findings
- Transport: `ChecklistSyncMessage.context(Data)` is phone→watch carrying the whole serialized `ChecklistEnvelope` (`ChecklistSync.swift:102-121`); the pocket key is `ChecklistSyncKey.context = "checklists"` (`:6`).
- **Phone push**: `PhoneSyncAdapter.sendContext` → `session.updateApplicationContext` ("latest state wins", `PhoneSyncAdapter.swift:30`). The watch never pushes context (`WatchSyncAdapter.swift:26-27` returns `false`).
- **Watch receipt** (`WatchSyncAdapter` WCSessionDelegate): cold launch reads `receivedApplicationContext` on activation (`:39-46`); live `didReceiveApplicationContext` → `receive(..., source: "context")` (`:64-65`); `didReceiveUserInfo` → `"userInfo"` (`:71-72`); `receive` decodes the message and routes to `onMessage` (`:78-83`).
- **Store ingest**: `WatchChecklistStore.start()` sets `onMessage = receive`; `.context` classifies `.loaded` or `.migratable(from: >=2)` → sets `checklists` and `folders` `@Observable` arrays (`ChecklistSync.swift:346-359`, arrays at `:265,:267`). Decodes the whole envelope; absent keys fall to the `decodeIfPresent` defaults.
- **ViewModel resolution** (`WatchChecklistViewModel.swift`): `checklists`/`folders` passthroughs (`:16,:19`); `looseChecklists` via `ChecklistGrouping.isLoose` (`:25-29`); `checklists(in:)` = filter `folderID == folder.id` (`:34-36`); `current(_:)` returns the live store copy (`:49-52`); `visibleItems(of:)` filters `!item.isBlank` (`:61-63`).
- **Views**: main list `WatchChecklistListView.swift:13-27` (folder rows → `WatchFolderDetailView`, loose rows → `WatchChecklistDetailView`); folder detail `WatchFolderDetailView.swift:13-15,24` (`List(members)`); checklist detail `WatchChecklistDetailView.swift:28-29,65` (`List(visibleItems)`).
- **Where a per-checklist boolean becomes visible**: `Checklist` travels whole through the envelope (`ChecklistSync.swift:352` holds complete values), so **any new per-checklist boolean on `Checklist` is immediately visible to all three watch views** via `current(_:)` and `store.checklists`. The existing analogous boolean `prefixesReminderNumbers` (`Checklist.swift:160-162`) demonstrates this.
- Two existing filters: folder membership (`folderID == folder.id`, `WatchChecklistViewModel.swift:35`) and item visibility (`!isBlank`, `:62`).

## Q4: How is folder membership modeled and resolved, and how does the watch enumerate a folder's children?

### Findings
- **One-field relationship**: `Checklist.folderID: UUID?` (`Checklist.swift:186`, "a one-field relationship... decided by the same last-write-wins rule"). Init `:150,:159`. Codec: CodingKey `:197`; decode `decodeIfPresent(UUID.self, forKey: .folderID)` (`:212`); encode value or `encodeNil` (`:239-242`, "nil is encoded, never dropped").
- `Folder` is a separate model with its own `id` UUID (`Checklist.swift:342`, id at `public let id: UUID`). The envelope carries complete `[Checklist]` + `[Folder]` + tombstone arrays (`:407-409`).
- **Membership is derived, never stored on the Folder** — resolved by matching `$0.folderID == folder.id`:
  - Watch view model: `checklists(in:)` at `WatchChecklistViewModel.swift:40-42`; loose handling `:18-22` via `ChecklistGrouping.isLoose` with known folder IDs (`ChecklistGrouping.isLoose(folderID == nil OR unknown id)`, `Checklist.swift:551-556`); `current(_ folder:)` `:45-47`.
  - Core helper: `ChecklistGrouping.sections(folders:checklists:)` builds `byFolder` and a loose section (`Checklist.swift:559-571`).
- **Root list**: `WatchChecklistListView.swift` renders `viewModel.folders` as NavigationLink rows (`:20-24`) pushing `WatchFolderDetailView`, and `viewModel.looseChecklists` below (`:32-35`).
- **Folder detail**: `WatchFolderDetailView.swift` `members = viewModel.checklists(in: current)` (`:17-19`), renders `List(members)` (`:23-29`) with a "No checklists" `ContentUnavailableView` when empty.
- **Implication for folder hiding**: the rendering layer knows a folder's children purely by filtering the synchronised in-memory `store.checklists` on `folderID == folder.id`; folders own no child pointer. A "hide folder if all members hidden" rule would compute over that derived child set.

## Q5: What is the convention for adding a user-facing string key?

### Findings
- **Three catalogs**, mapped to targets, centralised in two synced places:
  - `scripts/l10n-check.sh:15-19` `CATALOGS = { App: CheckStitch/Localizable.xcstrings, Core: CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings, Watch: CheckStitchWatch/Localizable.xcstrings }`
  - `LocalizationFixtures.swift:8` `guardedCatalogs = ["App","Core","Watch"]`
- **Which catalog**: iOS app views → **App**; code shared by Core (used by phone + watch) → **Core**; watch views → **Watch**.
- **AGENTS.md:116** codifies: a new key needs all 6 languages + a `LocalizationFixtures.requiredKeys` entry; run `scripts/l10n-check.sh` first.
- **Catalog shape**: `sourceLanguage: "en"`, a `strings` map key → `{ extractionState: "manual", localizations: { en,de,es,fr,ja,zh-Hans each { stringUnit: { state: translated, value } } } }`.
- **Test fixture**: `LocalizationFixtures.requiredKeys` (`LocalizationFixtures.swift:12`) groups keys by catalog, alphabetically; Watch list at `:140-145`.
- **Enforcers**: Swift `LocalizationTests.swift` — `catalogsParseAndHaveNonEmptyEnglish` (`:10`), `catalogsHaveAllSixLanguages` (`:26`), `everyRequiredKeyIsPresent` (`:39`), `watchCatalogCarriesEveryUIKey` (`:48`), `nonEnglishValuesDifferFromEnglish` (`:57`, honours `excludedIdentities` fixture `:166-183`), `coreCatalogValuesAreEmbeddedInTheResourceBundle` (`:74`). Shell mirror `scripts/l10n-check.sh` (6 langs `:10`, `NON_EN` `:11`, per-key six-lang check `:22-26`, differs-from-English unless excluded).

## Q6: How are codec decode/version and view toggle behaviors tested? Platform gating?

### Findings
- **`ChecklistCodecTests.swift`** (`@MainActor :5`): `testDecodesV5PayloadWithoutPrefixesReminderNumbersAsFalse` (`:167`, absent key → `false`, additive guarantee); `testPrefixesReminderNumbersSurvivesEnvelopeRoundTrip` (`:178`); description round trips (`:194,:208`); priority absent → `.none` (`:223`) / malformed → `.unreadable` (`:241`); version classification `:29,:43,:51,:61,:98,:334,:369,:309`; field-clock seeding `:288`; `PinnedV4Codec`/`PinnedV5Codec` pin the v4/v5 `classify` switches (`:399`).
- **`ChecklistStoreTests.swift`**: version 99 rejected (`:147`); v1 restamp (`:321`); v2 load+seed (`:416`); `setPrefixesReminderNumbers` suite `:1840-1882` — updates revision+persists (`:1840`), unchanged is no-op (`:1858`), unknown-id `.notFound` (`:1877`); version-4 absent-keys payload (`:2221`).
- **`ChecklistMergeTests.swift`**: numbering toggle newest-editor-wins (`:756,:771`).
- **Watch store**: `WatchChecklistStoreTests.swift` current-version and version-2 decode paths (`:22,:36,:51`).
- **No edit-checklist/`numberReminders` view test file exists** — the checklist-detail view is covered by `ChecklistDetailViewTests.swift` (`@MainActor :13`, `#if os(macOS)` gates at `:72,:164,:179,:238,:260,:276`).
- **Platform gating / actor isolation**: whole-file `#if os(macOS)` (`MacWindowFrameTests.swift:1`, `ColorCrossPlatformTests.swift:5`); per-region `#if os` in many view suites. `@MainActor` opt-in is near-universal (codec/sync/store suites). UI smoke `CheckStitchUITests.swift` `#if os(iOS)` (`:34`), XCTest (`:1`), `runsForEachTargetApplicationUIConfiguration=false` (`:8`).

## Cross-Cutting Observations
- **Additive per-checklist boolean precedent is `prefixesReminderNumbers`**: a new `Checklist` boolean rides `decodeIfPresent ?? default`, no `currentVersion` bump, encode unconditional, and shares the checklist coarse `revision`/`modifiedAt` clock. The watch sees it automatically because `Checklist` travels whole.
- **All existing stored booleans default to `false`** (`prefixesReminderNumbers`, `isCollapsed`). A default-enabled flag is a new convention here but still a valid `decodeIfPresent ?? true` additive field.
- **Store mutation contract** is uniform: `set<Field>(_ value:, for id:) -> SetDestinationOutcome` (guard notFound → no-op if unchanged → mutate → bump `revision`/`modifiedAt` → `scheduleSave()`).
- **Folder membership is always derived from `folderID`**; folder-hiding must be computed over `store.checklists` / `viewModel.checklists(in:)`, never a folder-side pointer.
- **Localization** for this feature's string lands in the App catalog (`CheckStitch/Localizable.xcstrings`) with a `requiredKeys` entry + six translations.

## Open Areas
- **Store `scheduleSave()` persistence internals** were not fully traced (shared by all store mutations, `ChecklistStore.swift:282`); relevant only insofar as the new field's save is identical to existing ones.
- **Default-true semantics**: every existing stored boolean defaults to `false`, so confirming the decode-default and codec-round-trip tests for a `default true` additive field (and any merge newest-editor-wins expectations) is design/test work beyond this pass.
- Exact watch view-model shape for computing "folder all-members-hidden" is an implementation matter; the derivation primitives (`checklists(in:)`, `store.checklists`) exist.
