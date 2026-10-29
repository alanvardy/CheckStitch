# Implementation Plan

## Overview

`((n))` markers must resolve at **every** scaling factor, including `1`:
`((2))` becomes `2` at factor 1, exactly as the shipped help text promises. The
fix is a single guard change in `ChecklistScaling.resolve`, which every
render/create surface already funnels through, locked by unit tests at the
resolver, funnel, and run-VM levels.

Phase order follows `structure.md`: a walking skeleton that corrects the resolver
and its pinned test (Phase 1), a run-path regression lock end to end (Phase 2),
then a hardening/audit phase with the full gate and manual checks (Phase 3).
Phases 1 and 2 are test-verified increments over the same production change — the
one place the vertical-slice rule compresses, because the shared `resolve` seam
makes the production change complete in Phase 1 and Phase 2 pins the run stack
against it.

---

## Phase 1: Walking skeleton — the resolver strips markers at every multiplier

**Outcome**: `ChecklistScaling.resolve(text, multiple:)` rewrites `((n))` to
`n * multiple` for any multiplier, including `1`. The production fix is complete
after this phase because the seam is shared by every caller. Its unit tests go
green.

### Changes

#### 1. Correct the resolver guard and its doc comment
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift`
**Action**: modify (lines ~30-36)

Replace the `multiple != 1` short-circuit — the sole defect — with the pure
"is there a marker to look for" guard. Leave the marker grammar, ASCII-digit
check, exact-`))` rule, `Int` parse, overflow guard and character-by-character
copy untouched (`:38-58`). Update the doc comment to state the single rule.

```swift
/// Replaces every `((n))` marker (literal `((`, one or more ASCII digits, `))`)
/// with the product `n * multiple`, leaving all other text byte-for-byte
/// unchanged. Every `((n))` marker is replaced regardless of `multiple`,
/// including `multiple == 1`. A marker whose digits do not parse as `Int`, or
/// whose product overflows `Int`, is left literal. Pure; no model dependency.
public enum ChecklistScaling {
    public static func resolve(_ text: String, multiple: Int) -> String {
        guard text.contains("((") else { return text }
        // ... body unchanged ...
    }
}
```

The doc comment change deletes the sentence "Returns `text` unchanged when
`multiple == 1`." and adds the "regardless of `multiple`" statement.

#### 2. Replace the test that pins factor-1 identity
**File**: `CheckStitchTests/ChecklistCreatorTests.swift`
**Action**: modify (lines ~213-216)

`multipleOneIsAFastPath` asserts the buggy behaviour; replace it with
`markersResolveAtOne`, asserting the corrected contract. Keep `#expect` and the
behaviour-named function convention.

```swift
@Test
func markersResolveAtOne() {
    #expect(ChecklistScaling.resolve("((2)) raw", multiple: 1) == "2 raw")
}
```

Delete `multipleOneIsAFastPath` entirely — it must not survive. The nearby
parameterised cases (`resolveScalesMarkers`, `nonMarkersPassThroughByteForByte`,
`overflowingDigitsPassThrough`) need no change: they already use multiples
`2/3/4/5`, and their pass-through expectations are unaffected by removing the
fast path.

#### 3. Audit callers relying on the default `multiple: Int = 1`
**File**: `CheckStitchTests/ChecklistCreatorTests.swift` (and any else in
`CheckStitchTests/` found by the search below)
**Action**: audit only — edit only if a test asserts literal brackets.

`ChecklistCreator.create(from:multiple:)` defaults `multiple` to `1`
(`ChecklistCreator.swift:95`), so any test invoking `create(from:)` without a
multiple now resolves markers. `createScalesTitlesWhenMultipleProvided` passes
`multiple: 5` and is unaffected. Search for callers and confirm none assert
literal brackets:

```bash
rg -n 'create\(from:' CheckStitchTests CheckStitchCore | rg -v 'multiple:'
```

If such an assertion exists, update its expected string to the resolved text
(do not weaken the assertion). If none exists, no edit.

### Verification

#### Automated
- [x] `make test-unit` passes.
- [x] `markersResolveAtOne` is present and `multipleOneIsAFastPath` is gone:
      `rg -n 'multipleOneIsAFastPath' CheckStitchTests` returns nothing;
      `rg -n 'markersResolveAtOne' CheckStitchTests` returns exactly one hit.
