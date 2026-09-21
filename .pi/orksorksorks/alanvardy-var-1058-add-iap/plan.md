# Implementation Plan

## Overview

Gate *reminder creation only* at the one seam every entry point converges on
(`ChecklistReminders.create`), driven by an App-Group run counter (20 free
successful runs) plus a StoreKit-2 entitlement resolved by a Core
`@MainActor @Observable` `PurchaseService` over a `PurchaseProviding` seam. A new
`ReminderRunOutcome.purchaseRequired` maps to a blocking paywall; the gate runs
before any EventKit work, so a refused run writes nothing and does not advance
the counter. No migrations. Two genuinely cross-cutting edits are flagged inline
(the `ReminderRunOutcome` → `RunResultKind` case addition, and the Core
`PurchaseService` state machine).

> **Framework note (read once):** the app target compiles with
> `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so new `CheckStitch/` types are
> implicitly `@MainActor`. `CheckStitchCore` is **not** default-isolated — Core
> types must carry `@MainActor` explicitly where needed. Test targets are **not**
> default-isolated; new suites opt in with `@MainActor`. Every compiling gate leg
> passes `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, so warnings fail the build.

> **Localization note (read once):** `LocalizationTests.catalogsHaveAllSixLanguages`
> and `nonEnglishValuesDifferFromEnglish` run over **every** entry in
> `CheckStitch/Localizable.xcstrings`. Any key you add must carry all six
> languages (`en`, `de`, `es`, `fr`, `ja`, `zh-Hans`) with a value that differs
> from English. Exact JSON is supplied per phase. Keys are stored sorted.

---

## Phase 1: Walking skeleton — durable counter + threshold refusal, all entry points

A successful run increments a durable App-Group counter; once 20 runs are
recorded and the (stubbed, always-locked) entitlement is absent, the next run is
refused **before any EventKit work** on the UI, voice-intent and remote/sync
paths, and the UI shows a placeholder paywall.

### Changes

#### 1. Core: durable counter + gate
**File**: `CheckStitchCore/Sources/CheckStitchCore/RunCounter.swift`
**Action**: create

Both types live in this one file. `@MainActor` makes them implicitly `Sendable`
(so the `RunGate` can be stored in the `Sendable` `RunChecklistIntent`) and
matches the app target's MainActor-default isolation.

```swift
import Foundation

/// Durable "successful runs" counter in an injected `UserDefaults` suite (the
/// App Group in production). Mirrors `AppLanguagePreference`'s validated-read
/// convention: missing/corrupt/negative reads as `0`.
@MainActor
public final class RunCounter {
    public init(defaults: UserDefaults, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public static let defaultsKey = "runCount.v1"

    /// Validated count; absent, non-integer or negative → 0.
    public var count: Int {
        guard let stored = defaults.object(forKey: key) as? Int, stored >= 0 else { return 0 }
        return stored
    }

    public func increment() { defaults.set(count + 1, forKey: key) }
    public func reset() { defaults.removeObject(forKey: key) }

    private let defaults: UserDefaults
    private let key: String
}

/// The "may I run this checklist?" policy. Permits every run while unlocked;
/// otherwise permits while `count < limit`. Callers must call `recordSuccess()`
/// exactly once per `.created` outcome — nothing else advances the counter.
@MainActor
public struct RunGate: Sendable {
    public static let freeRunLimit = 20

    public init(counter: RunCounter, isUnlocked: Bool, limit: Int = freeRunLimit) {
        self.counter = counter
        self.isUnlocked = isUnlocked
        self.limit = limit
    }

    public var permitsRun: Bool { isUnlocked || counter.count < limit }

    public func recordSuccess() { counter.increment() }

    private let counter: RunCounter
    private let isUnlocked: Bool
    private let limit: Int
}
```

#### 2. Core: purchase service (locked stub)
**File**: `CheckStitchCore/Sources/CheckStitchCore/PurchaseService.swift`
**Action**: create

Phase 1 ships the public shape only; Phase 2 fills it in.

```swift
import Foundation
import Observation

/// Entitlement source for the run gate. Phase 1 is a stub: always locked.
@MainActor
@Observable
public final class PurchaseService {
    public enum EntitlementState: Equatable, Sendable {
        case unknown
        case locked
        case unlocked
    }

    public init() {}

    public private(set) var entitlement: EntitlementState = .locked

    public var isUnlocked: Bool { entitlement == .unlocked }

    public func start() async {}
}
```

#### 3. Core: new outcome case
**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`
**Action**: modify

Add `case purchaseRequired` to `ReminderRunOutcome` and its `errorMessage` arm.
This is cross-cutting: every exhaustive `switch` over the enum must gain an arm.

```swift
public enum ReminderRunOutcome: Equatable, Sendable {
    case created(count: Int)
    case destinationMissing
    case permissionDenied
    /// The free-run limit was reached and no license is held. Refused before
    /// any EventKit work; the UI presents the paywall.
    case purchaseRequired
    case partiallyCreated(created: Int, total: Int, reason: String)
    case failed(String)

    public var errorMessage: String? {
        switch self {
        case .created: return nil
        case .destinationMissing: return "That list no longer exists; no reminders were created."
        case .permissionDenied: return "CheckStitch doesn't have permission to access Reminders; no reminders were created."
        case .purchaseRequired: return "CheckStitch needs a license to keep creating reminders."
        case .partiallyCreated(let created, let total, let reason):
            return "Created \(created) of \(total) reminders; the rest were not created. \(reason)"
        case .failed(let message): return message
        }
    }
}
```

#### 4. Core: sync mirror + watch mapping
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

`RunResultKind` mirrors `ReminderRunOutcome` across the watch wire. Add the case
to **all five** of its exhaustive sites, plus the watch's `receive` switch.

```swift
public enum RunResultKind: Equatable, Sendable {
    case created(Int)
    case partiallyCreated(created: Int, total: Int)
    case permissionDenied
    case destinationMissing
    /// The phone refused the run at the free limit; the watch cannot purchase.
    case purchaseRequired
    case notFound
    case failed

