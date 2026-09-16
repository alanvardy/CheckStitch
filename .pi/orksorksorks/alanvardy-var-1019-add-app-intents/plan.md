# Implementation Plan

## Overview

Add two App Intents to the app target — **Run Checklist** (creates every
non-blank item of a chosen checklist as a Reminder through the production
`ChecklistReminders` + `ReminderDestinationTargeting` seam) and **List My
Checklists** (side-effect-free spoken query). Both return localized dialogue,
never prompt mid-intent, and report partial creation exactly.

**Verified up front (throwaway compile against this SDK, Swift 6 +
`-default-isolation MainActor`, the app target's settings):** `AppIntent`,
`@Parameter`, `AppEntity`/`EntityStringQuery`, `AppShortcutsProvider`,
`ProvidesDialog` + `IntentDialog`, `Summary` parameter summaries, and a
`static let`-based conformance all type-check. Two concrete constraints fell
out and are baked into the snippets below:

1. `static var title` / `typeDisplayRepresentation` / `openAppWhenRun` are
   *nonisolated* under app-target default isolation (protocol requirements are
   nonisolated), so they **must be `static let`** or the build fails with
   "not concurrency-safe … mutable global state".
2. `ReminderDestinationTargeting` must add `: Sendable`, otherwise storing
   `any ReminderDestinationTargeting` in the (Sendable) intent struct fails.
   A `@MainActor protocol P: Sendable` existential is itself Sendable, so this
   is a one-line Core change.

`String(localized: LocalizedStringResource)` does **not** exist on this SDK.
Tests resolve a `LocalizedStringResource` via its own `defaultValue` + `table`
parts (helper in Phase 1, verified to compile).

---

## Phase 1: Walking skeleton — "Run Groceries" creates the reminders, and says exactly what happened

### Changes

#### 0. Spike checkpoint (before writing real bodies)

**File**: `CheckStitch/Intents/SpikeIntent.swift` (temporary)
**Action**: create, verify, delete

A throwaway `struct SpikeIntent: AppIntent` with a trivial
`perform() -> some IntentResult` body plus a minimal
`AppShortcutsProvider`. Then:

- `make build` and `make build-mac` must both succeed.
- Confirm metadata extraction ran and produced an artifact:
  - `ls DerivedData/Build/Products/Debug-iphonesimulator/CheckStitch.app | rg -i appintents`
  - `ls DerivedData/Build/Products/Debug/CheckStitch.app/Contents/Resources | rg -i appintents`
  - Build log: `make build-mac 2>&1 | rg -i "ExtractAppIntentsMetadata|actionsdata"`
- **If metadata is missing/failing**: drop `CheckStitchShortcuts.swift`
  (design decision 9) — both intents stay reachable from Shortcuts.app — and
  record that in the completion artifact. Do **not** block the slice; delete
  `SpikeIntent.swift` either way and continue.

#### 1. Core seam — access status + Sendable

**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`
**Action**: modify

Add the status enum, add the protocol requirement, and make the protocol
`Sendable` (required so the intent can hold `any ReminderDestinationTargeting`;
all conformers are `@MainActor` classes, hence already Sendable).

```swift
/// Whether the app may create reminders right now, read without prompting.
public enum ReminderAccessStatus: Equatable, Sendable {
    case fullAccess
    case notDetermined
    case denied
}

@MainActor
public protocol ReminderDestinationTargeting: Sendable {
    func requestAccess() async throws -> Bool
    /// Status-only read: never triggers the system prompt (unlike
    /// `requestAccess()`), so intents can fail cleanly instead of prompting.
    func accessStatus() -> ReminderAccessStatus
    func reminderLists() async throws -> ReminderListsSnapshot
    func create(title: String, notes: String?, in list: ReminderListOption, dueDateComponents: DateComponents?) async throws
}
```

Leave `ReminderRunOutcome` untouched in this phase.

#### 2. Real adapter implements the status read

**File**: `CheckStitch/EventKitReminderDestination.swift`
**Action**: modify

```swift
func accessStatus() -> ReminderAccessStatus {
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .fullAccess: return .fullAccess
    case .notDetermined: return .notDetermined
    // .denied, .restricted, and .writeOnly all fail our read-then-create flow.
    default: return .denied
    }
}
```

Do **not** touch `requestAccess()` — the in-app path keeps using it.

#### 3. Entity + query

**File**: `CheckStitch/Intents/ChecklistEntity.swift`
**Action**: create (new `CheckStitch/Intents/` folder is inside the
`PBXFileSystemSynchronizedRootGroup` — no `project.pbxproj` edit)

```swift
import AppIntents
import CheckStitchCore

