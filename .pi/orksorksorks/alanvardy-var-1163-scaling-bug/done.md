# Done

- **Branch / head SHA**: `alanvardy-var-1163-scaling-bug` @ `f34338be2edebf97e4b069f80d399e1484809a84`
  (pushed to `origin/alanvardy-var-1163-scaling-bug`; working tree clean, no rebase conflicts to resolve).

- **Mechanical checks**: `./scripts/test.sh` passed and printed `gate: ok` —
  `make build` (simulator) → headless simulator pre-boot → `make test` → `make build-mac`
  → `make watch-build` (watchOS) → `scripts/tests/run.sh` (39 passed, 0 failed) →
  `shellcheck`. Warnings-as-errors is enforced on every Xcode leg. No warnings flagged.

- **Review outcome**: One bounded reviewer pass over `git diff main...HEAD`, cross-checked
  against source by the supervisor.
  - **Blockers: none.** The single defect — `guard multiple != 1, text.contains("((")`
    in `ChecklistScaling.resolve` — is now `guard text.contains("((")`.
    `ChecklistCreator.swift:36`. The resolver body (marker grammar, ASCII-digit
    check, exact-`))` rule, `Int` parse, overflow guard, byte-for-byte copy) is
    unchanged. Verified every render/create path funnels through `resolve`
    (`ChecklistReminders.swift:73,75`; `ChecklistCreator.swift:107`;
    `ChecklistDetailView.swift:274,293`; `WatchChecklistDetailView.swift:53,55`) and
    no other site gates on `multiple != 1`. `multiple` is clamped to `1...99`
    everywhere, so `0` cannot reach the removed fast path.
  - **Tests pin real behaviour**: `markersResolveAtOne` resolver-level;
    `fixedOneStripsMarkersOnRun` run-funnel (`"1: milk 2"` / `"4 boxes"`);
    `promptConfirmedAtOneStripsMarkers` prompt path plus the not-persisted
    invariant. No surrounding test relied on the old identity behaviour.
  - **Fixes applied: none needed.** No fixes worth doing now.
  - **Optional improvement (noted, not applied)**: add a one-line `#expect` in
    `CheckStitchTests/ScalingTests.swift` coupling `Scaling.prompt(lastFixed:).
    displayNumber == 1` to `ChecklistScaling.resolve` so the watch/detail preview
    claim is pinned directly rather than only via `markersResolveAtOne`. Deferred
    to the user (optional, not a blocker).
  - Doc comments on `ChecklistScaling` and `Scaling.displayNumber` are accurate;
    the shipped help text ("the brackets are removed") is now true at Scaling 1.

- **Remaining manual items** (from `plan.md`, cannot close on static evidence):
  - `make run`; open a checklist whose item title is `((2))` at factor 1 (or confirm
    the prompt with 1), run it, and confirm the created reminder reads `2` with no
    literal brackets while the stored item text still shows `((2))`.
  - Eyeball the app detail view for `.prompt` mode and the Watch detail preview —
    both should show bracket-free text (the deliberate consequence recorded in
    `design.md`'s "Open Risks").