- [x] `make build` passes (warnings-as-errors on the app target).
- [x] The audit search above returns no test relying on default-1 literal
      brackets (or any found case was updated in this phase).

#### Manual
- [ ] Confirm the resolver body below the guard is byte-identical to the previous
      implementation (`git diff` shows only the guard line, the doc comment, and
      the test file).

### Testing checkpoint
Do not start Phase 2 until `make test-unit` is green and
`markersResolveAtOne` has replaced `multipleOneIsAFastPath`.

---

## Phase 2: Run-path regression lock — fixed-1 and prompt-confirmed-1 end to end

**Outcome**: The two user-visible run paths are pinned by tests: a `fixed(1)`
checklist and a prompt run confirmed at `1` both emit bracket-free reminder
text, while stored item text is never rewritten.

### Changes

#### 1. Funnel test: `.fixed(1)` strips markers on run
**File**: `CheckStitchTests/ChecklistRemindersTests.swift`
**Action**: modify (add a test near `runScalesTitleAndDescription`, `:566`)

Mirror `runScalesTitleAndDescription` with `scaling: .fixed(1)`. Use the
existing `create(_:targeting:)` helper (`:19`, gate-free, isolated counter) and
`SpyReminderDestination`.

```swift
/// A factor of 1 is not an identity: markers are still removed on run.
@Test
func fixedOneStripsMarkersOnRun() async {
    let spy = SpyReminderDestination()
    spy.lists = snapshot()
    let checklist = Checklist(
        items: [makeItem("milk ((2))", description: "((4)) boxes")],
        destination: .list("list-a"),
        prefixesReminderNumbers: true,
        scaling: .fixed(1))

    let outcome = await create(checklist, targeting: spy)

    #expect(outcome == .created(count: 1))
    #expect(spy.createdTitles == ["1: milk 2"])
    #expect(spy.createdNotes == ["4 boxes"])
}
```

#### 2. Run-VM test: prompt confirmed at `1` strips markers
**File**: `CheckStitchTests/ChecklistRunViewModelTests.swift`
**Action**: modify (add a test in the run-VM suite near `:400`)

Mirror `createRemindersForwardsTheOverrideWithoutPersisting` / the
`promptModeParksTheRunUntilConfirmed` flow:
`makeStore(items:)` (defaults to `.fixed(1)`), `store.setScaling(.prompt(lastFixed: 1), for: id)`,
`resolvableDestination()`, `makeViewModel(store:targeting:)`, then
`startRun` → `confirmPrompt(multiple: 1)` → `await task?.value`.

```swift
@Test
func promptConfirmedAtOneStripsMarkers() async {
    let (store, id) = makeStore(items: ["milk ((2))"])
    store.setScaling(.prompt(lastFixed: 1), for: id)
    let spy = resolvableDestination()
    let viewModel = makeViewModel(store: store, targeting: spy)

    viewModel.startRun(for: id)
    #expect(viewModel.promptingRunID == id)

    let task = viewModel.confirmPrompt(multiple: 1)
    await task?.value

    #expect(spy.createdTitles == ["milk 2"])
    #expect(store.checklist(id: id)?.scaling == .prompt(lastFixed: 1),
            "a confirmed factor is never persisted")
}
```

#### 3. Reword the `displayNumber` rationale comment
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify (comment only, lines ~224-229)

`displayNumber` keeps returning `1` for `.prompt`; only its comment must no
longer imply a prompt preview keeps brackets. Value and API unchanged.

```swift
    /// The multiplier a *display* surface uses when no number has been asked for:
    /// a prompt's `lastFixed` is not the multiplier for this run, so the surface
    /// resolves at the neutral value. Markers still resolve — at factor `1` a
    /// `((2))` preview therefore reads `2`, not `((2))`.
    public var displayNumber: Int {
        switch self {
        case .fixed(let value): return Checklist.clampedMultiple(value)
        case .prompt: return 1
        }
    }
```

### Verification

#### Automated
- [x] `make test-unit` passes.
- [x] New tests exist:
      `rg -n 'fixedOneStripsMarkersOnRun|promptConfirmedAtOneStripsMarkers' CheckStitchTests`.
