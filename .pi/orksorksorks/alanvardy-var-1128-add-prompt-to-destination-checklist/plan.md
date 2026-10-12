# Implementation Plan

## Overview

Replace `Checklist.destinationListIdentifier: String?` with a typed
`ChecklistDestination` (`.systemDefault` / `.list(id)` / `.prompt`) encoded under
a new `destination` key, bump `ChecklistCodec.currentVersion` 5 → 6 with a
tolerant v5 decode, and thread an optional destination override through the one
run funnel so `prompt` resolves at Run time in the app sheet, the intent, the
widget deep-link, and the watch reply.

## Structure corrections (read first)

Four points in `structure.md` do not match the tree; this plan uses the tree:

1. **There is no `ChecklistCodec.swift`.** `ChecklistCodec` lives in
   `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` (lines ~563–642).
   All codec edits target `Checklist.swift`.
2. **The intent dialogue string goes in the App catalog, not Core.**
   `RunChecklistDialogue` builds `LocalizedStringResource(..., bundle: .main)`
   and every sibling ("Open CheckStitch and allow Reminders access…",
   "That list no longer exists…") is a key in
   `CheckStitch/Localizable.xcstrings`. A Core-catalog key cannot resolve from
   `.main` (`Bundle.core` is the package bundle — see
   `LocalizationTests.coreCatalogValuesAreEmbeddedInTheResourceBundle`).
3. **Phase 3 also needs `ChecklistCore/.../ChecklistWidgetDisplayModel.swift`.**
   The widget row must carry the prompt flag for the views to branch on; the
   structure's file list omitted it.
4. **No Watch catalog key.** `RunPhase.detail` / `RunResultKind.message` are
   plain `String`s in Core and are not localized in this repo (`WatchChecklistDetailView`
   renders `Text(detail)`); the watch copy for the new kind is a plain English
   `RunResultKind.message` string, matching `.destinationMissing`. Also, the
   Phase 1 sheet needs a confirm-button label, so "Run" is a 5th App key.

Everything else follows `structure.md`'s phase order and vertical shape.

---

## Phase 0: Horizontal prerequisite — `ChecklistDestination` model + codec v6

No user-visible change; validates the schema across codec/store/merge/export/sync.
This is intentionally the one horizontal phase (the enum replaces the persisted
field at every call site; no vertical slice can land while the type is half-converted).

### Changes

#### 1. `ChecklistDestination` enum

**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify (add type above `public struct Checklist`)

```swift
/// A checklist's run destination: the system default list, one concrete
/// Reminders list, or "ask at run time". `nil`/absent legacy payloads decode to
/// `.systemDefault`, so a v5 checklist keeps today's behaviour.
public enum ChecklistDestination: Codable, Equatable, Hashable, Sendable {
    case systemDefault
    case list(String)
    case prompt

    private enum CodingKeys: String, CodingKey { case list }

    public init(from decoder: Decoder) throws {
        // Single-value form: "systemDefault" / "prompt".
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            switch raw {
            case "systemDefault": self = .systemDefault; return
            case "prompt": self = .prompt; return
            default: break
            }
        }
        // Keyed form: {"list":"<calendarIdentifier>"}.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .list(try container.decode(String.self, forKey: .list))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .systemDefault, .prompt:
            var single = encoder.singleValueContainer()
            try single.encode(self == .systemDefault ? "systemDefault" : "prompt")
        case .list(let identifier):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identifier, forKey: .list)
        }
    }
}
```

#### 2. `Checklist` field, init, coding, decode fallback, encode

**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

- Memberwise init param: `destinationListIdentifier: String? = nil` →
  `destination: ChecklistDestination = .systemDefault`; assignment
  `self.destination = destination`.
- Stored property:
  ```swift
  /// Where a run creates its reminders. `.prompt` means "ask at run time" and is
  /// deliberately distinct from `.systemDefault` (design decision 1). Shares the
  /// checklist's coarse `revision`/`modifiedAt` clock (like the name).
  public var destination: ChecklistDestination
  ```
- `CodingKeys` adds `destination` and keeps `destinationListIdentifier` (read
  only, for the v5→v6 path): 
  ```swift
  case id, name, items, destination, destinationListIdentifier,
       prefixesReminderNumbers, showsOnWatch, multiple, folderID, isArchived, archivedAt
  case modifiedAt, revision, itemOrder, orderRevision, orderModifiedAt
  ```
