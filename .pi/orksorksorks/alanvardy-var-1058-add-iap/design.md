# Design Discussion

## Current State

CheckStitch turns a checklist into Reminders. Every run converges on one app seam,
`ChecklistReminders.create(from:)` (`CheckStitch/ChecklistReminders.swift:18-54`),
and one core policy, `ChecklistCreator.create` (`CheckStitchCore/.../ChecklistCreator.swift:30-42`):

- **UI** — `ChecklistRunViewModel.createReminders(for:)` (`CheckStitch/ChecklistRunViewModel.swift:32-48`),
  bound from `ContentView.swift:503-505`, alert at `:161-168`.
- **Voice/shortcut** — `RunChecklistIntent.swift:53-58` calls `ChecklistReminders.create` directly.
- **Remote/sync** — `ChecklistSyncCoordinator.handle(.runChecklist(...))` (`CheckStitchCore/.../ChecklistSyncCoordinator.swift:98-118`)
  dedupes by `runID`/`inFlightRunIDs`, then calls an injected `createReminders` closure.

Outcomes are `.created(count)`, `.destinationMissing`, `.permissionDenied`,
`.partiallyCreated`, `.failed` (`ChecklistReminders.swift:20-53`). A run counts as
completed when `createReminders` returns and the UI/coordinator records success.

Durable small state today:
- **App Group `UserDefaults`** — `AppGroup.defaults`, suite `group.app.alanvardy.CheckStitch`
  (`CheckStitch/AppGroup.swift:6-10`), enabled by `CheckStitch/AppGroup.entitlements:7-10`.
  Backs `ChecklistStore` under key `checklists.v1` (`ChecklistStore.swift:63-66`).
- **`NSUbiquitousKeyValueStore`** — only `checklists.v1`, via `UbiquitousChecklistSync`
  (`CheckStitchCore/.../ChecklistSyncing.swift:22-42`) and `ChecklistSyncService`.
- **`@AppStorage` view prefs** — `UserDefaults.standard`, display-only (`ContentView.swift:11-17`).
- **Single-value wrapper convention** — `AppLanguagePreference.swift:6-29`,
  `AppearanceMode.swift:95-120`: validated getter, `setRawValue`, injectable `defaults`/`key`.

There is **no counter store, no purchase/entitlement surface, and no gating precedent**
anywhere in `*.swift`; the only "gate" hits are unrelated (delete confirmation, sync
diagnostics, test actors, orientation lock). IAP is greenfield.

App-level state is a single-process iOS/macOS `MyApp` that builds `@State` singletons,
injects them via `.environment(...)` (`MyApp.swift:21-45,56-86`), and views read them
with `@Environment(Type.self)` (`ContentView.swift:7-13`). watchOS is a separate `@main`
(`CheckStitchWatch/CheckStitchWatchApp.swift:5-7`) with read-only EventKit and no coordinator.

## Desired End State

A user can run checklists freely up to a limit of 20 successful runs. On the 21st run,
every entry point (UI button, voice/shortcut intent, remote/sync coordinator) refuses to
create reminders and presents a paywall offering a single non-consumable
**CheckStitch License**. Purchasing once unlocks unlimited runs on all devices signed in
to the same App Store account, persisting across launches. "Restore Purchases" recovers
a purchase on a new device or after reinstall.

Verification of correctness:
- A fresh install runs 20 checklists, succeeds on all 20, and the 21st is refused with the
  paywall visible.
- Completing the purchase (StoreKit test/sandbox) unlocks immediately without relaunch;
  the 21st run then succeeds.
- Restore on a device with no local purchase state re-unlocks the app.
- `Transaction.updates` re-unlocks if the purchase completes elsewhere (Ask to Buy,
  another device) while the app is running.
- Failed/denied/partial runs do **not** advance the counter.
- Editing, viewing, exporting and syncing checklists remain available while locked.
- `./scripts/test.sh` prints `gate: ok`.

## Patterns to Follow

- **Core protocol seam + platform adapter** — mirror `ReminderCreating`
  (`ReminderCreating.swift:7`) and `ChecklistSyncing` (`ChecklistSyncing.swift:6-16`):
  declare `public protocol PurchaseProviding: Sendable` in
  `CheckStitchCore/Sources/CheckStitchCore/`; keep the StoreKit adapter in `CheckStitch/`.
- **`@MainActor @Observable` service assembled once** — follow `ChecklistSyncService`
  (`ChecklistSyncService.swift:26`): concrete type, injected seams, `private(set)` state,
  explicit `start()`. Declare it `@State` in `MyApp.init()` and inject via `.environment(...)`
  (`MyApp.swift:21-45,78-86`); read with `@Environment(...)`.
- **Small-value persistence wrapper** — model the counter on `AppLanguagePreference`
  (`AppLanguagePreference.swift:6-29`): injectable `defaults` + `static let defaultsKey`,
  validated read, typed write helper. Persist through `AppGroup.defaults`
  (`AppGroup.swift:6-10`).
- **Core policy owns the rule** — put the "may I run?" decision next to `ChecklistCreator`
  so all callers inherit it; keep `ChecklistReminders` the thin app seam it already is.
- **Swift Testing conventions** — `struct <Thing>Tests`, `@Test`/`#expect`, behaviour-named
  methods, `@Test(arguments:)` tables, `@MainActor` for suites touching the run path;
  fakes live in `CheckStitchTests/TestFixtures.swift` alongside `makeIsolatedDefaults`.
  `@testable import CheckStitch` / `CheckStitchCore`.