- [x] Existing pins still green and unchanged:
      `runningDoesNotRewriteStoredItemText` (`ChecklistRemindersTests.swift:585`),
      `displayNumberIsNeutralForPrompt` (`ScalingTests.swift:25`),
      `createRemindersForwardsTheOverrideWithoutPersisting`
      (`ChecklistRunViewModelTests.swift:400`).
- [x] `make build` passes.

#### Manual
- [ ] `git diff CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` shows only
      the comment lines changed — no switch arm or value change.

### Testing checkpoint
Do not start Phase 3 until `make test-unit` is green and both new run-path tests
pass.

---

## Phase 3: Hardening — contract audit, previews, full gate

**Outcome**: The full gate is green and the two non-testable surfaces (app detail
view, Watch preview) are manually confirmed, so the deliberate UX consequence is
seen rather than assumed.

### Changes

No production changes in this phase. Audit only:

#### 1. Confirm no preview call site needs a mode branch
**Files** (read-only):
`CheckStitch/ChecklistDetailView.swift` (`:274`, `:293` — on `scaling.number`),
`CheckStitchWatch/WatchChecklistDetailView.swift` (`:53`, `:55` — on
`scaling.displayNumber`).
**Action**: audit only.

Confirm both sites call `ChecklistScaling.resolve` with their existing value and
contain no `if scaling.isPrompt` / literal-bracket special case. `resolve` is now
mode-agnostic; `scaling.number` for `.prompt` is `lastFixed` and
`scaling.displayNumber` for `.prompt` is `1`, and both now resolve. No call-site
edit.

#### 2. Confirm the help text and six translations already match
**Files** (read-only): `CheckStitch/ChecklistOptionsView.swift:78` and
`CheckStitch/Localizable.xcstrings:3079`.
**Action**: audit only. Both already say "The brackets are removed" in all six
languages; `LocalizationFixtures.requiredKeys` (`:102`) already pins the key. **No
catalog or fixtures edit.** Do not run an l10n key addition; nothing new.

#### 3. Confirm `RunChecklistIntent` resolution is untouched
**File** (read-only): `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift:140-172`.
**Action**: audit only. It delegates to `ChecklistReminders.create`, so it
inherits the corrected contract with no edit.

### Verification

#### Automated
- [x] `./scripts/test.sh` prints `gate: ok` (this runs `make build`, simulator
      pre-boot, `make test`, `make build-mac`, `make watch-build`,
      `scripts/tests/run.sh`, `shellcheck`).
- [x] `rg -n 'displayNumber' CheckStitchWatch CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
      confirms the Watch preview still uses `displayNumber` and its value is
      unchanged.
- [x] `git status` shows no changes under `CheckStitch/Localizable.xcstrings` or
      `CheckStitchTests/LocalizationFixtures.swift`.

#### Manual
- [ ] `make run`; open a checklist whose item title is `((2))` at factor 1 (or
      set scaling to 1 / confirm the prompt with 1), run it, and confirm the
      created reminder reads `2` (no literal brackets), while the checklist's
      stored item text still shows `((2))`.
- [ ] Eyeball the app detail view for `.prompt` mode (renders at `lastFixed`) and
      the Watch detail preview (renders at `displayNumber == 1`) — both should
      show bracket-free text, the deliberate consequence recorded in
      `design.md`'s "Open Risks".

---

## Files touched — cross-check against `structure.md`

- `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift` — guard + doc
  comment (Phase 1).
- `CheckStitchTests/ChecklistCreatorTests.swift` — replace
  `multipleOneIsAFastPath`, audit default-1 callers (Phase 1).
- `CheckStitchTests/ChecklistRemindersTests.swift` — `fixedOneStripsMarkersOnRun`
  (Phase 2).
- `CheckStitchTests/ChecklistRunViewModelTests.swift` —
  `promptConfirmedAtOneStripsMarkers` (Phase 2).
- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` — `displayNumber`
  comment only (Phase 2).
- `CheckStitch/ChecklistDetailView.swift`,
  `CheckStitchWatch/WatchChecklistDetailView.swift`,
  `CheckStitch/ChecklistOptionsView.swift` — audit only (Phase 3).

No migration, no codegen, no localization key, no schema change: the change is a
pure seam correction whose stored data is never rewritten and whose behavior
applies at the next run.
