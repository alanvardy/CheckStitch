# Implementation Plan

## Overview

Close the high-value unit-coverage gaps in the existing, deliberate DI design — pure
Core logic (`ChecklistSyncDiagnostics`) first, then the one in-view dispatcher and the
contract-critical app constants — and record everything that cannot be honestly unit-tested
in a `findings.md` artifact. No new protocols, no coverage tooling, no real EventKit/KVS
round-trips, no new user-facing strings. Verified by `make test-unit` per slice and the
authoritative `bash ./scripts/test.sh` (`gate: ok`) at the end.

---

## Reconnaissance results (Phase 0 gate, no code)

The structure's pre-Phase-1 gate is satisfied. Verified by `rg`/`ls` over `CheckStitchTests/`
plus SDK interface inspection (evidence in parentheses). **These results shrink Phases 4 and 5
relative to `structure.md` — see "Deviations" at the end.**

| Target | Existing coverage | Verdict |
|---|---|---|
| `ChecklistSyncDiagnostics` | no file references it in `CheckStitchTests/` | **new suite** |
| `SyncGate` raw values | only consumed indirectly via fakes | **new suite** |
| `SettingsDataActionRoute` / `ContentView.perform` | no suite; `SettingsDataAction` only used by `SettingsViewModelTests` | **new suite** |
| `AppGroup` | `rg AppGroup CheckStitchTests/` → none | **new suite** |
| `Color.systemBackground` | `rg systemBackground CheckStitchTests/` → none | **new suite** |
| `ChecklistExportDocument` | `ChecklistExportTests.swift:104 testFileWrapperCarriesEncodedBytes` (XCTest) already covers `init(checklists:)` + `data` semantics. `readableContentTypes` and the config inits are uncovered. | **1 new test only** |
| `init(configuration:)` / `fileWrapper(configuration:)` | SDK: `FileDocumentReadConfiguration` / `FileDocumentWriteConfiguration` expose only `public let` fields, **no public initializer** (`SwiftUI.swiftinterface:7460-7472, 7479-7486`) | **untestable → finding** |
| `AppearanceViewModel` | no suite; type is stateless, forwards to `MacAppDelegate`/`AppDelegate` statics. Persistence it fronts is already covered by `AppearanceModePreferenceTests` / `OrientationPreferenceTests`. | **finding, no suite** |
| `ChecklistSyncing` / `UbiquitousChecklistSync` | `UbiquitousChecklistSyncTests` covers construction + cancel-idempotence; the seam is exercised via `InMemoryChecklistSync`/`FakeChecklistSyncTransport` in `ChecklistSyncServiceTests` | **fixture-contract guard only** |
| `AppEnvironment` | no test; `rg AppEnvironment CheckStitchCore CheckStitch` → definition only, **no production construction site**, no default `reminderCreator` | **1 contract test + finding** |
| `ViewRenderTests` / `SmokeTests` reach | `rg 'AppGroup\|systemBackground\|ChecklistExportDocument\|AppearanceViewModel' CheckStitchTests/` → no hits | confirms the gaps above |

Duplicate-fake check: no new fake is needed; `SpyReminderCreator`, `InMemoryChecklistSync`,
`makeIsolatedDefaults`, `makeItem` already exist in `TestFixtures.swift`.

New files under `CheckStitchTests/` need **no** `project.pbxproj` edit —
`PBXFileSystemSynchronizedRootGroup` picks them up automatically.

---

## Phase 1: Walking skeleton — `ChecklistSyncDiagnostics` is testable and tested

### Changes

#### 1. Extract a pure formatter and rotation predicate
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncDiagnostics.swift`
**Action**: modify

Replace the field-formatting inside `log` with an internal pure `record`,
and the size comparison inside `appendToDisk` with an internal pure
`shouldResetFile`. `log`'s public signature is unchanged; `SyncGate` is
unchanged (already `CaseIterable`).

```swift
public static func log(_ gate: SyncGate, _ fields: [String: String] = [:]) {
    let line = record(gate, fields)
    logger.notice("\(line, privacy: .public)")
    appendToDisk(line)
}

/// Single-line record shared by the logger and the disk copy: keys sort
/// alphabetically so a field's position is stable across records, and a
/// fieldless record has no trailing space. Internal so tests can pin the
/// on-device wire shape.
static func record(_ gate: SyncGate, _ fields: [String: String] = [:]) -> String {
    let detail = fields
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " ")
    return detail.isEmpty ? "[\(gate.rawValue)]" : "[\(gate.rawValue)] \(detail)"
}