- In `init(from:)` replace the `destinationListIdentifier` read with:
  ```swift
  // v6 key first; a v5 (or earlier) payload has no `destination`, so fall back
  // to the legacy string: absent/null → `.systemDefault`, value → `.list(id)`.
  let destination: ChecklistDestination
  if let decoded = try container.decodeIfPresent(ChecklistDestination.self, forKey: .destination) {
      destination = decoded
  } else if let legacy = try container.decodeIfPresent(String.self, forKey: .destinationListIdentifier) {
      destination = .list(legacy)
  } else {
      destination = .systemDefault
  }
  ```
  Pass `destination: destination` to the self-heal `Checklist(...)` call.
- In `encode(to:)` replace the legacy line with
  `try container.encode(destination, forKey: .destination)` (the legacy key is
  never encoded).

#### 3. `ChecklistCodec` version + v5 classification

**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` (~line 563)
**Action**: modify

```swift
public static let currentVersion = 6
```

Add a `case 5:` arm above `case 4:` in `classify`:

```swift
case 5:
    // v5 carries full sync/ordering/folder state; only the destination key was
    // renamed and is recovered by `Checklist.init(from:)`'s legacy fallback.
    let previous = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
    return .migratable(from: 5, envelope: previous)
```

All `.migratable` consumers (`ChecklistStore.init` `default:` branch,
`ChecklistSyncService.reconcileNow` `default:` branch,
`ChecklistImportSession.decoded` `default:` branch,
`WatchChecklistStore.receive(.context)` `from >= 2` guard) already load v3+
verbatim, so `from: 5` needs **no** new consumer arms. Confirm by reading the
four switch sites; do not add branches. Update the `currentVersion` doc comment
if it names 5.

#### 4. Store

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

- `duplicate` (~:257) and `freshCopy` (~:282): `destination: source.destination`
  / `destination: checklist.destination`.
- `setDestination` (~:346) signature and body:
  ```swift
  public func setDestination(_ destination: ChecklistDestination, for id: UUID) -> SetDestinationOutcome {
      guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
      checklists[index].destination = destination
      checklists[index].revision += 1
      checklists[index].modifiedAt = now()
      scheduleSave()
      return .updated
  }
  ```
- Fix doc comments that say `destinationListIdentifier`.

#### 5. Merge

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistMerge.swift`
**Action**: modify

`merged.destinationListIdentifier = remoteChecklist.destinationListIdentifier`
(~:150) → `merged.destination = remoteChecklist.destination`.

