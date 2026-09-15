# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `89585d0` | Item model field + Codable round-trip |
| 2     | `7fca015` | Envelope v3 + version-aware migration |
| 3     | `bca2558` | Pure offset → date-only arithmetic |
| 4     | `3ee031d` | Store mutation API for the offset |
| 5     | `88ff4f6` | Reminder creation paths (live + core mirror) |
| 6     | `331a015` | Detail-row date field (buffered) |
| 6 fix | `a035376` | fix: compile ItemRow keyboard guard on iOS |

Also on the branch: `c439265` removes the ticket-workflow `DELETEME` placeholder (the
file itself demanded `git rm` before merging), applied on top of the mandated
`git rebase origin/main`. A Phase-4-era force-with-lease was sanctioned by the
owner after lineage verification: the remote's only stale commit was the
ticket-start placeholder; no third-party commits were affected.

## Automated Checks
- [x] `make test-unit` green at every checkpoint (Phases 1–6; final run 186 tests / 30 suites, TEST SUCCEEDED)
- [x] `bash scripts/test.sh` — full gate green on the final tree (`gate: ok`): simulator build → headless pre-boot → test → macOS build → watchOS build → shell tests → shellcheck
- [x] Phase 1: item JSON round-trip incl. absent-key decode → `nil` and unconditional `relativeDate` key emit (`null`)
- [x] Phase 2: envelope v3 stored; v2 payloads classified `.migratable(from: 2, envelope:)` with tombstones/deviceID, load verbatim without restamping (store, sync, watch arms); version 4 → `.unsupportedVersion`
- [x] Phase 3: `dueDateComponents(today:calendar:)` deterministic — today/tomorrow/past, month & year boundaries, late-day `startOfDay`, no time components
- [x] Phase 4: `updateItem(…relativeDate:)` set / clear / no-op-when-unchanged / ignore-unknown-IDs / coalesced-until-flush; `duplicate` copies the offset
- [x] Phase 5: creator passes computed date-only components to the seam (offsets 0/1/nil), blank items skipped even when dated; `EventKitReminderCreator` crash-canary proves `EKReminder.dueDateComponents` is readable; live path carries components through `ReminderDestinationTargeting`
- [x] Phase 6: `ItemRow` buffer/parse/format tests (10 argument cases); real UI compiles on iosimulator + macOS legs

## Deviations from plan.md (all intentional; owner-approved where noted)
1. **Phase 5 live path (owner-approved Option A)** — plan item 5.3 targeted `ChecklistReminders.swift` constructing `EKReminder` inline, but that code was replaced (pre-plan) by the `ReminderDestinationTargeting` seam. The date is threaded as `dueDateComponents: DateComponents?` through `ReminderDestinationTargeting.create(title:in:)`, set nil-guarded in `EventKitReminderDestination.create`, and computed per item in `ChecklistReminders.create` via `item.dueDateComponents(today: Date())`. Files added beyond the plan's table: `ReminderDestinationTargeting.swift`, `EventKitReminderDestination.swift`, `SpyReminderDestination`, plus a live-path parity test in `ChecklistRemindersTests` (this layer turned out to be testable, contrary to the plan's assumption).
2. **`.keyboardType(.numbersAndPunctuation)` is iOS-only** on this toolchain — the macOS SwiftUI SDK has no such modifier. Guarded with `#if os(iOS)` / `#else` whole-chain duplication in `ItemRow.dueDateField` (`a035376`). iOS gets the planned keyboard; macOS builds without it.
3. **`Int?.none/.some` does not exist in this codebase** — test argument arrays use `nil` with `as [(String, Int?)]` / `as [(Int?, String)]` casts (existing suite convention).
4. **Gate staging** — per the delegation policy, workers verified with `make test-unit` only; the full `scripts/test.sh` gate ran once, as the parent, after all phases committed (covers the plan's Phase 2/5/6 gate requirements).

## Observations (not blocking)
- Pre-existing timing flake seen once in `ChecklistSyncServiceTests.concurrentRefreshesCoalesceIntoOneRead` (passes in isolation and in final runs) — worth watching, unrelated to this change.
- The `#if os(iOS)` keyboard guard is unexercised by the automated legs (macOS-hosted tests can't compile iOS UI branches); the plan's manual `make run` covers it.
- `ChecklistViewModelTests` needed no assertion changes — `SpyReminderCreator.createdTitles` is a computed shim over `createdItems`.

## Manual Verification Items (from the plan)
- [ ] Phase 5 — `make run`, create a checklist with one item titled `today` (offset `0`), one `tomorrow` (offset `1`) and one unnumbered item, run the checklist, and confirm in Reminders that the first two show today/tomorrow and the third has no date
- [ ] Phase 6 — `make run`; open a checklist; type `1` in an item's Days field → the value sticks; change it to `-2` (minus is typeable) → sticks; clear the field → date cleared; background the app and relaunch → the value persists
- [ ] Phase 6 — Reminder check: run the checklist and confirm the same item shows the expected today-relative date in Reminders
- [ ] Phases 1–4 list `None` manual items (fully covered by unit suites)

## Post-review fixes (commit `745ebf9`)

The pre-merge review found two blockers, both fallout from the mandated
`git rebase origin/main`: the design/plan assumed the base was `currentVersion
= 2`, but main was already **v3** (the itemOrder/VAR-969 ticket had consumed
that bump) before this branch's Phase 2 ran. Consequent fixes:

1. **Envelope v3 → v4.** `relativeDate` had been added to the v3 wire shape
   while `currentVersion` stayed 3, so an existing v3 client would classify the
   payload as `.loaded`, silently strip `relativeDate` on re-encode, and push
   back. Now `currentVersion = 4`, `case 3` classifies as
   `.migratable(from: 3, envelope:)` (v3 carries full sync + ordering state;
   load verbatim, `relativeDate` decodes `nil`), and old v3 clients see v4 as
   `.unsupportedVersion` and refuse to overwrite.
2. **v2 ordering regression.** `itemOrder`/`orderRevision`/`orderModifiedAt`
   arrived with v3, so a real v2 payload has none. The Phase 2 change loaded
   v2 verbatim, leaving `orderRevision == 0` and losing every order LWW. Added
   `Checklist.seededOrder()`, applied in both `ChecklistStore` and
   `ChecklistSyncService`: it seeds ordering from the record's own sync state
   **without** restamping item/checklist `revision`/`modifiedAt`. The v2 tests
   now use a hand-built, key-less JSON payload rather than the current encoder.
3. **Nits/optional.** Unique `itemRelativeDateField-<uuid>` accessibility ids;
   `ItemRow` refreshes its buffered text on an external (iCloud) `relativeDate`
   change without clobbering a padded/in-progress draft; trailing newlines;
   doc comments.

Full `bash scripts/test.sh` re-run green after the fixes (`gate: ok`, 187 unit
tests).