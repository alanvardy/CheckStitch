# Done

- **Branch / head SHA**: `alanvardy-var-1000-set-relative-dates-for-items` @
  `745ebf9` (review fixes; artifacts added on top in a follow-up commit).
- **Mechanical checks**: `bash scripts/test.sh` green — `gate: ok`. Full chain:
  simulator build → headless pre-boot → `make test` (187 tests / 30 suites) →
  macOS build → watchOS build → `scripts/tests/run.sh` (17 pass) → shellcheck.
  One transient host-level `Killed: 9` on `make watch-build` was observed on the
  first gate run; the leg builds green standalone and the rerun is fully green.
- **Review outcome**: one bounded fresh-context reviewer + parent inspection.
  Reviewer verdict BLOCK; both blockers fixed:
  - **B1 (fixed)** — envelope stayed v3 while `relativeDate` joined the v3 wire
    shape (main had already consumed the planned v2→v3 bump for itemOrder). Fixed
    by `currentVersion = 4`, `case 3 → .migratable(from: 3, envelope:)` loaded
    verbatim, so pre-`relativeDate` v3 clients now classify v4 as unsupported and
    refuse to overwrite instead of silently stripping the field.
  - **B2 (fixed)** — real v2 payloads have no ordering keys, and verbatim v2
    loading left `orderRevision == 0`, losing every order LWW. Added
    `Checklist.seededOrder()` (seed ordering from the record's own sync state,
    no restamping) applied in the store and sync loaders; v2 tests now use a
    hand-built key-less JSON payload.
  - Nits fixed: trailing newlines, `Outcome.migratable` doc, watch/loader
    comments.
  - Optional improvements applied (owner chose menu `[2]`): unique
    `itemRelativeDateField-<uuid>` accessibility ids and sync-aware `ItemRow`
    draft refresh.
  - No reviewer findings were declined.
- **Remaining manual items**: the plan's `make run` verification (Phase 5/6 UI
  and Reminders date checks listed in `implement.md`). Note the deliberate
  consequence of B1: a shipped v3 client degrades to read-only on a v4 payload
  until it updates — this is the design's intended data-protection trade-off.