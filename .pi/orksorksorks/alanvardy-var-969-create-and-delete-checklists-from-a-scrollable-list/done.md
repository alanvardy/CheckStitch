# Done

- **Branch / head SHA**: `alanvardy-var-969-create-and-delete-checklists-from-a-scrollable-list` @ `e953b9b` (pushed to `origin`; branch level with `main`, working tree clean).
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` — simulator build, `CheckStitchTests` (14 tests, 0 failures) and `shellcheck scripts/*.sh` all pass. Run after every applied fix, before each commit.

## Review outcome

One fresh-context `reviewer` plus the parent's own scan. The application code was
found correct: App Group persistence with a versioned envelope, `save()` on every
mutation, no force unwraps/index-unsafe access, MainActor-clean reminder task,
`Identifiable` `ForEach` ids, and the load-bearing invariant that deleting a
checklist never touches reminders already in Reminders.

**Blocker resolved (option 1 — keep and document).** The diff added a
`CheckStitchTests` unit target, a committed shared scheme, a `Makefile test`
goal, and `make test` in the gate, which directly contradicted `AGENTS.md`,
`conventions.md` and `design.md` ("There is no test target… do not add one as
part of a small task"). The target was planned and approved at the plan step but
the repo contract was never updated. Resolution: the change is kept and the
contract is now updated — `AGENTS.md` (Layout + gate), `conventions.md`
(Test-suite inventory), `design.md` ("What We're NOT Doing"), and `implement.md`
(Deviation 8) all record the amended gate (`make build` + `make test` +
shellcheck).

**Fixes applied (worth doing now):**

- `ChecklistCodec.classify` now distinguishes `.unsupportedVersion` from
  `.unreadable`; `ChecklistStore` refuses to overwrite a payload written by a
  newer app version (mutations stay in memory, persistence is declined) rather
  than silently downgrading it. Corrupt payloads are still repaired on save.
  Two new tests (`testUnsupportedVersionPayloadIsNotOverwritten`,
  `testCorruptPayloadIsRepairedOnSave`) plus a `classify` test.
- `ContentView.createReminders` marks the checklist in-flight synchronously
  before spawning the task, closing the double-tap duplicate-reminders window.
- `ChecklistDetailView` skips the "Checklist not found" placeholder during a
  self-initiated delete so the pop animation never flashes it.

**Optional improvement applied (owner request):** per-keystroke `save()` was
coalesced over a 300ms debounce (`ChecklistStore.scheduleSave`). The durability
window is bounded rather than open: `flushPendingSave()` runs synchronously when
the detail screen disappears and when the app leaves the foreground, and every
structural edit (`create`/`addItem`/`removeItems`/`delete`) cancels the queued
write and persists immediately. The delay is injectable — tests asserting on
disk right after a mutation pass `nil` for synchronous saving — and
`testTextEditsAreCoalescedUntilFlush` + `testStructuralSaveCancelsPendingTextEdit`
cover the new path.

## Remaining manual items

All Phase 3–5 runtime checks in `implement.md` are still unchecked and must
accompany merge:

- Create reminders from a checklist with named + blank items and with Reminders
  access denied — expected reminders only, no crash, log-only errors.
- Rename/add/edit/swipe-delete items, relaunch → persisted.
- Remove Checklist → list entry gone and the screen pops with no
  "Checklist not found" flash; reminders already created remain in Reminders.
- Create two checklists, force-quit, relaunch → both intact.
- Optional device proof of real App Group sharing via `bash scripts/run-devices.sh`.