/// Siri-facing identity for a checklist. `id` is `Checklist.id.uuidString` — the
/// same stable, rename-proof key sync merges on, so a rename never orphans an
/// in-flight utterance.
struct ChecklistEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Checklist"
    static var defaultQuery: ChecklistEntityQuery { ChecklistEntityQuery() }

    let id: String
    let name: String

    init(id: String, name: String) { self.id = id; self.name = name }
    init(_ checklist: Checklist) { self.init(id: checklist.id.uuidString, name: checklist.name) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ChecklistEntityQuery: EntityStringQuery {
    private let store: ChecklistStore?

    init() { self.store = nil }
    init(store: ChecklistStore) { self.store = store }

    /// Fresh store per call when nothing is injected (design decision 7).
    @MainActor private func currentStore() -> ChecklistStore {
        store ?? ChecklistStore(defaults: AppGroup.defaults)
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ChecklistEntity] {
        let wanted = Set(identifiers)
        return currentStore().checklists
            .filter { wanted.contains($0.id.uuidString) }
            .map(ChecklistEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ChecklistEntity] {
        currentStore().checklists
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(ChecklistEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [ChecklistEntity] {
        currentStore().checklists.map(ChecklistEntity.init)
    }
}
```

Display order is `store.checklists` order (no sort), matching the app list.

#### 4. The run intent + its dialogue

**File**: `CheckStitch/Intents/RunChecklistIntent.swift`
**Action**: create

```swift
import AppIntents
import CheckStitchCore

/// Thrown when the entity id no longer resolves (checklist deleted between the
/// user's pick and `perform()`).
enum RunChecklistIntentError: LocalizedError {
    case checklistNotFound
    var errorDescription: String? {
        String(localized: "That checklist no longer exists.", table: "Localizable", bundle: .main)
    }
}

struct RunChecklistIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Checklist"
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Checklist")
    var checklist: ChecklistEntity

    // test seam; nil → fresh production collaborators
    private let injectedStore: ChecklistStore?
    private let injectedTargeting: (any ReminderDestinationTargeting)?

    init() { self.injectedStore = nil; self.injectedTargeting = nil }

    @MainActor
    init(store: ChecklistStore, targeting: ReminderDestinationTargeting) {
        self.injectedStore = store
        self.injectedTargeting = targeting
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$checklist)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = injectedStore ?? ChecklistStore(defaults: AppGroup.defaults)
        let targeting = injectedTargeting ?? EventKitReminderDestination.shared

        guard let uuid = UUID(uuidString: checklist.id),
              let stored = store.checklist(id: uuid)
        else { throw RunChecklistIntentError.checklistNotFound }

        // Status-only pre-check: a cold process may be unauthorized but must
        // never prompt from inside an intent.
        switch targeting.accessStatus() {
        case .fullAccess:
            break
        case .notDetermined:
            return .result(dialog: IntentDialog(RunChecklistDialogue.notDetermined))
        case .denied:
            return .result(dialog: IntentDialog(RunChecklistDialogue.denied))
        }

        let outcome = await ChecklistReminders.create(from: stored, targeting: targeting)
        return .result(dialog: IntentDialog(
            RunChecklistDialogue.message(for: outcome, checklistName: stored.name)))
    }
}

/// Outcome→speech mapping. Lives here (not in the intent body) so exact text is
/// unit-testable without a speech stack. Keys are in the app catalog.
enum RunChecklistDialogue {
    static let notDetermined = LocalizedStringResource(
        "Open CheckStitch and allow Reminders access, then ask again.",
        table: "Localizable", bundle: .main)
    static let denied = LocalizedStringResource(
        "CheckStitch doesn't have permission to access Reminders. Turn it on in Settings, then ask again.",
        table: "Localizable", bundle: .main)

    @MainActor
    static func message(for outcome: ReminderRunOutcome, checklistName: String) -> LocalizedStringResource {
        switch outcome {
        case .created(let count):
            return LocalizedStringResource(
                "Created \(count) reminders for \(checklistName).", table: "Localizable", bundle: .main)
        case .destinationMissing:
            return LocalizedStringResource(
                "That list no longer exists, so no reminders were created for \(checklistName).",
                table: "Localizable", bundle: .main)
        case .permissionDenied:
            return denied
        case .partiallyCreated:            // added in Phase 2
            return denied                  // replaced in Phase 2
        case .failed(let reason):
            return LocalizedStringResource(
                "Couldn't create reminders for \(checklistName): \(reason)", table: "Localizable", bundle: .main)
        }
    }
}
```

> In Phase 2 replace the `case .partiallyCreated` placeholder with the real
> partial-creation key. It is written this way now so Phase 1 compiles before
> the enum case exists — in Phase 1 the enum has no such case, so delete the
> placeholder line here and re-add it in Phase 2.

#### 5. Shortcuts provider

**File**: `CheckStitch/Intents/CheckStitchShortcuts.swift`
**Action**: create (only if the spike's metadata extraction succeeded)

```swift
import AppIntents

struct CheckStitchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunChecklistIntent(),
            phrases: [
                "Run \(\.$checklist) in \(.applicationName)",
                "Create reminders from \(\.$checklist) in \(.applicationName)",
            ],
            shortTitle: "Run Checklist",
            systemImageName: "checklist")
    }
}
```

#### 6. Catalog keys (all six languages)

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Every entry uses `"extractionState": "manual"` and six `localizations`
(`en`, `de`, `es`, `fr`, `ja`, `zh-Hans`), each a
`stringUnit` with `"state": "translated"`, exactly like the existing 63 keys.
Keys are source strings *with format specifiers* (`%lld`, `%@`) — that is what
`LocalizedStringResource` interpolations emit and look up by.

| Key (en) | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|
| `Created %lld reminders for %@.` | `%lld Erinnerungen für %@ erstellt.` | `Se crearon %lld recordatorios para %@.` | `%lld rappels créés pour %@.` | `%@ のリマインダーを %lld 件作成しました。` | `已为 %@ 创建 %lld 个提醒事项。` |
| `That list no longer exists, so no reminders were created for %@.` | `Diese Liste existiert nicht mehr, daher wurden für %@ keine Erinnerungen erstellt.` | `Esa lista ya no existe, así que no se crearon recordatorios para %@.` | `Cette liste n'existe plus, aucun rappel n'a été créé pour %@.` | `そのリストは存在しないため、%@ のリマインダーは作成されませんでした。` | `该列表已不存在，因此未为 %@ 创建任何提醒事项。` |
| `Open CheckStitch and allow Reminders access, then ask again.` | `Öffne CheckStitch und erlaube den Zugriff auf Erinnerungen, und frage dann erneut.` | `Abre CheckStitch y permite el acceso a Recordatorios, y vuelve a pedirlo.` | `Ouvrez CheckStitch et autorisez l'accès aux Rappels, puis redemandez.` | `CheckStitch を開いてリマインダーへのアクセスを許可してから、もう一度話しかけてください。` | `请打开 CheckStitch 并允许访问提醒事项，然后再问一次。` |
| `CheckStitch doesn't have permission to access Reminders. Turn it on in Settings, then ask again.` | `CheckStitch hat keine Berechtigung für Erinnerungen. Aktiviere sie in den Einstellungen und frage dann erneut.` | `CheckStitch no tiene permiso para acceder a Recordatorios. Actívalo en Ajustes y vuelve a pedirlo.` | `CheckStitch n'a pas l'autorisation d'accéder aux Rappels. Activez-la dans Réglages, puis redemandez.` | `CheckStitch にリマインダーへのアクセス権限がありません。設定で有効にしてから、もう一度話しかけてください。` | `CheckStitch 无权访问提醒事项。请在设置中开启，然后再问一次。` |
| `Couldn't create reminders for %@: %@` | `Erinnerungen für %@ konnten nicht erstellt werden: %@` | `No se pudieron crear recordatorios para %@: %@` | `Impossible de créer des rappels pour %@ : %@` | `%@ のリマインダーを作成できませんでした: %@` | `无法为 %@ 创建提醒事项：%@` |
| `That checklist no longer exists.` | `Diese Checkliste existiert nicht mehr.` | `Esa lista ya no existe.` | `Cette liste n'existe plus.` | `そのチェックリストは存在しません。` | `该清单已不存在。` |

