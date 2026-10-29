# Research Findings — VAR-1163 Scaling Marker Resolution

## Q1: How does `ChecklistScaling.resolve(_:multiple:)` transform text today — the exact marker grammar and output for `multiple == 1` vs `> 1`?

### Findings
- Definition: `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift:34` —
  `public enum ChecklistScaling`, single member `resolve(_ text:multiple:)` at `:35`.
- Fast-path guard: `guard multiple != 1, text.contains("((") else { return text }`
  (`ChecklistCreator.swift:36`). **`multiple == 1` returns the input unchanged**, so
  `((2))` markers survive literally.
- Doc comment (`:30-33`) explicitly documents this identity: "Returns `text`
  unchanged when `multiple == 1`."
- Marker grammar (must satisfy all, `:38-58`): literal `((` (`:38-39`); one or more
  **ASCII** digits (`character.isASCII && character.isNumber`, helper `:75-77`);
  closed by exactly `))` (`:45-50`); a third `)` immediately after makes it an
  over-parenthesised literal (`:50-52`); digits must parse as `Int` (`:53`);
  `value * multiple` must not overflow (`multipliedReportingOverflow`, `:54`).
- On match the whole `((n))` run is replaced by the decimal product (`:55`); all
  other text is appended one character at a time (`:62-63`), byte-for-byte.
- `multiple == 0` is not special-cased: it takes the non-fast path and yields
  `((n))` → `0`.
- Sibling `ChecklistTitleNumbering.title(_:position:numbered:itemCount:)` at
  `:23`: when `numbered` is false returns the title unchanged (`:24`); otherwise
  prefixes `"<position>: "`, zero-padding single digits only when
  `itemCount > 9` (`:25-26`).
- Composition order: `ChecklistCreator.create` scales first, then numbers
  (`:105-108`).

## Q2: How is a checklist's scaling factor modeled and derived?