    public init(_ outcome: ReminderRunOutcome) {
        switch outcome {
        case .created(let count): self = .created(count)
        case .partiallyCreated(let created, let total, _):
            self = .partiallyCreated(created: created, total: total)
        case .permissionDenied: self = .permissionDenied
        case .destinationMissing: self = .destinationMissing
        case .purchaseRequired: self = .purchaseRequired
        case .failed: self = .failed
        }
    }

    public var message: String {
        switch self {
        // … existing arms unchanged …
        case .purchaseRequired: "CheckStitch needs a license to keep creating reminders."
        // … existing arms unchanged …
        }
    }

    var wireName: String {
        switch self {
        // … existing arms unchanged …
        case .purchaseRequired: "purchaseRequired"
        // … existing arms unchanged …
        }
    }

    init?(wireName: String, count: Int?, total: Int?) {
        switch wireName {
        // … existing arms unchanged …
        case "purchaseRequired": self = .purchaseRequired
        // … existing arms unchanged …
        }
    }
}
```

In `ChecklistSyncMessage.runResultDict(_:)`, add `.purchaseRequired` to the
payload-free list:

```swift
case .permissionDenied, .destinationMissing, .purchaseRequired, .notFound, .failed:
    break
```

In `WatchChecklistStore.receive(_:)`, map the new kind onto the existing
failure phase:

```swift
case .permissionDenied, .destinationMissing, .purchaseRequired, .notFound, .failed:
    .failed(result.kind.message)
```

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
**Action**: none (verified)

The coordinator routes outcomes through `RunResultKind(outcome)` and never
switches on `ReminderRunOutcome` directly, so the new case flows through with no
edit. Listed here because `structure.md` names it; re-check that its only
outcome use is `RunResultKind(outcome)` after editing.

#### 5. App: gate the chokepoint
**File**: `CheckStitch/ChecklistReminders.swift`
**Action**: modify

Replace the existing 2-arg `create(from:targeting:)` with a gated 3-arg method,
and make the production entry resolve its gate from the shared purchase service
plus the App-Group counter. The gate check is the **first** statement — a refused
run touches neither `requestAccess()` nor `reminderLists()`.

```swift
/// Production entry point: resolves entitlement, builds the gate, then delegates.
static func create(from checklist: Checklist) async -> ReminderRunOutcome {
    await create(from: checklist,
                 targeting: EventKitReminderDestination.shared,
                 gate: await productionGate())
}

/// The gate every entry point shares: the one injected purchase service plus
/// the durable App-Group counter.
static func productionGate() async -> RunGate {
    let purchases = PurchaseEnvironment.service
    await purchases.start()
    return RunGate(counter: RunCounter(defaults: AppGroup.defaults),
                   isUnlocked: purchases.isUnlocked)
}

static func create(from checklist: Checklist,
                   targeting: ReminderDestinationTargeting,
                   gate: RunGate) async -> ReminderRunOutcome {
    // Gate first: a refused run performs no EventKit work and writes nothing.
    guard gate.permitsRun else { return .purchaseRequired }

    let prefixNumbers = checklist.prefixesReminderNumbers
    var created = 0
    do {
        // … existing body unchanged through the item loop …
        // Exactly once, and only for a fully successful run.
        gate.recordSuccess()
        return .created(count: created)
    } catch {
        // … existing catch unchanged …
    }
}
```

`PurchaseEnvironment` is defined in `MyApp.swift` (step 8).

#### 6. App: run view model presents the paywall
**File**: `CheckStitch/ChecklistRunViewModel.swift`
**Action**: modify

Inject the counter and the purchase service; build the gate per run (so a
purchase mid-session is seen); surface `.purchaseRequired` as a presentation flag
rather than the failure alert.

```swift
init(
    store: ChecklistStore,
    targeting: ReminderDestinationTargeting = EventKitReminderDestination.shared,
    counter: RunCounter = RunCounter(defaults: AppGroup.defaults),
    purchases: PurchaseService = PurchaseEnvironment.service,
    spinnerDuration: Duration = .seconds(1)
) { … }

/// Present when a run was refused at the free limit.
private(set) var isShowingPaywall = false

func createReminders(for id: UUID) async {
    guard !creating.contains(id), let checklist = store.checklist(id: id) else { return }
    creating.insert(id)
    async let minimumSpinner: Void = Task.sleep(for: spinnerDuration)
    let gate = RunGate(counter: counter, isUnlocked: purchases.isUnlocked)
    let outcome = await ChecklistReminders.create(from: checklist, targeting: targeting, gate: gate)
    try? await minimumSpinner
    creating.remove(id)
    switch outcome {
    case .created:
        created.insert(id)
        try? await Task.sleep(for: .seconds(1))
        created.remove(id)
    case .purchaseRequired:
        isShowingPaywall = true
    case .destinationMissing, .permissionDenied, .partiallyCreated, .failed:
        runErrorMessage = outcome.errorMessage
    }
}

func dismissPaywall() { isShowingPaywall = false }
```

Add `private let counter: RunCounter` and `private let purchases: PurchaseService`
to the stored properties.

#### 7. App: voice/shortcut intent
**File**: `CheckStitch/Intents/RunChecklistIntent.swift`
**Action**: modify

Add an injectable gate (required on the test initializer so tests can never
accidentally use the production gate) and the `.purchaseRequired` dialogue arm.

```swift
// stored properties
private let injectedGate: RunGate?

init() { self.injectedStore = nil; self.injectedTargeting = nil; self.injectedGate = nil }

