# Done

- **Branch / head SHA**: `alanvardy-var-1058-add-iap` — code fixes at `0e46946`
  (review artifacts follow in a second commit).
- **Mechanical checks**: `make test-unit` — **415 tests / 52 suites passed**.
  `./scripts/test.sh` — full gate **`gate: ok`** (simulator build → tests →
  `build-mac` → `watch-build` → shell tests 25/25 → shellcheck, exit 0, all
  compiling legs under `WARNINGS_AS_ERRORS`). No rebase conflicts; the branch
  was already up to date with `origin`, so nothing was force-needed beyond the
  new commits.
- **Review outcome**:
  - **Blockers**: none. One bounded fresh-context `reviewer` covered
    concurrency/Sendable, SwiftUI state, crash resistance, API design,
    architecture/cross-cutting, gate semantics, and the watch wire mapping.
  - **Fixes applied** (user selected `[2]`):
    - *Revocation/refund ignored by the fail-open cache* — `PurchaseService.apply`
      now caches the verified result and clears the cache on a definitive
      `false`, so a revoked/refunded transaction re-locks. The cache still
      bridges cold launch (optimistic `.unlocked` before `start()` resolves), so
      the paywall does not flash for a paid user. `design.md` decisions 3 and 8
      updated to match.
    - *Atomic run reservation* — `RunGate` now `reserveRun()` / `releaseRun()`
      instead of check-then-`recordSuccess()`. The check and increment are one
      synchronous `@MainActor` step, so two concurrent runs at the limit cannot
      both pass; failed/partial/denied/missing runs release their slot.
    - *Empty run no longer consumes a free slot* — an all-blank checklist returns
      `.created(count: 0)` and releases its reservation.
    - *Counter bounded* — while unlocked the counter is capped at
      `RunGate.freeRunLimit` instead of growing without bound.
    - *Entitlement race on the UI path* — `ChecklistRunViewModel.createReminders`
      now awaits `purchases.start()` before reading `isUnlocked`, matching
      `RunChecklistIntent.productionGate`.
    - Tests added/updated: `emptyRunDoesNotAdvanceTheCounter`,
      `concurrentReservationsCannotBothPassTheLimit`,
      `verifiedRevocationClearsTheCacheAndLocks`,
      `cachedVerifiedEntitlementIsUnlockedBeforeResolution`,
      `unlockedPurchaseRunsPastTheLimit`, `decrementNeverGoesBelowZero`; the VM
      suite now injects `SpyPurchaseProvider` so it never touches real StoreKit.
  - **Rejected finding**: the reviewer's "dead/mismatched `%lld` localization"
    is a false positive — `Text("You've run \(RunGate.freeRunLimit) …")` uses
    `LocalizedStringKey`, whose `Int` interpolation renders `%lld`, matching the
    catalog key and `LocalizationFixtures`.
- **Remaining manual items**: the plan's device/simulator checks still require a
  human (StoreKit configuration selection in the scheme is a documented GUI-only
  follow-up in `implement.md`):
  - 20 free runs then a refused 21st run shows the paywall (shortcut: temporary
    `freeRunLimit = 1`, revert before committing).
  - Buy via the local StoreKit configuration unlocks without relaunch; Restore
    Purchases recovers on reinstall.
  - Airplane-mode cold launch after a purchase stays unlocked (the cache bridges
    launch, and StoreKit resolves the local transaction).
  - Intent/shortcut and paired-watch remote runs at the limit speak/ack the
    refusal and create nothing.
  - Paywall retry affordance when the store is unreachable; VoiceOver labels.