None are identical to English, so no `excludedIdentities` entry is needed.

#### 7. Test doubles + fixtures

**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify — `SpyReminderDestination` only

```swift
// inside SpyReminderDestination
/// Status served by `accessStatus()`; defaults to `.fullAccess` so the 13
/// existing ChecklistReminders suites stay green.
var accessStatusValue: ReminderAccessStatus = .fullAccess
/// Throw once `create` has already succeeded this many times (`0` = before any
/// create). `nil` never throws here; `createError` still throws unconditionally.
var createFailureCount: Int?

func accessStatus() -> ReminderAccessStatus { accessStatusValue }

func create(title: String, notes: String?, in list: ReminderListOption, dueDateComponents: DateComponents?) async throws {
    if let createError { throw createError }
    if let createFailureCount, createdTitles.count >= createFailureCount { throw TestError.boom }
    // …existing recording of title/notes/list/date unchanged…
}
```

**File**: `CheckStitchTests/LocalizationTestHelpers.swift`
**Action**: modify — add a `LocalizedStringResource` resolver (no
`String(localized: LocalizedStringResource)` overload exists on this SDK):

```swift
extension LocalizedStringResource {
    /// Resolves the resource against the app bundle for a pinned locale.
    /// Unpicks the resource's own `defaultValue`/`table` instead of restating
    /// the key; `bundle` is a `BundleDescription`, so `.main` is supplied.
    func resolved(locale: Locale = Locale(identifier: "en")) -> String {
        String(localized: defaultValue, table: table, bundle: .main, locale: locale)
    }
}
```

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify — append the six Phase 1 keys to the `"App"` array of
`requiredKeys` (Phase 2/3 keys come in their phases).

