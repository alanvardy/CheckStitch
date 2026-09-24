# Design Discussion

## Current State

CheckStitch is a thin SwiftUI app over a sources-only SPM package
(`CheckStitchCore`). Testability is **already mature and deliberate**: side
effects are isolated behind protocols and everything else is constructor-injected.

**Seams that already exist (the model to copy, not replace):**
- `ReminderDestinationTargeting` (`CheckStitchCore/.../ReminderDestinationTargeting.swift:95-108`) —
  EventKit seam, doc-commented "injected so tests can drive denial/missing-list/save-failure
  without touching EventKit"; value types `ReminderListOption` (7-20),
  `ReminderListsSnapshot` (26-75), `ReminderAccessStatus` (128-130).
- `ReminderCreating` (`ReminderCreating.swift:5-10`) — older, narrower EventKit seam.
- `PurchaseProviding` (`PurchaseProviding.swift:13-28`) — StoreKit seam kept out of Core so Core
  stays StoreKit-free for watchOS.
- `ChecklistSyncing` + `ChecklistSyncDiagnostics` (Core) — sync seam, referenced by
  `TestFixtures` only and untested directly.
- `BackgroundImageFetching` (internal, `BackgroundImageStore.swift:20-60`).

**Injection already in place:** `ChecklistStore.init(defaults:key:textEditDelay:now:)`
(`ChecklistStore.swift:50-57`) — `textEditDelay: nil` makes saves synchronous for tests;
`ChecklistRunViewModel(store:targeting:counter:purchases:spinnerDuration:)`
(`ChecklistRunViewModel.swift:14-30`) — `spinnerDuration: .zero`; `ChecklistSyncService`
takes `any ChecklistSyncing` (`24-96`); `now` injected in `ChecklistImportSession`.

**Deliberate non-seams:** no protocols between the app target and the concrete
`@Observable` stores. Every view model takes the store directly
(`ChecklistListViewModel.swift:15-60`). This is a stable architectural choice, not
a defect.

**Untested surface (from research Q3, symbol map):**
- Core: `ChecklistSyncDiagnostics.swift`, `ChecklistSyncing.swift`, `Environment.swift`.
- App: `AppGroup.swift`, `Color+CrossPlatform.swift`, `ChecklistExportDocument.swift`
  (indirect only), `AppearanceViewModel.swift` (indirect only), `PhoneSyncAdapter.swift`,
  `StoreKitPurchaseService.swift`, thin views `PaywallView` / `BackgroundSettingsView` /
  `ContentView` / `MyApp`. `AppDelegate`, `ChecklistDetailView`, `BackgroundPhotoLayer`,
  `Intents/*` are already covered.
- The strongest Core gap is **`ChecklistSyncDiagnostics`**: pure logic by name, zero tests.

**Residual in-view logic (the one real gap in "thin views"):** `ContentView.swift` (645
lines) — injects seven environment objects (9-16); the `perform(_:)` dispatcher (`594`) and
move-arrow translation (`460-472`) are logic with no behavioural test.

## Desired End State

An audit that (a) closes the high-value pure-logic coverage gaps with suites matching
the existing Swift Testing conventions, (b) adds a behavioural test for the one piece of
in-view logic that warrants it, and (c) records any genuine architecture/testability/code-smell
findings in a `findings.md` artifact — fixing only those that are in scope for testability.

Verification: `make test-unit` (fast) passes, then the full gate `bash ./scripts/test.sh`
prints `gate: ok`. No new compiler warnings (the gate is warnings-as-errors on every
Swift leg). New suites follow `struct <Thing>Tests`, `@Test`/`#expect`, behaviour-named
functions, `@MainActor` where required.

## Patterns to Follow

**Do follow:**
- **Isolated defaults store tests** — `makeIsolatedDefaults()` (`TestFixtures.swift:12-17`)
  plus reload-same-suite persistence assertions (`ChecklistStoreTests.swift:21,52-82`).
- **Spy seams over real side effects** — `SpyReminderDestination` (`TestFixtures.swift:50-113`),
  `SpyPurchaseProvider`, `InMemoryChecklistSync`/`FakeChecklistSyncTransport`.
- **`textEditDelay: nil` for synchronous saves** in any new store-touching suite
  (`ChecklistStore.swift:50-57`).
- **`@MainActor` on suites touching EventKit or view models** — test targets deliberately
  do *not* set `SWIFT_DEFAULT_ACTOR_ISOLATION` (conventions.md).
- **Data-driven `@Test(arguments:)`** for pure enumeration/table logic (e.g. diagnostics
  severity mapping, status/color mapping).
- **Headless-safe view assertions** — `String(describing:)` on state-slot names +
  offscreen `ImageRenderer` render-oracles (`ChecklistDetailViewTests.swift:1-14`,
  `ViewRenderTests.swift:1-22`).