/// Whether `checklist-sync.log` has reached the size that resets it. Pure so
/// the rotation boundary is testable without touching the file system.
static func shouldResetFile(currentSize: UInt64) -> Bool {
    currentSize >= diskSizeLimit
}
```

In `appendToDisk`, replace the inline comparison:

```swift
let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
if shouldResetFile(currentSize: size) {
    try? fm.removeItem(at: url)
}
```

`record`/`shouldResetFile` are `internal`; `@testable import CheckStitchCore`
reaches them. `diskSizeLimit` stays `private` (same enclosing enum).

#### 2. New suite
**File**: `CheckStitchTests/ChecklistSyncDiagnosticsTests.swift`
**Action**: create

```swift
@testable import CheckStitchCore
import Foundation
import Testing

struct ChecklistSyncDiagnosticsTests {
    @Test(arguments: [
        (SyncGate.watchSend, "watchSend"),
        (SyncGate.watchReceive, "watchReceive"),
        (SyncGate.watchActivation, "watchActivation"),
        (SyncGate.phoneReceive, "phoneReceive"),
        (SyncGate.phoneSend, "phoneSend"),
        (SyncGate.phoneHandle, "phoneHandle"),
        (SyncGate.snapshotLookup, "snapshotLookup"),
        (SyncGate.createOutcome, "createOutcome"),
    ])
    func gateRawValueMatchesWireContract(_ gate: SyncGate, _ raw: String) {
        #expect(gate.rawValue == raw)
    }

    @Test
    func gateCasesAreUniqueAndComplete() {
        #expect(SyncGate.allCases.count == 8)
        #expect(Set(SyncGate.allCases.map(\.rawValue)).count == 8)
    }

    @Test
    func recordFormatsGateWithNoFields() {
        #expect(ChecklistSyncDiagnostics.record(.watchSend) == "[watchSend]")
    }

    @Test
    func recordSortsFieldsByKey() {
        let line = ChecklistSyncDiagnostics.record(.createOutcome, ["count": "2", "alpha": "1"])
        #expect(line == "[createOutcome] alpha=1 count=2")
    }

    @Test
    func recordJoinsFieldsWithSingleSpace() {
        let line = ChecklistSyncDiagnostics.record(.phoneSend, ["a": "1", "b": "2", "c": "3"])
        #expect(line == "[phoneSend] a=1 b=2 c=3")
    }

    @Test
    func shouldResetFileResetsAtAndAboveLimit() {
        let limit: UInt64 = 64 * 1024
        #expect(ChecklistSyncDiagnostics.shouldResetFile(currentSize: limit))
        #expect(ChecklistSyncDiagnostics.shouldResetFile(currentSize: limit + 1))
    }

    @Test
    func shouldResetFileKeepsFileBelowLimit() {
        #expect(!ChecklistSyncDiagnostics.shouldResetFile(currentSize: 0))
        #expect(!ChecklistSyncDiagnostics.shouldResetFile(currentSize: 64 * 1024 - 1))
    }
}
```

### Verification

#### Automated
- [x] Narrow (mirrors the `test-unit` recipe): `xcodebuild -scheme CheckStitch -destination 'platform=macOS' -configuration Debug -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES -only-testing:CheckStitchTests/ChecklistSyncDiagnosticsTests test`
- [x] `make test-unit` passes (whole `CheckStitchTests` target)
- [x] `rg 'privacy: .public' CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncDiagnostics.swift` still shows the two public-privacy interpolations (now one)

#### Manual
- [ ] `make build` succeeds; no compiler warning (gate is warnings-as-errors)
- [ ] On-device records are unchanged: after a run, `devicectl`/Console still shows `[<gate>] k=v` lines (no behavioural change to `log`)

---

## Phase 2: Risk — `ContentView`'s settings-action routing becomes a tested unit

### Changes

#### 1. Add the route type beside `SettingsDataAction`
**File**: `CheckStitch/SettingsBindings.swift`
**Action**: modify

Add immediately after the `SettingsDataAction` enum (line ~33):

```swift
/// The panel a staged `SettingsDataAction` opens. Kept beside the action so the
/// root dispatcher's switch is exhaustive by construction (a new action case
/// fails to compile until it is routed).
enum SettingsDataActionRoute: Equatable {
    case export
    case importChecklists

