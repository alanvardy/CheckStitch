# Implementation Plan

## Overview

Add an off-by-default preference that prefixes each created Reminders reminder
title with its 1-based position among the checklist's non-blank items
(`1: Buy milk`, `2: Call the plumber`, unbounded past 9).

**Recon deviation from `medium.md` (must read).** `medium.md` states that
`ChecklistCreator` "owns reminder creation for both paths" and that
`CheckStitch/ChecklistReminders.swift` uses it. That is **false** in the current
tree. `ChecklistReminders.create` (the real production path, called from
`ContentView.swift:509`, `MyApp.swift:67` and `RunChecklistIntent.swift:58`) has
its own duplicated loop over `checklist.items`, uses a different protocol
(`ReminderDestinationTargeting`, with notes/priority/destination), and never
constructs `ChecklistCreator`. `ChecklistCreator` + `ChecklistViewModel` are
test-only (`ChecklistViewModel` has zero production references).

This plan honours the *intent* of the ticket — the numbering format is defined
in exactly one place and both creation paths apply it — without the
out-of-scope refactor of routing production through `ChecklistCreator` (which
would require moving notes/priority/destination resolution and the
`ReminderRunOutcome` cases into Core). Concretely: the pure formatting policy
lives once in `ChecklistCreator.swift` as `ChecklistTitleNumbering`, and both
`ChecklistCreator.create` and `ChecklistReminders.create` call it. Both
creators take an explicit `prefixNumbers: Bool = false` parameter (no hidden
`UserDefaults` reads inside Core), and the three production call sites thread
the value in; non-View sites read it via a new `ReminderNumberingPreference`
that follows the existing `OrientationPreference` pattern.

Two further recon results that shape the plan:

- **Preferences live in `UserDefaults.standard`, not the App Group suite.** All
  `@AppStorage` keys in `ContentView.swift:11-17` use literal keys and no custom
  `store:`, and every preference type (`AppearanceModePreference`,
  `OrientationPreference`) defaults to `.standard`. Only `ChecklistStore` uses
  `AppGroup.defaults`. So the new key uses `.standard` — "like the other
  `@AppStorage` keys" means plain standard defaults, not App Group / KVS.
- **`@AppStorage` keys are written as string literals in this repo even where a
  shared constant exists** (e.g. `OrientationPreference.defaultsKey` vs the
  literal `"allowsLandscape"` in `ContentView`). Follow that: literal key in
  `@AppStorage`, shared constant on the preference type for non-View readers.

`prefixNumbers` defaults to `false` everywhere, so all 8 existing
`ChecklistCreator(` construction sites and all 17 existing
`ChecklistReminders.create(from:targeting:)` test call sites stay green
unchanged.

---

## Phase 1: Numbering policy in Core (walking skeleton)

Thinnest end-to-end slice: the single numbering policy exists and the Core
creator applies it, fully unit-tested. Phases 2 and 3 depend only on this
contract (`ChecklistTitleNumbering.title(_:position:numbered:)` and
`ChecklistCreator(prefixNumbers:)`), never on its internals.

### Changes

#### 1. Numbering policy + Core creator consumption

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift`
**Action**: modify

Add the shared policy next to `ChecklistCreator` (same file, so the format is
literally defined exactly once), add the `prefixNumbers` init parameter and
field, and apply the policy inside the existing loop. Blank items are still
dropped by the `where !item.isBlank` filter *before* the loop body runs, so the
position counter only advances for items that are actually created.

```swift
/// Policy for optional 1-based numbering of created reminder titles.
///
/// Defined here, in the one policy seam that drops blank titles, so the format
/// exists in exactly one place; both `ChecklistCreator` and the app-side
/// `ChecklistReminders` apply it. Numbering is unbounded past 9.
public enum ChecklistTitleNumbering {
    /// `"<position>: <title>"` when `numbered`, otherwise `title` unchanged.
    public static func title(_ title: String, position: Int, numbered: Bool) -> String {
        numbered ? "\(position): \(title)" : title
    }
}
```

`ChecklistCreator` gains a fourth defaulted parameter (existing call sites are
unaffected) and a stored property, and `create(from:)` becomes:

```swift
public init(reminders: ReminderCreating,
            now: @escaping @Sendable () -> Date = Date.init,
            calendar: Calendar = .current,
            prefixNumbers: Bool = false) {
    self.reminders = reminders
    self.now = now
    self.calendar = calendar
    self.prefixNumbers = prefixNumbers
}

