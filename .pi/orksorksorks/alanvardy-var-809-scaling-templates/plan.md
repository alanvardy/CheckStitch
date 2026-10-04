# Implementation Plan

## Overview

Add a per-checklist `multiple: Int` (default `1`, range `1...99`) that scales
every `((n))` marker in an item's title/description to `n × multiple` at
reminder-creation time (stored text is never rewritten), with a Scaling
`Stepper` on the detail screen, scaled read-only surfaces (iOS/macOS rows, Watch
detail) plus a `×N` row badge when `multiple > 1`, and an optional
`RunChecklistIntent` override validated before any side effect. All work lands on
the main ticket (`alanvardy-var-809-scaling-templates`); no child tickets.

> Deviations from `structure.md` are called out inline as **[Deviation]** and
> summarised at the end. Two matter: `ChecklistMerge` needs an explicit field
> assignment, and there is no Watch unit-test target.

---

## Phase 1: Walking skeleton — set a multiple and run a checklist with a scaled marker

**Outcome**: On the detail screen the user sets Scaling to `2`; running the
checklist creates reminders whose titles/notes have `((n))` replaced by
`n × multiple` (title scaled **then** prefixed by the existing positional number;
description scaled directly). Stored text untouched.

### Changes

#### 1. Model, codec, range + clamp
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

- Add `multiple: Int = 1` to the public `init` immediately after
  `showsOnWatch` (all call sites use argument labels, so inserting a defaulted
  parameter mid-list is source-compatible), assign `self.multiple = multiple`, and
  add the stored property right after `showsOnWatch`.

```swift
/// The template scaling factor applied to `((n))` markers in item
/// titles/descriptions at reminder-creation time. Defaults to 1 (no scaling).
/// Shares the checklist's coarse `revision`/`modifiedAt` clock (like the
/// name/destination/toggles), so a change rides the same last-write-wins rule.
/// Additive optional key: absent in v5-and-earlier payloads decodes to 1 with
/// no version bump; out-of-range payloads clamp into `multipleRange`.
public var multiple: Int
```

- Add `multiple` to `private enum CodingKeys`.
- In `init(from:)` decode with clamp (mirror the `prefixesReminderNumbers`
  comment style):

```swift
// Additive optional field: absent in v5-and-earlier payloads decodes to 1
// (no scaling) with no version bump. Hand-edited/imported payloads outside
// `multipleRange` clamp into range rather than being trusted.
let multiple = Checklist.clampedMultiple(
    try container.decodeIfPresent(Int.self, forKey: .multiple) ?? 1)
```

- Pass `multiple: multiple` into the `Checklist(...)` call at the end of
  `init(from:)` (before `folderID:` or anywhere labelled).
- In `encode(to:)` add `try container.encode(multiple, forKey: .multiple)`
  (every key is written unconditionally).
- In `extension Checklist` (the block holding `migrated`/`seededOrder`/
  `normalizedOrder`) add the shared range + clamp:

```swift
/// Inclusive range of allowed scaling factors. Read by the Stepper, the store
/// clamp and the intent validation so the bound lives in exactly one place.
public static let multipleRange: ClosedRange<Int> = 1...99

/// The nearest in-range scaling factor. Used at both ingress points (codec
/// decode and `ChecklistStore.setMultiple`).
public static func clampedMultiple(_ value: Int) -> Int {
    min(max(value, multipleRange.lowerBound), multipleRange.upperBound)
}
```

- In `migrated(at:)` add a clarifying comment only — no functional change:
  `multiple` shares the coarse clock, and `migrated(at:)` already restamps
  `modifiedAt`/`revision`, so there is no per-field clock to seed.

#### 2. Store mutator
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

Add `setMultiple` immediately after `setShowsOnWatch`, cloning its shape
(clamp → no-op guard → coarse bump → `scheduleSave()`). Return type follows the
existing sibling setters (`SetDestinationOutcome`, **not** a new
`MutationOutcome`) **[Deviation — structure.md named a non-existent
`MutationOutcome`]**.