    init(_ action: SettingsDataAction) {
        switch action {
        case .export: self = .export
        case .importChecklists: self = .importChecklists
        }
    }
}
```

#### 2. Dispatch through the route
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

`perform(_:)` (line ~594) — no other view change:

```swift
private func perform(_ action: SettingsDataAction) {
    switch SettingsDataActionRoute(action) {
    case .export: importExportVM.beginExport()
    case .importChecklists: importExportVM.beginImport()
    }
}
```

#### 3. New suite
**File**: `CheckStitchTests/ContentViewSettingsActionTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct ContentViewSettingsActionTests {
    @Test
    func routeMapsExport() {
        #expect(SettingsDataActionRoute(.export) == .export)
    }

    @Test
    func routeMapsImportChecklists() {
        #expect(SettingsDataActionRoute(.importChecklists) == .importChecklists)
    }

    @Test
    func stagedActionSurvivesTakeAndRoutes() throws {
        let viewModel = SettingsViewModel()
        viewModel.stage(.importChecklists)
        let taken = try #require(viewModel.takeStaged())
        #expect(SettingsDataActionRoute(taken) == .importChecklists)
        // Sad path: the queue hands the action over exactly once.
        #expect(viewModel.takeStaged() == nil)
    }

    /// Recon gap: `ChecklistListViewModelTests` has up/down reorders but no
    /// first/last boundary cases. `ChecklistStore.moved` returns `nil` out of
    /// range, so these must be no-ops.
    @Test
    func moveChecklistFirstUpIsANoOp() {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let viewModel = ChecklistListViewModel(store: store)
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.moveChecklist(id: first, up: true)
        #expect(viewModel.checklists.map(\.id) == [first, second])
    }

    @Test
    func moveChecklistLastDownIsANoOp() {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let viewModel = ChecklistListViewModel(store: store)
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.moveChecklist(id: second, up: false)
        #expect(viewModel.checklists.map(\.id) == [first, second])
    }
}
```

### Verification

#### Automated
- [x] `make test-unit` passes; `ContentViewSettingsActionTests` cases appear and pass
- [x] `make build` passes (proves `ContentView.perform` still compiles against the concrete VM)
- [x] `rg -n 'SettingsDataActionRoute' CheckStitch CheckStitchTests` shows exactly the definition, the one `perform` use, and the suite

#### Manual
- [ ] `make run`, open Settings → Export: the export multi-select presents; Settings → Import: the file importer presents (behaviour-preserving refactor)
- [ ] Reordering with the move arrows still moves first/last without change

---

## Phase 3: Contract constants — `AppGroup` + `Color+CrossPlatform`

### Changes

No source changes. Tests only. The `AppGroup.defaults` `?? .standard` fallback branch is
expected to be unforceable in the signed test host; recorded in `findings.md` (Phase 6),
**not** refactored (design Open Risk 2).

#### 1. `AppGroup` contract suite
**File**: `CheckStitchTests/AppGroupTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import Foundation
import Testing

struct AppGroupTests {
    @Test
    func suiteNameMatchesAppGroupEntitlementLiteral() {
        // Must stay byte-identical to `CheckStitch/AppGroup.entitlements` and
        // the watch app's shared container; a rename silently breaks the share.
        #expect(AppGroup.suiteName == "group.app.alanvardy.CheckStitch")
    }

    @Test
    func defaultsRoundTripsAProbeValue() {
        let defaults = AppGroup.defaults
        let key = "test.appGroup.probe.\(UUID().uuidString)"
        defer { defaults.removeObject(forKey: key) }
        defaults.set("probe", forKey: key)
        #expect(defaults.string(forKey: key) == "probe")
    }

    @Test
    func defaultsIsUsableWhenSuiteUnavailable() {
        // The `?? .standard` fallback cannot be forced from a test; this pins
        // that `defaults` is always a usable store and the probe is cleaned up.
        let defaults = AppGroup.defaults
        let key = "test.appGroup.probe.\(UUID().uuidString)"
        defer { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: key)
        #expect(defaults.bool(forKey: key))
        defaults.removeObject(forKey: key)
        #expect(defaults.object(forKey: key) == nil)
    }
}
```

#### 2. Cross-platform background mapping suite
**File**: `CheckStitchTests/ColorCrossPlatformTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import AppKit
import SwiftUI
import Testing