@MainActor
init(store: ChecklistStore, targeting: ReminderDestinationTargeting, gate: RunGate) {
    self.injectedStore = store
    self.injectedTargeting = targeting
    self.injectedGate = gate
}

// in perform(), replacing the existing create call
let gate = injectedGate ?? await ChecklistReminders.productionGate()
let outcome = await ChecklistReminders.create(from: stored, targeting: targeting, gate: gate)
```

`RunChecklistDialogue.message(for:)` gains an arm whose string is added to the
App catalog in this phase (step 11):

```swift
case .purchaseRequired:
    return LocalizedStringResource(
        "You've reached the CheckStitch free limit. Open CheckStitch to buy a license.",
        table: "Localizable", bundle: .main)
```

#### 8. App: assembly and injection
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Add the shared purchase environment, the `@State` service, its injection in both
scene branches, and launch resolution.

```swift
@State private var purchaseService: PurchaseService

// in init()
_purchaseService = State(initialValue: PurchaseEnvironment.service)

// in both WindowGroup bodies, alongside the other .environment(...) calls
.environment(purchaseService)
.task { await purchaseService.start() }

/// The one purchase service the UI, the intent and the sync coordinator share.
/// Defined here (app target) because `StoreKitPurchaseService` is app-side while
/// `PurchaseService` lives in Core.
@MainActor
enum PurchaseEnvironment {
    static let service = PurchaseService()
}
```

(Phase 2 changes the one line inside `PurchaseEnvironment`.)

#### 9. App: placeholder paywall
**File**: `CheckStitch/PaywallView.swift`
**Action**: create

```swift
import CheckStitchCore
import SwiftUI

/// Blocking unlock surface, presented when a run is refused at the free limit.
/// iOS and macOS share it; watchOS has no purchase surface.
struct PaywallView: View {
    @Environment(PurchaseService.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Unlock CheckStitch")
                .font(.title2.bold())
            Text("You've run \(RunGate.freeRunLimit) checklists. Buy once to keep creating reminders.")
                .multilineTextAlignment(.center)
            Button("Buy") {}          // Phase 2 wires the purchase
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("paywallBuyButton")
            Button("Not now") { dismiss() }
                .accessibilityIdentifier("paywallDismissButton")
        }
        .padding()
        .accessibilityIdentifier("paywallView")
    }
}
```

#### 10. App: present the paywall
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add a `.sheet` immediately after the existing `Couldn't create reminders` alert,
and add the service to the `#Preview` environment.

```swift
.sheet(isPresented: Binding(get: { runVM.isShowingPaywall },
                            set: { if !$0 { runVM.dismissPaywall() } })) {
    PaywallView()
}
```

```swift
// in #Preview, alongside the other .environment(...) calls
.environment(PurchaseEnvironment.service)
```

#### 11. App: localizable strings
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Insert these five keys in sorted position inside `"strings"` (all six languages
are mandatory — see the localization note). `%lld` is the `RunGate.freeRunLimit`
interpolation; keep the specifier exactly.

```json
"Buy" : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Kaufen" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Buy" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Comprar" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Acheter" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "購入" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "购买" } }
  }
},
"Not now" : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Nicht jetzt" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Not now" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Ahora no" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Pas maintenant" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "後で" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "以后再说" } }
  }
},
"Unlock CheckStitch" : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "CheckStitch freischalten" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Unlock CheckStitch" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Desbloquear CheckStitch" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Débloquer CheckStitch" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "CheckStitchをロック解除" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "解锁 CheckStitch" } }
  }
},
"You've reached the CheckStitch free limit. Open CheckStitch to buy a license." : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Du hast das kostenlose Limit von CheckStitch erreicht. Öffne CheckStitch, um eine Lizenz zu kaufen." } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "You've reached the CheckStitch free limit. Open CheckStitch to buy a license." } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Has alcanzado el límite gratuito de CheckStitch. Abre CheckStitch para comprar una licencia." } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Vous avez atteint la limite gratuite de CheckStitch. Ouvrez CheckStitch pour acheter une licence." } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "CheckStitchの無料上限に達しました。CheckStitchを開いてライセンスを購入してください。" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "你已达到 CheckStitch 的免费上限。请打开 CheckStitch 购买许可证。" } }
  }
},
"You've run %lld checklists. Buy once to keep creating reminders." : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Du hast %lld Checklisten ausgeführt. Einmal kaufen, um weiter Erinnerungen zu erstellen." } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "You've run %lld checklists. Buy once to keep creating reminders." } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Has ejecutado %lld listas. Compra una vez para seguir creando recordatorios." } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Vous avez exécuté %lld listes. Achetez une fois pour continuer à créer des rappels." } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "%lld個のチェックリストを実行しました。一度購入すると、引き続きリマインダーを作成できます。" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "你已运行 %lld 个清单。购买一次即可继续创建提醒。" } }
  }
}
```