#### 8. Tests

**File**: `CheckStitchTests/RunChecklistIntentTests.swift`
**Action**: create — `@MainActor struct RunChecklistIntentTests`
(behaviour-named `@Test` functions)

- `runCreatesEveryNonBlankItemAndReportsCount` — 3 items (one blank title, one
  blank description), `spy.lists` resolves the checklist's destination, assert
  `spy.createdTitles`, `spy.createdNotes` (nil for blank description),
  `spy.createdListIDs`, and the `.created` dialogue text.
- `runReportsExactCreatedDialogue` —
  `RunChecklistDialogue.message(for: .created(count: 2), checklistName: "Groceries").resolved() == "Created 2 reminders for Groceries."`
- `staleChecklistIdThrowsWithItsMessage` — entity id = `UUID().uuidString` not
  in the store; `#expect(throws:)` and assert
  `error.errorDescription == "That checklist no longer exists."`, `spy.createdTitles.isEmpty`.
- `notDeterminedAccessReportsInstructionAndCreatesNothing` — `spy.accessStatusValue = .notDetermined`;
  dialogue `.resolved()` equals the not-determined key; no creates.
- `deniedAccessReportsSettingsInstructionAndCreatesNothing` — `.denied`; its own
  distinct text; no creates.
- `destinationMissingReportsItsDialogueAndCreatesNothing` — `spy.lists` empty;
  dialog equals the destinationMissing key; no creates.

Intent construction helper in the suite:

```swift
let store = ChecklistStore(defaults: makeIsolatedDefaults())
store.create(name: "Groceries")
let spy = SpyReminderDestination()
spy.lists = ReminderListsSnapshot(
    options: [ReminderListOption(id: "list-1", title: "Reminders")],
    defaultIdentifier: "list-1")
let intent = RunChecklistIntent(store: store, targeting: spy)
intent.checklist = ChecklistEntity(id: store.checklists[0].id.uuidString, name: "Groceries")
let result = try await intent.perform()   // discard; assert on spy + dialogue
```