struct ColorCrossPlatformTests {
    @Test
    func systemBackgroundMatchesPlatformSystemColor() {
        // Resolve both sides through `NSColor` so the assert is on the rendered
        // colour, not on `Color`'s opaque provider identity.
        let actual = NSColor(Color.systemBackground).usingColorSpace(.sRGB)
        let expected = NSColor(Color(nsColor: .windowBackgroundColor)).usingColorSpace(.sRGB)
        #expect(actual == expected)
    }
}
```

### Verification

#### Automated
- [x] `make test-unit` passes; `AppGroupTests` + `ColorCrossPlatformTests` green
- [x] `rg -n 'test.appGroup.probe' CheckStitchTests/AppGroupTests.swift` shows both writes have a `defer { removeObject }` (no shared-defaults leak)
- [x] `make build-mac` passes (the macOS branch of `Color.systemBackground` is what the suite asserts)

#### Manual
- [ ] `make run`: app launches, list background renders as before; no crash from the App Group `UserDefaults`

---

## Phase 4: Export document contract (reduced per recon)

### Changes

No source changes. `init(checklists:)` + `data` are already covered by
`ChecklistExportTests.testFileWrapperCarriesEncodedBytes`; `init(configuration:)` and
`fileWrapper(configuration:)` are untestable (no public config init — see Phase 0). Only the
content-type contract is a real gap.

#### 1. Content-type contract suite
**File**: `CheckStitchTests/ChecklistExportDocumentTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import Testing
import UniformTypeIdentifiers

struct ChecklistExportDocumentTests {
    @Test
    func readableContentTypesIsJSONOnly() {
        // The export panel derives the `.json` extension from this; widening it
        // would silently change what the share sheet/import accept.
        #expect(ChecklistExportDocument.readableContentTypes == [.json])
    }
}
```

> Note: `ChecklistExportTests` is XCTest, so this is the Swift Testing home for the
> document type; do **not** duplicate its encoder assertions here.

### Verification

#### Automated
- [x] `make test-unit` passes; `ChecklistExportDocumentTests` green
- [x] `rg -n 'ChecklistExportDocument' CheckStitchTests/` shows the new suite plus the existing `ChecklistExportTests` (no contradictory assertions)

#### Manual
- [ ] `make run`, export a checklist to Files: the produced file is a `.json` document that re-imports (unchanged behaviour)

---

## Phase 5: Sync/environment definition contracts (reduced per recon)

### Changes

No source changes. `UbiquitousChecklistSync` is already covered by
`UbiquitousChecklistSyncTests` (construction + cancel-idempotence) and the seam is exercised
through `InMemoryChecklistSync` in `ChecklistSyncServiceTests`; a real KVS read/write round-trip
is entitlement/iCloud-dependent and is not added (design Decision 6 spirit). `AppEnvironment`
has no production construction site and no default `reminderCreator`.

#### 1. Shared fake contract guard
**File**: `CheckStitchTests/ChecklistSyncingContractTests.swift`
**Action**: create

Pins the contract of the shared `InMemoryChecklistSync` fixture (a buggy fake silently weakens
every suite that uses it); production transport behaviour stays a finding.

```swift
@testable import CheckStitchCore
@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct ChecklistSyncingContractTests {
    @Test
    func writeThenReadRoundTrips() throws {
        let sync = InMemoryChecklistSync()
        let payload = Data("payload".utf8)
        try sync.write(payload)
        #expect(try sync.read() == payload)
    }

    @Test
    func readReturnsNilWhenEmpty() throws {
        #expect(try InMemoryChecklistSync().read() == nil)
    }

    @Test
    func cancelObservationIsIdempotent() {
        let token = InMemoryChecklistSync().startObserving {}
        token.cancel()
        token.cancel()
    }
}
```

#### 2. `AppEnvironment` container contract
**File**: `CheckStitchTests/AppEnvironmentTests.swift`
**Action**: create

```swift
@testable import CheckStitchCore
import Testing