- **Fixtures in `TestFixtures.swift`** rather than per-suite local fakes; keep
  `StubBundle`'s `@unchecked Sendable` restatement (`StubBundle.swift:7-13`) and the
  process-lifetime `sharedTestEventStore` (weak `EKReminder` ref, `TestFixtures.swift:18`).

**Do NOT follow / do NOT introduce:**
- **No new protocols over stores.** The concrete `@Observable` store design is deliberate
  (`ChecklistListViewModel.swift:15-60`); extracting store protocols is scope creep and a
  large diff across every init call site.
- **Don't read `body`/`.environment().body`** — fatal-errors headlessly
  (`ChecklistDetailViewTests.swift:1-14`).
- **Don't add real-EventKit save round-trips** — permission/entitlement-dependent and flaky;
  real adapter suites stay crash-canaries (`EventKitReminderDestinationTests`).
- **Don't hand-roll l10n keys** — any new user-facing string needs all 6 languages in
  `Localizable.xcstrings` + a `LocalizationFixtures.requiredKeys` entry.
- **Don't leave a bare `name=` destination** in any test script; use this worktree's
  `.simulator_id`.

## Design Decisions

1. **Scope = test-addition first, refactor only where blocked**: Start from the existing
   patterns and fill coverage. Refactor a seam only if a genuinely high-value test cannot
   be written without it — no speculative protocol extraction. *Why:* research shows a
   mature, deliberate DI design; churn there is risk without benefit.

2. **Coverage targets, in priority order**: `ChecklistSyncDiagnostics` (pure logic, zero
   tests) → `AppGroup` / `Color+CrossPlatform` (contract-critical constants/mapping) →
   `ChecklistExportDocument` / `AppearanceViewModel` (confirm and formalize indirect
   coverage) → `ChecklistSyncing` / `Environment` (definition/gating contracts).
   *Why:* highest value per line, all reachable without new seams.

3. **One view-layer exception: `ContentView` dispatcher.** Add a behavioural test for
   `perform(_:)` (`ContentView.swift:594`) and move-arrow translation (`460-472`) rather
   than testing the whole view body. *Why:* it is the only real in-view logic; the rest of
   the view layer stays tested via VMs and render-oracles.

4. **Evidence basis = the research symbol map, no coverage instrumentation.** Do not add
   `xccov`/coverage flags to the Makefile or gate. *Why:* the file→suite mapping is already
   established; coverage tooling is a separate infrastructure task and would widen scope.

5. **Refactoring policy: fix in-scope, log out-of-scope.** In-scope = anything that blocks
   or materially weakens a unit test; fix it on this ticket. Everything else (architecture
   smells, non-testability issues) goes to `findings.md` with severity and evidence.
   *Why:* matches the task ("surface rather than silently fix") and the no-child-tickets rule.

6. **EventKit real adapters stay crash-canaries.** Keep spies as the behavioural surface;
   do not add save/resolve/delete round-trips to real `EKEventStore`. *Why:* environment-,
   permission- and entitlement-dependent, which makes them flaky in the gate.

7. **No new test infrastructure.** Reuse `TestFixtures.swift`, `StubBundle`,
   `BackgroundTestFixtures`, `LocalizationFixtures`; add fixtures there only when a new
   fake is genuinely needed. *Why:* infrastructure already covers the seams in scope.

## What We're NOT Doing

- No protocols over stores; no store/VM interface abstraction.
- No coverage-instrumentation Makefile/gate changes.
- No new real-EventKit integration tests, and no changes to `sharedTestEventStore` lifetime.
- No UI smoke expansion — the XCTest suite stays the single launch/accessibility smoke.
- No new user-facing strings (avoids the 6-language + `requiredKeys` obligation).
- No child tickets; all changes land on the main ticket.
- No refactors of healthy seams (`PurchaseProviding`, `ReminderDestinationTargeting`,
  `BackgroundImageFetching`) — they already satisfy their test contracts.
- No broad view testing (`PaywallView`, `MyApp`) beyond what render-oracles already reach.

## Open Risks

- **Untested thin views may still hide logic.** Research could not confirm whether
  `Color+CrossPlatform`, `ChecklistExportDocument`, `AppearanceViewModel`, `ContentView`
  are indirectly reached by `ViewRenderTests`/`SmokeTests`; the first task in the plan is a
  coverage-confirmation pass so we don't write duplicate suites.
- **`AppGroup` may be un-unit-testable as written** (static constants reading a real
  app-group container). If so, it is a finding, not a forced refactor.
- **Fake duplication risk**: `PhoneSyncAdapter`/`StoreKitPurchaseService` may only be
  reachable with fakes that already exist in a private suite — check before adding.
- **`ChecklistSyncDiagnostics` may couple to KVS transport**, making it need a seam.
  If so, this is the one place Option B (targeted extraction) is licensed.
- **Gate time**: new macOS-hosted suites lengthen `make test-unit`; keep suites fast and
  side-effect-free to avoid the simulator/UI leg becoming the bottleneck.