**File**: `CheckStitchTests/ChecklistEntityQueryTests.swift`
**Action**: create — `struct ChecklistEntityQueryTests`

- `suggestedEntitiesListsAllChecklistsInDisplayOrder`
- `entitiesForIdentifiersReturnsOnlyMatching`
- `entitiesMatchingFiltersByNameCaseInsensitively`
- `renamingKeepsEntityIdentity` — create, capture id, `store.rename(id:to:)`,
  assert the entity's `id` is unchanged and `name` is new
- `emptyStoreYieldsNoEntities`

### Verification

#### Automated
- [x] `make test-unit` passes (new suites + 13 existing `ChecklistRemindersTests` still green)
- [x] `make build` succeeds (simulator; metadata extraction)
- [x] `make build-mac` succeeds and `DerivedData/Build/Products/Debug/CheckStitch.app/Contents/Resources` contains the App Intents metadata
- [x] `make watch-build` succeeds (watch target must not compile `Intents/`)

#### Manual
- [ ] `make build-mac-signed`; open the macOS app; both `Run Checklist` and (after Phase 3) `List My Checklists` appear in Shortcuts.app
- [ ] Say "Run Groceries in CheckStitch"; the non-blank items appear in the checklist's destination Reminders list, with title/notes/due date mapped; Siri says the count
- [ ] Delete the destination list in Reminders, ask again → "That list no longer exists…"
- [ ] Reset Reminders permission (never asked) → the "open CheckStitch…" line, and **no prompt** appears

---

## Phase 2: Partial creation is reported exactly, not as a generic failure

### Changes

#### 1. New outcome case + its message

**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`
**Action**: modify

```swift
public enum ReminderRunOutcome: Equatable, Sendable {
    case created(count: Int)
    case destinationMissing
    case permissionDenied
    /// At least one item was created before the run failed. `.failed` is now
    /// only reachable with zero created items.
    case partiallyCreated(created: Int, total: Int, reason: String)
    case failed(String)

    public var errorMessage: String? {
        switch self {
        case .created: return nil
        case .destinationMissing: return "That list no longer exists; no reminders were created."
        case .permissionDenied: return "CheckStitch doesn't have permission to access Reminders; no reminders were created."
        case .partiallyCreated(let created, let total, let reason):
            return "Created \(created) of \(total) reminders; the rest were not created. \(reason)"
        case .failed(let message): return message
        }
    }
}
```

Adding an associated-value case keeps the synthesized `Equatable`/`Sendable`.

#### 2. Count-aware catch

**File**: `CheckStitch/ChecklistReminders.swift`
**Action**: modify — hoist `created` above the `do` so the `catch` can read it

```swift
static func create(from checklist: Checklist, targeting: ReminderDestinationTargeting) async -> ReminderRunOutcome {
    var created = 0
    do {
        guard try await targeting.requestAccess() else { return .permissionDenied }
        let snapshot = try await targeting.reminderLists()
        guard let destination = snapshot.resolve(checklist.destinationListIdentifier) else {
            // All-or-nothing: validate existence before the first create.
            return .destinationMissing
        }
        for item in checklist.items where !item.isBlank {
            let dueDateComponents = item.dueDateComponents(today: Date())
            try await targeting.create(
                title: item.title,
                notes: item.hasDescription ? item.description : nil,
                in: destination,
                dueDateComponents: dueDateComponents)
            created += 1
        }
        return .created(count: created)
    } catch {
        logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
        let total = checklist.items.filter { !$0.isBlank }.count
        if created > 0 {
            // Mid-loop throw: earlier items are already committed. Report the
            // exact split instead of a generic failure.
            return .partiallyCreated(created: created, total: total, reason: error.localizedDescription)
        }
        return .failed(error.localizedDescription)
    }
}
```

#### 3. Consumer switch gains the case

**File**: `CheckStitch/ContentView.swift`
**Action**: modify — the `switch outcome` in `createReminders(for:)` (~line 385)

```swift
case .destinationMissing, .permissionDenied, .partiallyCreated, .failed:
    // Never flash success: nothing (or only part) was created.
    runErrorMessage = outcome.errorMessage