@MainActor
struct AppEnvironmentTests {
    @Test
    func environmentIsUsableWithInjectedSeams() {
        let environment = AppEnvironment(reminderCreator: SpyReminderCreator())
        #expect(environment.reminderCreator is SpyReminderCreator)
    }
}
```

> `defaultEnvironmentProvidesReminderCreator` from `structure.md` is **not written**:
> `AppEnvironment(reminderCreator:)` has no default and no production construction site
> exists — recorded in `findings.md` instead.

### Verification

#### Automated
- [x] `make test-unit` passes; `ChecklistSyncingContractTests` + `AppEnvironmentTests` green
- [x] `make watch-build` passes (Core is compiled for watchOS; no new Core surface added)

#### Manual
- [ ] None required — no production code path changed in this phase

---

## Phase 6: Hardening, findings, full gate

### Changes

#### 1. Write the findings artifact
**File**: `.pi/orksorksorks/alanvardy-var-1076-test-suite-audit/findings.md`
**Action**: create (committed here with the other step artifacts)

Each entry: **severity** (high/medium/low) + **evidence** (file:line or command). Required entries:

| # | Finding | Severity |
|---|---|---|
| 1 | `PhoneSyncAdapter` / `StoreKitPurchaseService` untested: real iCloud/StoreKit transports, not headlessly drivable; the `ChecklistSyncing`/`PurchaseProviding` seams carry their behaviour | medium |
| 2 | `AppGroup.defaults` `?? .standard` fallback is unforceable in the signed macOS test host; only reachability pinned, not the branch | low |
| 3 | `ChecklistSyncDiagnostics.appendToDisk` (Documents write, lock, reset-on-disk) has no headless test — only `record`/`shouldResetFile` are covered | low |
| 4 | `ChecklistExportDocument.init(configuration:)` / `fileWrapper(configuration:)` cannot be unit-tested: `FileDocumentReadConfiguration`/`FileDocumentWriteConfiguration` have no public initializer (SwiftUI interface) | medium |
| 5 | `AppEnvironment` has no production construction site and no default `reminderCreator`; likely dead/unwired code | medium |
| 6 | `ChecklistSyncing` has no direct behavioural test of a production conformer: `UbiquitousChecklistSync` is a construction/cancel canary only, and `NSUbiquitousKeyValueStore` cannot be substituted with a fake (no public init) | medium |
| 7 | `AppearanceViewModel` is stateless delegate forwarding (no preference store); its `MacAppDelegate`/`AppDelegate` effects (`NSApp.windows` / `UIWindow`) are not assertable in a unit test without a new seam. Preference persistence is already covered by `AppearanceModePreferenceTests`/`OrientationPreferenceTests` | low |
| 8 | `ContentView.perform(_:)`'s two dispatch lines (`beginExport`/`beginImport`) remain untested; only the route mapping and the VM entry points are covered | low |
| 9 | `Color.systemBackground`'s iOS/watchOS branch is not compiled in the macOS-hosted suite; only the macOS branch is asserted | low |
| 10 | Duplicate fakes: none found — `TestFixtures.swift` already covers every fake needed (record the negative result) | — |

#### 2. Isolation pass
**File**: any suite touched above
**Action**: verify
- No suite writes a shared-domain key without removal (`test.appGroup.probe.*` has `defer` removal).
- No suite touches real `UserDefaults.standard`, real KVS, EventKit, or a simulator.
- New suites reuse `makeIsolatedDefaults()` where a store is built.

### Verification

#### Automated
- [x] `make test-unit` passes (all suites, no shared-state leak between them)
- [x] `bash scripts/tests/run.sh` passes (shell regressions; also run by the gate)
- [x] `bash ./scripts/test.sh` prints `gate: ok` (sim build → test → build-mac → watch-build → shell tests → shellcheck; warnings-as-errors on every Swift leg)
- [x] `git status` shows `findings.md` plus only the intended source/test files (no stray `.bak`/derived data)

#### Manual
- [ ] Open `findings.md`: every entry has severity + evidence, and no entry describes a fix that was silently applied
- [ ] `make test-unit` runtime is not materially longer than before (suites are pure; no I/O)

---

## Deviations from `structure.md`

1. **Phase 4 reduced to one test.** `ChecklistExportDocument`'s encoder paths are already
   asserted by `ChecklistExportTests.testFileWrapperCarriesEncodedBytes`, and the read/write
   configuration types have no public initializer, so `initFromConfiguration*` /
   `fileWrapperCarriesDocumentBytes` are unwritable. Per the structure's reconnaissance
   gate, the slice shrinks to `readableContentTypesIsJSONOnly` and a finding.
2. **Phase 4's `AppearanceViewModelTests` not written.** The VM is stateless delegate
   forwarding; there is no preference store to assert against and the existing preference
   suites already cover persistence. Recorded as finding #7 rather than a vacuous suite.
3. **Phase 5 reduced.** `UbiquitousChecklistSyncTests` already covers construction and
   cancel-idempotence; a real KVS round-trip is not headlessly safe. The suite keeps only a
   fixture-contract guard (the fake is shared infrastructure). `defaultEnvironmentProvidesReminderCreator`
   is impossible (no default initializer) and is replaced by `environmentIsUsableWithInjectedSeams`
   + finding #5.
4. **Phase 2 adds the recon-flagged move-boundary cases** to `ContentViewSettingsActionTests`
   (structure explicitly conditioned these on the recon gap, which is real:
   `ChecklistListViewModelTests` has no first/last cases).
5. **Everything else follows `structure.md` phase-for-phase.** Phases 1–3 are unchanged from
   the outline.