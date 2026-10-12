# Design Discussion

Ticket: VAR-1127 — add a "Prompt" scaling option alongside the existing numeric
scaling on a checklist. Running a Prompt checklist asks the user for a number
and scales the created reminders by it. Applies both in-app and via the App
Intent.

## Current State

- **Model.** Scaling is a single stored `Checklist.multiple: Int`, default 1,
  clamped to `1...99` by the one source `multipleRange`/`clampedMultiple`
  (`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:344-349`); the clamp is
  applied at decode (`:281`), in the store setter (`ChecklistStore.swift:388-402`)
  and in intent validation (`RunChecklistIntent.swift:70`). `multiple` is additive:
  `decodeIfPresent` + default, no version bump (`Checklist.swift:280-284`).
  `ChecklistCodec.currentVersion = 5` (`:564`), `classify(_:)` maps v5 → `.loaded`,
  v4–v2 → `.migratable`, future → `.unsupportedVersion` → store loads empty with
  `canOverwriteStoredPayload = false` (`ChecklistStore.swift:103-106`).
- **Run funnel.** Both consum points reach one function:
  `ChecklistReminders.create(from:targeting:gate:multipleOverride:)`
  (`ChecklistReminders.swift:26,34`) — the app passes `nil`
  (`Checklist/ChecklistRunViewModel.swift:57`), the intent passes its parameter
  (`RunChecklistIntent.swift:97-101`). `multipleOverride` is per-run only and never
  persisted. Scaling is pure: `ChecklistScaling.resolve(title, multiple)` multiplies
  `((n))` markers, no-op at 1 (`ChecklistCreator.swift:34-64`).
- **UI.** The detail view's Scaling section is one typed number `TextField`
  (`ChecklistDetailView.swift:324-344`), writing through
  `multipleBinding → store.setMultiple` (`:311-315`). An `×N` badge shows only when
  `multiple > 1` (`:425-435`); the watch resolves titles from `current.multiple`
  (`CheckStitchWatch/WatchChecklistDetailView.swift:53-55`); widgets have no
  scaling references.
- **Intents.** `RunChecklistIntent` is `openAppWhenRun = false`
  (`RunChecklistIntent.swift:22-24`) with `@Parameter multiple: Int?` (`:30-31`).
  There is **no** interactive input anywhere in the repo — only entity-query
  prompting (`ChecklistEntity.swift:24-51`) and status-precheck dialogs (`:74-83`).
- **Persistence.** Four paths already carry `multiple`: LWW merge
  (`ChecklistMerge.swift:137-148`, coarse `revision`/`modifiedAt` clock),
  `duplicate`/`freshCopy` (`ChecklistStore.swift:249-296`), export
  (`ChecklistExport.swift:11-23`), store setter. Deployment targets are iOS 18.7 /
  macOS 27.0 / watchOS 26.0 (`CheckStitchCore/Package.swift:8-11`), so App Intents
  `requestValue` (iOS 17+) is available.

## Desired End State

A checklist's scaling is an explicit **mode**:

- `.fixed(n)` — today's behaviour, `n` clamped to `1...99`, `((n))` markers
  multiplied by `n`.
- `.prompt(lastFixed:)` — at run time the app asks for a number; the run scales by
  the number entered. `lastFixed` is the value the picker restores when the user
  switches back to Fixed.

Correctness is verifiable as:

1. A checklist set to Prompt shows a picker reading "Prompt" and no number field;
   switching back to Fixed restores the previously used number.
2. Running a Prompt checklist in-app presents a validated sheet defaulting to
   `lastFixed`; confirming creates reminders scaled by the entered number and
   **does not** change the stored mode or number.
3. Running it through the App Intent (Siri/Shortcuts) with no `multiple` argument
   prompts natively and scales by the answer; passing `multiple` skips the prompt.
4. A payload written by this build still loads on an older build: it reads
   `multiple` (the last fixed value) and runs that. A payload written by an older
   build loads here as `.fixed(multiple)`.
5. `./scripts/test.sh` prints `gate: ok`; `bash scripts/l10n-check.sh` passes.

## Patterns to Follow

- **Additive-key codec convention** — new `Codable` keys use `decodeIfPresent` +
  default with **no** `currentVersion` bump (`Checklist.swift:280-284`,
  `prefixesReminderNumbers`/`showsOnWatch` precedent). Follow this; do **not** bump
  `currentVersion` to 6 (see Design Decision 1).
- **One clamp source** — route every numeric entry (decode, store setter, intent
  validation, and the new sheet) through `multipleRange`/`clampedMultiple`
  (`Checklist.swift:344-349`); never re-derive bounds.
- **One run funnel** — the prompt result must arrive as `multipleOverride` at
  `ChecklistReminders.create` (`ChecklistReminders.swift:34`); do not fork the
  scaling path.
- **Coarse checklist clock** — mode rides `revision`/`modifiedAt` like every other
  checklist field; per-field clocks are an items-only pattern
  (`ChecklistMerge.swift:178-244`) and must **not** be copied for mode.
- **Platform-split view fields** — the detail-view field duplicates per platform
  for `.keyboardType(.numberPad)` while sharing one a11y id
  (`ChecklistDetailView.swift:318-342`); the new sheet's field follows the same shape.
- **Use Swift Testing** `@Test`/`#expect` structs with `@MainActor` for EventKit /
  view-model / intent suites (`RunChecklistIntentTests.swift:8-12`), legacy XCTest
  only where the codec suite already is (`ChecklistCodecTests.swift:5-16`); fixtures
  live in `CheckStitchTests/TestFixtures.swift`.
