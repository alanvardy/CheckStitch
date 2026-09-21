# Structure Outline

## Approach

Gate *reminder creation only* at the one seam every entry point converges on
(`ChecklistReminders.create`), driven by an App-Group run counter (20 free
successful runs) plus a StoreKit-2 entitlement resolved by a Core
`@MainActor @Observable` `PurchaseService` over a `PurchaseProviding` seam. A
new `ReminderRunOutcome.purchaseRequired` maps to a blocking paywall; the gate
runs before any EventKit work, so a refused run writes nothing and does not
advance the counter. No migrations; two genuinely cross-cutting edits are noted
inline (the outcome enum fans out to its sync mirror and every switch site).

---

## Phase 1: Walking skeleton — durable counter + threshold refusal, all entry points

A successful run increments a durable App-Group counter; once 20 runs are
recorded and the (stubbed, always-locked) entitlement is absent, the next run is
refused **before any EventKit work** on the UI, voice-intent and remote/sync
paths, and the UI shows a placeholder paywall. Green tests prove counter
persistence, one-increment-per-success, no-increment on failure, and refusal
before writes. (Skeleton only: the paywall cannot yet purchase — Phase 2 fixes
that. Not shippable alone.)

**Files**: `CheckStitchCore/.../RunCounter.swift` (new),
`CheckStitchCore/.../PurchaseService.swift` (new — locked stub),
`CheckStitchCore/.../ReminderDestinationTargeting.swift`,
`CheckStitchCore/.../ChecklistSync.swift`,
`CheckStitchCore/.../ChecklistSyncCoordinator.swift`,
`CheckStitch/ChecklistReminders.swift`, `CheckStitch/ChecklistRunViewModel.swift`,
`CheckStitch/Intents/RunChecklistIntent.swift`, `CheckStitch/MyApp.swift`,
`CheckStitch/PaywallView.swift` (new — placeholder),
`CheckStitch/ContentView.swift`