#### 6. Funnel (Phase 0 form: behaviour-preserving)

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistReminders.swift`
**Action**: modify

Replace the resolve call:
```swift
let identifier: String? = switch checklist.destination {
case .systemDefault: nil
case .list(let id): id
case .prompt: nil  // Phase 1 makes this unreachable
}
guard let destination = snapshot.resolve(identifier) else {
    gate.releaseRun()
    return .destinationMissing
}
```
(Phase 1 replaces this block with the override/`.destinationRequired` flow.)

#### 7. Detail picker binding + staleness (Phase 0 form: two rows)

**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

- Picker rows (~:55): 
  ```swift
  Text("Default (Inbox)").tag(ChecklistDestination.systemDefault)
  ForEach(listsSnapshot?.selectableOptions ?? []) { list in
      Text(list.title).tag(ChecklistDestination.list(list.id))
  }
  ```
- `destinationBinding` (~:361) → `Binding<ChecklistDestination>`:
  ```swift
  get: {
      let stored = store.checklist(id: checklistID)?.destination ?? .systemDefault
      // A stored id that *is* the system default renders as the default row.
      if case .list(let id) = stored, let listsSnapshot,
         listsSnapshot.pickerSelection(for: id) == nil {
          return .systemDefault
      }
      return stored
  },
  set: { store.setDestination($0, for: checklistID) }
  ```
- `destinationIsStale` (~:287):
  ```swift
  guard !destinationUnavailable,
        let listsSnapshot,
        case .list(let id) = store.checklist(id: checklistID)?.destination,
        listsSnapshot.pickerSelection(for: id) != nil
  else { return false }
  return !listsSnapshot.selectableOptions.contains { $0.id == id }
  ```

#### 8. Mechanical test call-site migration

**Files**: `CheckStitchTests/ChecklistStoreTests.swift`,
`ChecklistMergeTests.swift`, `ChecklistCodecTests.swift`,
`ChecklistExportTests.swift`, `ChecklistImportSessionTests.swift`,
`ChecklistImportExportViewModelTests.swift`, `WatchChecklistStoreTests.swift`,
`ChecklistRemindersTests.swift`
**Action**: modify

Apply this replacement rule everywhere:
- `destinationListIdentifier: "X"` → `destination: .list("X")`
- `destinationListIdentifier: nil` → `destination: .systemDefault` (or drop the arg)
- `?.destinationListIdentifier == "X"` → `?.destination == .list("X")`
- `?.destinationListIdentifier` in an `XCTAssertNil`/`== nil` → `.destination == .systemDefault`
- helper params `destination: String?` (`ChecklistMergeTests.swift:1222`,
  `ChecklistCodecTests.swift` ~:2552) → `destination: ChecklistDestination = .systemDefault`

**Codec-test version fallout** (the one non-mechanical part):
`ChecklistCodecTests.swift` hardcodes `"version":5` in ~10 tests that mean
"current version" and bind `case .loaded(let envelope)`. With `currentVersion == 6`
those now classify `.migratable(from: 5, …)`. Fix by leaving the `"version":5`
literal (they are now genuine v5-payload tests) and reading the envelope through
a new helper:

```swift
/// The envelope from either a current-version or a migrated payload, so
/// additive-field tests survive a version bump.
private func decodedEnvelope(_ data: Data) -> ChecklistEnvelope? {
    switch ChecklistCodec.classify(data) {
    case .loaded(let envelope), .migratable(_, let envelope): return envelope
    case .unsupportedVersion, .unreadable: return nil
    }
}
```

Replace the `guard case .loaded...` + `envelope` uses in:
`testDecodesV5PayloadWithoutPrefixesReminderNumbersAsFalse` (:169),
`testDecodesV5PayloadWithoutShowsOnWatchAsShown` (:194),
`testDecodesItemWithoutIsEnabledAsTrue` (:219),
`testDecodesV5PayloadWithoutArchiveKeysAsActive` (:265),
`testPayloadWithUnrecognizedKeyStillClassifiesLoaded` (:293),
the two self-heal tests (:308, :341), the clock test (:402),
`testFolderWithoutCollapseKeyDecodesToFalse` (:483), and
`testV5PayloadWithoutArchiveKeysStaysLoaded` (:497) — the last two need the
envelope (folders), so the helper is required.

Also:
- `testFutureVersionIsUnsupported` (:99) `"version":6` → `"version":\#(ChecklistCodec.currentVersion + 1)`.
- Update the stale comment at ~:553 ("only knows versions 1...5") and keep
  `PinnedV4Codec`; add a `PinnedV5Codec` (switch `case 1...5: .loaded`) with
  `testV6PayloadIsUnsupportedByAPinnedV5Decoder`.

No change needed to `ChecklistListViewModelTests.unknownFolderIsRenderedAsLoose`
(:124): a v5 payload still loads through the store's `default:` migration branch.

### Verification

#### Automated
- [x] `make test-unit` passes (all codec/store/merge/export/import/sync suites green)
- [x] `make build` clean — no `destinationListIdentifier` compiler use remains:
      `grep -rn "destinationListIdentifier" --include='*.swift' .` returns only the
      `CodingKeys`/legacy-decode fallback in `Checklist.swift` (+ doc comments)
- [x] New/updated codec tests: v5 payload with no key → `.systemDefault`; v5 payload
      with `destinationListIdentifier:"list-a"` → `.list("list-a")`; v6 round-trip
      of all three cases; absent `destination` key on a v6 payload → `.systemDefault`;
      `PinnedV5Codec` rejects v6 bytes
- [x] `ChecklistMergeTests` winner carries `.prompt`; idempotence (`merged != envelope`) holds

#### Manual
- [ ] (none — no user-visible change)

---

## Phase 1: Walking skeleton — app prompt end to end

A user marks a checklist "Ask me each time" in the detail picker, taps Run, picks
a list from the app sheet, and reminders land in that list exactly once, without
the choice persisting.

### Changes

#### 1. `ReminderRunOutcome.destinationRequired`