// ...

var created = 0
var position = 0
let today = now()
for item in items where !item.isBlank {
    // Position is assigned after blank items are dropped, so an emptied
    // row never leaves a gap: item one is always 1.
    position += 1
    try await reminders.create(
        title: ChecklistTitleNumbering.title(
            item.title, position: position, numbered: prefixNumbers),
        dueDateComponents: item.dueDateComponents(today: today, calendar: calendar))
    created += 1
}

// ...

private let prefixNumbers: Bool
```

#### 2. Core creator tests — the four required cases + sad path

**File**: `CheckStitchTests/ChecklistCreatorTests.swift`
**Action**: modify

Append to the existing `@MainActor struct ChecklistCreatorTests`, following its
`let spy = SpyReminderCreator()` / `ChecklistCreator(reminders: spy)` pattern
and bare behaviour-named `@Test` functions (no `test` prefix). Assertions use
`spy.createdTitles`.

```swift
@Test
func numberingIsOffByDefault() async {
    let spy = SpyReminderCreator()
    let creator = ChecklistCreator(reminders: spy)
    let outcome = await creator.create(from: [makeItem("one"), makeItem("two")])
    #expect(outcome == .created(count: 2))
    #expect(spy.createdTitles == ["one", "two"])
}

@Test
func numberingPrefixesTitlesWithTheirPosition() async {
    let spy = SpyReminderCreator()
    let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
    let outcome = await creator.create(from: [makeItem("one"), makeItem("two")])
    #expect(outcome == .created(count: 2))
    #expect(spy.createdTitles == ["1: one", "2: two"])
}

@Test
func numberingSkipsBlankItemsWithoutGaps() async {
    let spy = SpyReminderCreator()
    let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
    let outcome = await creator.create(from: [
        makeItem("one"), makeItem(""), makeItem("two"), makeItem("   "),
    ])
    #expect(outcome == .created(count: 2))
    #expect(spy.createdTitles == ["1: one", "2: two"])
}

@Test
func numberingContinuesPastNine() async {
    let spy = SpyReminderCreator()
    let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
    let items = (1...10).map { makeItem("item \($0)") }
    let outcome = await creator.create(from: items)
    #expect(outcome == .created(count: 10))
    #expect(spy.createdTitles.first == "1: item 1")
    #expect(spy.createdTitles.last == "10: item 10")
}

/// Sad path: numbering must not bypass the permission gate.
@Test
func numberingStillRespectsPermissionDenial() async {
    let spy = SpyReminderCreator()
    spy.accessGranted = false
    let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
    let outcome = await creator.create(from: [makeItem("one")])
    #expect(outcome == .permissionDenied)
    #expect(spy.createdTitles.isEmpty)
}
```

### Verification
#### Automated
- [x] `make test-unit` passes (all `ChecklistCreatorTests`, old and new)
- [x] `make build-mac` passes (Core compiles cross-platform)

#### Manual
- [ ] `spy.createdTitles` in the four new cases shows exactly `1:`, `2:`, … with no gaps and no prefix when off.

---

## Phase 2: Production creation path honours the setting

Now the feature works end to end for a user who sets the key: every
`ChecklistReminders.create` path (root screen, phone-sync coordinator, Run
Checklist intent) prefixes titles when the preference is enabled.

### Changes

#### 1. Non-View preference reader

**File**: `CheckStitch/ReminderNumberingPreference.swift`
**Action**: create

Mirrors `CheckStitch/OrientationPreference.swift` (the established pattern for a
preference read outside a SwiftUI `View`, used because `MyApp`'s sync closure
and `RunChecklistIntent` cannot see `ContentView`'s `@AppStorage`). `.standard`
matches every other preference; an absent key resolves to `false`.

```swift
import Foundation

/// Persists the "number reminders" preference in `UserDefaults.standard`,
/// matching the other `@AppStorage`-backed preferences. Read outside SwiftUI by
/// the phone-sync coordinator and the Run Checklist intent.
struct ReminderNumberingPreference {
    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Single shared key used by `@AppStorage` and the non-View read sites.
    static let defaultsKey = "prefixReminderNumbers"

