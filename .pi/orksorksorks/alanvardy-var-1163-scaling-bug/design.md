# Design Discussion

## Current State

- Marker resolution is a pure function, `ChecklistScaling.resolve(_:multiple:)`
  (`CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift:34`). Its
  first line is `guard multiple != 1, text.contains("((") else { return text }`
  (`:36`), so **factor 1 is an identity**: `((2))` survives literally. Its doc
  comment (`:30-33`) explicitly documents "Returns `text` unchanged when
  `multiple == 1`."
- Otherwise the resolver replaces each `((n))` run (literal `((`, one or more
  ASCII digits, `))`) with `n * multiple` (`:38-58`), leaving all other bytes
  untouched; non-marker / unparseable / overflowing runs pass through (`:50-54`).
- The factor model is `Scaling` (`Checklist.swift:204`): `.fixed(Int)` or
  `.prompt(lastFixed:)`. `.number` (`:213-218`) is the fixed value or the
  prompt's remembered default; `.displayNumber` (`:224-229`) is the fixed value
  but **always `1` in `.prompt`** — "the multiplier a *display* surface uses
  when no number has been asked for." Clamping lives in one place
  (`Checklist.swift:457-463`, `multipleRange = 1...99`).
- Resolution call sites (`research.md` Q4): `ChecklistCreator.create`
  (`:107`, `multiple` default `1` at `:95`, title only); `ChecklistReminders`
  title (`:73`) and description (`:75`) using
  `clampedMultiple(override ?? checklist.multiple)` (`:38`); the app detail view
  (`ChecklistDetailView.swift:274,293`) using `scaling.number`; and the Watch
  detail preview (`WatchChecklistDetailView.swift:53,55`) using
  `scaling.displayNumber`.
- The run path: `startRun` / `confirmPrompt` / `perform(multipleOverride:)`
  (`ChecklistRunViewModel.swift:57-93`) funnel into `ChecklistReminders.create`;
  the App Intent resolves its own multiple (`RunChecklistIntent.swift:140-172`)
  and also delegates to that funnel. Initial storage is never rewritten —
  scaling is render/create-only.
- The user-facing help text says "Scaling multiplies any integer in double
  brackets — e.g. ((2)) becomes 6 at Scaling 3. **The brackets are removed.**"
  (`ChecklistOptionsView.swift:78`), translated into all six languages
  (`Localizable.xcstrings:3079`) and pinned in `LocalizationFixtures` (`:102`).
- So the contract is stated three ways that disagree: doc comment + fast path
  say identity at 1, help text says brackets always removed, and the ticket
  reports the literal brackets as the defect. `multipleOneIsAFastPath`
  (`CheckStitchTests/ChecklistCreatorTests.swift:214`) pins the identity.

## Desired End State

- `ChecklistScaling.resolve(_:text, multiple:)` resolves markers for **every**
  multiplier, including `1`: `((2))` at factor 1 yields `2`. The `multiple != 1`
  short-circuit is gone; only the cheap "no `((` present" guard remains.
- The resolver's doc comment states the single rule: markers are always
  rewritten to `n * multiple`; there is no identity case.
- Because the seam is shared, this holds for fixed-1 and prompt-confirmed-1
  runs alike, on every consuming surface (core creator, reminders funnel, app
  detail view, Watch preview).
- Verification:
  - `multipleOneIsAFastPath` is replaced by `markersResolveAtOne` asserting
    `resolve("((2)) raw", multiple: 1) == "2 raw"`.
  - A `ChecklistReminders` test proves a `fixed(1)` checklist strips brackets
    on run; a `ChecklistRunViewModel` test proves a prompt confirmed at 1 does.
  - `make test-unit` passes, then the full gate `./scripts/test.sh` prints
    `gate: ok`.

## Patterns to Follow

- **Single clamp/resolve source.** Keep the fix inside `ChecklistScaling.resolve`
  (`ChecklistCreator.swift:34`); do not add per-caller or per-mode branches
  (`Checklist.swift:457-463` is the precedent for keeping one truth).
- **Pure seam + parameterised tests.** Follow the existing resolver suite shape:
  `@Test(arguments:)` cases over `(input, multiple, expected)`
  (`ChecklistCreatorTests.swift:198-231`), behaviour-named functions, `#expect`.
- **Funnel and VM suites are `@MainActor`** with shared fakes
  (`TestFixtures.swift`: `SpyReminderCreator :29`, `SpyReminderDestination :52`,
  `FakeScalingPrompter ~:155`); mirror `runScalesTitleAndDescription`
  (`ChecklistRemindersTests.swift:566`) and
  `createRemindersForwardsTheOverrideWithoutPersisting`
  (`ChecklistRunViewModelTests.swift:400`).
- **Doc comments carry the contract.** Where a comment and behaviour disagree,
  fix the comment (`ChecklistCreator.swift:30-33`), not the promise in
  `ChecklistOptionsView.swift:78`.