#### 12. Tests: fixtures + new suites
**Files**: `CheckStitchTests/TestFixtures.swift`, `CheckStitchTests/RunCounterTests.swift` (new), `CheckStitchTests/ChecklistRemindersTests.swift`, `CheckStitchTests/ChecklistRunViewModelTests.swift`, `CheckStitchTests/RunChecklistIntentTests.swift`, `CheckStitchTests/ChecklistSyncCoordinatorTests.swift`, `CheckStitchTests/WatchChecklistStoreTests.swift`, `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify / create

- `TestFixtures.swift`: add a request counter to `SpyReminderDestination` so the
  "no EventKit work" assertion is direct:

  ```swift
  private(set) var requestAccessCount = 0
  func requestAccess() async throws -> Bool {
      requestAccessCount += 1
      if let onRequestAccess { await onRequestAccess() }
      if let accessError { throw accessError }
      return accessGranted
  }
  ```

- `RunCounterTests.swift` (new, **`@MainActor`** because `RunCounter` is
  MainActor-isolated), all using `makeIsolatedDefaults()`:
  - `missingValueReadsZero`
  - `incrementPersistsAcrossInstances` (increment, then a fresh `RunCounter` over
    the same defaults reads the value)
  - `corruptValueReadsZero` (`defaults.set("nope", forKey: RunCounter.defaultsKey)`)
  - `negativeValueReadsZero`
  - `resetReturnsToZero`

- `ChecklistRemindersTests.swift`: the only testable entry point changed shape, so
  add a private helper and rewrite every existing call to use it (mechanical
  search/replace: `ChecklistReminders.create(from: ` → `create(`):

  ```swift
  /// Gate-free seam for the existing sequencing/outcome tests: unlocked, and its
  /// counter lives in an isolated suite.
  private func create(_ checklist: Checklist,
                      targeting: SpyReminderDestination) async -> ReminderRunOutcome {
      let gate = RunGate(counter: RunCounter(defaults: makeIsolatedDefaults()),
                         isUnlocked: true)
      return await ChecklistReminders.create(from: checklist, targeting: targeting, gate: gate)
  }
  ```

  Add the gate tests:

  ```swift
  @Test
  func twentiethRunIsAllowedAndCounted() async {
      let counter = RunCounter(defaults: makeIsolatedDefaults())
      for _ in 0..<19 { counter.increment() }
      let gate = RunGate(counter: counter, isUnlocked: false)
      let spy = SpyReminderDestination(); spy.lists = snapshot()
      let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

      let outcome = await ChecklistReminders.create(from: checklist, targeting: spy, gate: gate)

      #expect(outcome == .created(count: 1))
      #expect(counter.count == 20)
  }

  @Test
  func twentyFirstRunIsRefusedBeforeAnyEventKitWork() async {
      let counter = RunCounter(defaults: makeIsolatedDefaults())
      for _ in 0..<20 { counter.increment() }
      let gate = RunGate(counter: counter, isUnlocked: false)
      let spy = SpyReminderDestination(); spy.lists = snapshot()
      let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

      let outcome = await ChecklistReminders.create(from: checklist, targeting: spy, gate: gate)

      #expect(outcome == .purchaseRequired)
      #expect(spy.createdTitles.isEmpty)
      #expect(spy.requestAccessCount == 0, "the gate is checked before any EventKit call")
      #expect(counter.count == 20, "a refused run does not advance the counter")
  }

  @Test
  func failedRunDoesNotAdvanceTheCounter() async { /* createError = TestError.boom → counter stays 0 */ }

  @Test
  func partialRunDoesNotAdvanceTheCounter() async { /* createFailureCount = 1 → counter stays 0 */ }

  @Test
  func unlockedUserRunsPastTheLimit() async { /* count 20, isUnlocked true → .created, count 21 */ }
  ```

  Extend `errorMessagesDescribeEachFailure`:
  ```swift
  #expect(ReminderRunOutcome.purchaseRequired.errorMessage != nil)
  ```

- `ChecklistRunViewModelTests.swift`: add
  `counter: RunCounter(defaults: makeIsolatedDefaults()),` to every
  `ChecklistRunViewModel(...)` construction (the purchase service keeps its
  production default, which is locked → under-limit runs still permit). Add:

  ```swift
  @Test
  func refusalAtTheLimitPresentsThePaywall() async {
      let (store, id) = makeStore(items: ["one"])
      let counter = RunCounter(defaults: makeIsolatedDefaults())
      for _ in 0..<20 { counter.increment() }
      let spy = resolvableDestination()
      let viewModel = ChecklistRunViewModel(store: store, targeting: spy,
                                            counter: counter, spinnerDuration: .zero)

      await viewModel.createReminders(for: id)

      #expect(viewModel.isShowingPaywall)
      #expect(viewModel.runErrorMessage == nil)
      #expect(spy.createdTitles.isEmpty)
      viewModel.dismissPaywall()
      #expect(!viewModel.isShowingPaywall)
  }
  ```

- `RunChecklistIntentTests.swift`: update `makeIntent()` to pass
  `gate: RunGate(counter: RunCounter(defaults: makeIsolatedDefaults()), isUnlocked: true)`
  to `RunChecklistIntent(store:targeting:gate:)`. Add a `.purchaseRequired`
  dialogue test asserting the new string.

- `ChecklistSyncCoordinatorTests.swift`: add
  `(.purchaseRequired, .purchaseRequired)` to the
  `everyOutcomeIsAnsweredOnTheWatchChannel` table and `.purchaseRequired` to the
  `aSadOutcomeStillReachesTheRunClosure` arguments table.

- `WatchChecklistStoreTests.swift`: add
  `(.purchaseRequired, .failed(RunResultKind.purchaseRequired.message))` to
  `everyResultKindMapsToAUserVisiblePhase`.

- `LocalizationFixtures.swift`: append the five new App keys (step 11) to the
  `("App", [...])` list in `requiredKeys`.

### Verification

#### Automated
- [x] `make build` passes (iOS simulator; warnings-as-errors)
- [x] `make build-mac` passes (macOS slice)
- [x] `make watch-build` passes (Core's new `@MainActor` types compile for watchOS)
- [x] `make test-unit` passes (`RunCounterTests` + gate/VM/intent/coordinator/watch
      suites green; `LocalizationTests` accepts the new catalog keys)
- [x] `grep -rn "case .destinationMissing, .permissionDenied" CheckStitch CheckStitchCore`
      returns no un-updated exhaustive switch

#### Manual
- [ ] `make run` on this worktree's simulator; run a checklist 20×. The 21st tap
      shows the paywall and the Reminders app receives no new reminders.
      (Shortcut while iterating: temporarily set `RunGate.freeRunLimit = 1` in
      `RunCounter.swift`, verify, then revert — do not commit the change.)
- [ ] Browse/edit/duplicate/export/import a checklist while at the limit — all
      still work.

---

## Phase 2: Real purchase — Buy unlocks without relaunch

Tapping **Buy** starts a StoreKit 2 purchase of the single non-consumable
product; on success entitlement flips to unlocked immediately, the paywall
dismisses, and the previously-refused run succeeds. `Transaction.updates` keeps
entitlement live for purchases completing elsewhere.

### Changes

#### 1. Core: purchase provider seam
**File**: `CheckStitchCore/Sources/CheckStitchCore/PurchaseProviding.swift`
**Action**: create

A price/value transport type is included so the paywall can show a price without
Core importing StoreKit (see Deviations).

```swift
import Foundation

/// Storefront offer for the license. Field subset of StoreKit's `Product` that
/// Core needs; the adapter maps it.
public struct PurchaseOffer: Equatable, Sendable {
    public init(id: String, displayName: String, displayPrice: String) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
    }

    public let id: String
    public let displayName: String
    public let displayPrice: String
}

/// Seam over StoreKit 2. Mirrors `ReminderDestinationTargeting`: a `@MainActor`
/// protocol so the service and its tests share one isolation domain.
@MainActor
public protocol PurchaseProviding: Sendable {
    /// Loads the license offer; `nil` when the store is unreachable.
    func offer() async -> PurchaseOffer?
    /// Verified entitlement for the license, `false` when none is held.
    func currentEntitlement() async -> Bool
    /// Runs the purchase flow. `true` means a verified entitlement is now held.
    func purchase() async throws -> Bool
    /// Fires on `Transaction.updates`; the argument is the new verified state.
    func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void)
}
```

#### 2. Core: real purchase service
**File**: `CheckStitchCore/Sources/CheckStitchCore/PurchaseService.swift`
**Action**: modify

Replace the stub with the state machine. Entitlement starts `.unknown`; `start()`
subscribes once and resolves; `purchase()`/`loadOffer()` drive the paywall.
(Phase 3 adds the cache and restore.)

```swift
@MainActor
@Observable
public final class PurchaseService {
    public enum EntitlementState: Equatable, Sendable { case unknown, locked, unlocked }