**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`
**Action**: modify

```swift
case destinationRequired
```
`errorMessage`:
```swift
case .destinationRequired: return "Choose a list before running this checklist."
```
(Distinct from `.destinationMissing`, which is a stored list that vanished —
design decision 13.)

#### 2. Funnel override

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistReminders.swift`
**Action**: modify

Add a trailing `destination: ChecklistDestination? = nil` parameter to the shared
`create(from:targeting:gate:multipleOverride:destination:)` (call sites with
defaults stay source-compatible). Replace the Phase 0 identifier block:

```swift
guard try await targeting.requestAccess() else {
    gate.releaseRun()
    return .permissionDenied
}
// Prompt resolves at run time; a missing override is a refusal, not a default.
let chosen: ChecklistDestination
switch (checklist.destination, destination) {
case (.prompt, .some(let override)): chosen = override
case (.prompt, .none):
    gate.releaseRun()
    return .destinationRequired
default:
    chosen = checklist.destination
}
let snapshot = try await targeting.reminderLists()
let identifier: String? = { if case .list(let id) = chosen { return id }; return nil }()
guard let destination = snapshot.resolve(identifier) else {
    gate.releaseRun()
    return .destinationMissing
}
```

#### 3. Run view model: sheet state + two-phase run

**File**: `CheckStitch/ChecklistRunViewModel.swift`
**Action**: modify

Add published state:
```swift
/// The checklist whose run is waiting for a one-shot destination choice.
private(set) var destinationPrompt: Checklist?
private(set) var destinationOptions: [ReminderListOption] = []
private(set) var destinationDefaultIdentifier: String?
```

Refactor the run body into a private `perform(checklist:destination:)` that holds
the existing spinner/gate/outcome mapping. `createReminders(for:)` keeps its
guards and calls `perform(checklist: checklist, destination: nil)`. Add:

```swift
/// Runs again with the sheet's one-shot choice; never written back to the store.
func run(_ checklist: Checklist, in destination: ChecklistDestination) async {
    destinationPrompt = nil
    await perform(checklist: checklist, destination: destination)
}

/// Widget deep-link entry point (`checkstitch://run?checklist=<id>`).
func presentDestinationPrompt(forChecklistID id: UUID) async {
    guard let checklist = store.checklist(id: id),
          !checklist.isArchived, checklist.destination == .prompt,
          checklist.hasRunnableItems else { return }
    await presentPrompt(for: checklist)
}

func dismissDestinationPrompt() { destinationPrompt = nil }

private func presentPrompt(for checklist: Checklist) async {
    do {
        let snapshot = try await targeting.reminderLists()
        guard !snapshot.options.isEmpty || snapshot.defaultIdentifier != nil else {
            runErrorMessage = ReminderRunOutcome.destinationMissing.errorMessage
            return
        }
        destinationOptions = snapshot.selectableOptions
        destinationDefaultIdentifier = snapshot.defaultIdentifier
        destinationPrompt = checklist
    } catch {
        runErrorMessage = ReminderRunOutcome.permissionDenied.errorMessage
    }
}
```

Inside `perform`, add `.destinationRequired` to the switch:
```swift
case .destinationRequired:
    await presentPrompt(for: checklist)
```
`.destinationRequired` must **not** set `runErrorMessage` (it opens the sheet), and
`.prompt` stays stored — nothing is written back (design decision 7).

#### 4. `DestinationPromptSheet`

**File**: `CheckStitch/DestinationPromptSheet.swift`
**Action**: create (no `project.pbxproj` edit — `PBXFileSystemSynchronizedRootGroup`)

```swift
import CheckStitchCore
import SwiftUI

/// One-shot destination chooser for a `.prompt` checklist. Pure presentation:
/// `ChecklistRunViewModel` has already enumerated the options.
struct DestinationPromptSheet: View {
    let checklistName: String
    let options: [ReminderListOption]
    let defaultIdentifier: String?
    let onRun: (ChecklistDestination) -> Void
    let onCancel: () -> Void