```swift
/// Sets a checklist's template scaling factor and reports whether it applied.
/// Clamps into `Checklist.multipleRange` first (defense in depth for
/// imported/hand-edited payloads), then follows the no-op-guard shape: an
/// unchanged value never manufactures a spurious LWW win. Shares the
/// checklist's coarse `revision`/`modifiedAt` clock.
@discardableResult
public func setMultiple(_ newValue: Int, for id: UUID) -> SetDestinationOutcome {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
    let clamped = Checklist.clampedMultiple(newValue)
    guard checklists[index].multiple != clamped else { return .updated }
    checklists[index].multiple = clamped
    checklists[index].revision += 1
    checklists[index].modifiedAt = now()
    scheduleSave()
    return .updated
}
```

#### 3. Pure resolver + Path B
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift`
**Action**: modify

Add `ChecklistScaling` as a sibling of `ChecklistTitleNumbering` (after it,
before `ChecklistCreator`). Grammar: literal `((` + one-or-more ASCII digits +
`))`; everything else byte-for-byte. `multiple == 1` returns the input
immediately. A digit run that does not parse as `Int` **or whose product
overflows `Int`** is treated as a non-match and left literal **[Deviation —
`design.md`'s "digit string that overflows Int parsing" is extended to
multiplication overflow to avoid an arithmetic trap]**.

```swift
/// Replaces every `((n))` marker (literal `((`, one or more ASCII digits, `))`)
/// with the product `n * multiple`, leaving all other text byte-for-byte
/// unchanged. Returns `text` unchanged when `multiple == 1`. A marker whose
/// digits do not parse as `Int`, or whose product overflows `Int`, is left
/// literal. Pure; no model dependency.
public enum ChecklistScaling {
    public static func resolve(_ text: String, multiple: Int) -> String {
        guard multiple != 1, text.contains("((") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "(", let second = text.index(index, offsetBy: 2, limitedBy: text.endIndex),
               second <= text.endIndex, text[text.index(after: index)] == "(" {
                let digitsStart = second
                var cursor = digitsStart
                while cursor < text.endIndex, isASCIIDigit(text[cursor]) {
                    cursor = text.index(after: cursor)
                }
                if cursor > digitsStart, cursor < text.endIndex, text[cursor] == ")" {
                    let afterClose = text.index(after: cursor)
                    if afterClose < text.endIndex, text[afterClose] == ")",
                       let value = Int(text[digitsStart..<cursor]),
                       value.multipliedReportingOverflow(by: multiple).overflow == false {
                        result += "\(value * multiple)"
                        index = text.index(after: afterClose)
                        continue
                    }
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
```

> Implementation note: the guard above is written to compile cleanly; the exact
> index arithmetic should be verified by `make test-unit` (compiler is the
> oracle). `Character.isASCII && isNumber` restricts to `0...9`; do not use
> `isWholeNumber` (it accepts non-ASCII numerals).

Add a `multiple` parameter to Path B (test-only) so the resolver is exercised
there too:

```swift
public func create(from items: [ChecklistItem], multiple: Int = 1) async -> ChecklistCreationOutcome {
    ...
    title: ChecklistTitleNumbering.title(
        ChecklistScaling.resolve(item.title, multiple: multiple),
        position: position, numbered: prefixNumbers, itemCount: itemCount),
```

#### 4. Production run path (Path A)
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistReminders.swift`
**Action**: modify

Add the override parameter and resolve the effective multiple once, then
scale-then-prefix the title and scale the description directly:

```swift
public static func create(from checklist: Checklist,
                          targeting: ReminderDestinationTargeting,
                          gate: RunGate,
                          multipleOverride: Int? = nil) async -> ReminderRunOutcome {
    ...
    let prefixNumbers = checklist.prefixesReminderNumbers
    let multiple = multipleOverride ?? checklist.multiple
    ...
        title: ChecklistTitleNumbering.title(
            ChecklistScaling.resolve(item.title, multiple: multiple),
            position: position, numbered: prefixNumbers, itemCount: itemCount),
        notes: item.hasDescription ? ChecklistScaling.resolve(item.description, multiple: multiple) : nil,
```

The default `nil` keeps every existing caller (view model, phone-sync path)
working unchanged; they now pick up the stored `multiple`.

#### 5. Detail-screen Scaling section
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Insert a Scaling section immediately after the numbering `Section` (before the
`showOnWatch` `Section`, ~line 74). Use the shared range as the Stepper bound,
and a per-selection binding that reads the store (sync updates the control) and
writes through `setMultiple`:

```swift
Section {
    Stepper("Scaling", value: multipleBinding(checklistID: checklistID),
            in: Checklist.multipleRange)
        .accessibilityIdentifier("checklistScalingStepper")
}
```

```swift
/// Per-selection write through the store for the scaling factor. The getter
/// reads the store so a value that arrives over sync updates the Stepper;
/// `.notFound` (deleted while this screen was open) is ignored, matching
/// `numberingBinding`.
private func multipleBinding(checklistID: UUID) -> Binding<Int> {
    Binding(
        get: { store.checklist(id: checklistID)?.multiple ?? 1 },
        set: { store.setMultiple($0, for: checklistID) }
    )
}
```

#### 6. App catalog + fixture (Scaling key)
**Files**: `CheckStitch/Localizable.xcstrings`,
`CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add key `Scaling` to the App catalog with all six languages, `state:
translated`, `extractionState: manual` (the `Light` entry is the shape model).
Insert via the `edit` tool with a small byte-exact anchor (e.g. next to a
neighbouring key) — do not paste a whole block.

| lang | value |
|---|---|
| en | `Scaling` |
| de | `Skalierung` |
| es | `Escalado` |
| fr | `Mise à l'échelle` |
| ja | `倍率` |
| zh-Hans | `倍数` |

Add `"Scaling"` to the `("App", [...])` list in
`LocalizationFixtures.requiredKeys`.

> Translation note: these are short UI strings supplied for the plan; the
> implementer should keep them (the l10n canary requires non-English values to
> differ from English and to be non-empty).

#### 7. Tests — Phase 1
**Files**: `CheckStitchTests/ChecklistCreatorTests.swift`,
`CheckStitchTests/ChecklistCodecTests.swift`,
`CheckStitchTests/ChecklistStoreTests.swift`,
`CheckStitchTests/ChecklistRemindersTests.swift`
**Action**: modify

- `ChecklistCreatorTests` — resolver behaviour and scale-then-prefix order:
```swift
@Test(arguments: [("((3))", 2, "6"), ("((0))", 5, "0"), ("x ((2)) y", 3, "x 6 y")])
func resolveScalesMarkers(_ text: String, _ multiple: Int, _ expected: String) {
    #expect(ChecklistScaling.resolve(text, multiple: multiple) == expected)
}

@Test(arguments: ["((abc))", "(x)", "((3)", "3))", "((3)))"])
func nonMarkersPassThroughByteForByte(_ text: String) {
    #expect(ChecklistScaling.resolve(text, multiple: 4) == text)
}

@Test func overflowingDigitsPassThrough() {
    let text = "((99999999999999999999))"
    #expect(ChecklistScaling.resolve(text, multiple: 2) == text)
}

@Test func multipleOneIsAFastPath() {
    #expect(ChecklistScaling.resolve("((2)) raw", multiple: 1) == "((2)) raw")
}

@Test func titleIsScaledThenPrefixed() {
    let scaled = ChecklistScaling.resolve("milk ((2))", multiple: 3)
    #expect(ChecklistTitleNumbering.title(scaled, position: 1, numbered: true, itemCount: 1) == "1: milk 6")
}
```
  Also a Path B test: `ChecklistCreator(...).create(from: items, multiple: 5)`
  yields the scaled title.
- `ChecklistCodecTests` — round-trip / missing-key / clamp:
```swift
@Test func multipleRoundTrips() throws {
    let decoded = try ChecklistCodec.decode(ChecklistCodec.encode([Checklist(multiple: 7)])).checklists[0]
    #expect(decoded.multiple == 7)
}

@Test func missingMultipleDecodesToOne() throws {
    // encode, strip the "multiple" key with JSONSerialization, decode
    #expect(decoded.multiple == 1)
}

@Test(arguments: [(0, 1), (100, 99), (-5, 1)])
func outOfRangeMultipleClamps(_ raw: Int, _ expected: Int) throws {
    let decoded = try ChecklistCodec.decode(ChecklistCodec.encode([Checklist(multiple: raw)])).checklists[0]
    #expect(decoded.multiple == expected)
}
```
- `ChecklistStoreTests` — no-op guard / clamp / coarse bump:
```swift
@Test func setMultipleBumpsCoarseRevision() {
    let store = ChecklistStore(defaults: makeIsolatedDefaults())
    let checklist = store.create(name: "Groceries")
    let before = store.checklist(id: checklist.id)!.revision
    #expect(store.setMultiple(3, for: checklist.id) == .updated)
    #expect(store.checklist(id: checklist.id)!.multiple == 3)
    #expect(store.checklist(id: checklist.id)!.revision == before + 1)
}

@Test func setMultipleNoOpDoesNotBump() {
    let store = ChecklistStore(defaults: makeIsolatedDefaults())
    let checklist = store.create(name: "Groceries")
    let before = store.checklist(id: checklist.id)!.revision
    #expect(store.setMultiple(1, for: checklist.id) == .updated)
    #expect(store.checklist(id: checklist.id)!.revision == before) // already 1
}

@Test(arguments: [(0, 1), (100, 99)])
func setMultipleClamps(_ raw: Int, _ expected: Int) { ... }
```
- `ChecklistRemindersTests` — Path A scales title **and** description while
  numbering still applies:
```swift
@Test func runScalesTitleAndDescription() async throws {
    // checklist multiple = 2, numbering on, item title "milk ((3))" desc "((4)) boxes"
    // → title "1: milk 6", notes "8 boxes"
}
```

### Verification
#### Automated
- [x] `make test-unit` passes (resolver, codec, store, run-path suites green)
- [x] `make build` passes (warnings-as-errors clean)
- [x] `scripts/l10n-check.sh` passes (App `Scaling` key)

#### Manual
- [ ] `make run`; open a checklist, see the Scaling stepper; increment to `2`
- [ ] Add an item titled `Milk ((3))` with description `((4)) boxes`; run it; the created reminders read `1: Milk 6` / notes `8 boxes`
- [ ] Confirm the stored item text still reads `Milk ((3))` after the run

---

## Phase 2: Read-only surfaces render scaled text, with a `×N` row badge

**Outcome**: the iOS/macOS row and the Watch detail show resolved title **and**
description without running; rows show a `×N` badge when `multiple > 1`;
`ItemEditView` still shows raw `((n))`.

### Changes

#### 1. `ItemRow` scaling + badge
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

- Add `let multiple: Int` to `ItemRow` (memberwise init gains the parameter).
- Resolve the title/description; fall back to the existing empty-title
  placeholder **after** resolution. Add the badge in the title `HStack` right
  after the title, only when the factor is shown:

```swift
Text(Self.displayTitle(ChecklistScaling.resolve(title, multiple: multiple)))
Spacer(minLength: 0)
if Self.showsScalingFactor(multiple) {
    Text(LocalizedStringResource("×\(multiple)", table: "Localizable", bundle: .main))
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("scalingFactorBadge")
}
...
if !description.isEmpty {
    Text(ChecklistScaling.resolve(description, multiple: multiple))
        .font(.footnote)
        .foregroundStyle(.secondary)
}
```

- Add the testable condition helper (mirrors the priority-marker "hidden when
  absent" shape):

```swift
/// The `×N` factor badge is only meaningful when scaling actually changes
/// marker text, so it is hidden at the neutral value.
static func showsScalingFactor(_ multiple: Int) -> Bool { multiple > 1 }
```

- Update the `ItemRow(...)` call site in the `Items` `ForEach` to pass
  `multiple: checklist.multiple`.
- `ItemEditView` untouched (raw).

#### 2. Watch detail
**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: modify

Resolve title and description against the live copy; no badge:

```swift
Text(ChecklistScaling.resolve(item.title, multiple: current.multiple))
if item.hasDescription {
    Text(ChecklistScaling.resolve(item.description, multiple: current.multiple))
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

#### 3. App catalog + fixture (badge key)
**Files**: `CheckStitch/Localizable.xcstrings`,
`CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add key `×%lld` to the App catalog, all six languages with the literal value
`×%lld` (the `×` is locale-invariant; only the format placeholder matters). Add
`"×%lld"` to the App `requiredKeys` list **and** an `ExclusionEntry` so the
non-English-differs canary is skipped exactly as it is for `"%lld%%"`:

```swift
ExclusionEntry(catalog: "App", key: "×%lld"),
```

> The `×` glyph and `%lld` must be copied byte-exact. Use a small `edit` anchor;
> the key is non-ASCII, so avoid retyping it (see `macos-clipboard`/`edit`
> skills).

#### 4. Tests — Phase 2
**Files**: `CheckStitchTests/ChecklistDetailViewTests.swift`,
`CheckStitchTests/LocalizationTests.swift`
**Action**: modify

- Badge visibility condition:
```swift
@Test(arguments: [(1, false), (2, true), (99, true)])
func scalingBadgeHiddenOnlyAtNeutral(_ multiple: Int, _ visible: Bool) {
    #expect(ItemRow.showsScalingFactor(multiple) == visible)
}
```
- Detail render with a scaled checklist stays renderable (extend the existing
  store-backed render test) and a scaled `ItemRow` render pass produces a frame:
```swift
@Test func scaledDetailViewRenders() {
    let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
    let checklist = store.create(name: "Groceries")
    store.setMultiple(3, for: checklist.id)
    store.addItem(to: checklist.id, title: "Milk ((2))")
    let view = ChecklistDetailView(checklistID: checklist.id).environment(store)
    #if os(macOS)
    #expect(ImageRenderer(content: view).nsImage != nil)
    #else
    #expect(ImageRenderer(content: view).uiImage != nil)
    #endif
}
```
- `LocalizationTests` already asserts every `requiredKeys` entry exists in its
  catalog across the six languages; adding `×%lld` to the fixture is the test
  change.

**[Deviation]** `structure.md` lists a "Watch render suite". There is **no**
watch test target importable from `CheckStitchTests` (`WatchChecklistStoreTests`
imports only `CheckStitchCore`), so the Watch text is covered by the pure-resolver
tests plus the Phase 5 installed-bundle check — not a Watch unit suite.

### Verification
#### Automated
- [x] `make test-unit` passes (badge condition, render, localization)
- [x] `make watch-build` passes
- [x] `scripts/l10n-check.sh` passes (`Scaling`, `×%lld`)

#### Manual
- [ ] `make run`: with Scaling `3`, rows preview `×3` and show resolved text; set Scaling `1`, the badge disappears and raw `((n))` shows
- [ ] `ItemEditView` still shows the raw `((n))` text
- [ ] `bash scripts/run-watch.sh`: the Watch detail shows the scaled title/description and no badge (expected outcome; installed bundle)

---

## Phase 3: Persistence integrity — multiple survives duplicate, export/import, merge

**Outcome**: duplicating, exporting/sharing/re-importing, or receiving a remote
merge keeps `multiple` (out-of-range payloads clamp to `1...99`).

### Changes

#### 1. Carry points
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

Add `multiple: source.multiple` to the `duplicate` `Checklist(...)` call and
`multiple: checklist.multiple` to `freshCopy`'s `Checklist(...)` call (alongside
`destinationListIdentifier`/`prefixesReminderNumbers`/`showsOnWatch`).

#### 2. Merge field assignment
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistMerge.swift`
**Action**: modify

**[Deviation — `structure.md` claims the coarse copy already carries it, but the
remote-win branch copies fields explicitly]** Add the field to the
remote-wins assignment block (ChecklistMerge.swift:145-157):

```swift
merged.multiple = remoteChecklist.multiple
```

Without this, a remote win silently drops the remote's `multiple` (the
`result.append(remoteChecklist)` new-record path already carries it). No other
merge change: the value rides the existing coarse `wins()` decision.

#### 3. Tests — Phase 3
**Files**: `CheckStitchTests/ChecklistStoreTests.swift`,
`CheckStitchTests/ChecklistExportTests.swift`,
`CheckStitchTests/ChecklistImportSessionTests.swift`,
`CheckStitchTests/ChecklistMergeTests.swift`,
`CheckStitchTests/UbiquitousChecklistSyncTests.swift`
**Action**: modify

- `ChecklistStoreTests`: `duplicate` and `importInsert` both carry `multiple`
  (set source to 4, assert the copy is 4).
- `ChecklistExportTests`: export→import round-trip preserves `multiple`;
  a payload constructed with `multiple: 100` decodes/imports as `99`, and `0` as
  `1`.
- `ChecklistImportSessionTests`: `stage(data:)` of an out-of-range payload clamps.
- `ChecklistMergeTests`: remote has higher coarse `revision` with `multiple: 7`,
  local `multiple: 1` → merged `multiple == 7`; local wins → stays local.
- `UbiquitousChecklistSyncTests`: a remote-win apply carries `multiple`.

### Verification
#### Automated
- [x] `make test-unit` passes (duplicate/export/import/merge/sync suites)

#### Manual
- [ ] `make run`: duplicate a checklist set to Scaling `4`; the copy shows `4`
- [ ] Export a scaled checklist and import it; the imported copy keeps the factor

---

## Phase 4: Intent override — one-run multiple with side-effect-free validation

**Outcome**: running via the Shortcut with an optional `multiple` uses it for
this run only; absent → stored value; out-of-range (`0`, `100`) throws
`.invalidMultiple` with a localized message **before** any gate reserve or
reminder creation.

### Changes

#### 1. Intent parameter, error and validation
**File**: `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift`
**Action**: modify

- Add the optional parameter after `checklist`:

```swift
@Parameter(title: "Multiple")
public var multiple: Int?
```

- Add the error case and switch the `errorDescription` (currently a single
  expression) to a `switch`:

```swift
enum RunChecklistIntentError: LocalizedError {
    case checklistNotFound
    case invalidMultiple
    var errorDescription: String? {
        switch self {
        case .checklistNotFound:
            LocalizedStringResource(
                "That checklist no longer exists.", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
        case .invalidMultiple:
            LocalizedStringResource(
                "Multiple must be between 1 and 99.", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
        }
    }
}
```

- In `perform()`, immediately after the `checklistNotFound` guard and before the
  access-status switch, validate and then pass the override:

```swift
guard let uuid = UUID(uuidString: checklist.id),
      let stored = store.checklist(id: uuid)
else { throw RunChecklistIntentError.checklistNotFound }

// Validate before the status pre-check and before any side effect, so a bad
// override can never reserve a run slot or create a reminder.
if let multiple, !Checklist.multipleRange.contains(multiple) {
    throw RunChecklistIntentError.invalidMultiple
}
...
let outcome = await ChecklistReminders.create(
    from: stored,
    targeting: targeting,
    gate: gate,
    multipleOverride: multiple)
```

The override is never written back to the store.

#### 2. Core catalog + fixture
**Files**: `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`,
`CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add key `Multiple must be between 1 and 99.` to the Core catalog, all six
languages, `state: translated`, `extractionState: manual`:

| lang | value |
|---|---|
| en | `Multiple must be between 1 and 99.` |
| de | `Der Multiplikator muss zwischen 1 und 99 liegen.` |
| es | `El múltiplo debe estar entre 1 y 99.` |
| fr | `Le multiplicateur doit être compris entre 1 et 99.` |
| ja | `倍率は 1〜99 の範囲で指定してください。` |
| zh-Hans | `倍数必须在 1 到 99 之间。` |

Add the key to the `("Core", [...])` list in `LocalizationFixtures.requiredKeys`.

#### 3. Tests — Phase 4
**File**: `CheckStitchTests/RunChecklistIntentTests.swift`
**Action**: modify

- Absent override uses the stored multiple; override applies for one run only
  and does not persist:
```swift
@Test func absentOverrideUsesStoredMultiple() async throws {
    let (intent, spy, store) = makeIntent()
    store.setMultiple(3, for: store.checklists[0].id)
    store.addItem(to: store.checklists[0].id, title: "Milk ((2))")
    _ = try await intent.perform()
    #expect(spy.createdTitles == ["Milk 6"])
}

@Test func overrideAppliesForOneRunWithoutPersisting() async throws {
    let (intent, spy, store) = makeIntent()
    store.addItem(to: store.checklists[0].id, title: "Milk ((2))")
    intent.multiple = 5
    _ = try await intent.perform()
    #expect(spy.createdTitles == ["Milk 10"])
    #expect(store.checklists[0].multiple == 1)
}

@Test(arguments: [0, 100, -1])
func outOfRangeOverrideThrowsBeforeAnySideEffect(_ value: Int) async throws {
    let (intent, spy, _) = makeIntent()
    intent.multiple = value
    spy.accessStatusValue = .notDetermined // must be ignored; validation is first
    do {
        _ = try await intent.perform()
        Issue.record("out-of-range multiple should throw")
    } catch let error as RunChecklistIntentError {
        #expect(error.errorDescription == "Multiple must be between 1 and 99.")
    }
    #expect(spy.createdTitles.isEmpty)
}
```
- `LocalizationTests` requires no change beyond the Core fixture entry.

### Verification
#### Automated
- [x] `make test-unit` passes (intent suite + Core localization)
- [x] `scripts/l10n-check.sh` passes (Core key)

#### Manual
- [ ] In Shortcuts, run "Run Checklist" with no Multiple → stored factor applies
- [ ] Run with Multiple `4` → this run scales by 4; re-run without it → stored factor returns
- [ ] Run with Multiple `0` → `Multiple must be between 1 and 99.` and no reminders created

---

## Phase 5: Hardening — edge cases, i18n completeness, full gate

**Outcome**: no new capability; sad paths and residual risks are pinned and the
whole tree is provably green.

### Changes

**Files**: the resolver/render/intent test suites; `ChecklistScaling` and the
catalogs only if a sad path surfaces a fix.

- Pin, if not already covered by earlier phases:
  - resolver: `((0))` → `0`, unmatched/non-numeric/overflow → literal,
    `multiple == 1` fast path, scale-then-prefix ordering, marker on
    description path (Path A);
  - Stepper bound is `Checklist.multipleRange` (`1...99`) and its accessibility
    identifier is `checklistScalingStepper`;
  - all new keys present in all six languages and in `requiredKeys`;
  - `×%lld` is an `ExclusionEntry` (identical across languages).
- No `currentVersion` bump, no migration, no codegen.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `scripts/l10n-check.sh` passes
- [x] `make watch-build` passes
- [x] `./scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Installed-bundle Watch render check per `AGENTS.md` (scaled title/description, no badge)
- [ ] Confirm no `ChecklistCodec.currentVersion` reference changed and no test references a new schema version

---

## Phase order & dependencies

- Phase 1 establishes the contract everything else consumes:
  `ChecklistScaling.resolve(_:multiple:)`, `Checklist.multiple`,
  `Checklist.multipleRange`, `Checklist.clampedMultiple(_:)`,
  `ChecklistStore.setMultiple(_:for:)`,
  `ChecklistReminders.create(...multipleOverride:)`.
- Phases 2–4 depend only on that contract and on each other's surface/carry
  changes; they can be verified independently via `make test-unit` and stop at
  the full `./scripts/test.sh` once, at the end.

## Deviations from `structure.md` (summary)

1. **`ChecklistStore.setMultiple` returns `SetDestinationOutcome`**, the existing
   sibling-setters' type — `MutationOutcome` does not exist in the codebase.
2. **`ChecklistMerge.swift` needs `merged.multiple = remoteChecklist.multiple`**;
   the remote-win branch copies coarse fields explicitly, so treating it as
   "coverage only" would drop remotely-won multiples.
3. **No Watch unit-test suite** exists/importable; Watch rendering is verified by
   the pure-resolver tests plus the installed-bundle check, not a Watch render
   suite.
4. **Overflow-safe multiplication** in the resolver (`multipliedReportingOverflow`)
   so a large parsed `n` cannot trap; treated as a non-match, consistent with the
   stated overflow policy.