    public init(provider: any PurchaseProviding) {
        self.provider = provider
    }

    public private(set) var entitlement: EntitlementState = .unknown
    public private(set) var offer: PurchaseOffer?
    public private(set) var isLoadingOffer = false
    public private(set) var isPurchasing = false
    public private(set) var lastError: String?

    public var isUnlocked: Bool { entitlement == .unlocked }

    /// Resolve entitlement and subscribe to `Transaction.updates`. Idempotent.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        provider.startObserving { [weak self] unlocked in
            self?.entitlement = unlocked ? .unlocked : .locked
        }
        entitlement = await provider.currentEntitlement() ? .unlocked : .locked
    }

    public func loadOffer() async {
        guard offer == nil, !isLoadingOffer else { return }
        isLoadingOffer = true
        defer { isLoadingOffer = false }
        offer = await provider.offer()
    }

    public func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }
        do {
            if try await provider.purchase() { entitlement = .unlocked }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private let provider: any PurchaseProviding
    private var hasStarted = false
}
```

#### 3. App: StoreKit adapter
**File**: `CheckStitch/StoreKitPurchaseService.swift`
**Action**: create

```swift
import CheckStitchCore
import StoreKit

/// The only StoreKit-importing type. Kept in the app target so
/// `CheckStitchCore` (also compiled for watchOS) stays StoreKit-free.
@MainActor
final class StoreKitPurchaseService: PurchaseProviding {
    static let productID = "app.alanvardy.CheckStitch.license"

    private var updatesTask: Task<Void, Never>?

    func offer() async -> PurchaseOffer? {
        guard let product = try? await Product.products(for: [Self.productID]).first else {
            return nil
        }
        return PurchaseOffer(id: product.id,
                             displayName: product.displayName,
                             displayPrice: product.displayPrice)
    }

    func currentEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    func purchase() async throws -> Bool {
        guard let product = try await Product.products(for: [Self.productID]).first else {
            throw PurchaseError.productUnavailable
        }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PurchaseError.unverified
            }
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void) {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                guard transaction.productID == Self.productID,
                      transaction.revocationDate == nil else { continue }
                await transaction.finish()
                onChange(true)
            }
        }
    }
}

