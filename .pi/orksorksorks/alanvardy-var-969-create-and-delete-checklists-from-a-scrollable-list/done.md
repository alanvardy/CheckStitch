# Done

- **Branch / head SHA**: `alanvardy-var-969-create-and-delete-checklists-from-a-scrollable-list` @ `3bc1bb5` (pushed to `origin`; branch level with `main`, working tree clean).
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` — simulator build, `CheckStitchTests` (12 tests, 0 failures) and `shellcheck scripts/*.sh` all pass. Run once after the review fixes and before the fix commit.

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

**Optional improvement declined:** per-keystroke `save()` debouncing. The cost
is one JSON encode of a small array per keystroke (`UserDefaults.set` is
in-memory); a debounce would trade that for a real data-loss window if the app
is killed mid-edit, and would complicate the reload-immediately test seam. Not
worth the risk for this payload size. Revisit only if checklists grow large.

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