- **Per-platform gating** — `#if os(iOS)` for the paywall surface; do not change the test
  targets' missing `SWIFT_DEFAULT_ACTOR_ISOLATION`.

Patterns **not** to follow:
- Do **not** persist the counter with `@AppStorage`/`.standard` (`ContentView.swift:11-17`) —
  that path is per-install display state, not App-Group durable state.
- Do **not** thread the counter through `ChecklistStore`'s encoded envelope or the
  `checklists.v1` KVS key — mixing billing state into the checklist codec drags in its
  migration/`unsupportedVersion` surface (`ChecklistStore.swift:70-101`).
- Do **not** put the gate only in `ChecklistRunViewModel` — `RunChecklistIntent` and the
  coordinator bypass it.

## Design Decisions

1. **Product model**: a single non-consumable **CheckStitch License**, one product ID,
   lifetime unlock. Entitlement reduces to "does `Transaction.currentEntitlements` contain
   this product?" — the least StoreKit state to manage.
2. **Counter storage**: an App Group `UserDefaults` counter (e.g. `runCount.v1`) behind a
   small preference-style type with injectable defaults/key. Local to the App Group,
   isolated in tests via `makeIsolatedDefaults`, and free of the unresolved
   KVS/watchOS-reachability questions from research.
3. **Threshold semantics**: runs 1–20 succeed; the 21st is refused. The counter increments
   exactly once per `.created` outcome — `.failed`, `.partial`, `.permissionDenied` and
   `.destinationMissing` do not advance it.
4. **Gate location**: a core policy seam consulted by `ChecklistReminders.create` (thus by
   all three entry points), producing a **new outcome case** (e.g. `.purchaseRequired`)
   that maps to the paywall. `ChecklistRunViewModel` and the coordinator map that outcome
   to the paywall presentation/acknowledgement; the intent maps it to spoken feedback.
5. **Purchase service**: `@MainActor @Observable` service in `CheckStitchCore` over a
   `PurchaseProviding` protocol seam, with `StoreKitPurchaseService` in `CheckStitch/`
   handling `Product.products(for:)`, `product.purchase()`, `Transaction.currentEntitlements`,
   the `Transaction.updates` listener, and `AppStore.sync()` for restore. Injected once in
   `MyApp.swift`.
6. **Gate scope**: only *creating reminders* is blocked. Browsing, editing, exporting and
   sync of checklists stay available; the app is not fully locked out.
7. **Paywall UX**: a blocking paywall presented when the threshold is crossed and whenever
   a run is refused while locked, with **Buy** and **Restore Purchases**. Entitlement is
   refreshed at launch, after purchase, on restore, and on `Transaction.updates`.
8. **Offline/failure policy**: fail-open on a previously verified entitlement — if StoreKit
   is unreachable, a user who already purchased stays unlocked. If entitlement is unknown
   and the counter is at the limit, show the paywall with a retry rather than unlocking.
9. **Platform scope**: gate iOS and macOS (shared `MyApp`/`ContentView`). watchOS is out of
   scope for the purchase surface — separate `@main`, no coordinator, read-only EventKit.
10. **Verification hook**: the counter and entitlement are checked before any per-item
    EventKit work, so a refused run performs no writes and returns the new outcome cleanly.

## What We're NOT Doing

- No subscriptions, consumables, credit packs, trials, or introductory offers.
- No server-side receipt validation, no backend, no account system — StoreKit 2 locally
  verified transactions only.
- No KVS/iCloud sync of the run counter or the entitlement; App Group local + StoreKit's
  own per-Apple-ID entitlement is the source of truth.
- No watchOS paywall, purchase flow, or watch-side gating.
- No App Store Connect metadata/product configuration work beyond what the ticket needs to
  run against a local StoreKit configuration file for testing and sandbox for device checks.
- No change to the existing outcome cases, `ChecklistStore` codec, or the `checklists.v1`
  KVS key.
- No analytics/telemetry for purchases.
- No retroactive counting of checklists run before this ships (counter starts at 0).
- No child tickets — all work stays on the main VAR-1058 ticket.

## Open Risks

- **StoreKit testability in `make test-unit`** — the fast gate is macOS-hosted with no
  signing. The seam keeps the gate green with a fake, but real purchase/renewal/restore
  behavior can only be exercised via `SKTestSession` or sandbox on a device/simulator;
  plan a deliberate manual verification step.
- **Entitlement timing** — `Transaction.currentEntitlements` is async; the paywall must not
  flash for an already-purchased user on cold launch. Resolve entitlement before evaluating
  the gate, or treat "not yet resolved" as not-locked on first paint.
- **Counter/limit interpretation** — "purchase after they have run 20 checklists" is taken
  as 20 free successful runs, then blocked. If the intended reading is 20 then one more free
  run, the threshold constant changes in one place.
- **Fail-open window** — cached-entitlement fail-open means a user with a stale local flag
  could briefly stay unlocked while offline; mitigated by only caching after a verified
  transaction and re-checking on every launch/update.
- **App Group writability** — the counter assumes the App Group suite is usable on all
  gated platforms (research notes watchOS reachability is unverified); since watch is out of
  scope this is acceptable, but confirm iOS/macOS writes land in the same suite.
- **`StoreKit` framework link/warnings** — new framework usage must compile under
  `WARNINGS_AS_ERRORS`; verify with `make build` / `make test-unit` before the full gate.