enum PurchaseError: LocalizedError {
    case productUnavailable
    case unverified

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "The CheckStitch license isn't available right now."
        case .unverified: "The purchase couldn't be verified."
        }
    }
}
```

#### 4. App: StoreKit configuration for local/simulator testing
**File**: `CheckStitch/CheckStitch.storekit`
**Action**: create

Create via Xcode (**File → New → File → StoreKit Configuration File**), add one
**Non-Consumable** product with product ID `app.alanvardy.CheckStitch.license`,
reference name/display name "CheckStitch License", a description, and a price, then
commit the generated file at this path. Creating it through Xcode guarantees the
schema; a hand-written JSON is the fallback if the file must be authored directly
(same product ID and `"type": "NonConsumable"`).

Then select it for the Run action (**Product → Scheme → Edit Scheme → Run →
Options → StoreKit Configuration**) and commit
`CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme`. Xcode writes
a `<StoreKitConfigurationFileReference identifier="…">` inside `<LaunchAction>`;
it does **not** affect the Test action, so the gate is unchanged.

#### 5. App: wire the paywall
**File**: `CheckStitch/PaywallView.swift`
**Action**: modify

Replace the placeholder Buy button with the real flow (Restore arrives in
Phase 3; failure/retry polish in Phase 4).

```swift
Button {
    Task { await purchases.purchase() }
} label: {
    Text(purchases.isPurchasing ? "Purchasing…" : "Buy")
        .frame(maxWidth: .infinity)
}
.buttonStyle(.borderedProminent)
.disabled(purchases.isPurchasing)
.accessibilityIdentifier("paywallBuyButton")
```

Show the storefront price above the button when the offer has loaded:

```swift
if let offer = purchases.offer {
    Text(offer.displayName).font(.headline)
    Text(offer.displayPrice).font(.subheadline)
}
```

Auto-dismiss on unlock, and load the offer when the sheet appears:

```swift
.task { await purchases.loadOffer() }
.onChange(of: purchases.isUnlocked) { _, unlocked in
    if unlocked { dismiss() }
}
if let error = purchases.lastError {
    Text(error).font(.footnote).foregroundStyle(.red)
}
```

#### 6. App: shared service construction + launch resolution
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

```swift
enum PurchaseEnvironment {
    static let service = PurchaseService(provider: StoreKitPurchaseService())
}
```

The `@State` wiring, `.environment(purchaseService)` and
`.task { await purchaseService.start() }` from Phase 1 are unchanged.

#### 7. App: `Purchasing…` string
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

```json
"Purchasing…" : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Wird gekauft…" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Purchasing…" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Comprando…" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Achat en cours…" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "購入中…" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "购买中…" } }
  }
}
```

Append `"Purchasing…"` to `LocalizationFixtures.requiredKeys` (`App`).

#### 8. Tests: purchase service + provider spy
**Files**: `CheckStitchTests/TestFixtures.swift`, `CheckStitchTests/PurchaseServiceTests.swift` (new)
**Action**: modify / create

Add to `TestFixtures.swift`:

```swift
@MainActor
final class SpyPurchaseProvider: PurchaseProviding {
    var offer: PurchaseOffer? = PurchaseOffer(id: "license", displayName: "CheckStitch License",
                                              displayPrice: "$4.99")
    var entitlement = false
    var purchaseResult = true
    var purchaseError: Error?
    private(set) var purchaseCount = 0
    private var onChange: (@MainActor (Bool) -> Void)?

    func offer() async -> PurchaseOffer? { offer }
    func currentEntitlement() async -> Bool { entitlement }
    func purchase() async throws -> Bool {
        purchaseCount += 1
        if let purchaseError { throw purchaseError }
        return purchaseResult
    }
    func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void) { self.onChange = onChange }
    func fireChange(_ unlocked: Bool) { onChange?(unlocked) }
}
```

`PurchaseServiceTests.swift` (new, `@MainActor`):
- `purchaseFlipsLockedToUnlocked` — `entitlement = false`; `await start()` ⇒
  `.locked`; `purchaseResult = true`; `await purchase()` ⇒ `.unlocked`,
  `lastError == nil`.
- `providerThrowLeavesLockedAndRecordsError` — `purchaseError = TestError.boom`.
- `observerCallbackUpdatesEntitlement` — `provider.fireChange(true)` ⇒ `.unlocked`.
- `offerLoadsFromTheProvider` — `await loadOffer()` ⇒ `offer?.displayPrice == "$4.99"`.

### Verification

#### Automated
- [x] `make test-unit` passes (`PurchaseServiceTests` green; existing suites unchanged)
- [x] `make build` passes (StoreKit links on iOS under warnings-as-errors)
- [x] `make build-mac` passes (StoreKit 2 API available on the macOS slice)
- [x] `make watch-build` passes (Core unchanged for watchOS)

#### Manual
- [ ] Set the scheme's StoreKit configuration, `make run`, drive the counter to
      the limit (20 runs or a temporary `freeRunLimit = 1`), tap **Buy**, confirm
      the local StoreKit purchase sheet, and verify the paywall dismisses **without
      relaunching** and the next run creates reminders.
- [ ] Confirm the price shown matches the `.storekit` configuration.
- [ ] Cancel the purchase sheet; verify the paywall stays and `lastError` copy is
      shown only for a thrown error (cancellation shows nothing).

---

## Phase 3: Restore + entitlement lifecycle (new device, offline, no paywall flash)

**Restore Purchases** re-unlocks a reinstall or a second device; entitlement is
resolved at launch before the gate is first evaluated (no paywall flash for a
paid user); a previously-verified offline user stays unlocked (fail-open), while
unknown-at-limit shows the paywall with a retry rather than unlocking.

### Changes

#### 1. Core: restore on the seam
**File**: `CheckStitchCore/Sources/CheckStitchCore/PurchaseProviding.swift`
**Action**: modify

```swift
public protocol PurchaseProviding: Sendable {
    func offer() async -> PurchaseOffer?
    func currentEntitlement() async -> Bool
    func purchase() async throws -> Bool
    /// `AppStore.sync()` then re-read entitlement. `true` means unlocked now.
    func restore() async throws -> Bool
    func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void)
}
```

#### 2. Core: verified-entitlement cache + fail-open
**File**: `CheckStitchCore/Sources/CheckStitchCore/PurchaseService.swift`
**Action**: modify

Add the cache struct (same file, so no extra Core file) and change `init` and the
state application.

```swift
/// Durable cache of a *verified* entitlement, so a paid user stays unlocked on a
/// cold launch while StoreKit is unreachable. Only ever written after a verified
/// transaction; never downgraded (fail-open).
public struct PurchaseEntitlementCache {
    public init(defaults: UserDefaults, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public static let defaultsKey = "purchase.verified.v1"

    public var isVerified: Bool { defaults.bool(forKey: key) }
    public func setVerified(_ verified: Bool) { defaults.set(verified, forKey: key) }

    private let defaults: UserDefaults
    private let key: String
}
```

```swift
public init(provider: any PurchaseProviding,
            cache: PurchaseEntitlementCache = PurchaseEntitlementCache(defaults: .standard)) {
    self.provider = provider
    self.cache = cache
    self.entitlement = cache.isVerified ? .unlocked : .unknown
}

public func restore() async {
    guard !isPurchasing else { return }
    isPurchasing = true
    lastError = nil
    defer { isPurchasing = false }
    do {
        apply(try await provider.restore())
    } catch {
        lastError = error.localizedDescription
    }
}

private func apply(_ verifiedUnlocked: Bool) {
    if verifiedUnlocked {
        cache.setVerified(true)
        entitlement = .unlocked
    } else if cache.isVerified {
        // Fail-open: never downgrade an already-verified unlock.
        entitlement = .unlocked
    } else {
        entitlement = .locked
    }
}
```

Route the other mutations through `apply`: `start()` calls
`apply(await provider.currentEntitlement())`; the observer callback calls
`apply(unlocked)`; `purchase()` calls `apply(true)` on success.

**Contract:** verified → unlocked (fail-open); unknown-at-limit → not unlocked, so
the gate shows the paywall, never a silent unlock.

#### 3. App: StoreKit restore
**File**: `CheckStitch/StoreKitPurchaseService.swift`
**Action**: modify

```swift
func restore() async throws -> Bool {
    try await AppStore.sync()
    return await currentEntitlement()
}
```

#### 4. App: cache in the shared service
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

```swift
enum PurchaseEnvironment {
    static let service = PurchaseService(
        provider: StoreKitPurchaseService(),
        cache: PurchaseEntitlementCache(defaults: AppGroup.defaults))
}
```

Launch ordering is already correct: the cache makes a paid user `.unlocked`
*synchronously at construction*, and `MyApp`'s
`.task { await purchaseService.start() }` refreshes before the user can run.

#### 5. App: Restore button + retry
**File**: `CheckStitch/PaywallView.swift`
**Action**: modify

```swift
Button("Restore Purchases") {
    Task { await purchases.restore() }
}
.disabled(purchases.isPurchasing)
.accessibilityIdentifier("paywallRestoreButton")

if purchases.offer == nil, !purchases.isLoadingOffer {
    Text("Couldn't load the store. Check your connection and try again.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    Button("Try Again") { Task { await purchases.loadOffer() } }
        .accessibilityIdentifier("paywallRetryButton")
}
```

#### 6. App: `Restore Purchases` string
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

```json
"Restore Purchases" : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Käufe wiederherstellen" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Restore Purchases" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Restaurar compras" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Restaurer les achats" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "購入を復元" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "恢复购买" } }
  }
}
```

Append `"Restore Purchases"` to `LocalizationFixtures.requiredKeys` (`App`).

#### 7. Tests
**Files**: `CheckStitchTests/TestFixtures.swift`, `CheckStitchTests/PurchaseServiceTests.swift`
**Action**: modify

Add to `SpyPurchaseProvider`:

```swift
var restoreResult = true
var restoreError: Error?
private(set) var restoreCount = 0