    /// Whether created reminder titles get a 1-based prefix. Missing key → false.
    var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

#### 2. Production creator applies the shared policy

**File**: `CheckStitch/ChecklistReminders.swift`
**Action**: modify

Both overloads gain `prefixNumbers: Bool = false`; the loop applies
`ChecklistTitleNumbering` (imported from `CheckStitchCore`) exactly once, after
blank rows are skipped. No formatting logic is duplicated here.

```swift
static func create(from checklist: Checklist, prefixNumbers: Bool = false) async -> ReminderRunOutcome {
    await create(
        from: checklist,
        targeting: EventKitReminderDestination.shared,
        prefixNumbers: prefixNumbers)
}

static func create(from checklist: Checklist,
                   targeting: ReminderDestinationTargeting,
                   prefixNumbers: Bool = false) async -> ReminderRunOutcome {
    // ... unchanged access/destination resolution ...
    var position = 0
    for item in checklist.items where !item.isBlank {
        // Numbering is assigned after blank items are dropped, so an emptied
        // row never leaves a gap: item one is always 1.
        position += 1
        let dueDateComponents = item.dueDateComponents(today: Date())
        try await targeting.create(
            title: ChecklistTitleNumbering.title(
                item.title, position: position, numbered: prefixNumbers),
            notes: item.hasDescription ? item.description : nil,
            priority: item.priority,
            in: destination,
            dueDateComponents: dueDateComponents)
        created += 1
    }
    // ... unchanged outcome handling ...
}
```

#### 3. Thread the setting through all three production call sites

**Files**: `CheckStitch/ContentView.swift`, `CheckStitch/MyApp.swift`,
`CheckStitch/Intents/RunChecklistIntent.swift`
**Action**: modify

`ContentView.swift` — add the key to the `@AppStorage` block (lines 11-17,
literal key to match the neighbours), default `false`, and pass it at line 509:

```swift
@AppStorage("prefixReminderNumbers") var prefixReminderNumbers = false
```

```swift
// ContentView.swift:509
let outcome = await ChecklistReminders.create(from: checklist, prefixNumbers: prefixReminderNumbers)
```

`MyApp.swift:67` (sync closure — non-View, so read at call time so a settings
change is honoured on the next run):

```swift
createReminders: { await ChecklistReminders.create(from: $0, prefixNumbers: ReminderNumberingPreference().isEnabled) })
```

`RunChecklistIntent.swift:58`:

```swift
let outcome = await ChecklistReminders.create(
    from: stored,
    targeting: targeting,
    prefixNumbers: ReminderNumberingPreference().isEnabled)
```

#### 4. Tests — production path + preference reader

**Files**: `CheckStitchTests/ChecklistRemindersTests.swift`,
`CheckStitchTests/ReminderNumberingPreferenceTests.swift`
**Action**: modify / create

`ChecklistRemindersTests.swift` (app-target suite) — add the same four cases and
a sad path, following its existing `SpyReminderDestination` + `makeItem` +
`ChecklistReminders.create(from:targeting:spy)` shape (all 17 existing call
sites stay green because `prefixNumbers` defaults to `false`). Assert against
`spy.createdTitles`:

- `numberingIsOffByDefault` — titles unchanged.
- `numberingPrefixesTitlesWithTheirPosition` — `["1: one", "2: two"]`.
- `numberingSkipsBlankItemsWithoutGaps` — blank middle row → `["1: one", "2: two"]`.
- `numberingContinuesPastNine` — ten items → first `"1: item 1"`, last `"10: item 10"`.
- Sad path `numberingStillReportsMissingDestination` — an unresolvable
  `destinationListIdentifier` returns `.destinationMissing` and creates nothing
  even with numbering on.

`ReminderNumberingPreferenceTests.swift` (create) — follow
`AppearanceModePreferenceTests` / `TestFixtures.makeIsolatedDefaults()`:

```swift
@Suite(.serialized)
struct ReminderNumberingPreferenceTests {
    @Test
    func missingKeyDefaultsToDisabled() {
        let preference = ReminderNumberingPreference(defaults: makeIsolatedDefaults())
        #expect(!preference.isEnabled)
    }

    @Test
    func enabledValueRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let preference = ReminderNumberingPreference(defaults: defaults)
        preference.setEnabled(true)
        #expect(ReminderNumberingPreference(defaults: defaults).isEnabled)
    }
}
```

### Verification
#### Automated
- [x] `make test-unit` passes (existing `ChecklistRemindersTests` unchanged, new cases green)
- [x] `make build` passes (app target compiles with the new key and call sites)

#### Manual
- [ ] `defaults write app.alanvardy.CheckStitch prefixReminderNumbers -bool true` then a checklist run creates `1: …`, `2: …` reminders (and off still creates plain titles).

---

## Phase 3: Settings-sheet toggle

The user-facing surface: the preference becomes toggleable in the Settings
sheet and persists like its neighbours.

### Changes

#### 1. Staged settings bag

**File**: `CheckStitch/SettingsBindings.swift`
**Action**: modify

Add a defaulted `Bool` field alongside `backgroundEnabled`, matching the
staged-preference pattern.

```swift
init(
    backgroundEnabled: Bool = true,
    backgroundFadePercent: Int = BackgroundFade.defaultValue,
    backgroundPinned: Bool = false,
    textSize: TextSize = .system,
    allowsLandscape: Bool = true,
    prefixReminderNumbers: Bool = false) {
    // ...
    self.prefixReminderNumbers = prefixReminderNumbers
}

var prefixReminderNumbers: Bool
```

#### 2. ContentView staging + write-back

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

In the `extension ContentView` block (lines ~546-578): include the field in
`makeSettingsBag()` and `writeBack(_:)`, and observe it in
`settingsSheetWritebacks(_:)` so a toggle change is persisted immediately:

```swift
.onChange(of: bag.prefixReminderNumbers) { _, _ in writeBack(bag) }
```

```swift
func writeBack(_ bag: SettingsBindings) {
    // ... existing lines ...
    prefixReminderNumbers = bag.prefixReminderNumbers
}

func makeSettingsBag() -> SettingsBindings {
    SettingsBindings(
        // ... existing arguments ...
        prefixReminderNumbers: prefixReminderNumbers)
}
```

#### 3. Toggle row

**File**: `CheckStitch/SettingsView.swift`
**Action**: modify

New `Section` in the `Form`, using the `BackgroundSettingsView.swift:12-18`
toggle shape and the `settings…Row` accessibility-identifier convention. The
binding is `@Bindable var bindings: SettingsBindings` (already present), so
`$bindings.prefixReminderNumbers` works directly.

```swift
Section {
    Toggle(isOn: $bindings.prefixReminderNumbers) {
        Label("Number Reminders", systemImage: "textformat.123")
    }
    .accessibilityIdentifier("settingsPrefixNumbersRow")
} footer: {
    Text("Prefix each reminder title with its position, like \"1: Buy milk\".")
}
```

#### 4. Extend `SettingsBindingsTests`

**File**: `CheckStitchTests/SettingsBindingsTests.swift`
**Action**: modify

Add the new key to all four existing tests so the staged bag stays covered:

- `defaultsMatchPreferenceDefaults` — `#expect(!bag.prefixReminderNumbers)`.
- `snapshotReadsCurrentUserDefaults` — set `prefixReminderNumbers` to `true`,
  assert `bag.prefixReminderNumbers`.
- `writeBackPersistsEachKey` — construct the bag with
  `prefixReminderNumbers: true`, assert
  `UserDefaults.standard.bool(forKey: "prefixReminderNumbers") == true`.
- `clearPreferences()` — add `"prefixReminderNumbers"` to the key list.

### Verification
#### Automated
- [x] `make test-unit` passes (all `SettingsBindingsTests`, old and new assertions)
- [x] `make build` passes (SettingsView compiles with the new Section)
- [x] Full gate `bash scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Open Settings from the gear button → the "Number Reminders" row is present, off by default; toggling it on, running a checklist gives `1: …` titles, and the value survives relaunch (reopening Settings shows it still on).

---

## Out of scope (deliberately not done)

- Routing `ChecklistReminders` through `ChecklistCreator`, or moving
  notes/priority/destination resolution into Core. `medium.md`'s premise that
  the production path already uses `ChecklistCreator` is untrue; making it true
  is a separate refactor (it would also have to unify `ReminderRunOutcome` with
  `ChecklistCreationOutcome`).
- Any change to `ReminderCreating` / `EventKitReminderCreator` (adapters stay
  numbering-free).
- Any App Group / KVS migration of preferences (they all use `.standard` today).