```

#### 4. Intent dialogue for the case

**File**: `CheckStitch/Intents/RunChecklistIntent.swift`
**Action**: modify — replace the Phase 1 placeholder

```swift
case .partiallyCreated(let created, let total, let reason):
    return LocalizedStringResource(
        "Created \(created) of \(total) reminders for \(checklistName); the rest were not created. \(reason)",
        table: "Localizable", bundle: .main)
```

#### 5. Catalog key

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

| Key (en) | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|
| `Created %lld of %lld reminders for %@; the rest were not created. %@` | `%lld von %lld Erinnerungen für %@ erstellt; der Rest wurde nicht erstellt. %@` | `Se crearon %lld de %lld recordatorios para %@; el resto no se creó. %@` | `%lld rappels sur %lld créés pour %@ ; le reste n'a pas été créé. %@` | `%@ のリマインダーを %lld 件中 %lld 件作成しました。残りは作成されませんでした。%@` | `已为 %@ 创建 %lld 个（共 %lld 个）提醒事项；其余未创建。%@` |

Add to `LocalizationFixtures.requiredKeys["App"]`.

#### 6. Tests

**File**: `CheckStitchTests/ChecklistRemindersTests.swift`
**Action**: modify — add to the existing `ChecklistRemindersTests`

- `midLoopThrowAfterSomeCreatesReportsPartiallyCreated` — 7 items,
  `spy.createFailureCount = 3`; expect
  `.partiallyCreated(created: 3, total: 7, reason: TestError.boom.localizedDescription)`
  and `spy.createdTitles.count == 3`.
- `midLoopThrowBeforeAnyCreateStillReportsFailed` — `spy.createFailureCount = 0`;
  expect `.failed(TestError.boom.localizedDescription)`.
- Existing `destinationMissing` zero-creation test stays unchanged (it proves
  pre-loop ordering).

**File**: `CheckStitchTests/RunChecklistIntentTests.swift`
**Action**: modify

- `partialCreationReportsExactSplitDialogue` — `spy.createFailureCount = 3`,
  7 items; dialogue `.resolved()` equals
  `"Created 3 of 7 reminders for Groceries; the rest were not created. <boom>"`.

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `make build` succeeds — every `switch` over `ReminderRunOutcome` is exhaustive (`ContentView`, `ChecklistReminders`, `RunChecklistDialogue`)
- [ ] `rg -n "case .destinationMissing" CheckStitch CheckStitchCore` shows both call sites updated

#### Manual
- [ ] Delete the destination list from Reminders *while* a multi-item run is in flight (or simulate with the spy in a test) → Siri says "Created N of M …"; the in-app alert shows the counts + reason

---

## Phase 3: "List My Checklists" — the side-effect-free spoken query

### Changes

#### 1. New intent + dialogue

**File**: `CheckStitch/Intents/ListChecklistsIntent.swift`
**Action**: create

```swift
import AppIntents

struct ListChecklistsIntent: AppIntent {
    static let title: LocalizedStringResource = "List My Checklists"
    static let openAppWhenRun: Bool = false

    private let query: ChecklistEntityQuery
    init() { self.query = ChecklistEntityQuery() }
    @MainActor init(store: ChecklistStore) { self.query = ChecklistEntityQuery(store: store) }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let names = try await query.suggestedEntities().map(\.name)
        return .result(dialog: IntentDialog(ListChecklistsDialogue.message(for: names)))
    }
}

enum ListChecklistsDialogue {
    @MainActor
    static func message(for names: [String]) -> LocalizedStringResource {
        guard !names.isEmpty else {
            return LocalizedStringResource(
                "You don't have any checklists yet.", table: "Localizable", bundle: .main)
        }
        return LocalizedStringResource(
            "You have \(names.count) checklists: \(names.joined(separator: ", ")).",
            table: "Localizable", bundle: .main)
    }
}
```

Reads through Phase 1's `ChecklistEntityQuery`; no store mutation, no EventKit
type referenced.

#### 2. Second phrase

**File**: `CheckStitch/Intents/CheckStitchShortcuts.swift`
**Action**: modify — add to `appShortcuts`

