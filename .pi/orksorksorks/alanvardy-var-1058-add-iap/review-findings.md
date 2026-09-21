I have no write-capable tool in this session, so per the runtime policy I'll return the complete artifact in my final response for persistence to the configured output path.

## Review — CheckStitch IAP paywall (VAR-1058)

Reviewed the full diff against the cited files (`ChecklistReminders.swift`, `PurchaseService.swift`, `RunCounter.swift`, `ChecklistRunViewModel.swift`, `ContentView.swift`, `PaywallView.swift`, `MyApp.swift`, `ChecklistSync.swift`, `RunChecklistIntent.swift`, `PurchaseProviding.swift`, `StoreKitPurchaseService.swift`, tests). Verified all five `RunResultKind` sites (outcome ctor, `message`, `wireName`, `fromWireName`, `runResultDict`) plus the `WatchChecklistStore.phase` mapping and both `ReminderRunOutcome` switchers handle `.purchaseRequired`. Gate semantics are correctly sequenced: the guard sits before `requestAccess`/EventKit work, and `recordSuccess()` is only reached on `.created`.

### Blockers
None found. Gate correctness, refusal-before-EventKit, "exactly once on fully successful run", concurrency (MainActor serialization, weak-self observer capture, Sendable `RunGate`/`RunResultKind`), memory (no force unwraps, no retain cycles — the weak `[weak self]` in `startObserving` is correct for the singleton `PurchaseService`), and shared-`PurchaseEnvironment.service` wiring are all sound.

### Fixes worth doing now

1. **PaywallView.swift:14 ↔ Localizable.xcstrings "You've run %lld…" — dead/mismatched localization.**
   The view renders `Text("You've run \(RunGate.freeRunLimit) checklists…")` (Swift interpolation → literal "…20…"), while the catalog + `LocalizationFixtures.swift` (`test = .app` list) ship the key `"You've run %lld checklists. Buy once to keep creating reminders."` with 5 translations. The two strings are not textually equal, so the `%lld` entry can never match the view's literal: non-English users see an untranslated/interpolated headline and the catalog entry (+translations +fixture entry) is orphaned. Either route the headline through a locale-aware `%lld`/`LocalizedStringResource(arguments:)` so the key matches, or drop the `%lld` entry/translations and localize the literal actually shown.

2. **PurchaseService.swift:78-81 — fail-open cache silently defeats StoreKit revocation/refund.**
   `apply(false)` with `cache.isVerified == true` force-keeps `.unlocked`, and the cache is only ever written `true`. `StoreKitPurchaseService.currentEntitlement` (StoreKitPurchaseService.swift:33) explicitly detects revocation (`transaction.revocationDate == nil`), but the fail-open layer ignores that `false` result, so a refunded/revoked user is unlocked forever. Distinguish "provider unreachable" from "verified(no) / revoked" — only fail open on connectivity, and clear/invalidate the cache (`setVerified(false)`) when a verified revocation is observed — otherwise the revocation check is dead code.

3. **ChecklistReminders.swift:58-59 — a run that creates 0 reminders still counts against the free limit.**
   A fully-blank/empty checklist reaches `final postfix let total = …filter…count`? No — it returns `.created(count: 0)` without entering `catch`, so `gate.recordSuccess()` increments the counter for a run that created nothing, consuming a free slot. Consider only advancing the counter when `created > 0` (or move the increment behind `if created > 0`), matching "successful run that created reminders."

### Optional improvements

4. **ChecklistRunViewModel.swift:44 — entitlement resolution race on cold launch.** The VM builds its gate from `purchases.isUnlocked` without awaiting `purchases.start()` (unlike `RunChecklistIntent.productionGate`, which awaits `start()` first). A paid user at the limit who taps Run before MyApp's `.task { await purchaseService.start() }` resolves sees the paywall spuriously. Fail-closed and recoverable, but inconsistent with the intent path — consider `guard purchases.hasStarted`/resolving entitlement before reading `isUnlocked`.

5. **RunCounter.swift:38-46 — check-then-act boundary over-count.** `permitsRun` (reads `count`) and `recordSuccess()` (increments) are separated by the async EventKit work; two concurrent runs (different checklist ids; the tap-guard is per-id) can both pass a `count == 19` read and drive the total to 21, soft-exceeding the 20-run limit. Acceptable for a free tier, but note the limit is not enforced atomically across concurrent runs.

6. **RunCounter.swift:44 — counter grows unbounded for unlocked users.** `recordSuccess()` always increments (test `unlockedUserRunsPastTheLimit` expects 21). Harmless while `isUnlocked` stays true, but if lock-state is ever queried by stored count it would be wrong. Minor.

7. **PaywallView.swift:16 — hardcoded free-limit string text.** `Text("You've run \(RunGate.freeRunLimit)…")` duplicates the limit number in a user-facing literal rather than a single localized source; also the source of finding #1.

Merge verdict: **OK with notes** (binding #1 and #2 before release; #3 is a behavioral edge worth deciding on now; #4–#7 follow-ups).

---
Note: The configured output path `.pi/orksorksorks/alanvardy-var-1058-add-iap/review-findings.md` does not exist and I have no file-write tool in this session, so the artifact is returned inline for the runtime to persist.