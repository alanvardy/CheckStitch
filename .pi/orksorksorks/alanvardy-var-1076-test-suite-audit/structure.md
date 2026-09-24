# Structure Outline

## Approach

Test-addition first, refactor only where a genuinely high-value test is otherwise
unwritable (design Decision 1). Each slice takes one untested symbol from its source
layer through a real behaviour-asserting suite to a green `make test-unit`, ordered
by design's coverage priorities (Decision 2) with the two licensed extractions
(`ChecklistSyncDiagnostics` formatting, `ContentView` dispatch) front-loaded as the
only integration risk. No new protocols, no coverage tooling, no real EventKit/StoreKit
round-trips, no new user-facing strings. Each slice's tests are green before the next
starts; anything unfixable in scope is recorded in `findings.md` (Phase 6), not silently
worked around.

**Before Phase 1 (reconnaissance gate, no code):** for each target below, confirm no
existing suite already reaches it — grep `CheckStitchTests/` for the type name and
read the suite headers; check `ViewRenderTests`/`SmokeTests` for `ContentView`/
`ChecklistExportDocument`/`AppearanceViewModel` reach. Record the result; if a target is
already covered, the slice shrinks to a gap claim in `findings.md` instead of a new suite
(design Open Risk 1).

---

## Phase 1: Walking skeleton — `ChecklistSyncDiagnostics` is testable and tested

The thinnest real path: one untested Core symbol → a real pure seam → a real suite green
in `make test-unit`. Its green tests prove the diagnostics record format (the
cross-device debugging contract, currently a zero-test black box) and the log-file
rotation boundary.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncDiagnostics.swift`,
`CheckStitchTests/ChecklistSyncDiagnosticsTests.swift` (new)

**Key changes**:
- `ChecklistSyncDiagnostics.record(_ gate: SyncGate, _ fields: [String: String]) -> String` — new internal pure formatter (`"[gate] k=v …"`, keys sorted); `log(_:_:)` keeps its signature and now calls `record` before `logger.notice`/`appendToDisk`.
- `ChecklistSyncDiagnostics.shouldResetFile(currentSize: UInt64) -> Bool` — new internal pure predicate for the `>= diskSizeLimit` rule; `appendToDisk` calls it.
- `SyncGate` unchanged (already `CaseIterable`).

**Contract**: `record`/`shouldResetFile` are internal SPI the suite consumes; `SyncGate`'s
eight raw values are the frozen on-device wire contract (`[watchSend]`…`[createOutcome]`).

**Tests**: `ChecklistSyncDiagnosticsTests` — `gateRawValueMatchesWireContract` (`@Test(arguments:)`), `gateCasesAreUniqueAndComplete`, `recordFormatsGateWithNoFields` (no trailing space), `recordSortsFieldsByKey` (unsorted input), `recordJoinsFieldsWithSingleSpace`, `shouldResetFileResetsAtAndAboveLimit`, `shouldResetFileKeepsFileBelowLimit` (sad + boundary)
**Verify**: `make test-unit` passes for this slice; optional narrow run
`xcodebuild … -only-testing:CheckStitchTests/ChecklistSyncDiagnosticsTests test`

---

## Phase 2: Risk — `ContentView`'s settings-action routing becomes a tested unit

Choosing Import or Export in Settings routes deterministically to the right
import/export panel — the one piece of in-view logic gets a behavioural test without
reading `body`.

**Files**: `CheckStitch/ContentView.swift`, `CheckStitch/SettingsBindings.swift` (route type beside `SettingsDataAction`), `CheckStitchTests/ContentViewSettingsActionTests.swift` (new)

**Key changes**:
- `enum SettingsDataActionRoute: Equatable { case export, importChecklists; init(_ action: SettingsDataAction) }` — new pure mapping.
- `ContentView.perform(_:)` switches on `SettingsDataActionRoute(action)`; no other view change.
- `ChecklistListViewModel.moveChecklist(id:up:)` untouched — the move-arrow controls are a pass-through; add first/last boundary cases here **only if** `ChecklistListViewModelTests` lacks them (recon result).

**Contract**: mapping is the seam the next slices/tests rely on; the view holds no
decision beyond dispatch, and the switch stays exhaustive (compile-time sad path).

**Tests**: `ContentViewSettingsActionTests` — `routeMapsExport`, `routeMapsImportChecklists`, `stagedActionSurvivesTakeAndRoutes` (through `SettingsViewModel.stage`/`takeStaged`); plus move-boundary cases if the recon gap is real
**Verify**: `make test-unit`

---

## Phase 3: Contract constants — `AppGroup` + `Color+CrossPlatform`

The App Group id and the cross-platform background mapping are pinned, so a rename can't
silently break the phone↔watch share or the shared plate look.

**Files**: `CheckStitch/AppGroup.swift`, `CheckStitch/Color+CrossPlatform.swift`, `CheckStitchTests/AppGroupTests.swift` (new), `CheckStitchTests/ColorCrossPlatformTests.swift` (new)

**Key changes**: none required — tests only. The `?? .standard` fallback branch is
expected to be unreachable on the macOS host; if so it is recorded as a finding, **not**
refactored (design Open Risk 2).

**Contract**: `AppGroup.suiteName` literal and `Color.systemBackground`'s per-platform
resolution are frozen; consumers (watch share, shared plates) may rely on them.

**Tests**: `AppGroupTests` — `suiteNameMatchesAppGroupEntitlementLiteral`, `defaultsRoundTripsAProbeValue` (write/read then remove a test-only key), `defaultsIsUsableWhenSuiteUnavailable` (no crash); `ColorCrossPlatformTests` — `systemBackgroundMatchesPlatformSystemColor` (macOS `Color(nsColor: .windowBackgroundColor)`, iOS `Color(uiColor: .systemBackground)`)
**Verify**: `make test-unit`; sad path asserts the probe key is cleaned up

---

## Phase 4: Export document + appearance write-through formalized

Export produces a JSON file document that reads back, and appearance/landscape changes
reach their preference stores — coverage confirmed rather than assumed.

**Files**: `CheckStitch/ChecklistExportDocument.swift`, `CheckStitch/AppearanceViewModel.swift`, `CheckStitchTests/ChecklistExportDocumentTests.swift` (new), `CheckStitchTests/AppearanceViewModelTests.swift` (new)

**Key changes**: none expected; add only the suites the recon pass shows are missing.

**Contract**: `ChecklistExportDocument.init(checklists:)` encodes through
`ChecklistExport.data`; `init(configuration:)` throws `CocoaError(.fileReadCorruptFile)`
on a missing payload; `resolvedReadableContentTypes == [.json]`.

**Tests**: `ChecklistExportDocumentTests` — `readableContentTypesIsJSONOnly`, `initEncodesChecklistsToEnvelopeBytes`, `fileWrapperCarriesDocumentBytes`, `initFromConfigurationRoundTripsBytes`, `initFromConfigurationThrowsOnEmptyFile` (sad); `AppearanceViewModelTests` — `appearanceModeChangePersistsPreference`, `allowsLandscapeChangePersistsPreference` (against isolated defaults/preference injection)
**Verify**: `make test-unit`

---

## Phase 5: Sync/environment definition contracts

The `ChecklistSyncing` seam and `AppEnvironment` wiring are exercised directly, not only
via `TestFixtures`.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift`, `CheckStitchCore/Sources/CheckStitchCore/Environment.swift`, `CheckStitchTests/ChecklistSyncingContractTests.swift` (new), `CheckStitchTests/AppEnvironmentTests.swift` (new)