func restore() async throws -> Bool {
    restoreCount += 1
    if let restoreError { throw restoreError }
    return restoreResult
}
```

Add to `PurchaseServiceTests.swift` (all with a `PurchaseEntitlementCache` over
`makeIsolatedDefaults()`):
- `restoreUnlocks` — locked service, `restoreResult = true` ⇒ `.unlocked`.
- `restoreFailureStaysLocked` — `restoreError = TestError.boom` ⇒ `.locked`,
  `lastError != nil`, `restoreCount == 1`.
- `cachedVerifiedEntitlementStaysUnlockedOffline` — cache pre-set verified,
  provider `currentEntitlement() == false`; `await start()` ⇒ `.unlocked`.
- `unknownAtLimitReportsLocked` — fresh cache, provider false, no `start()`:
  `entitlement == .unknown` and `isUnlocked == false`.

### Verification

#### Automated
- [x] `make test-unit` passes (restore/fail-open/unknown semantics green)
- [x] `make build` and `make build-mac` pass
- [x] `make watch-build` passes

#### Manual
- [ ] On the simulator: buy, then delete the app, reinstall (`make run`), and
      confirm a run at the limit shows the paywall; tap **Restore Purchases** and
      confirm it unlocks.
- [ ] Airplane-mode cold launch after a prior purchase: the app stays unlocked
      (no paywall) and runs still succeed.
- [ ] First-ever launch with no purchase and StoreKit unreachable: at the limit,
      the paywall shows with the retry affordance (no silent unlock).

---

## Phase 4: Hardening & polish — every entry point, every state

Voice/shortcut and remote/sync refusals read clearly; the paywall handles
product-load failure, retry and pending; browsing/editing/exporting/syncing stay
usable while locked; accessibility labels and empty/error states covered.

### Changes

#### 1. App: spoken/shortcut copy finalised
**File**: `CheckStitch/Intents/RunChecklistIntent.swift`
**Action**: modify (verify)

The Phase 1 `.purchaseRequired` dialogue arm is the final wording. Confirm the
intent's prod path (gate = `ChecklistReminders.productionGate()`) is the only
route used in `init()` and add a test for the refusal dialogue (below).

#### 2. App: paywall polish
**File**: `CheckStitch/PaywallView.swift`
**Action**: modify

- Disable **Buy** and **Restore** while `purchases.isPurchasing` (already added).
- Distinguish loading from failure: while `isLoadingOffer`, show
  `ProgressView().controlSize(.small)`; the Phase 3 retry block only renders when
  the load finished and failed.
- Accessibility: `.accessibilityLabel("Buy CheckStitch License")` on the buy
  button; identifiers already set (`paywallView`, `paywallBuyButton`,
  `paywallRestoreButton`, `paywallDismissButton`, `paywallRetryButton`).
- Empty/error states: `Text(purchases.lastError ?? "")` only when non-nil.

```swift
if purchases.isLoadingOffer {
    ProgressView().controlSize(.small)
}
```

#### 3. App: locked browsing/editing unaffected
**File**: `CheckStitch/ContentView.swift`
**Action**: verify (no edit expected)

Confirm no gate was added to list/detail/edit/export/import/sync paths — only
`createRemindersButton` routes through the gated `runVM.createReminders`, and
`createChecklist()` (creating a checklist *object*) stays ungated. If a gate
appears anywhere else, remove it.

#### 4. Tests: sad paths across suites
**Files**: `CheckStitchTests/ChecklistRemindersTests.swift`, `CheckStitchTests/ChecklistRunViewModelTests.swift`, `CheckStitchTests/PurchaseServiceTests.swift`, `CheckStitchTests/RunChecklistIntentTests.swift`
**Action**: modify

- `ChecklistRemindersTests`: `.purchaseRequired` returns zero creates with zero
  `requestAccess` calls (already added); add an assertion that an unlocked gate at
  count 20 still counts.
- `ChecklistRunViewModelTests`: refusal presents the paywall, `runErrorMessage`
  stays nil, success still flashes (already added); add pending/locked
  (`isPurchasing`) does not double-fire — covered by the service's guard.
- `PurchaseServiceTests`: add `concurrentPurchaseIsIgnored` (call `purchase()`
  twice while the spy suspends; `purchaseCount == 1`) and
  `offerStaysNilOnFailure` (spy `offer = nil`; `loadOffer()` ⇒ `offer == nil`,
  `isLoadingOffer == false`).
- `RunChecklistIntentTests`: add
  `purchaseRequiredSpeaksTheLimitDialogue` asserting
  `RunChecklistDialogue.message(for: .purchaseRequired, checklistName: "Groceries").resolved()`
  equals the new catalog string, and that no reminders were created.

#### 5. App: retry/failure strings
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

```json
"Couldn't load the store. Check your connection and try again." : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Der Store konnte nicht geladen werden. Prüfe deine Verbindung und versuche es erneut." } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Couldn't load the store. Check your connection and try again." } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "No se pudo cargar la tienda. Comprueba tu conexión e inténtalo de nuevo." } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Impossible de charger la boutique. Vérifiez votre connexion et réessayez." } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "ストアを読み込めませんでした。接続を確認して、もう一度お試しください。" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "无法加载商店。请检查网络连接后重试。" } }
  }
},
"Try Again" : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Erneut versuchen" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Try Again" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Reintentar" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Réessayer" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "再試行" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "重试" } }
  }
}
```

Append both keys to `LocalizationFixtures.requiredKeys` (`App`).

### Verification

#### Automated
- [x] `./scripts/test.sh` prints `gate: ok` (build → test → build-mac → watch-build
      → shell tests → shellcheck)
- [x] `make test-unit` green, including all Phase 4 sad-path tests
- [x] `grep -rn "purchaseRequired" CheckStitch CheckStitchCore CheckStitchTests`
      shows every entry point (`Intent`, `Reminders`, `RunResultKind`, `VM`) handled

#### Manual
- [ ] Voice/shortcut (`RunChecklistIntent`) at the limit speaks the limit dialogue;
      no reminders are created.
- [ ] A remote run from the paired watch at the limit shows the refusal on the
      watch (the `.runResult(purchaseRequired)` ack), and the phone does not create
      reminders.
- [ ] While locked at the limit: browse, edit, duplicate, delete, export, import
      and sync checklists all still work.
- [ ] Paywall: with the store unreachable, the retry row shows; **Try Again**
      reloads; the buy button shows the price once loaded.
- [ ] Accessibility: VoiceOver reads the paywall title, price, buy, restore and
      dismiss controls.

---

## Test Checkpoints

- After Phase 1: `make test-unit` green — counter persists, 21st run refused with
  zero EventKit calls, `.failed`/`.partial` don't increment, all enum switch sites
  compile, catalog canary green.
- After Phase 2: `make test-unit` green — `SpyPurchaseProvider` purchase →
  unlocked; manual `make run` + local StoreKit config buy unlocks a run in place.
- After Phase 3: `make test-unit` green — restore/fail-open/unknown semantics;
  manual reinstall + offline checks pass.
- After Phase 4: `./scripts/test.sh` prints `gate: ok`; manual entry-point and
  locked-browsing checks pass.

---

## Deviations from `structure.md`

1. **`PurchaseOffer` / `offer()` / `loadOffer()` added to the seam.** Phase 2 of
   `structure.md` requires the paywall to show a price "from `Product`", but its
   `PurchaseProviding` list has no price source and Core must not import StoreKit.
   A small `PurchaseOffer` value type + `offer()` method bridges it.
2. **`PurchaseEnvironment` shared service lives in `MyApp.swift`.** The intent and
   the remote/sync path run outside the SwiftUI environment, so the one injected
   `PurchaseService` is exposed as an app-target global next to the assembly point
   rather than only as a `@State` in `MyApp`. `structure.md` lists `MyApp.swift`
   among Phase 1/2 files, so no new production file was invented.
3. **`ChecklistSyncCoordinator.swift` needs no edit.** It routes outcomes through
   `RunResultKind(outcome)`, so the new case passes through; it is listed in the
   plan as a verified no-op because `structure.md` names it.
4. **Test files added to Phase 1.** Adding `.purchaseRequired` to
   `ReminderRunOutcome`/`RunResultKind` breaks the exhaustive tables in
   `ChecklistSyncCoordinatorTests` and `WatchChecklistStoreTests`; they are updated
   in the same phase, per `structure.md`'s "every switch site must compile" note.
5. **Localization entries are part of each phase.** The repo's
   `LocalizationTests.catalogsHaveAllSixLanguages` /
   `nonEnglishValuesDifferFromEnglish` canaries run over every catalog key, so new
   user-facing strings ship with all six translations in the phase that introduces
   them (plus a `LocalizationFixtures.requiredKeys` append).

Next: run `!1` to implement.