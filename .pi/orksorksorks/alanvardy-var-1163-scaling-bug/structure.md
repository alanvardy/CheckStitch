# Structure Outline

## Approach

VAR-1163 is a **single-seam correction**, not a feature build. `ChecklistScaling.resolve`
is a pure function every render/create surface already funnels through
(`ChecklistCreator`, `ChecklistReminders`, app detail view, Watch preview), so the
behaviour change is one guard in one file. The only genuinely vertical work is
(a) make the seam resolve markers at every multiplier, and (b) prove the run stack
honours it at factor 1 and locks the corrected contract with tests. There is no
new persistence, no call-site change, and no UI/launch seam — the design forbids them.

The "layers" here are thin (pure resolver → funnel → run VM / previews), and the
design states the fix at `ChecklistScaling.resolve` "automatically covers every
caller." Phases 1 and 2 are therefore test-verified increments over the same code
change rather than independent features — this is the one place the vertical-slice
rule compresses, and it is called out per phase.

## Phase 1: Walking skeleton — the resolver strips markers at every multiplier

**Outcome**: A checklist run with any scaling factor — including `fixed(1)` and a
prompt confirmed at `1` — produces reminder title/description text with `((n))`
rewritten to `n`, exactly as the shipped help text promises. Because the seam is
shared, this is the whole production fix; its green tests prove the core contract.

**Files** (`CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift`,
`CheckStitchTests/ChecklistCreatorTests.swift`)

**Key changes**:
- `ChecklistScaling.resolve(_ text: String, multiple: Int) -> String` — **modified
  guard**: `guard multiple != 1, text.contains("((")` →
  `guard text.contains("((") else { return text }`. Marker grammar, ASCII-digit
  check, exact-`))` rule, `Int` parse, overflow guard untouched (`:38-58`).
- Doc comment `:30-33` — **modified**: delete the "Returns `text` unchanged when
  `multiple == 1`." sentence; state that every `((n))` marker resolves regardless
  of `multiple`.
- `markersResolveAtOne` — **new** `@Test` replacing `multipleOneIsAFastPath`
  (`:214`): `#expect(resolve("((2)) raw", multiple: 1) == "2 raw")`.

**Contract**: `resolve(text, multiple:)` returns `n * multiple` for every
`multiple` (including `1`); the only pass-through case is "no `((` substring".
Callers may rely on factor 1 removing markers; no caller passes a mode flag.

**Tests**: `markersResolveAtOne` (happy, factor 1) + existing
`resolveScalesMarkers`, `nonMarkersPassThroughByteForByte`,
`overflowingDigitsPassThrough` (sad paths) still green. Audit
`createScalesTitlesWhenMultipleProvided` / "Path B" callers that rely on
`create`'s default `multiple: Int = 1` and confirm none assert literal brackets.
**Verify**: `make test-unit` passes.

---

## Phase 2: Run-path regression lock — fixed-1 and prompt-confirmed-1 end to end

**Outcome**: The user-visible run paths are pinned by tests: a `fixed(1)` checklist
and a prompt run confirmed at `1` both emit bracket-free reminder text, while
stored item text is never rewritten.

**Files** (`CheckStitchTests/ChecklistRemindersTests.swift`,
`CheckStitchTests/ChecklistRunViewModelTests.swift`,
`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` — comment only)

**Key changes**:
- Funnel test **new**: `fixedOneStripsMarkersOnRun` — `fixed(1)` checklist through
  `ChecklistReminders.create`, asserting created title/description carry `2`.
  Mirrors `runScalesTitleAndDescription` (`ChecklistRemindersTests.swift:566`).
- Run-VM test **new**: `promptConfirmedAtOneStripsMarkers` — prompt-mode checklist,
  `confirmPrompt(multiple: 1)`, asserting created text is bracket-free. Mirrors
  `createRemindersForwardsTheOverrideWithoutPersisting`
  (`ChecklistRunViewModelTests.swift:400`).
- `Checklist.displayNumber` rationale comment (`:224-229`) — **modified** only:
  it no longer implies a prompt preview keeps brackets; value and API unchanged.

**Contract**: `ChecklistReminders.create` with `multiple == 1` (from either a
`fixed(1)` checklist or a `1` override) yields resolved text; run override remains
per-run and is never persisted. `displayNumber` stays `1` in `.prompt`, and it now
resolves at `1` — no call-site change.

**Tests**: `fixedOneStripsMarkersOnRun`, `promptConfirmedAtOneStripsMarkers` +
existing `runningDoesNotRewriteStoredItemText` (`:585`) and
`displayNumberIsNeutralForPrompt` (`ScalingTests.swift:25`) unaffected.
**Verify**: `make test-unit` passes.

---

## Phase 3: Hardening — contract audit, previews, full gate

**Outcome**: The change ships with the full gate green and the two non-testable
surfaces (app detail view, Watch preview) manually confirmed, so the deliberate
UX consequence is seen rather than assumed.

**Files** (audit only; `CheckStitch/ChecklistDetailView.swift`,
`CheckStitchWatch/WatchChecklistDetailView.swift`, `CheckStitch/ChecklistOptionsView.swift`)

**Key changes**: none in production. Audit that no preview call site needs a
mode branch (`ChecklistDetailView.swift:274,293` on `scaling.number`;
`WatchChecklistDetailView.swift:53,55` on `scaling.displayNumber`) and that the
help text + six translations already match the corrected behaviour (no catalog
edit). Confirm `RunChecklistIntent` resolution is untouched.

**Contract**: `resolve` remains mode-agnostic; only the "no `((`" guard survives;
no `Localizable.xcstrings` or `LaunchSeams` change.

**Tests**: full suite `CheckStitchTests` + shell tests via the gate.
**Verify**: `./scripts/test.sh` prints `gate: ok`; **manual** — `make run`, open a
checklist with item text `((2))` at factor 1, run it and confirm the reminder reads
`2`; eyeball the app detail and Watch preview.

## Testing Checkpoints

- **After Phase 1**: `make test-unit` green — resolver returns `2` at `multiple: 1`
  and all pass-through sad paths unchanged; do not proceed until
  `markersResolveAtOne` replaces `multipleOneIsAFastPath`.
- **After Phase 2**: `make test-unit` green — funnel and run-VM tests prove
  `fixed(1)` and prompt-confirmed-1 strip markers; `displayNumber` value test
  still green.
- **After Phase 3**: `./scripts/test.sh` prints `gate: ok` and the manual run +
  preview check is observed.