- **Localization** — every new string (picker label, sheet title, confirm/cancel,
  intent prompt) needs all six languages plus a `LocalizationFixtures.requiredKeys`
  entry (`LocalizationFixtures.swift:8-17`); run `bash scripts/l10n-check.sh` first.
- **Bad pattern to avoid** — do not model Prompt as a sentinel `multiple` value
  (`0`/`-1`); it breaks the single `multipleRange` clamp applied in three places.
- **Bad pattern to avoid** — do not persist the prompted number; `multipleOverride`
  is explicitly per-run and never written back (`ChecklistReminders.swift:34`).

## Design Decisions

1. **Model: replace `multiple` with an enum** — `Checklist.scaling: Scaling` with
   `.fixed(Int)` / `.prompt(lastFixed: Int)`. Chosen over an additive
   `scalingMode` side-key for a single source of truth and for a picker that
   cannot express contradictory state (mode + stale number).
2. **Codec: dual-key, no version bump** — the in-memory enum is `.fixed(n)` /
   `.prompt(lastFixed: n)`, but the payload keeps the legacy `multiple: n` key and
   adds an additive `scalingMode` key. Decode prefers `scalingMode` and falls back
   to `multiple` (absent → `.fixed(1)`); encode writes both (`multiple` = the fixed
   or last-fixed value). This honours decision 1 without the blank-store downgrade
   window a v6 bump creates: an older build still reads `multiple` and keeps
   working (`ChecklistStore.swift:103-106`), matching the additive-key convention
   (`Checklist.swift:280-284`).
3. **`.prompt` retains `lastFixed`** — switching to Prompt does not discard the
   number; the picker restores it on return to Fixed, and `lastFixed` is exactly
   the value the legacy `multiple` key carries for downgrade safety.
4. **Detail-view editor: mode Picker + gated number field** — a `Picker` between
   Fixed and Prompt; the existing number `TextField` (`ChecklistDetailView.swift:324-344`)
   renders only for `.fixed`, so no state can contradict another.
5. **In-app prompt: validated sheet** — a sheet with a numeric field, default
   `lastFixed`, confirm disabled until the value is within `multipleRange`
   (`Checklist.swift:344-349`), then `createReminders(for:multipleOverride:)`. An
   alert was rejected (cannot gate its confirm button on validity).
6. **Intent prompt: `$multiple.requestValue(...)`** — when mode is `.prompt` and no
   `multiple` argument was supplied, request the value natively (deployment target
   iOS 18.7 supports it); `openAppWhenRun` stays `false`. If the request cannot be
   satisfied (e.g. a fully headless automation), fall back to the existing
   `IntentDialog` error path.
7. **Explicit intent parameter wins** — a caller-supplied `multiple` always
   overrides Prompt mode and skips the request, preserving existing Shortcuts
   automations; `requestValue` fires only when the parameter is absent.
8. **Prompted value is per-run, never persisted** — the entered number flows only
   into `multipleOverride` (`ChecklistReminders.swift:34`); the sheet's default
   comes from `lastFixed` but the run never calls `setMultiple`.
9. **Persistence paths carry mode like any checklist field** — add it to the LWW
   win set (`ChecklistMerge.swift:137-148`), `duplicate`/`freshCopy`
   (`ChecklistStore.swift:249-296`), export (`ChecklistExport.swift:11-23`) and the
   store setter; coarse clock only, no per-field clock.
10. **Prompt mode suppresses the `×N` badge** — the detail-view badge shows only for
    `.fixed(n)` with `n > 1` (`ChecklistDetailView.swift:425-435`), and the watch
    resolves the un-multiplied title in Prompt mode (`WatchChecklistDetailView.swift:53-55`);
    no new badge style or indicator string.

## What We're NOT Doing

- **No `currentVersion` bump / no v6 migration** — rejected in favour of the
  dual-key payload (decision 2); the existing `.migratable` machinery
  (`Checklist.swift:591-623`) is untouched.
- **No sentinel `multiple` values** (0 / -1) — would break the single clamp source.
- **No write-back of the prompted number** — no "last used" persistence.
- **No per-field sync clock for mode** — coarse checklist clock only.
- **No watch or widget scaling editor, and no new display indicator** — surfaces
  stay display-only; the only display change is hiding the `×N` badge in Prompt
  mode.
- **No new scaling semantics** — `ChecklistScaling.resolve` and the `((n))` marker
  language are unchanged; Prompt only supplies the multiplier.
- **No change to `openAppWhenRun`**, no app-launch-on-prompt, no new intent.
- **No child tickets** — all work lands on the main VAR-1127 ticket.
- **No unrelated refactors** of the codec, merge, or import/export paths.

## Open Risks

- **`requestValue` behaviour in headless contexts.** App Intents can run without a
  UI (automations, focus modes); an unsatisfiable `requestValue` may throw or
  time out. Mitigation: fall back to the existing dialog/error path (decision 6);
  needs a spike inside the plan, since there is no repo precedent (research Q3).
- **Downgrade fidelity.** On an older build a Prompt checklist silently runs at
  `lastFixed` (the shadow `multiple`) with no indication of prompt intent — data
  is safe but behaviour differs across devices during rollout. Accepted as the
  cost of avoiding a blank store; worth calling out in the PR description.
- **Two-key payload drift.** `multiple` and `scalingMode` must always be written
  together and stay consistent; a codec round-trip test (both directions,
  `.fixed` and `.prompt`) is the guard.
- **Picker vs. the task's "third scaling option" phrasing.** The design uses a
  mode Picker plus a number field, not a single list of numbers with Prompt
  appended; confirm with the user that this reading is intended.
- **Sheet vs. alert product feel.** A validated sheet is heavier than an alert;
  if the reviewer prefers the lighter alert, only decision 5 changes.