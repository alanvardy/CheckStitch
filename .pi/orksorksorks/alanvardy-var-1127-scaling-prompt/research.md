# Research Findings

Source: 6 delegated reports (Q1–Q6) + branch-overlap check. Paths relative to
repo root unless noted. Core package = `CheckStitchCore/Sources/CheckStitchCore/`.

## Q1: How is the checklist scaling value stored, validated/clamped, and encoded/decoded, including backward compatibility?

### Findings
- Stored as `Checklist.multiple: Int`, default 1 (no scaling), doc-commented
  as an additive key — `Checklist.swift:233` (init default `:178`, property
  decl `:199`).
- Single range source: `public static let multipleRange: ClosedRange<Int> = 1...99`
  — `Checklist.swift:344`; single clamp helper
  `clampedMultiple(_:) = min(max(value, lower), upper)` — `Checklist.swift:348-349`.
- Encode/decode inside `Checklist`'s `Codable` conformance (no separate codec
  file): `CodingKeys` includes `multiple` — `Checklist.swift:266-268`; decode
  clamps and defaults —
  `clampedMultiple(try container.decodeIfPresent(Int.self, forKey: .multiple) ?? 1)`
  `Checklist.swift:281`; encode writes the key unconditionally
  ("encoder writes every key" invariant) — `Checklist.swift:312`.
- Out-of-range numeric values are clamped, never rejected; only a future
  *version* yields `.unsupportedVersion` (`multiple` is not a version gate).
- Codec versioning: `ChecklistCodec.currentVersion = 5` — `Checklist.swift:564`;
  `classify(_:)` probes `version` first via `VersionProbe` — `Checklist.swift:591-623`
  (`:660`), returning `.loaded` (v5 `:595`), `.migratable` (v4/v3/v2/v1 `:598-616`),
  `.unsupportedVersion` (`:617-622`), `.unreadable` (`:623-625`).
- Store load handling: v1 restamps sync state, v2 seeds ordering, v3+ verbatim;
  `.unsupportedVersion` → empty + `canOverwriteStoredPayload = false`
  — `ChecklistStore.swift:71-116` (flag `:103-106`).
- `multiple` rides the checklist's **coarse** `revision`/`modifiedAt` clock —
  no per-field clock (unlike items) — `Checklist.swift:228-237`.
- Additive-optional precedent: `prefixesReminderNumbers`, `showsOnWatch`,
  `destinationListIdentifier` also decode via `decodeIfPresent` with no version
  bump (see `Checklist.swift:280-284`).

## Q2: How does the in-app run flow work, and what role does `multipleOverride` play?

### Findings
- App entry: per-row button `createRemindersButton(for:)` action
  `Task { await runVM.createReminders(for: id) }` — `ContentView.swift:727-751`
  (action `:730`, disable while `runVM.creating` `:748`).
- App view model: `CheckStitch/ChecklistRunViewModel.swift:38` `@MainActor @Observable`
  `createReminders(for:)` — duplicate-tap guard + `hasRunnableItems` `:39-41`,
  `creating.insert` `:43`, spinner `:47`, `RunGate(counter,isUnlocked)` `:52-53`,
  calls `ChecklistReminders.create(from:targeting:gate:)` **without**
  `multipleOverride` `:57`.
- Shared funnel: `ChecklistReminders.swift:26`
  `create(from:targeting:gate:multipleOverride: Int? = nil)`; `:31`
  `gate.reserveRun()`; `:34` `let multiple = multipleOverride ?? checklist.multiple`;
  per-item loop `:49-68` resolves title via
  `ChecklistTitleNumbering.title(ChecklistScaling.resolve(title, multiple), ...)`
  and notes via `resolve(description, multiple)`; release on
  `destinationMissing` `:44-45`; `permissionDenied` `:37-40`; mid-loop throw →
  `partiallyCreated`, zero → `created(0)` `:73-76`.
- Scaling resolver: `ChecklistCreator.swift:34-57` `enum ChecklistScaling`,
  pure; no-op at `multiple == 1` or no `((`; multiplies `((n))` markers with
  `multipliedReportingOverflow` guard `:60-64`; unknown/overflowing marker left
  literal.
- Intent path passes the override: `RunChecklistIntent.swift:97-101`
  `create(..., multipleOverride: multiple)` where `@Parameter multiple: Int?`
  (`:44`) is range-validated at `:79-81`.