### Findings
- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:204` —
  `public enum Scaling: Equatable, Hashable, Sendable` with `case fixed(Int)`
  and `case prompt(lastFixed: Int)` (`:204-210`). Doc: "The legacy numeric view
  of this value is `Checklist.multiple`" (`:202-203`).
- `.number` (`:213-218`): clamped `.fixed` value, or the prompt's remembered
  `lastFixed` for `.prompt`; both route through `Checklist.clampedMultiple`.
- `.displayNumber` (`:224-229`): `.fixed` → clamped value; **`.prompt` → `1`**
  ("the multiplier a *display* surface uses when no number has been asked for").
- `.isPrompt` (`:232-235`): `true` only for `.prompt`; boolean discriminant used
  by run/decode/UI (`RunChecklistIntent.swift:141`,
  `ChecklistRunViewModel.swift:62`, `ChecklistOptionsView.swift:74,143`,
  `Checklist.swift:430`).
- `.clamped()` (`:240-243`) normalises the carried number; `.toggled()` (`:249-252`)
  converts `.fixed(v)` ↔ `.prompt(lastFixed: v)` carrying the number.
- Range/clamp in one place (`Checklist.swift:457-463`):
  `multipleRange: ClosedRange<Int> = 1...99`, `clampedMultiple(_:)`.
- Persistence: stored `scaling` at `:328`; `init(from:)` (`:389-392`) reads the
  numeric `multiple` key (default 1, clamped) and `scalingMode`
  (`"prompt"` → `.prompt(lastFixed:)`, absent/unknown → `.fixed`); `encode(to:)`
  (`:429-430`) writes both `multiple` (shadow) and `scalingMode`. CodingKeys
  `:376`; additive keys, no version bump (`:322-327`).
- Legacy accessor `public var multiple: Int { scaling.number }` (`:333`),
  read-only. `ChecklistStore.setScaling` (`ChecklistStore.swift:403-412`) clamps
  via `.clamped()`, no-ops on equality, bumps `revision`/`modifiedAt`.

## Q3: How does the run path select a multiple and thread it into marker resolution?

### Findings
- App run VM `CheckStitch/ChecklistRunViewModel.swift`:
  - `startRun(for:)` (`:57-68`): `.prompt` parks the run (`promptingRunID = id`,
    return nil); `.fixed` runs immediately via `createReminders(for: id)` with no
    override.
  - `cancelPrompt()` (`:71-73`) clears `promptingRunID`.
  - `confirmPrompt(multiple:)` (`:78-82`): sheet's Int becomes `multipleOverride`.
  - `createReminders(for:multipleOverride:)` (`:87-93`) → `perform(...)`.
  - `perform(checklist:multipleOverride:destination:)` (`:131-157`) calls
    `ChecklistReminders.create(... multipleOverride: ...)` at `:140-142`. Override
    is per-run, never persisted (comment `:85-86`).
- Prompt sheet `CheckStitch/PromptScalingSheet.swift`: seeded from clamped
  `lastFixed` (`:16-21`); `validated(_:)` returns Int only in `multipleRange`
  (`:27-33`); Confirm disabled unless valid (`:56-60`). Wired at
  `CheckStitch/ContentView.swift:764-768` with `lastFixed: checklist.scaling.number`;
  dismissal cancels the parked run via the binding (`:757-761`).
- Funnel `CheckStitchCore/Sources/CheckStitchCore/ChecklistReminders.swift`:
  `create(from:targeting:gate:multipleOverride:destination:)` (`:25`); resolves
  `let multiple = Checklist.clampedMultiple(multipleOverride ?? checklist.multiple)`
  (`:35`, per Q4 report line 38); threads it into title (`:72-73`) and description
  (`:75`) resolution. Convenience `create(from:)` (`:9-11`) passes nil override;
  used at `CheckStitch/MyApp.swift:135`.
- App Intent `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift`:
  `@Parameter(title: "Multiple") var multiple: Int?` (`:51-52`); explicit value
  validated against range before side effects (`:103-105`); resolution (`:140-155`):
  explicit `multiple` wins; else a `.prompt` checklist asks via `ScalingPrompting`
  (`AppIntentScalingPrompter` `:18-25`); failure/cancel → dialog
  `scalingPromptUnavailable`; out-of-range → `.invalidMultiple`. `resolvedMultiple`
  passed at `:167-172`.

## Q4: How do each of the marker-resolution call sites invoke it and with what multiple?

### Findings
Four call sites, one definition (`ChecklistCreator.swift:34`):
- Core `ChecklistCreator.create(from:multiple:)` — `ChecklistCreator.swift:107`.
  Parameter default `multiple: Int = 1` (`:95`); resolves **title only**. Passing
  the default takes the fast path.
- `ChecklistReminders` — `ChecklistReminders.swift:73` (title) and `:75`
  (description). Multiple = `clampedMultiple(multipleOverride ?? checklist.multiple)`
  (`:38`). Passes 1 only indirectly when the override is nil and the stored value
  clamps to 1 (e.g. default `.fixed(1)`).
- App detail view `CheckStitch/ChecklistDetailView.swift:274` (title) / `:293`
  (description) — uses `scaling.number`. For `.prompt` this resolves at
  `lastFixed`, **not** 1. `scaling` comes from `checklist.scaling`
  (`ChecklistDetailView.swift:60`).
- Watch detail preview `CheckStitchWatch/WatchChecklistDetailView.swift:53` (title)
  / `:55` (description) — uses `scaling.displayNumber`, which is **always `1` in
  `.prompt` mode** and the fixed factor otherwise.
- App Intent does not call `resolve` directly; it delegates to
  `ChecklistReminders.create` (`RunChecklistIntent.swift:167-172`).

## Q5: What tests and fixtures pin marker-resolution and scaling behavior?

### Findings
Resolver unit tests — `CheckStitchTests/ChecklistCreatorTests.swift`:
- `resolveScalesMarkers` (`:198`) parameterised: `((3))`×2→`6`, `((0))`×5→`0`,
  `x ((2)) y`×3→`x 6 y`.
- `nonMarkersPassThroughByteForByte` (`:203`): `((abc))`, `(x)`, `((3)`, `3))`,
  `((3)))` unchanged at multiple 4.
- `overflowingDigitsPassThrough` (`:207`).
- **`multipleOneIsAFastPath` (`:214`)**: `resolve("((2)) raw", multiple: 1) == "((2)) raw"`
  — pins the unchanged behaviour.
- `titleIsScaledThenPrefixed` (`:219`); `createScalesTitlesWhenMultipleProvided`
  (`:225`).

Funnel — `CheckStitchTests/ChecklistRemindersTests.swift` (`@MainActor`):
- `runScalesTitleAndDescription` (`:566`); `runningDoesNotRewriteStoredItemText`
  (`:585`); `overrideScalesThisRunOnly` (`:675`).

Run VM — `CheckStitchTests/ChecklistRunViewModelTests.swift` (`@MainActor`):
`fixedModeRunsImmediatelyWithoutPrompting` (`:352`),
`promptModeParksTheRunUntilConfirmed` (`:366`), `cancelPromptDismissesWithoutRunning`
(`:391`), `createRemindersForwardsTheOverrideWithoutPersisting` (`:400`).

App Intent — `CheckStitchTests/RunChecklistIntentTests.swift` (`@MainActor`):
`absentOverrideUsesStoredMultiple` (`:246`), `overrideAppliesForOneRunWithoutPersisting`
(`:256`), `outOfRangeOverrideThrowsBeforeAnySideEffect` (`:268`),
`promptModeAsksForANumberAndScalesByIt` (`:444`), `explicitMultipleSkipsThePrompt`
(`:463`), `fixedModeNeverPrompts` (`:479`), `failingPrompterReportsADialogAndCreatesNothing`
(`:495`), `cancelledPrompterReportsADialogAndCreatesNothing` (`:~525`),
`outOfRangePromptedValueThrowsInvalidMultiple` (`:560`).

Scaling model — `CheckStitchTests/ScalingTests.swift`: `numberClampsIntoTheSharedRange`
(`:6`), `toggledPreservesTheNumberAcrossModes` (`:12`),
`clampedNormalisesTheCarriedNumber` (`:19`), **`displayNumberIsNeutralForPrompt`
(`:25`)** (`.prompt(7).displayNumber == 1`).

Prompt sheet — `CheckStitchTests/PromptScalingSheetTests.swift:7,12,18`.

Codec (XCTest) — `CheckStitchTests/ChecklistCodecTests.swift`:
`testEncodeWritesBothScalingKeys` (`:600`), `testScalingRoundTripsBothModes`
(`:609`), `testLegacyPayloadWithoutScalingModeDecodesAsFixed` (`:618`),
`testOutOfRangeMultipleClamps` (`:659`), etc.

Fakes/fixtures — `CheckStitchTests/TestFixtures.swift`: `makeItem`
(`:149` area), `makeIsolatedDefaults` (`:17`), `SpyReminderCreator` (`:29`),
`SpyReminderDestination` (`:52`), `FakeScalingPrompter` (`:~155`),
`TestError.boom`.

Detail badge — `CheckStitchTests/ChecklistDetailViewTests.swift:188-228` pins
`showsScalingFactor` and `multipleRange == 1...99`.

No scaling-specific UI test exists; `CheckStitchUITests/CheckStitchUITests.swift`
has none, and `LaunchSeams.swift` contains no scaling seam.

## Q6: What does the user-facing scaling help text/localization say, and where is it surfaced?

### Findings
- Footer help text — `CheckStitch/ChecklistOptionsView.swift:78`: "Scaling
  multiplies any integer in double brackets — e.g. ((2)) becomes 6 at Scaling 3.
  **The brackets are removed.**"
- Factor accessibility hint — `ChecklistOptionsView.swift:177` (iOS) / `:185`
  (macOS): "Scale item markers by this factor when creating reminders."
- Surfaced as the footer of the Scaling `Section` (`:71-79`), reachable from
  `ChecklistDetailView.swift:47` (`NavigationLink`), title "Checklist Options"
  (`:81`).
- Catalog key at `Localizable.xcstrings:3079` (footer) and `:3038` (hint), both
  translated into all 6 languages (en/de/es/fr/ja/zh-Hans); all six translations
  state that the brackets are removed.
- Both keys are pinned in `CheckStitchTests/LocalizationFixtures.swift`
  `requiredKeys` `:100` (hint) and `:102` (footer).

## Cross-Cutting Observations
- **The `multiple == 1` fast path is load-bearing for two preview surfaces.**
  The Watch preview deliberately passes `1` in `.prompt` mode via
  `displayNumber` (`Checklist.swift:224-229`; pinned by `ScalingTests.swift:25`),
  so the marker text shown on the Watch stays bracketed. The app detail view
  instead passes `scaling.number` (`.prompt` → `lastFixed`). Any change to the
  `resolve` fast path interacts with both.
- **The contract is stated in three places that disagree**: the resolver doc
  comment (`ChecklistCreator.swift:30-33`, identity at 1), the user help text
  (`ChecklistOptionsView.swift:78`, brackets always removed), and the ticket.
- **Genuine production call sites all funnel through `ChecklistReminders.create`**
  for actual reminder creation (`ChecklistRunViewModel`, `RunChecklistIntent`,
  `MyApp.swift:135`); `ChecklistCreator.create` is described in tests as the
  "Path B" test-only path.
- **Scaling is render/create-only** — stored item text is never rewritten
  (`ChecklistRemindersTests.swift:585`), so this affects created reminder titles
  and notes plus previews, not persistence.
- **The clamp lives in exactly one place** (`Checklist.multipleRange`,
  `clampedMultiple`), read by the store, codec, intent validation, and sheet
  validation.

## Open Areas
- The exact intended semantics at `multiple == 1` (strip brackets vs leave
  literal) is not resolvable from the codebase — the code, doc comment, and help
  text contradict, and the ticket leaves it open. This is the DESIGN_SIGN-OFF
  question for the design step.
- Whether fixed-1 checklists (not just prompt-confirmed runs) must also strip
  brackets is a product decision not derivable from source.
- `ChecklistCreator.create`'s `multiple` parameter default value line was
  reported at `:95` from a partial read; confirm exact declaration when editing.
- No UI test asserts bracket handling end-to-end through the run button.
