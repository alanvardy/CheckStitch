# Done

- **Branch / head SHA**: `alanvardy-var-995-make-items-in-a-checklist-rearrangeable-by-dragging-up-and` @ `583e69e` (pushed; `main` unchanged).
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` (simulator build, headless pre-boot, tests, `build-mac`, `watch-build`, 16 shell tests, shellcheck); `make test-unit` → 140 tests / 24 suites passed. No blockers or warnings.
- **Review outcome**:
  - One bounded `reviewer` (fresh context) on the code diff (`CheckStitch/ChecklistDetailView.swift`, `ChecklistMerge.swift`, `ChecklistStore.swift`, `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`, and five test files). No blockers.
  - **Applied fix (agreed)**: `Checklist.normalizedOrder()` now builds its id→item map with `uniquingKeysWith:` instead of `Dictionary(uniqueKeysWithValues:)`, which trapped on duplicate item ids on the decode path (a previously loadable hand-corrupted payload became `.unreadable` and was wiped on save). `ChecklistMerge.reorder` hardened the same way for consistency. Regression tests added in `CheckStitchTests/ChecklistItemTests.swift` (`normalizedOrderDedupesDuplicateIds`, `decodeWithDuplicateItemIdsIsTotal`). Commit `583e69e`.
  - **Reviewer finding rejected**: the P2 claiming `ChecklistStore.moved` can compute an out-of-bounds insertion is incorrect — `insertion ≤ result.count` is provable (`insertion − result.count = −(n − destination) + #{offsets ≥ destination} ≤ 0`), and a brute force over all arrays of size 1–7, all offset subsets and all destinations found zero unsafe cases. No guard added.
  - **Deferred (optional)**: migration seeds `orderRevision = max(revision, 1)` (converges; a synced device already adopts the migrated stamp); a no-op drag still bumps `orderRevision`/saves; multi-row non-contiguous move and duplicate-id test gaps (the latter now closed).
- **Remaining manual items** (from `plan.md`):
  - `make run`: create a checklist, add ≥3 items, tap **Edit**, drag rows, confirm order changes and text is unchanged; relaunch and confirm persistence.
  - macOS signed build (`make build-mac-signed` + run): confirm `Form` rows drag-reorder without an edit button and the items section did not regress.
  - PR #31 is still a **draft** — flip to ready (and merge with `--rebase`) when desired. Known accepted limitation: a pre-v3 build sees a v3 payload as `.unsupportedVersion` and stops saving/syncing until updated.
