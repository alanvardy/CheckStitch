# Structure Outline

## Approach

Replace the stored `Checklist.multiple: Int` with a `Scaling` enum (`.fixed` /
`.prompt(lastFixed:)`) using the additive dual-key codec (`multiple` shadow +
new `scalingMode`, **no** `currentVersion` bump). Prompt is never persisted as
run state: the entered number flows through the existing per-run
`multipleOverride` seam on both the in-app and App-Intent paths.

---

## Phase 0: `Scaling` type end to end, `.fixed` unchanged (walking skeleton)

> **Genuine horizontal exception.** The stored-type swap is atomic across every
> consumer; no vertical slice can land green before it. It is still one
> shippable, green commit (expand only — legacy `multiple` keeps being written).

**User-visible outcome**: the app behaves exactly as today, but the checklist
payload now carries both `multiple` (shadow) and `scalingMode`, so a downgrade
still reads `multiple` and an old payload loads as `.fixed`.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`.../ChecklistStore.swift`, `.../ChecklistMerge.swift`, `.../ChecklistExport.swift`,
`.../ChecklistReminders.swift`,
`CheckStitch/Models`-adjacent consumers (`ContentView`, `ChecklistDetailView`,
`CheckStitchWatch/WatchChecklistDetailView`) compile against the accessor.

**Key changes**:
- `public enum Scaling: Equatable, Codable, Sendable { case fixed(Int); case prompt(lastFixed: Int) }`
  — new. `var number: Int` (fixed value or `lastFixed`; the legacy `multiple`
  shadow), `var isPrompt: Bool`, `static func clamped(_:) -> Int` delegating to
  the existing `multipleRange` / `clampedMultiple` (single clamp source kept).
- `Checklist.multiple: Int` → `Checklist.scaling: Scaling` — stored property and
  `CodingKeys`; `multiple` becomes a computed compatibility accessor if any
  non-stored reader remains.
- Codec: add `scalingMode` key (`encode` writes `"fixed"`/`"prompt"` + `multiple =
  scaling.number`; `decode` prefers `scalingMode`, else
  `.fixed(clampedMultiple(multiple ?? 1))`). `currentVersion` stays `5`.
- `ChecklistStore.setMultiple(_:)` → `setScaling(_ scaling: Scaling, for id: UUID)`
  (same clamp / unchanged no-op); `duplicate` / `freshCopy` carry `scaling`.

**Contract** (consumed by every later slice): `Checklist.scaling: Scaling`,
`Scaling.number` / `.isPrompt`, `ChecklistStore.setScaling(_:for:)`, and the
unchanged funnel signature `ChecklistReminders.create(from:targeting:gate:
multipleOverride: Int?)`. `.prompt(lastFixed:)` is fully representable and
round-trips at this point.

**Tests**: `ChecklistCodecTests` (dual-key round-trip for `.fixed` + `.prompt`,
legacy payload with no `scalingMode` → `.fixed`, clamp), `ChecklistStoreTests`
(setScaling clamp/no-op/duplicate/freshCopy), `ChecklistMergeTests` +
`UbiquitousChecklistSyncTests` (win carries `scaling`), `ChecklistExportTests`,
`ChecklistImportSessionTests`, `ChecklistRemindersTests` (funnel runs `.fixed`).
**Verify**: `make test-unit`; legacy-payload fixture decodes; `make build-mac`.

---

## Phase 1: In-app Prompt scaling, end to end

**User-visible outcome**: a checklist set to Prompt shows a Fixed/Prompt picker
instead of the number field (Fixed restores `lastFixed`); running it presents a
validated sheet defaulting to `lastFixed`, and confirming creates reminders
scaled by the entered number **without** changing stored state.

**Files**: `CheckStitch/ChecklistDetailView.swift`,
`CheckStitch/ContentView.swift`, `CheckStitch/ChecklistRunViewModel.swift`,
`CheckStitch/PromptScalingSheet.swift` (new), `CheckStitchCore/.../Checklist.swift`
(read-only use), `CheckStitch/Localizable.xcstrings`.

**Key changes**:
- `ChecklistDetailView`: `Scaling` section becomes `Picker` over
  Fixed/Prompt; `scalingField` renders only when `scaling` is `.fixed`; new
  `scalingBinding` → `store.setScaling`.
- `struct PromptScalingSheet: View` — new: `init(lastFixed: Int, onConfirm: (Int) -> Void, onCancel: () -> Void)`;
  confirm disabled unless the value is in `multipleRange`.
- `ChecklistRunViewModel`: `func startRun(for id: UUID)` sets `promptingRunID`
  when `scaling.isPrompt`; `func createReminders(for id: UUID, multipleOverride: Int? = nil)`
  forwards the override. The view model never calls `setScaling` on a run.

