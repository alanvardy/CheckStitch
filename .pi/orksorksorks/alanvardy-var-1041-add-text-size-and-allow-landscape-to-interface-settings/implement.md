# Implementation Summary

All three phases of VAR-1041 (Interface settings subscreen) are implemented, verified, and pushed. One unplanned preparatory fix was required: `origin/main` itself did not compile (`RunResultKind.init(_:)` was missing the `.partiallyCreated` case), which blocked every automated check for every phase. Per the operator's decision (Option A), a one-line Core fix was committed separately, then all phase verification ran green — including the full gate (`bash scripts/test.sh` → `gate: ok`).

## Commits

| Commit | Description |
|--------|-------------|
| e4b776a | Phase 1: Interface subscreen — Appearance moves behind a new row (walking skeleton) |
| d8d17d0 | Phase 2: Text Size — picker scales text app-wide |
| a2de050 | fix(core): handle partiallyCreated in RunResultKind mapping (pre-existing origin/main compile break; operator-approved deviation from the plan's out-of-scope list) |
| 65bf83e | Phase 3: Allow landscape — iOS-only orientation lock |

Branch pushed to `origin/alanvardy-var-1041-...` (force-with-lease; remote only held the pre-rebase "chore: start" commit). PR #59 exists (draft).

## Automated Checks

- [x] `make test-unit` passes (308 tests / 39 suites incl. new TextSize, OrientationPreference, interface-subscreen suites)
- [x] `make build` (iOS simulator) succeeds
- [x] `make build-mac` succeeds
- [x] `make watch-build` succeeds
- [x] `bash scripts/tests/run.sh` passes (17/17)
- [x] `bash scripts/test.sh` prints `gate: ok` — single full gate run for this branch

`plan.md` automated checkboxes ticked (11 items across the three phases). No manual items ticked.

## Deviations from the plan (all small, all operator-visible)

1. **`fix(core)` preparatory commit (a2de050)** — operator-approved Option A. `CheckStitchCore/.../ChecklistSync.swift` line 29: `RunResultKind.init(_:)` switched `ReminderRunOutcome` over only 4 cases; the enum gained `case .partiallyCreated(...)` in `b4eb0cd` (VAR-1019) but the VAR-1027 switch (65ba443) never handled it. Added `case .partiallyCreated: self = .failed`. This break exists at `origin/main` HEAD ee65aac (reproduced on pristine worktrees / cold builds by all three phase workers). **Worth routing separately to main** — it is a genuine pre-existing merge-remnant bug independent of this ticket (the same one-liner likely belongs on main too; I did not touch main).
2. **`@MainActor` added to `OrientationPreferenceTests`** — the test target deliberately has no default actor isolation; the app target's `OrientationPreference`/`OrientationPolicy` are implicitly `@MainActor`. Same adaptation the plan's own reasoning already applied to `TextSizeTests` (Phase 2 worker noted it).
3. **`InterfaceSettingsViewTests` does not assert `"Interface"`** — `String(describing: view.body)` cannot render navigation titles (they live in a `TransactionalPreferenceTransformModifier<NavigationTitleKey>(transform: (Function))`, invisible to describing). Sibling suites (`AboutViewTests` et al.) never assert `.navigationTitle` either. The suite still renders both pickers + captions, which is its stated intent.
4. **`InterfaceSettingsViewTests` uses whole-call `#if os(iOS)`** when constructing the view — Xcode 26 / Swift 6.4 rejects `#if` inside argument lists; the Phase 3 worker verified this on minimal probes. The pattern matches how `SettingsView` passes the binding (and matches SingleThread), and the gate's `test-ui` leg compiles `CheckStitchTests` for iOS, so the test had to compile on both platforms.

## Manual Verification Items (from the plan — not done, operator confirms)

- [ ] `make run`: gear → Settings now shows an **Interface** row; tapping it pushes a screen titled "Interface" holding the Appearance picker; picking **Dark** still applies app-wide and survives dismissal.
- [ ] `make run`: Interface → **Text Size** = Extra Large grows all app text (checklist rows, Settings itself); **System** restores the device size.
- [ ] Kill and relaunch the app: the chosen size is still applied.
- [ ] macOS (`make build-mac-signed` / run the macOS app): the Text Size picker is present and changes the macOS window's text too.
- [ ] `make run` on the iPhone simulator: Interface shows **Allow landscape** (ON by default). Rotate with ⌘←/⌘→ → the app rotates.
- [ ] Toggle **Allow landscape** off → the app immediately snaps back to portrait and no longer rotates; toggle on → it rotates again.
- [ ] Relaunch the app with the toggle off: it launches in portrait with no landscape flash, and Rotation Lock-independent ⌘→ does nothing.
- [ ] macOS app: no landscape row on the Interface screen; Text Size still applies.

## Observations (noted, not fixed — out of scope)

- `origin/main` is red as of ee65aac (the CheckStitchCore switch break). Anyone branching off main today hits it; worth a ticket + fix on main.
- The `.partiallyCreated → .failed` mapping means a partially-created run shows "Couldn't create reminders." on the watch even though some reminders were created; `RunResultKind` intentionally drops the free-form message and has no partial-count case. If partial-run reporting matters for the watch UI, that is a separate feature decision (expand `RunResultKind`), not something to fold into this ticket.