**Key changes**: none. If `UbiquitousChecklistSync` cannot take an injected
`NSUbiquitousKeyValueStore`, the round-trip case is dropped and the coupling is recorded
as a finding — do not widen the seam beyond design Decision 1.

**Contract**: `ChecklistSyncing` (`read`/`write`/`synchronize`/`startObserving`) is the
transport contract the coordinator and fakes already satisfy; `AppEnvironment.reminderCreator`
is non-nil by default.

**Tests**: `ChecklistSyncingContractTests` — `writeThenReadRoundTrips`, `readReturnsNilWhenEmpty` (sad), `cancelObservationIsIdempotent` (sad); `AppEnvironmentTests` — `defaultEnvironmentProvidesReminderCreator`, `environmentIsUsableWithInjectedSeams`
**Verify**: `make test-unit`

---

## Phase 6: Hardening, findings, full gate

Accumulated findings are recorded with severity and evidence, the whole tree passes the
authoritative gate, and no suite leaves state behind.

**Files**: `.pi/orksorksorks/alanvardy-var-1076-test-suite-audit/findings.md` (artifact), `CheckStitchTests/TestFixtures.swift` (only if a new fake is genuinely shared), any suite touched for isolation/flakiness

**Key changes**: `findings.md` entries with severity + evidence — `PhoneSyncAdapter`/`StoreKitPurchaseService` untested and why (env-dependent), `AppGroup.defaults` fallback branch reachability, `ChecklistSyncDiagnostics` disk append not headlessly assertable, any duplicate fake found, `ContentView` slot-assertion stability; a final isolation pass (no shared defaults/KVS/sim state leaks between suites).

**Contract**: none new — this slice consumes everything above.

**Tests**: no new suites required; `HarnessTests` stays green; re-run all suites.
**Verify**: `make test-unit`, then the authoritative `bash ./scripts/test.sh` prints `gate: ok` (warnings-as-errors on every Swift leg)

---

## Testing Checkpoints

- **After Phase 1**: `ChecklistSyncDiagnosticsTests` green → the pure formatter/rotation contract is frozen; safe to proceed.
- **After Phase 2**: `ContentViewSettingsActionTests` green and `perform(_:)` now switches on the route type → the in-view risk is retired.
- **After Phase 3**: `AppGroupTests` + `ColorCrossPlatformTests` green → constants pinned; any `?? .standard` finding filed for Phase 6.
- **After Phase 4**: export-document (incl. corrupt-file sad path) and appearance write-through suites green → indirect-coverage claims are now asserted.
- **After Phase 5**: syncing/environment contract suites green (or the coupling finding filed) → all Core gaps addressed.
- **Before believing "done"**: `make test-unit` green after every slice; Phase 6 not closed until `bash ./scripts/test.sh` prints `gate: ok`.