- `multipleOverride` is **per-run only** — merged over stored `multiple`, never
  written back; app-side persistence is the separate
  `multipleBinding → store.setMultiple` (`ChecklistDetailView.swift:311-315`).
- Outcome → UI switch: `.created` flash, `.purchaseRequired` paywall,
  destination/permission/partial/failed set `runErrorMessage`
  — `ChecklistRunViewModel.swift:63-76`.

## Q3: How do existing App Intents declare params, validate, error, and prompt?

### Findings
- Intent files (all Core): `RunChecklistIntent.swift`, `CreateChecklistIntent.swift`,
  `ListChecklistsIntent.swift`, `ChecklistEntity.swift`,
  `ChecklistConfigurationIntent.swift`, `MultiChecklistConfigurationIntent.swift`;
  provider `CheckStitch/Intents/CheckStitchShortcuts.swift`.
- `RunChecklistIntent` — `AppIntent`, `openAppWhenRun = false`
  `RunChecklistIntent.swift:22-24`; params `@Parameter checklist: ChecklistEntity`
  `:27-28` and `@Parameter multiple: Int?` `:30-31`;
  `parameterSummary Summary("Run $checklist")` `:50-52`.
- `perform()` validation order: UUID+existence+not-archived guard → throw
  `.checklistNotFound` `:61-65`; range guard before any side effect →
  `.invalidMultiple` `:69-71`; EventKit permission handled as a **status
  pre-check** returning a dialog, never a prompt from inside the intent
  `:74-83`; then `runState.beginRun/finishRun` and the create call `:84-99`.
- Errors: `RunChecklistIntentError: LocalizedError` (`.checklistNotFound`,
  `.invalidMultiple`) `:7-21`; `errorDescription` uses
  `LocalizedStringResource(...).resolvedInAppLanguage()`.
- Dialogs: `perform()` returns `some IntentResult & ProvidesDialog`;
  `IntentDialog(...)` built from `RunChecklistDialogue`
  (`:111-117`, outcome mapping `:119-143`), kept separate for unit tests.
- Interactive prompting in repo: **none**. No `requestValue`,
  `requestConfirmation`, `needValue`, or `progress(...)` anywhere in source;
  inputs are declarative `@Parameter` presence/type plus imperative
  guard/throw/`IntentDialog`.
- The only interactive parameter-prompting is framework-driven entity picking:
  `ChecklistEntityQuery: EntityStringQuery` (`ChecklistEntity.swift:24-51`),
  backing `@Parameter` entity vars via `entities(for:)` `:33-40`,
  `entities(matching:)` `:41-47`, `suggestedEntities()` `:48-51`.
- Widget config intents use optional entity params:
  `ChecklistConfigurationIntent.swift:9-10` (`ChecklistEntity?`);
  `MultiChecklistConfigurationIntent` (`[ChecklistEntity]?`).
- `CreateChecklistIntent` precedent: `@Parameter String` + `[String]`, trims,
  throws `.blankName`/`.noItems`, returns dialog — `CreateChecklistIntent.swift:21-65`.

## Q4: How do UI surfaces edit/display the scaling value, and where are platform branches?

### Findings
- Detail-view edit: dedicated Scaling `Section` built at
  `ChecklistDetailView.swift:81` (footer explains `((n))`), placed between the
  numbering toggle and the "Show on watch" section.
- `scalingField(checklistID:)` `:324-344` is a **typed number field**
  (`LabeledContent("Scaling")` + `TextField(... format: .number)`), not a
  Stepper. Platform branch: `#if os(iOS)` adds `.keyboardType(.numberPad)`
  `:326-334`; the `#else` arm omits it `:335-342`; both share the a11y id
  `checklistScalingField` (comment `:318-323` explains the duplication of
  distinct opaque view types).
- Binding writes through the store: `multipleBinding` get/set
  (`store.checklist(id:)?.multiple ?? 1` / `store.setMultiple`) `:311-314`;
  setter clamps and no-ops on unchanged (`ChecklistStore.swift:388-402`).
- Display: `multiple` passed into each `ItemRow` `:100`; title resolved
  `:423`; `×N` badge only when `showsScalingFactor` (`multiple > 1`) `:425-435`,
  a11y id `scalingFactorBadge`, with the `×%lld` App-catalog string resolved at
  runtime because symbol generation cannot derive an identifier from `×%lld`
  (comment `:426-431`); description resolved in the footnote `:442`.