**Contract**: `PromptScalingSheet` public init; `createReminders(for:multipleOverride:)`;
`promptingRunID` drives sheet presentation from `ContentView`.

**Tests**: `ChecklistDetailViewTests` (picker for prompt hides field; fixed still
renders), new `PromptScalingSheetTests` (range validation enable/disable),
`ChecklistRunViewModelTests` (prompt state enters/clears, override forwarded,
store untouched), `ChecklistRemindersTests` (override multiplies `((n))`).
**Verify**: `make test-unit`; manual `make run` — pick Prompt, run, enter 3,
confirm reminders; reopen checklist and confirm mode still Prompt.

---

## Phase 2: App-Intent prompt (Siri / Shortcuts)

> **Front-loads the one open design risk** (`requestValue` in headless
> contexts, design decision 6). **Timebox a spike** as the first task:
> confirm `$multiple.requestValue` works inside the existing `AppIntent` test
> harness with `openAppWhenRun == false`. If unsatisfiable, land the designed
> fallback (existing `IntentDialog` error path) and update the design's risk note.

**User-visible outcome**: running a Prompt checklist via Siri/Shortcuts with no
`multiple` argument asks natively for a number and scales by it; passing
`multiple` skips the prompt; a Prompt checklist still works headless via the
fallback.

**Files**: `CheckStitchCore/.../RunChecklistIntent.swift`,
`CheckStitchCore/.../ChecklistConfigurationIntent.swift` (compile only),
`CheckStitch/Intents/CheckStitchShortcuts.swift` (compile only),
`CheckStitch/Localizable.xcstrings`.

**Key changes**:
- `RunChecklistIntent`: inject a prompting seam —
  `protocol ScalingPrompting { func requestMultiple(prompt: String) async throws -> Int }`
  with a default `AppIntentScalingPrompter` calling `$multiple.requestValue(...)`;
  tests inject a fake. Order in `perform()`: validate → EventKit pre-check →
  `if multiple == nil && checklist.scaling.isPrompt { resolve via prompter }`
  → existing `create(..., multipleOverride:)`. Explicit `multiple` always wins.
- Fallback: prompter throw/cancel reuses the existing dialog/error return; no
  new error case unless the spike shows one is needed.

**Contract**: `ScalingPrompting` protocol + default implementation (the test
seam); the override resolution rule (explicit param > prompt > `scaling.number`).

**Tests**: `RunChecklistIntentTests` (prompt fired when nil + `.prompt`; skipped
when `multiple` supplied; skipped in `.fixed`; fake-prompt value reaches
`multipleOverride`; failing prompter → error/dialog, no reminders created).
**Verify**: `make test-unit`; manual Shortcuts run of a Prompt checklist.

---

## Phase 3: Hardening, display polish, rollout

**User-visible outcome**: Prompt mode no longer shows a misleading `×N` badge;
the watch shows an un-multiplied title in Prompt mode; all new strings are
localized; the two-key payload/downgrade behaviour is pinned by tests.

**Files**: `CheckStitch/ChecklistDetailView.swift` (badge),
`CheckStitchWatch/WatchChecklistDetailView.swift`,
`CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`.

**Key changes**:
- `showsScalingFactor` becomes `if case .fixed(let n) = scaling, n > 1`.
- Watch title resolves with multiplier `1` when `scaling.isPrompt`.
- Every new key (picker label, sheet title, Confirm/Cancel, intent prompt) added
  to all 6 languages + `LocalizationFixtures.requiredKeys`.

**Contract**: none new — pure display/localization/pinning.

**Tests**: `ChecklistDetailViewTests` (badge for `.fixed(n>1)`, absent for
`.prompt`/`.fixed(1)`), watch detail test, `LocalizationTests` +
`LocalizationFixtures.requiredKeys`.
**Verify**: `bash scripts/l10n-check.sh`; `make build`; then full `./scripts/test.sh`
→ `gate: ok`.

---

## Testing Checkpoints

- After **Phase 0**: `make test-unit` green — the `.fixed` path is identical and
  the dual-key codec round-trips both cases; nothing downstream may break.
- After **Phase 1**: `make test-unit` green and the manual `make run` prompt loop
  works and does not persist the entered number.
- After **Phase 2**: `make test-unit` green with the injected prompter; the
  headless fallback is exercised by a test, not by hand.
- After **Phase 3**: `bash scripts/l10n-check.sh` and the full `./scripts/test.sh`
  print `gate: ok`; badge/watch display verified on the installed bundle.