```swift
AppShortcut(
    intent: ListChecklistsIntent(),
    phrases: ["List my checklists in \(.applicationName)"],
    shortTitle: "List Checklists",
    systemImageName: "list.bullet")
```

#### 3. Catalog keys

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

| Key (en) | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|
| `You have %lld checklists: %@.` | `Du hast %lld Checklisten: %@.` | `Tienes %lld listas: %@.` | `Vous avez %lld listes : %@.` | `%lld 件のチェックリストがあります: %@` | `你有 %lld 个清单：%@` |
| `You don't have any checklists yet.` | `Du hast noch keine Checklisten.` | `Todavía no tienes ninguna lista.` | `Vous n'avez encore aucune liste.` | `まだチェックリストがありません。` | `你还没有任何清单。` |

Add both to `LocalizationFixtures.requiredKeys["App"]`.

#### 4. Tests

**File**: `CheckStitchTests/ListChecklistsIntentTests.swift`
**Action**: create — `@MainActor struct ListChecklistsIntentTests`

- `listsNamesInDisplayOrderWithExactDialogue` — 3 checklists; dialogue
  `.resolved() == "You have 3 checklists: Groceries, Packing, Chores."`
- `emptyStoreReportsEmptyState` — dialogue equals the empty-state key
- `performDoesNotMutateStore` — snapshot `store.checklists` + persistence key
  before/after; assert unchanged, and no EventKit double is involved

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `make build` succeeds

#### Manual
- [ ] Both phrases resolve in Shortcuts.app and via Siri
- [ ] "List my checklists in CheckStitch" answers the names in app order; with
      none saved, the empty-state line; the app does not open

---

## Phase 4: Hardening — the states the happy path never saw

### Changes

No production behaviour changes to Phases 1–3 contracts. The intents already:

- build a fresh `ChecklistStore(defaults: AppGroup.defaults)` per `perform()`
  and never read scene/`@State` (cold-dispatch safe),
- read `accessStatus()` fresh on every `perform()` (so a grant made between two
  asks is honoured, and a denial re-ask re-reads),
- keep `openAppWhenRun = false`.

#### 1. Catalogue every dialogue key

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify — confirm the `"App"` `requiredKeys` array contains all nine
Phase 1–3 keys (`Created %lld reminders for %@.`, destination-missing,
not-determined, denied, `Couldn't create reminders for %@: %@`,
`That checklist no longer exists.`, partial, list, empty-state). No
`excludedIdentities` additions (all translations differ from English).

#### 2. Tests

**File**: `CheckStitchTests/RunChecklistIntentTests.swift`
**Action**: modify

- `coldRunReadsFreshStoreEachPerform` — construct the intent via `init()`
  path's collaborators (`init(store:targeting:)`) with an isolated-defaults
  store; assert a second `perform()` after a store mutation sees the new state
  (proves no cached state).
- `accessGrantedBetweenAsksIsHonoured` — `spy.accessStatusValue = .denied` →
  first ask returns the denied dialogue and zero creates; flip to `.fullAccess`
  → second ask creates.
- `notDeterminedAfterPriorDenialIsStable` — flip `.denied` → `.notDetermined` →
  `.denied` across three asks; assert each text is the expected constant.
- `longChecklistNameDialogueIsWhole` — a 120-char name; assert the resolved
  dialogue contains the full name (no truncation assumptions in the helper).

**File**: `CheckStitchTests/ListChecklistsIntentTests.swift`
**Action**: modify

- `manyChecklistsDialogueIsWhole` — 20 long-named checklists; assert the
  resolved dialogue contains all names in display order, comma-joined.

#### 3. Confirm the watch leg excludes the intents

**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: none (verify only) — the watch target lists its sources explicitly
(`project.pbxproj:683-729`), so `CheckStitch/Intents/` is not compiled by
`make watch-build`. If `make watch-build` fails referencing an intent type, the
watch target is picking up the synchronized `CheckStitch` group — stop and
report; do not add watch exclusions by hand.

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `bash scripts/tests/run.sh` passes (shell tests unchanged)
- [ ] `bash scripts/test.sh` prints `gate: ok` (includes `make build`, `make test`, `make build-mac`, `make watch-build`, shellcheck)