- Watch: display-only, no editor/badge —
  `CheckStitchWatch/WatchChecklistDetailView.swift:53-55` resolve via
  `current.multiple` (live store copy `:25-27`).
- Widget config surfaces contain no scaling references (no
  `scal|multiple|template` matches in `CheckStitchWidget/`).

## Q5: How do persistence and sync carry checklist fields?

### Findings
- Store is `@MainActor @Observable`, holding checklists/tombstones/folders and
  folder tombstones `ChecklistStore.swift:9-20`; `envelope` wraps all four +
  version + deviceID `:118-126`.
- Save path: `scheduleSave()` coalesces text edits over 300 ms `:785`;
  structural edits call `save()` directly; `save()` cancels pending save,
  encodes, writes UserDefaults, fires `onChange` unless applying remote
  `:799-815`. `apply(remote:)` = LWW entry → `ChecklistMerge.merge` +
  `normalizedOrder` + idempotence guard, saves with `isApplyingRemote`
  `:732-757`; `reconcileFromDefaults()` `:760-780`.
- LWW: `wins()` orders by higher `revision`, then newer `modifiedAt`, then
  lexicographically smaller `deviceID` — `ChecklistMerge.swift:272-277`.
  `mergedChecklists` `:121-177` overwrites, on a checklist win,
  `name, destinationListIdentifier, prefixesReminderNumbers, showsOnWatch,
  multiple, folderID, isArchived, archivedAt, revision, modifiedAt` `:137-148`;
  order merged separately `:155-169`. Items use a coarse clock plus per-field
  wins for `title/description/relativeDate/priority/isEnabled` `:178-244`.
- Duplicate/fresh-copy: `duplicate(id:name:)` `ChecklistStore.swift:249-272`
  and `freshCopy` (import) `:274-296` both carry destination, prefixes,
  `showsOnWatch`, `multiple`, folderID/archived state; note item `isEnabled`
  is **not** passed, so copies reset to enabled=true (descriptive asymmetry).
  `importInsert` `:299-310`, `importReplace` (tombstone + insert one save)
  `:313-326`.
- Export: `ChecklistExport.swift:11-23` takes selected checklists with
  `deviceID ""`, no tombstones/folder tombstones, only referenced folders;
  carries full item fields incl. `isEnabled` and `multiple`.
- Watch sync transport is latest-wins, not LWW:
  `ChecklistSyncCoordinator.swift:47-60` encodes `ChecklistEnvelope` from
  `snapshot()/folders()`, keyed by `ChecklistSyncKey` (`ChecklistSync.swift:8-19`);
  language goes via `transferUserInfo`, not context.
- All four paths (setter, LWW merge, duplicate/fresh-copy, export) already
  carry `multiple`; only item `isEnabled` is dropped by duplicate/import.

## Q6: What test-suite and localization conventions apply?

### Findings
- Targets: `CheckStitchTests/` (Swift Testing + legacy XCTest store/codec
  suites, macOS-hosted) and `CheckStitchUITests/` (one XCTest smoke)
  `AGENTS.md:13`. Unit suites `@testable import CheckStitchCore`; test targets
  do not set `SWIFT_DEFAULT_ACTOR_ISOLATION` (opt-in `@MainActor`).
- Gate `./scripts/test.sh` `AGENTS.md:35` (`scripts/test.sh:1-8`): sim build →
  headless pre-boot → `make test` → `make build-mac` → `make watch-build` →
  `scripts/tests/run.sh` → shellcheck → `gate: ok`. Fast: `make test-unit`
  (macOS, `CODE_SIGNING_ALLOWED=NO`).
- Suite styles by area: codec is XCTest `final class ChecklistCodecTests: XCTestCase`
  `@MainActor` `ChecklistCodecTests.swift:5-16`; run path/intents/view model are
  Swift Testing structs with `#expect` — `RunChecklistIntentTests.swift:8-12`,
  `ChecklistRunViewModelTests.swift:7,49,63` (table-driven
  `@Test(arguments:)`); detail view describes the view value via
  `String(describing:)` `ChecklistDetailViewTests.swift:1-19`.
- Fixtures/doubles: `TestFixtures.swift` (`makeItem`, `makeIsolatedDefaults`,
  `SpyReminderCreator`, `SpyReminderDestination`, shared `sharedTestEventStore`
  that must outlive reminders to avoid SIGTRAP) `:1-61`.