**Key changes**:
- `RunCounter { init(defaults: UserDefaults, key: String = "runCount.v1"); var count: Int { get }; func increment(); func reset() }` — new; validated read (0 on missing/corrupt), mirrors `AppLanguagePreference`.
- `RunGate { static let freeRunLimit = 20; init(counter: RunCounter, isUnlocked: Bool, limit: Int = freeRunLimit); var permitsRun: Bool { get }; func recordSuccess() }` — new (Core, next to `ChecklistCreator`).
- `PurchaseService { private(set) var entitlement: EntitlementState; var isUnlocked: Bool { get } }` — new, `@MainActor @Observable`, stubbed `.locked`.
- `ReminderRunOutcome` — **add `case purchaseRequired`**; add its `errorMessage` arm.
- `RunResultKind` / `ChecklistSync` mirror — **add `purchaseRequired`** to the wire mapping (cross-cutting: the enum's sync mirror and every switch site must compile).
- `ChecklistReminders.create(from:targeting:gate:) async -> ReminderRunOutcome` — gate check first; `gate.recordSuccess()` exactly once on `.created`.
- `ChecklistRunViewModel` — takes `counter` + `purchases`, builds the `RunGate` per run, sets a `purchaseRequired` presentation flag on refusal.

**Contract**: `RunCounter`/`RunGate` types and `ReminderRunOutcome.purchaseRequired`; the gate is evaluated *before* permission/destination resolution and increments only on `.created`.

**Tests**: `RunCounterTests` (round-trip, corrupt value → 0, increment/reset);
`ChecklistRemindersTests` additions — 20th run allowed + counted, 21st →
`.purchaseRequired` with **zero** `targeting.create` calls, `.failed`/`.partial`
do not increment; `ChecklistRunViewModelTests` — refusal surfaces the paywall
flag, success still flashes.
**Verify**: `make test-unit` + `make build` (warnings-as-errors); manual — run a
checklist 20× on the simulator and confirm the 21st is refused with no new
reminders.

---

## Phase 2: Real purchase — Buy unlocks without relaunch

Tapping **Buy** starts a StoreKit 2 purchase of the single non-consumable
product; on success entitlement flips to unlocked immediately, the paywall
dismisses, and the previously-refused run succeeds. `Transaction.updates` keeps
entitlement live for purchases completing elsewhere.

**Files**: `CheckStitchCore/.../PurchaseProviding.swift` (new),
`CheckStitchCore/.../PurchaseService.swift`,
`CheckStitch/StoreKitPurchaseService.swift` (new),
`CheckStitch/CheckStitch.storekit` (new), `CheckStitch/PaywallView.swift`,
`CheckStitch/MyApp.swift`

**Key changes**:
- `PurchaseProviding: Sendable` — `func currentEntitlement() async -> Bool`; `func purchase() async throws -> Bool`; `func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void)`.
- `PurchaseService.start() async`, `purchase() async`, `private(set) var entitlement: EntitlementState { .unknown | .locked | .unlocked }` — no longer stubbed.
- `StoreKitPurchaseService` — `Product.products(for:)`, `product.purchase()`, `Transaction.currentEntitlements`, `Transaction.updates`; product ID `app.alanvardy.CheckStitch.license`.
- `PaywallView` — real Buy button (price from `Product`), in-flight/error states.
- `MyApp` — `@State` service, `.environment(...)`, `.task { await purchaseService.start() }`.

**Contract**: `PurchaseProviding` seam + `PurchaseService.isUnlocked` /
`start()` / `purchase()`; entitlement is the only thing the gate reads for
unlock, and `Transaction.updates` re-publishes it while running.

**Tests**: `PurchaseServiceTests` with a `SpyPurchaseProvider`
(`TestFixtures.swift`) — purchase flips `.locked → .unlocked`; provider throw
leaves locked; observer callback updates state.
**Verify**: `make test-unit`; manual — `SKTestSession` / simulator StoreKit
config: buy, paywall dismisses, 21st run succeeds with no relaunch.

---

## Phase 3: Restore + entitlement lifecycle (new device, offline, no paywall flash)

**Restore Purchases** re-unlocks a reinstall or a second device; entitlement is
resolved at launch before the gate is first evaluated (no paywall flash for a
paid user); a previously-verified offline user stays unlocked (fail-open), while
unknown-at-limit shows the paywall with a retry rather than unlocking.

**Files**: `CheckStitch/StoreKitPurchaseService.swift`,
`CheckStitchCore/.../PurchaseService.swift`, `CheckStitch/PaywallView.swift`,
`CheckStitch/MyApp.swift`

**Key changes**:
- `PurchaseProviding.restore() async throws -> Bool` (adapter: `AppStore.sync()` then re-read `currentEntitlements`).
- `PurchaseService.restore() async`, verified-entitlement cache, `.unknown` + fail-open policy; `start()` resolves entitlement before the first gate read.
- `PaywallView` — Restore button; retry affordance when entitlement is `.unknown`.
- `MyApp` — launch ordering so `start()` completes before first run evaluation.

**Contract**: `PurchaseService.restore()` and the rule "verified → unlocked
(fail-open); unknown-at-limit → paywall, never a silent unlock".

**Tests**: `PurchaseServiceTests` — restore unlocks; restore failure stays
locked; cached-verified offline stays unlocked; unknown-at-limit reports locked.
**Verify**: `make test-unit`; manual — delete the app, reinstall, Restore, confirm
unlock; airplane-mode cold launch with a prior purchase stays unlocked.

---

## Phase 4: Hardening & polish — every entry point, every state

Voice/shortcut and remote/sync refusals read clearly; the paywall handles
product-load failure, retry and pending; browsing/editing/exporting/syncing stay
usable while locked; accessibility labels and empty/error states covered.

**Files**: `CheckStitch/Intents/RunChecklistIntent.swift`,
`CheckStitchCore/.../ChecklistSync.swift`,
`CheckStitchCore/.../ChecklistSyncCoordinator.swift`,
`CheckStitch/PaywallView.swift`, `CheckStitch/ContentView.swift`,
`CheckStitch/ChecklistRunViewModel.swift`

**Key changes**:
- Spoken/shortcut message for `.purchaseRequired`; remote `RunResultKind.purchaseRequired` ack message finalised.
- `PaywallView` — load-failure + retry, pending, disabled/locked copy; accessibility.
- `ContentView` — verify list/edit/export/import/sync paths carry no gate; only run/create is blocked.

**Contract**: `.purchaseRequired` is fully handled at all three entry points and
never silently swallowed; the paywall is the only new blocking surface.

**Tests**: sad-path suites across `ChecklistRemindersTests`,
`ChecklistRunViewModelTests`, `PurchaseServiceTests`; existing suites unchanged
and green.
**Verify**: `bash scripts/test.sh` prints `gate: ok`; manual — voice/shortcut and
a remote run while locked both surface the refusal; editing/export still work.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` green — counter persists, 21st run refused, no EventKit writes, `.failed`/`.partial` don't increment.
- After Phase 2: `make test-unit` green — `SpyPurchaseProvider` purchase → unlocked; manual SKTestSession buy unlocks a run.
- After Phase 3: `make test-unit` green — restore/fail-open/unknown semantics; manual reinstall + offline checks pass.
- After Phase 4: `./scripts/test.sh` prints `gate: ok`; manual entry-point + locked-browsing checks pass.

> Cross-cutting note: no schema migration exists here; the only horizontal edits
> are the `ReminderRunOutcome`/`RunResultKind` case addition (Phase 1) and the
> Core `PurchaseService` state machine, both landed green in a single phase.