#### Manual
- [ ] `make build-mac-signed` + `bash scripts/run-devices.sh` (or the signed macOS build): install the bundle, confirm both actions in Shortcuts.app, run one spoken checklist end-to-end and confirm the reminders appear with titles/notes/due dates, and confirm the not-determined path produces no prompt
- [ ] State in the completion artifact what the user should see for the permission and partial-create paths (sync/icon/render rule)

---

## File manifest (every file from `structure.md`)

| File | Phase | Action |
|---|---|---|
| `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift` | 1 (+2) | modify: `ReminderAccessStatus`, `accessStatus()`, `: Sendable`; Phase 2 `partiallyCreated` + `errorMessage` |
| `CheckStitch/EventKitReminderDestination.swift` | 1 | modify: `accessStatus()` |
| `CheckStitch/Intents/ChecklistEntity.swift` | 1 | create |
| `CheckStitch/Intents/RunChecklistIntent.swift` | 1 (+2) | create: intent, `RunChecklistIntentError`, `RunChecklistDialogue` |
| `CheckStitch/Intents/CheckStitchShortcuts.swift` | 1 (+3) | create: run phrase; Phase 3 list phrase |
| `CheckStitch/Localizable.xcstrings` | 1 (+2, +3) | modify: 6 + 1 + 2 keys × 6 languages |
| `CheckStitchTests/TestFixtures.swift` | 1 | modify: `SpyReminderDestination.accessStatus` + `createFailureCount` |
| `CheckStitchTests/LocalizationTestHelpers.swift` | 1 | modify: `LocalizedStringResource.resolved()` |
| `CheckStitchTests/LocalizationFixtures.swift` | 1/2/3/4 | modify: `requiredKeys["App"]` |
| `CheckStitch/ChecklistReminders.swift` | 2 | modify: count-aware `catch` |
| `CheckStitch/ContentView.swift` | 2 | modify: switch arm |
| `CheckStitch/Intents/ListChecklistsIntent.swift` | 3 | create |
| `CheckStitchTests/RunChecklistIntentTests.swift` | 1/4 | create (+2/4) |
| `CheckStitchTests/ChecklistEntityQueryTests.swift` | 1 | create |
| `CheckStitchTests/ListChecklistsIntentTests.swift` | 3/4 | create |
| `CheckStitch/Intents/SpikeIntent.swift` | 1 | create → verify → delete |

## Deviations from `structure.md` (decided, not open)

1. **`RunChecklistDialogue` / `ListChecklistsDialogue` live in the app target**
   (inside their intent files), not Core — `structure.md` parenthetically placed
   `RunChecklistDialogue` "in Core" while the same phase's file list requires
   the dialogue keys in `CheckStitch/Localizable.xcstrings` and asserts them in
   `CheckStitchTests`. App-target placement keeps one catalog as the single home
   for all six translations and one suite asserting exact text.
2. **`ReminderAccessStatus` carries no `message`.** Its user-facing text is the
   two app-catalog keys, surfaced through `RunChecklistDialogue.notDetermined` /
   `.denied`. A Core `message` would either be an untranslated duplicate or an
   unreferenced member (Periphery).
3. **`ListChecklistsIntent` seam is `init(store:)`** (building the
   `ChecklistEntityQuery` internally) rather than `init(store:query:)`; the
   query is an implementation detail of "read my checklists", and injecting the
   store exercises the same seam the run intent uses.
4. **Two extra keys beyond the outline's sketch**: `Couldn't create reminders
   for %@: %@` (the `.failed` speech path) and `That checklist no longer
   exists.` (the stale-entity throw).
5. **Phase 1 compiles without a partial case**: the `case .partiallyCreated`
   arm is added to `RunChecklistDialogue` in Phase 2 (Phase 1 has no such enum
   case); the placeholder note in the Phase 1 snippet is removed there.

## Not doing (from `design.md`)

No per-run parameters, no reminder editing/deleting, no URL/deep-link/notification
surface, no watch intents, no changes to the legacy `ChecklistCreator` path, no
store-mutation intents, no changes to in-app prompting/Info.plist/signing, no
donations/widgets/snippet views.