- Platform gating: whole-case/per-test `#if os(...)` — e.g.
  `ColorCrossPlatformTests.swift:5,15`, many macOS branches in
  `ChecklistDetailViewTests.swift:72,165,181,207,277,299,315,350`,
  `InterfaceSettingsViewTests.swift:12,29,37`.
- Localization: four catalogs (App `CheckStitch/Localizable.xcstrings`, Core
  `.../Resources/Localizable.xcstrings`, Watch, Widget) `scripts/l10n-check.sh:13-18`;
  six languages en/de/es/fr/ja/zh-Hans `:10-11`.
- `LocalizationFixtures.requiredKeys` is a `[(catalog, keys)]` list every key
  must join `LocalizationFixtures.swift:8-17` (App list `:18+`);
  `LocalizationTests.swift` checks parse/non-empty en `:9-19`, six languages
  `:22-28`, required keys `:34-41`, Watch carries every UI key `:46-51`,
  non-English-differs canary `:56-64`, embedded bundles `:70-100`.
  `scripts/l10n-check.sh:37-44` mirrors the canary with exclusion entries.
- Pinned-locale helpers (`String.en`, `resolved(locale:)`)
  `LocalizationTestHelpers.swift:1-17`; catalog keys must be resolved as
  resources, not eager `String(localized:)`
  (`WatchChecklistDetailView.swift:31`, `PrivacySettingsContent.swift:29`).
- Intent UI strings live in the app catalog, e.g.
  `RunChecklistIntent.swift:117`.

## Cross-Cutting Observations

- **Additive-key convention**: new optional `Codable` keys decode with
  `decodeIfPresent` + default/clamp and no `currentVersion` bump
  (`multiple` `Checklist.swift:280-284`; `prefixesReminderNumbers`,
  `showsOnWatch` likewise). `currentVersion` currently 5 `:564`.
- **One clamp source**: `multipleRange`/`clampedMultiple`
  (`Checklist.swift:344-349`) is applied at codec decode `:281`, store setter
  (`ChecklistStore.swift:393-397`), and intent validation
  (`RunChecklistIntent.swift:70`).
- **Funnel contract**: both consum points (`ChecklistRunViewModel.swift:57`
  and `RunChecklistIntent.swift:97-101`) reach
  `ChecklistReminders.create(..., multipleOverride:)`; the app passes nil, the
  intent passes its parameter. `multipleOverride` is never persisted
  (`ChecklistReminders.swift:34`).
- **Clock granularity**: checklist-level fields ride the coarse
  `revision`/`modifiedAt`; items have per-field clocks for
  `title/description/relativeDate/priority/isEnabled` (`ChecklistMerge.swift:178-244`).
- **Intents are non-interactive today**: no `requestValue` /
  `requestConfirmation` / `needValue` / `progress` usage; only entity-query
  prompting (`ChecklistEntity.swift:24-51`) and status-precheck dialogs
  (`RunChecklistIntent.swift:74-83`).
- **Localization**: any new UI string needs all 6 languages plus a
  `requiredKeys` entry and a passing `scripts/l10n-check.sh`/gate.
- **Branch overlap**: sibling `origin/alanvardy-var-809-scaling-templates`
  is stale relative to main (main already contains the scaling implementation;
  two-dot diff shows main is ~3400 lines ahead, i.e. 809 lacks later VAR-1114
  archive / VAR-1117 enabled work). Sibling
  `origin/alanvardy-var-1128-add-prompt-to-destination-checklist`'s diff vs
  main is only a `DELETEME` placeholder — no relevant changes. No overlap risk
  from either.

## Open Areas

- No repo precedent for App Intents interactive numeric input; the intent-side
  behavior for a scaling *mode* (prompt vs. default) is unprecedented and not
  answered by the codebase (Q3).
- The in-app run path has no numeric input today; the only numeric field is the
  detail-view `TextField` (Q4).
- `ChecklistCodec` is embedded in `Checklist.swift` (no separate file); the
  version-classify paths are exercised only for existing field shapes.
- Semantics of a stored scaling *mode* versus the existing per-run
  `multipleOverride` are not determined by existing code (both funnel
  independently) — a design decision, not a research finding.
- Watch and widget surfaces show no scaling editor; whether a mode needs any
  display change there is unresolved by the codebase.