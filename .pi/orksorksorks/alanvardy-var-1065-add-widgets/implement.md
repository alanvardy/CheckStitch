# Implementation Summary

iOS-only CheckStitch widget extension: reads the App Group `checklists.v1` payload
and runs a checklist through the single live reminder path (`ChecklistReminders.create`).
All six phases implemented, committed, and verified.

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 0     | 533da8b | Core extraction (move run seam + read model into `CheckStitchCore`) |
| 1     | 761d47b | Walking skeleton: small widget runs a checklist |
| 2     | 1d869d9 | Choose which checklist (small widget config) |
| 3     | 8a713c7 | Large widget with per-row run buttons |
| 4     | cddc8e0 | Access and purchase states |
| 5     | 58a3a12 | Hardening, empty states, localization |

(Plus one prior cleanup: `a947321 chore: remove DELETEME placeholder` — removed
the pre-existing placeholder that blocked the rebase.)

## Automated Checks (all passed)
- [x] `make test-unit` passes (final: 457 tests / 61 suites; all `ChecklistWidgetDisplayModelTests` + `LocalizationTests` green)
- [x] `make build-mac` passes
- [x] `make watch-build` passes (Core's EventKit/AppIntents additions watchOS-safe)
- [x] `make widget-build` passes with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`
- [x] `make build` passes and `.appex` exists at `DerivedData/Build/Products/Debug-iphonesimulator/CheckStitch.app/PlugIns/CheckStitchWidget.appex`
- [x] `scripts/l10n-check.sh` prints `ok` (4 catalogs, 145 keys, 6 languages) — Widget catalog wired in
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` clean
- [x] `bash scripts/tests/run.sh` passes (26 passed; `widget-build` pinned in `WARNINGS_AS_ERRORS_LEGS`)
- [x] `./scripts/test.sh` prints `gate: ok` (full gate run once by the parent after all phases)

## Deviations / Observations (from the plan)
- **Phase 0 — `ChecklistStore.conflictingChecklist` made `public`**: not in the
  plan's public list, but the app-target `ChecklistImportSession.swift` (and tests)
  call it, so it had to cross the package boundary — a mechanical necessity of the
  pure move, not a design change.
- **Phase 0 — `PurchaseEnvironment` seam added to Core** (plan-documented deviation):
  Core's `ChecklistReminders.productionGate()` needs a purchase service; the StoreKit
  provider stays out of Core (watchOS compile). Core holds the StoreKit-free
  `CachedEntitlementProvider` default; `MyApp.init()` injects the StoreKit-backed
  service.
- **Phase 1 — widget target omits `SWIFT_DEFAULT_ACTOR_ISOLATION`** (plan-sanctioned):
  WidgetKit's `TimelineProvider` requirements are nonisolated; extension opts into
  `@MainActor` explicitly. `runIntent` uses `let ... ; intent.checklist = ...` (the
  compiler confirmed `RunChecklistIntent(checklist:)` is not synthesized; matches
  `RunChecklistIntentTests`). Callback params use `@escaping @Sendable` for WidgetKit
  conformance.
- **Phase 2/3 — compiler-driven snippet fixes** (all plan-sanctioned): dropped the
  old callback annotations when switching to async `AppIntentTimelineProvider`;
  intent `@Parameter` fields are optional-typed (`ChecklistEntity?`,
  `[ChecklistEntity]?`); added the missing `import AppIntents` in
  `MultiChecklistWidget`.
- **Phase 4 — no Core API change needed**; `RunGate.freeRunLimit` lives in
  `RunCounter.swift` (referenced as `RunGate.freeRunLimit`).
- **Phase 5** — "Open CheckStitch to buy a license" added as a catalog key
  (plan only required the key, not a view swap); widget sources follow the repo
  no-trailing-newline convention.

## Manual Verification Items (from the plan — NOT yet confirmed)
- [ ] Phase 0: Launch the app (`make run`); the checklist list, run button, Siri
      shortname entry and import/export still behave as before (pure move).
- [ ] Phase 1: `make run`; press the simulator Home button, long-press the Home
      Screen, tap **+** → **CheckStitch** → add the small widget. It shows the first
      checklist's name.
- [ ] Phase 1: Tap the run button. Reminders appear in Reminders → CheckStitch
      **without CheckStitch coming to the foreground** (foreground the app only
      afterwards to confirm; check the free-run counter is not stuck).
- [ ] Phase 2: `make run`; long-press the placed small widget → **Edit Widget** →
      choose a checklist; it renders that checklist and its run button creates its
      reminders.
- [ ] Phase 3: `make run`; add the large widget, edit it to select three checklists
      — three ordered rows render.
- [ ] Phase 3: Tap each row's button in turn; each tap creates only that checklist's
      reminders, and no other row's reminders.
- [ ] Phase 3: Confirm a 7th/8th selected checklist is not rendered (row budget).
- [ ] Phase 4: `make run`; Settings → Privacy & Security → Reminders → turn
      CheckStitch off. The widget renders the "open app" state on both sizes.
- [ ] Phase 4: Tap the widget body: CheckStitch launches to the foreground.
- [ ] Phase 4: Re-enable access; the widget returns to a runnable state (may need a
      timeline refresh — remove/re-add or wait).
- [ ] Phase 5: Add an unconfigured widget: the empty-state hint renders, no crash.
- [ ] Phase 5: Widget gallery shows the display name, description, and previews for
      both sizes.
- [ ] Phase 5: Delete all checklists in the app; the widget shows the empty state
      within the refresh window.
- [ ] Phase 5: Switch the app language (Settings → Language); the widget strings
      follow on the next timeline refresh.