    @State private var selection: ChecklistDestination = .systemDefault

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination list") {
                    Picker("List", selection: $selection) {
                        Text("Default (Inbox)").tag(ChecklistDestination.systemDefault)
                        ForEach(options) { list in
                            Text(list.title).tag(ChecklistDestination.list(list.id))
                        }
                    }
                    .accessibilityIdentifier("destinationPromptPicker")
                }
            }
            .navigationTitle("Choose a list")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run") { onRun(selection) }
                        .accessibilityIdentifier("destinationPromptRunButton")
                }
            }
        }
    }
}
```

#### 5. Present the sheet

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add beside the paywall sheet (~:188):
```swift
.sheet(item: Binding(get: { runVM.destinationPrompt },
                     set: { if $0 == nil { runVM.dismissDestinationPrompt() } })) { checklist in
    DestinationPromptSheet(
        checklistName: checklist.name,
        options: runVM.destinationOptions,
        defaultIdentifier: runVM.destinationDefaultIdentifier,
        onRun: { destination in
            Task { await runVM.run(checklist, in: destination) }
        },
        onCancel: { runVM.dismissDestinationPrompt() })
}
```

#### 6. Detail picker third row

**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

In the picker add the prompt row after the default row (before/after the list rows):
```swift
Text("Ask me each time").tag(ChecklistDestination.prompt)
```
The `destinationIsStale` guard stays `case .list`, so `.prompt` is never flagged
(Phase 5 pins this with a test).

#### 7. Localization (App catalog)

**Files**: `CheckStitch/Localizable.xcstrings`,
`CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add these App-catalog keys with all six languages (`en, de, es, fr, ja, zh-Hans`,
non-English differing from English) and a `requiredKeys` App entry for each:
- `"Ask me each time"`
- `"Default (Inbox)"`
- `"Choose a list"`
- `"Run"`

Run `bash scripts/l10n-check.sh` first; it is the fast static gate.

### Verification

#### Automated
- [x] `make test-unit` passes for `ChecklistRemindersTests`, `ChecklistRunViewModelTests`, `ReminderListsSnapshotTests`, `LocalizationTests`
- [x] New funnel tests: prompt + override `.list("list-a")` creates in `list-a`; prompt + `nil` → `.destinationRequired` and `spy.createdTitles.isEmpty`; non-prompt unchanged
- [x] New run-VM tests: prompt run sets `destinationPrompt` + `destinationOptions`; `run(_:in:)` creates in the chosen list and clears `destinationPrompt`; enumeration failure sets `runErrorMessage`
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `make build` clean

#### Manual
- [ ] `make run`; open a checklist → Destination list → tap **Ask me each time**; back out; tap Run; the sheet lists every Reminders list plus **Default (Inbox)**; pick one, tap Run; reminder lands in that list; re-open the detail picker → still **Ask me each time**

---

## Phase 2: Intent prompt — Siri & Shortcuts

Running a `.prompt` checklist from Siri/Shortcuts asks for the list through the
system parameter prompt (still `openAppWhenRun = false`); a headless call with no
presenter reports `.destinationRequired`.

### Changes

#### 1. `ReminderListEntity` + query

**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderListEntity.swift`
**Action**: create (modelled on `ChecklistEntity.swift`)

```swift
import AppIntents

/// Siri/Shortcuts identity for a Reminders list. `"default"` is the synthetic
/// system-default choice; every other id is `EKCalendar.calendarIdentifier`.
public struct ReminderListEntity: AppEntity {
    public static let defaultID = "default"
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Reminder List"
    public static var defaultQuery: ReminderListEntityQuery { ReminderListEntityQuery() }

    public let id: String
    public let name: String

    public init(id: String, name: String) { self.id = id; self.name = name }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

public struct ReminderListEntityQuery: EntityQuery {
    private let targeting: (any ReminderDestinationTargeting)?

    public init() { self.targeting = nil }
    public init(targeting: any ReminderDestinationTargeting) { self.targeting = targeting }

