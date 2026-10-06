# Done

- **Branch / head SHA**: `alanvardy-var-1116-add-a-create-checklist-app-intent-name-items`
  @ `e389006` (`review: apply VAR-1116 review fixes`). The completion marker is
  the follow-up commit containing this file; the pre-review branch commits
  (branch-start chore `48640b9`, phases `5224ce9`/`31f58b1`, artifact chore
  `90d670a`) were already pushed.
- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok`, run **before and
  after** the review fixes — simulator build + `make test` (195 XCTest, 1 UI
  test, 584 Swift Testing cases in 67 suites), `make build-mac`,
  `make watch-build`, `make widget-build`, `scripts/tests/run.sh` (26/26),
  shellcheck. `make test-unit` → `TEST SUCCEEDED`. `bash scripts/l10n-check.sh`
  → `ok (4 catalogs, 175 keys, 6 languages)`. Warnings-as-errors on; the only
  warning in the log is the benign
  `Metadata extraction skipped, no AppIntents.framework dependency found` for
  the `CheckStitchUITests` target (no AppIntents dependency).
- **Rebase**: none in progress at session start (`rebase-merge` /
  `rebase-apply` absent); no conflicts. Branch was `origin`-aligned.
- **App Intents metadata** (iOS-simulator product, post-gate):
  `CreateChecklistIntent` present with `isDiscoverable: true`, title
  "Create Checklist", summary `"Create ${name} with ${items}"`, params
  `name`/`items` — ticket unknown (b) resolved; the intent stays in Core.

## Review outcome

One fresh-context `reviewer` pass over `git diff main...HEAD` (source + tests;
`.pi/orksorksorks` artifacts excluded), plus the parent's own scan.
**Verdict: merge OK — zero blockers.**

Applied (user approved `[2]` — fixes worth doing now + optional improvements):

- **Trailing newlines** added to `CreateChecklistIntent.swift` and
  `CreateChecklistIntentTests.swift` (both had `\ No newline at end of file`).
- **`synchronize()` comment** (`ChecklistStore.swift:727`) aligned with reality
  — the call is a modern-Darwin no-op kept only as a harmless visibility nudge,
  not a guarantee that a cross-process App Group write is visible.
- **Folder-only reconcile test** `testReconcileFiresOnceForAFolderOnlyChange`
  (`ChecklistStoreTests.swift`) pins that a payload change which adds no
  checklist still rides exactly one `onChange`.

Deferred / declined (with reasons):

- **`create(name:, itemTitles:)` guards** — declined. The method returns a
  non-optional `Checklist`, so enforcement needs a `precondition`/crash or a
  signature change; decisions 7–8 deliberately centralize validation in the
  intent, and the sibling `create(name:)` is equally unguarded by design. The
  doc comment already states the precondition.
- **`parameterSummary` `[String]` rendering** — needs eyes on Shortcuts.app;
  covered by the manual run below, no code change.

**Residual risk (accepted, ticket-scope):** the "next save cannot clobber"
guarantee holds only for a save that happens *after* the `.active` reconcile. A
backgrounded-process save landing between the intent's App Group write and the
`.active` transition can still overwrite the payload. This matches decision 9's
accepted narrow window and is recorded here rather than implied away.

**Not verified by the reviewer**: per-commit scoping of the pre-review commits,
device/manual plan steps, and a full language-by-language catalog read (covered
by `l10n-check` + `LocalizationFixtures` instead).

## Remaining manual items

Device/Shortcuts.app verification from `plan.md`, still open (cannot be closed
on static evidence per the repo's sync/render rule):

- **Phase 1** — `make build-mac-signed`, open macOS Shortcuts.app, confirm a
  **Create Checklist** action exists with Name + Items (list) fields and
  summary "Create (Name) with (Items)".
- **Phase 2** — `make build-mac-signed` / `scripts/run-devices.sh`; in
  Shortcuts.app run Create Checklist while the app is backgrounded; return to
  the app and confirm the checklist lists with its items and survives a
  subsequent edit. Re-run with a duplicate name (expect "… 2"), blank name
  (expect "Give the checklist a name."), and no items (expect
  "Add at least one item.").
- Confirm the created checklist reaches the watch/widget after returning to
  `.active`.