- **Bad pattern to avoid (found in research):** the `guard multiple != 1, ...`
  fast path (`ChecklistCreator.swift:36`) conflates "nothing to do" with
  "multiplier is 1". Correct it to the pure "no marker present" guard — do not
  reintroduce a numeric early-return.
- **Do NOT follow** the `displayNumber` divergence as a resolver contract: it is
  a display-only value (`Checklist.swift:224-229`) and must not leak into
  marker-removal semantics.

## Design Decisions

1. **Intended semantics at factor 1**: markers always resolve — `((2))` becomes
   `2` at `multiple == 1`. The shipped help text (`ChecklistOptionsView.swift:78`)
   is the user-facing contract and the ticket reports the literal brackets as the
   bug; keeping identity would invert a shipped promise (`ChecklistCreator.swift:36`).
2. **Scope**: universal, not prompt-only. A factor of 1 means the same thing in
   `.fixed(1)` and prompt-confirmed-1, and `resolve` is mode-agnostic
   (`ChecklistReminders.swift:38`); a per-mode split would need a new flag and
   produce two results for the same multiplier.
3. **Implementation locus**: inside `ChecklistScaling.resolve`
   (`ChecklistCreator.swift:34`). Replace the guard with
   `guard text.contains("((") else { return text }`; leave the marker grammar,
   ASCII-digit check, exact-`))` rule, `Int` parse and overflow guard untouched
   (`:38-58`). A single-seam change automatically covers every caller.
4. **Watch preview follows the contract** (`WatchChecklistDetailView.swift:53,55`):
   no call-site change. `displayNumber` stays `1` in prompt mode, but it now
   resolves, so a prompt preview renders `2` rather than `((2))`. One rule
   everywhere; no new preview/literal API.
5. **`displayNumber` value unchanged**: it stays `1` for `.prompt`
   (`Checklist.swift:224-229`) and is not removed. Only its rationale comment is
   reworded (it no longer implies brackets survive previews). The app detail
   view keeps using `scaling.number` (`:274,293`) — no change.
6. **Doc comments aligned**: delete the "Returns `text` unchanged when
   `multiple == 1`" sentence (`ChecklistCreator.swift:30-33`); state that every
   `((n))` marker is replaced regardless of `multiple`.
7. **Test contract (unit-only)**: replace `multipleOneIsAFastPath`
   (`ChecklistCreatorTests.swift:214`) with `markersResolveAtOne`; add a
   `fixed(1)` funnel test (`ChecklistRemindersTests.swift` pattern `:566`) and a
   prompt-confirmed-at-1 run-VM test (`ChecklistRunViewModelTests.swift` pattern
   `:352-400`). No launch seam, no UI test.
8. **Help text and localization unchanged**: `ChecklistOptionsView.swift:78` and
   the six catalog translations (`Localizable.xcstrings:3079`) already describe
   the corrected behavior, so no `Localizable.xcstrings` or
   `LocalizationFixtures` edit is needed.

## What We're NOT Doing

- Changing the help text or any localization/catalog entry — the current copy is
  correct under the chosen contract.
- Changing `Scaling` itself: no new case, no change to `.number`,
  `.displayNumber`'s value, `.isPrompt`, `.clamped()` or `.toggled()`.
- Removing or renaming `displayNumber` (its value stays; only the comment moves).
- Threading a mode/flag through `ChecklistReminders.create` or special-casing
  prompt-confirmed runs.
- Changing the marker grammar, the exact-`))` rule, the ASCII-digit check, `Int`
  parse, overflow handling, or `multiple == 0` behavior.
- Touching title numbering (`ChecklistTitleNumbering.title`,
  `ChecklistCreator.swift:23-26`) or create-order composition (`:105-108`).
- Changing persistence, codable keys, clamping, export/import or sync; scaling
  remains render/create-only and stored item text is never rewritten.
- Changing the App Intent's multiple resolution (`RunChecklistIntent.swift:140-172`).
- Adding a UI/launch seam or an end-to-end UI test for scaling.
- Migrating or rewriting existing checklists; the change applies at the next run.

## Open Risks

- **Prompt-mode Watch preview loses the marker cue.** After the fix a prompt
  preview shows `2` where it previously showed `((2))`. This is the deliberate
  consequence of Q3=A; if it turns out to be a UX regression, revisit with the
  "unify previews on `scaling.number`" option rather than re-special-casing
  `resolve`.
- **Silent retitle of existing fixed-1 checklists.** Any stored checklist with a
  literal `((n))` and factor 1 will produce `n` on its next run. Intended, but it
  is a user-visible change shipped without a migration.
- **`ChecklistCreator.create`'s default `multiple: Int = 1` (`:95`)** now strips
  markers in tests that relied on the default taking the fast path; audit those
  callers when editing (the "Path B" test-only path).
- **`displayNumber` orphan risk.** It now behaves identically to a resolve at 1;
  Periphery may later flag it. Not removed in this ticket.