    private func currentTargeting() -> any ReminderDestinationTargeting {
        targeting ?? EventKitReminderDestination.shared
    }

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [ReminderListEntity] {
        let all = await allEntities()
        let wanted = Set(identifiers)
        return all.filter { wanted.contains($0.id) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [ReminderListEntity] {
        await allEntities()
    }

    /// Enumerates EventKit lists plus a synthetic default. Never prompts; a
    /// denied/unauthorized read degrades to the synthetic default only.
    @MainActor
    private func allEntities() async -> [ReminderListEntity] {
        let defaultEntity = ReminderListEntity(id: Self.defaultID, name: "Default (Inbox)")
        guard case .fullAccess = currentTargeting().accessStatus() else { return [defaultEntity] }
        guard let snapshot = try? await currentTargeting().reminderLists() else { return [defaultEntity] }
        return [defaultEntity] + snapshot.selectableOptions.map {
            ReminderListEntity(id: $0.id, name: $0.title)
        }
    }
}
```

`EntityQuery` (not `EntityStringQuery`) is enough: the parameter picker uses
`entities(for:)`/`suggestedEntities()`, and free-text search is not needed.

#### 2. Intent parameter + perform

**File**: `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift`
**Action**: modify

Add the parameter and an injectable query seam:
```swift
@Parameter(title: "List")
public var destination: ReminderListEntity?
```
(Use the existing `"List"` App-catalog key for the title.)

In `perform()`, after the access-status pre-check and the `multiple` validation,
before `runState.beginRun`:
```swift
var resolvedDestination: ChecklistDestination? = nil
if stored.destination == .prompt {
    if let entity = destination ?? (try? await $destination.requestValue()) {
        resolvedDestination = entity.id == ReminderListEntity.defaultID
            ? .systemDefault
            : .list(entity.id)
    } else {
        // No presenter (headless automation); report rather than silently default.
        return .result(dialog: IntentDialog(RunChecklistDialogue.destinationRequired))
    }
} else {
    resolvedDestination = stored.destination
}
```
Pass `destination: resolvedDestination` to `ChecklistReminders.create(...)`.
(`requestValue(_:) async throws -> Value.ValueType` is SDK-confirmed; the
`?? (try? await …)` collapses a user-cancel throw into the `.destinationRequired`
dialogue.)

#### 3. Dialogue case

**File**: `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift`
**Action**: modify

```swift
static let destinationRequired = LocalizedStringResource(
    "Open CheckStitch to choose a list, then run this checklist again.",
    table: "Localizable", bundle: .main)
```
Add `.destinationRequired` to `RunChecklistDialogue.message(for:checklistName:)`
returning `destinationRequired` (the funnel can still return it if the override
never arrived).

#### 4. Localization (App catalog)

**Files**: `CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add App keys (six languages + `requiredKeys`):
- `"Open CheckStitch to choose a list, then run this checklist again."`
- `"Reminder List"`

### Verification

#### Automated
- [x] `make test-unit` passes for `RunChecklistIntentTests`, `ChecklistEntityQueryTests` (new `ReminderListEntityQuery` cases)
- [x] Tests: prompt intent requests the value and passes `.list(id)` to the funnel; prompt + no value (headless) → `.destinationRequired`; non-prompt never calls `requestValue` (assert via injected spy/the `destination` param); unauthorized `allEntities()` returns only the synthetic default; synthetic default maps to `.systemDefault`
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `make build` clean

#### Manual
- [ ] In Shortcuts, add **Run Checklist**, choose a `.prompt` checklist; the run shows the list picker; picking a list creates reminders there. Delete the parameter value and run from a non-UI context → the `.destinationRequired` dialog appears

---

## Phase 3: Widget hand-off — prompt opens the app

A `.prompt` widget tile no longer runs headlessly; tapping it opens the app to
the prompt sheet for that checklist (and the unfiltered `onOpenURL` swallow is fixed).

### Changes

#### 1. Widget row carries the prompt flag

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidgetDisplayModel.swift`
**Action**: modify

Add `public let isPrompt: Bool` to `ChecklistWidgetRow` (init param, default
`false`), set in `ChecklistWidgetDisplayModel.init`:
```swift
isPrompt: checklist.destination == .prompt,
```

#### 2. Widget views

**Files**: `CheckStitchWidget/SingleChecklistWidget.swift`,
`CheckStitchWidget/MultiChecklistWidget.swift`
**Action**: modify

Add a shared local helper in each view:
```swift
private func widgetURL(for row: ChecklistWidgetRow) -> URL? {
    if row.needsAccess { return URL(string: "checkstitch://") }
    if row.isPrompt { return URL(string: "checkstitch://run?checklist=\(row.entityID)") }
    return nil
}
```
- Single: replace `.widgetURL(row.needsAccess ? URL(string: "checkstitch://") : nil)`
  with `.widgetURL(widgetURL(for: row))`; render a plain `runIcon(for: .play)` (no
  `Button(intent:)`) when `row.isPrompt`:
  ```swift
  if row.isRunnable {
      if row.isPrompt {
          runIcon(for: .play).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      } else {
          Button(intent: runIntent(for: row)) { runIcon(for: row.indicator) }
              .buttonStyle(.plain).disabled(row.indicator == .spinner)
              .accessibilityLabel("Create reminders")
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }
  }
  ```
- Multi: `.widgetURL(widgetURL(for: row))` on the row `HStack`; same
  `isPrompt`-withholds-the-button branch per row.

#### 3. Deep-link routing

**File**: `CheckStitch/ContentView.swift` (~:167)
**Action**: modify

```swift
.onOpenURL { url in
    if url.scheme == "checkstitch", url.host == "run",
       let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
           .queryItems?.first(where: { $0.name == "checklist" })?.value,
       let id = UUID(uuidString: raw) {
        Task { await runVM.presentDestinationPrompt(forChecklistID: id) }
        return
    }
    SharedImportInbox.shared.receive(url: url)
    consumePendingSharedImport()
}
```
Filter strictly (scheme + host) before the import path; malformed
`checkstitch://run` URLs fall through to the importer and are ignored there,
exactly like any other non-file URL.

### Verification

#### Automated
- [x] `make test-unit` passes for `ChecklistRunViewModelTests`, `SharedImportInboxTests`, `ChecklistWidgetDisplayModelTests`
- [x] Tests: `presentDestinationPrompt(forChecklistID:)` presents the sheet for a `.prompt` id and ignores a non-prompt id; `isPrompt` is set only for `.prompt` checklists; a non-`checkstitch` URL still imports; a malformed `checkstitch://run` URL does not present and does not import
- [x] `make widget-build` succeeds

#### Manual
- [ ] `make run`; add a widget for a `.prompt` checklist; tap the tile → app opens on the prompt sheet for that checklist; `checkstitch://` access prompts still work

---

## Phase 4: Watch reply — "Choose a list on iPhone"

A watch run of a `.prompt` checklist replies instead of creating. No destination
data crosses the boundary; the phone owns EventKit.

### Changes

#### 1. Wire kind

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

- `RunResultKind` add `case destinationRequired`.
- `init(_ outcome:)` add `case .destinationRequired: self = .destinationRequired`.
- `message` add `case .destinationRequired: "Choose a list on iPhone."` (plain
  English, matching the other Core reason strings; there is no Watch catalog entry
  because `RunPhase.detail` is a plain `String` — see structure corrections).
- `wireName` add `case .destinationRequired: "destinationRequired"`.
- `init?(wireName:count:total:)` add `case "destinationRequired": self = .destinationRequired`.
- `runResultDict` add `.destinationRequired` to the zero-payload group
  (`.permissionDenied, .destinationRequired, .destinationMissing, …: break`).
- `RunPhase` mapping in the `.runResult` receive arm adds `.destinationRequired`
  to the `.failed(result.kind.message)` group.

The wire name is additive; an older watch reading it fails `init?(wireName:)` and
rejects the message (its existing behavior for unknown kinds), never crashes.

#### 2. Coordinator

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
**Action**: no code change

`RunResultKind(outcome)` now maps the funnel's `.destinationRequired`; the
phone closure (`MyApp.swift:112`, `ChecklistReminders.create(from: $0)`) already
returns it for a `.prompt` checklist with no override. Add a coordinator test
pinning the reply.

### Verification

#### Automated
- [x] `make test-unit` passes for `ChecklistSyncMessageTests`, `ChecklistSyncCoordinatorTests`, `WatchChecklistStoreTests`
- [x] Tests: wire round-trip of `.destinationRequired` (userInfo → message → kind); coordinator's `createReminders` returning `.destinationRequired` replies with that kind; watch `store.run(...)` reaches the `.failed("Choose a list on iPhone.")` phase
- [x] `make watch-build` succeeds

#### Manual
- [ ] `bash scripts/run-watch.sh`; tap Run on a `.prompt` checklist on the Watch → the footer shows **Choose a list on iPhone.** and no reminders are created

---

## Phase 5: Hardening & edge states

Polish-only: pin the sad paths and access ordering deferred by the earlier slices.

### Changes

#### 1. Behaviour assertions/tests only (no new production surface)

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`
(only if a doc comment needs it), plus the test files below.
**Action**: test additions (and any small fix a failing test exposes)

Cases to pin:
- `ChecklistDestination` equality/Hashable under merge stress: a `.prompt` vs
  `.list` concurrent edit resolves by whole-checklist winner; `merged != envelope`
  idempotence holds for `.prompt`.
- Access ordering: intent `.notDetermined`/`.denied` dialogs still short-circuit
  *before* `requestValue`; the sheet is never shown with an empty list (VM routes
  to `destinationMissing`/`permissionDenied` text instead).
- `destinationIsStale` is `false` for `.prompt` and `.systemDefault`, and only
  `true` for a `.list` id absent from `selectableOptions`.
- Empty `ReminderListsSnapshot` (no options, no default) → `.destinationMissing`
  on a resolved prompt override, and the VM error path on presentation.
- Malformed deep links (`checkstitch://run` with a bad/missing id) neither present
  nor import.
- Cross-version: `canAcceptRemoteChanges` is `false` for a v6 payload read by a
  v5-pinned codec (`PinnedV5Codec`), and a v5 remote migrates on a v6 device.

**Test files**: `ChecklistRemindersTests.swift`, `ChecklistRunViewModelTests.swift`,
`ReminderListsSnapshotTests.swift`, `ChecklistMergeTests.swift`,
`RunChecklistIntentTests.swift`, `ChecklistCodecTests.swift`.

### Verification

#### Automated
- [x] `make test-unit` passes for all destination/run/intent/merge/codec suites
- [x] `./scripts/test.sh` prints `gate: ok` (build → sim test → build-mac → watch-build → shell tests → shellcheck)
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`

#### Manual
- [ ] `make run`: revoke Reminders access → Run a prompt checklist → the permission-denied message appears, no empty sheet; restore access and confirm the prompt flow still works
- [ ] Confirm the app still builds with warnings-as-errors (gate covers this)

---

## Files touched (completeness check)

| File | Phase | Action |
|---|---|---|
| `CheckStitchCore/.../Checklist.swift` | 0 | modify (enum, field, codec version/classify) |
| `CheckStitchCore/.../ChecklistStore.swift` | 0 | modify |
| `CheckStitchCore/.../ChecklistMerge.swift` | 0 | modify |
| `CheckStitchCore/.../ChecklistReminders.swift` | 0, 1 | modify |
| `CheckStitchCore/.../ReminderDestinationTargeting.swift` | 1, 5 | modify |
| `CheckStitchCore/.../ReminderListEntity.swift` | 2 | create |
| `CheckStitchCore/.../RunChecklistIntent.swift` | 2 | modify |
| `CheckStitchCore/.../ChecklistSync.swift` | 4 | modify |
| `CheckStitchCore/.../ChecklistSyncCoordinator.swift` | 4 | no code change (test only) |
| `CheckStitchCore/.../ChecklistWidgetDisplayModel.swift` | 3 | modify |
| `CheckStitch/ChecklistDetailView.swift` | 0, 1 | modify |
| `CheckStitch/ChecklistRunViewModel.swift` | 1, 5 | modify |
| `CheckStitch/ContentView.swift` | 1, 3 | modify |
| `CheckStitch/DestinationPromptSheet.swift` | 1 | create |
| `CheckStitch/Localizable.xcstrings` | 1, 2 | modify |
| `CheckStitchWidget/SingleChecklistWidget.swift` | 3 | modify |
| `CheckStitchWidget/MultiChecklistWidget.swift` | 3 | modify |
| `CheckStitchTests/*` (codec/store/merge/export/import/watch/reminders/run-VM/intent/widget-display/shared-inbox/localization) | 0–5 | modify |
| `CheckStitchTests/LocalizationFixtures.swift` | 1, 2 | modify |

Not touched (per design "What We're NOT Doing"): `ChecklistDetailView` third-row
writes only the enum; no per-field clock; no `String?` accessor; no new URL
scheme; no widget-config-intent destination parameter; no watch destination data.

## New user-facing strings (all six languages, each with a `LocalizationFixtures.requiredKeys` entry)

| Catalog | Key |
|---|---|
| App | `Ask me each time` |
| App | `Default (Inbox)` |
| App | `Choose a list` |
| App | `Run` |
| App | `Open CheckStitch to choose a list, then run this checklist again.` |
| App | `Reminder List` |

Not localized (matches existing Core reason strings):
`ReminderRunOutcome.destinationRequired.errorMessage` and
`RunResultKind.destinationRequired.message`.
