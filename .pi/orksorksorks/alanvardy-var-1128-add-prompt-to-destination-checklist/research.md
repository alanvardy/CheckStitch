# Research Findings

## Q1: How is a checklist's destination represented, persisted, decoded/encoded, and migrated in `Checklist` and its export format, and what happens when the field is absent or unknown in stored or imported data?

### Findings
- Destination is `Checklist.destinationListIdentifier: String?` — `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:212`; doc (`:210-211`) says it holds the `EKCalendar.calendarIdentifier` and `nil` means the system default list. Memberwise init param defaulted `nil` at `:175`, assigned `:188`.
- `CodingKeys` includes `.destinationListIdentifier` (`Checklist.swift:259`).
- Decode is absent-key tolerant: `container.decodeIfPresent(String.self, forKey: .destinationListIdentifier)` (`Checklist.swift:268`), then passed through the self-healing rebuild at `:298`. An absent key (legacy v1–v4 payload) decodes to `nil` and never throws.
- Encode is unconditional: `encode(destinationListIdentifier, forKey:)` (`Checklist.swift:314`) — `nil` round-trips as JSON `null`.
- The field rides the checklist's coarse clock (`revision`/`modifiedAt`, `Checklist.swift:168-170,209-215`) and is an additive-optional field, so it needs no version bump and has no migration path: `ChecklistCodec.currentVersion = 5` (`:564`), `classify` only distinguishes `.loaded`, `.migratable(from: 1-4)`, `.unsupportedVersion`, `.unreadable` (`:595-618`); `decode` returns `[]` for unsupported/unreadable (`:618-625`).
- Export/import is envelope-based: `ChecklistExport.envelope(checklists:from:)` builds `ChecklistEnvelope(version: currentVersion, deviceID: "", checklists:)` (`ChecklistExport.swift:14-18`); `data(...)` = `ChecklistCodec.encode` (`:22-24`). Destination rides inside each `Checklist` verbatim; no export-specific handling.
- Store write: `ChecklistStore.setDestination(_:for:)` sets `checklists[index].destinationListIdentifier`, bumps `revision += 1` and `modifiedAt`, `scheduleSave()`, returns `SetDestinationOutcome.updated/.notFound` (`ChecklistStore.swift:346-355`).
- `duplicate(id:name:)` (`ChecklistStore.swift:262`) and `freshCopy(of:folderID:)` (`:281`) carry the source destination; `importInsert` (`:292-298`) and `importReplace` (`:302-313`) rebuild only via `freshCopy`, so imports preserve it.
- Unknown/foreign identifier: preserved as an opaque string, not validated at decode; the `freshCopy` doc (`ChecklistStore.swift:269-273`) intentionally keeps a stale id and defers failure to the run path's `.destinationMissing`.

## Q2: How does the destination-holding field flow through the sync and store layer (`ChecklistStore`, sync coordinator/merge), including last-write-wins conflict handling and cross-device reconciliation?

### Findings
- Local persistence: `save()` encodes the whole `ChecklistEnvelope` to App Group `UserDefaults` key `"checklists.v1"` and, unless `isApplyingRemote`, fires `onChange?()` (`ChecklistStore.swift:799-815`). A stable per-install `deviceID` is stamped into every envelope (`:49`, `:63-68`, envelope `:120`).
- Push to iCloud: `ChecklistSyncService.start()` wires `store.onChange` → `schedulePush()` (500 ms debounce) (`CheckStitch/ChecklistSyncService.swift:44-54`, `:85-99`); `pushNow` (scene background) calls `reconcileNow()` which writes via `UbiquitousChecklistSync.write = NSUbiquitousKeyValueStore.set(data, forKey: "checklists.v1")` (`CheckStitchCore/.../ChecklistSyncing.swift:22-23,32`).
- Remote pull: `UbiquitousChecklistSync.startObserving` subscribes to `didChangeExternallyNotification` (`ChecklistSyncing.swift:35-49`); `ChecklistSyncService.start()` routes it to `Task { await self.reconcile() }` (`ChecklistSyncService.swift:46-48`).
- Reconcile: `reconcileNow()` (`ChecklistSyncService.swift:101-158`) guards `store.canAcceptRemoteChanges` (`:105`; false unless stored payload came from a newer app version — `ChecklistStore.swift:31,38-95`), migrates v1/v2/v3 remote bytes (`:119-145`), seeds cloud when local non-empty and cloud nil (`:114-122`), else calls `store.apply(remote:)` and re-writes merged bytes if changed.
- Merge: `ChecklistStore.apply(remote:)` (`ChecklistStore.swift:732-760`) calls `ChecklistMerge.merge`, self-heals via `normalizedOrder()`, is idempotent (`merged != envelope` guard `:740`), and sets `isApplyingRemote = true` so the push does not echo (`:743-749`).
- Destination is copied as part of the whole-checklist scalar set: in `ChecklistMerge.mergedChecklists`, when `wins(...)` is true, `merged.destinationListIdentifier = remoteChecklist.destinationListIdentifier` (`ChecklistMerge.swift:150`). `wins` is symmetric LWW: higher `revision`, then newer `modifiedAt`, then lexicographically smaller device-id (`ChecklistMerge.swift:283-289`).
- Consequence: there is **no per-field clock for destination** — a rename on one device and a destination change on another resolve by whole-checklist winner, not field-merge (`ChecklistMerge.swift:136-152`). Tombstones union and suppress the live checklist regardless of concurrent destination edits (`ChecklistMerge.swift:16-20,36-53`).
- Watch channel is separate: `ChecklistSyncCoordinator` pushes the encoded checklist envelope (including destination) to the watch via `ChecklistSyncTransport` (`ChecklistSyncCoordinator.swift:73-78`); the watch stores it in `WatchChecklistStore` (`ChecklistSync.swift:255`). That path sends `deviceID: ""` (`ChecklistSyncCoordinator.swift:74`), so no LWW tie-break applies phone→phone on it.

## Q3: How does running a checklist turn items into reminders — what resolves the destination, what outcome/error states exist, and where is the access/permission gating applied?

### Findings
- Single funnel: `ChecklistReminders.create(from:)` builds a gate via `productionGate()` and delegates to the shared `create(from:targeting:gate:multipleOverride:)` (`CheckStitchCore/.../ChecklistReminders.swift:8-20,24-84`), used by every entry point.
- Order inside the core (`ChecklistReminders.swift`): gate first `guard gate.reserveRun() else { .purchaseRequired }` (`:39-40`) → `requestAccess()` (`:45-48`) → destination resolve (`:50-54`) → per-item loop (`:57-72`). There is no `store.run(...)`; the run bypasses `ChecklistStore`.
- Destination resolution: `targeting.reminderLists()` builds `ReminderListsSnapshot` from `eventStore.calendars(for: .reminder)` + `defaultCalendarForNewReminders()` (`EventKitReminderDestination.swift:26-31`); `snapshot.resolve(checklist.destinationListIdentifier)` (`ReminderDestinationTargeting.swift:35-40`, called `ChecklistReminders.swift:51`) maps `nil` → system default and returns `nil` for an identifier not in the snapshot → `.destinationMissing` before any create (`ChecklistReminders.swift:51-54`).
- Mid-loop TOCTOU: `EventKitReminderDestination.create(...)` re-finds the calendar by identifier and throws `ReminderDestinationError.listMissing` if deleted between validation and save (`EventKitReminderDestination.swift:37-45`).
- Item → reminder: loops `checklist.items where item.isRunnable` (`ChecklistReminders.swift:57-72`), computes `item.dueDateComponents(today:)` (`:64`), calls `targeting.create(title:notes:priority:in:dueDateComponents:)` which builds an `EKReminder`, sets `calendar`, `priority` (none 0 / low 9 / medium 5 / high 1), optional due date, then `eventStore.save(reminder, commit: true)` (`EventKitReminderDestination.swift:46-53`). Per-item save is not transactional.
- Outcomes — `enum ReminderRunOutcome` (`ReminderDestinationTargeting.swift:69-104`): `.created(count:)`, `.destinationMissing`, `.permissionDenied`, `.purchaseRequired`, `.partiallyCreated(created:total:reason:)`, `.failed(String)`; user-facing `errorMessage` mapping `:81-92`.
- Permission seams: (a) status-only pre-check `ReminderAccessStatus.accessStatus()` — only call site `RunChecklistIntent.swift:76-85` (never prompts inside an intent); (b) prompting `requestAccess()` via `requestFullAccessToReminders()` inside the run (`ChecklistReminders.swift:46-48`; `EventKitReminderDestination.swift:18-19`); (c) purchase/run-limit `RunGate.reserveRun()` (`RunCounter.swift:55-66`, `freeRunLimit = 20` `:38`, durable `"runCount.v1"` `:14`); slots released on zero-created/early returns (`ChecklistReminders.swift:55,58,63-64,66`).
- Intent-side gates before the seam: checklist exists + not archived else `checklistNotFound`; `multiple` within `Checklist.multipleRange` else `invalidMultiple` (`RunChecklistIntent.swift:63-72`).
- `ReminderAccessStatus` = `.fullAccess/.notDetermined/.denied` (`ReminderDestinationTargeting.swift:112-116`).

## Q4: How does the run-time UI let a user choose a destination and run a checklist, and where do the view model and the picker surface their states?

### Findings
- Destination picker lives in the checklist detail screen: `Picker("List", selection: destinationBinding(...))` (`CheckStitch/ChecklistDetailView.swift:54`) with a "Default (Inbox)" row (`tag String?.none`) then `listsSnapshot?.selectableOptions` rows keyed by list id (`:55-60`); header/footer `:62-68`.
- `destinationBinding` reads stored `destinationListIdentifier` and writes `store.setDestination` (`ChecklistDetailView.swift:361-370`); lists load via `loadReminderLists()` on `.onAppear` (`:198-200,267-282`) calling `EventKitReminderDestination.shared.requestAccess()`/`.reminderLists()`.
- Staleness: `destinationIsStale` is true when the stored id is absent from enumerated lists (`ChecklistDetailView.swift:287-293`), noted in the footer (`:66-68`).
- Option model: `ReminderListsSnapshot` (`ReminderDestinationTargeting.swift:18`) with `selectableOptions` (`:43-48`), `pickerSelection(for:)` (`:51-56`), `resolve` (`:28-37`).
- Run control is a per-row button in the list (`CheckStitch/ContentView.swift:546-551`; implemented `:727-751`), firing `Task { await runVM.createReminders(for: id) }` (`:729-731`), disabled while in-flight or when `!checklist.hasRunnableItems` (`:748`).
- `ChecklistRunViewModel` (`CheckStitch/ChecklistRunViewModel.swift`) surfaces: `creating: Set<UUID>` (`:30`), `created: Set<UUID>` auto-cleared after ~1 s (`:32`, `:47-49`), `runErrorMessage: String?` (`:34`, `clearRunError()` `:52-53`), `isShowingPaywall` (`:36`, `dismissPaywall()` `:55-56`).
- `createReminders(for:)` (`ChecklistRunViewModel.swift:38-68`) guards duplicate taps/`hasRunnableItems`, resolves entitlement (`purchases.start()` + `RunGate`), calls `ChecklistReminders.create(...)` (`:47`), and maps outcomes: `.created` → success check; `.purchaseRequired` → paywall; `.destinationMissing/.permissionDenied/.partiallyCreated/.failed` → `runErrorMessage` (`:57-67`). Alert driven at `ContentView.swift:180-187`; paywall sheet `:188-189`.
- `targeting` defaults to `EventKitReminderDestination.shared` at `ChecklistRunViewModel.swift:15` — the injection seam used by tests (`:7-8`).

## Q5: What are the App Intent entry points that can run a checklist and how does each perform, report failure, and expose parameters/configuration, including any App Shortcuts?

### Findings
- Only one intent actually runs a checklist: `RunChecklistIntent` (`CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift:22`), `openAppWhenRun = false` (`:25-26`).
- Parameters: `@Parameter("Checklist") checklist: ChecklistEntity` (`:29-30`) and `@Parameter("Multiple") multiple: Int?` (`:32-33`); `parameterSummary` interpoles the checklist name (`:48-50`). **No destination parameter exists** — destination is not user-configurable through the intent; it uses the production EventKit seam.
- `perform()` (`:59-110`): builds production `ChecklistStore` or injected seam (`:62`); `injectedTargeting ?? EventKitReminderDestination.shared` (`:61`); throws `checklistNotFound` if id is stale/archived (`:63-66`); validates `multiple` (`:68-72`); status-only access pre-check returning `RunsChecklistDialogue.notDetermined`/`.denied` dialogs (`:77-85`); writes `WidgetRunStateStore` `beginRun`/`finishRun` (`:93`, `:103`); 1 s `minimumSpinner`; calls `ChecklistReminders.create(...)` (`:99`); outcome→speech via `RunChecklistDialogue.message` (`:112-162`).
- App Shortcuts: `CheckStitch/Intents/CheckStitchShortcuts.swift` `AppShortcutsProvider` registers "Run Checklist" → `RunChecklistIntent()` with phrases "Run <checklist> in CheckStitch" and "Create reminders from <checklist> in CheckStitch" (`:6-10`), and "List Checklists" → `ListChecklistsIntent()` (`:13-17`, read-only, does not run).
- Other intents do **not** run: `CreateChecklistIntent` (creation only, `CreateChecklistIntent.swift:19-52`), `ListChecklistsIntent` (read-only `:3-18`). `ChecklistConfigurationIntent`/`MultiChecklistConfigurationIntent` are `WidgetConfigurationIntent`s (widget pickers), not run intents.

## Q6: How do the widget and watch targets invoke or represent a checklist run, and what data do they pass across the app/watch boundary?

### Findings
- Widget is self-contained on the phone: its run button builds a `RunChecklistIntent` with a `ChecklistEntity` (`CheckStitchWidget/SingleChecklistWidget.swift:172-176`; `MultiChecklistWidget.swift:102-104`). `RunChecklistIntent.perform()` resolves the checklist from `ChecklistStore(defaults: AppGroup.defaults)` (`RunChecklistIntent.swift:61,67-72`), runs with `openAppWhenRun = false` (`:24`).
- Widget↔app run state is a shared App Group `UserDefaults` record: `WidgetRunStateStore` written by `RunChecklistIntent` and read by `ChecklistWidgetTimeline.make` (`SingleChecklistWidget.swift:74-98`). Not WatchConnectivity.
- Watch only *requests* runs; the phone owns EventKit. `WatchChecklistViewModel.run(checklist)` → `WatchChecklistStore.run(checklist)` (`CheckStitchWatch/WatchChecklistViewModel.swift:45-47`; `CheckStitchCore/.../ChecklistSync.swift:303-317`), which records a `PendingRun(runID, checklistID)`, sets `.sending`, and sends `.runChecklist(id:runID:)` via `transferUserInfo` (`ChecklistSync.swift:327-337`).
- Transport seams: watch half `WatchSyncAdapter` (`CheckStitchWatch/WatchSyncAdapter.swift`; `sendContext` deliberately empty `:34`); phone half `PhoneSyncAdapter` (`CheckStitch/PhoneSyncAdapter.swift:36-57`); incoming `.runChecklist` routed to coordinator (`:112-132`), answering `.failed` if no handler yet.
- Coordinator: `ChecklistSyncCoordinator` pushes the encoded checklist/folder snapshot on `.context` (`:75-77`), de-dups runs by `runID` (`:86-120`), serializes creates through a `pendingRun` Task chain, and replies `.runResult(RunResult(runID, checklistID, kind:))` (`:120-136`).
- Wire format: `ChecklistSyncMessage` enum (`ChecklistSync.swift:118-198`) with keys `runChecklist`/`runChecklistRunID` (UUID strings), `requestChecklists`, `runResult`/`runID`/`checklistID`/`kind`/`count`/`total` (`:11-26`); `RunResultKind` serializes name+counts (`:33-116`).
- Cross-boundary payloads: (1) `.context(Data)` phone→watch whole snapshot (latest wins); (2) `.runChecklist(id, runID)` watch→phone; (3) `.runResult(RunResult)` phone→watch; plus `.language(String)` and `.requestChecklists`. No destination crosses this boundary — the watch sends only the checklist id.

## Q7: What localization and test conventions apply to user-facing destination and run strings, and how are the affected areas tested?

### Findings
- Four `.xcstrings` catalogs: `CheckStitch/Localizable.xcstrings`, `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`, `CheckStitchWatch/Localizable.xcstrings`, `CheckStitchWidget/Localizable.xcstrings`; six languages enforced by `scripts/l10n-check.sh` (`en, de, es, fr, ja, zh-Hans`).
- Destination/run strings: `"Create reminders from checklist"` (App catalog `CheckStitch/Localizable.xcstrings:1808`; used as `.accessibilityLabel` at `ContentView.swift:749`) and `"Couldn't create reminders for %@: %@"` (`Localizable.xcstrings:5006`; produced in `RunChecklistIntent.swift:152`).
- `CheckStitchTests/LocalizationFixtures.swift` defines `guardedCatalogs = ["App","Core","Watch","Widget"]` and `requiredKeys` (destination/run entries at lines 37 and 129); a new key needs all six languages plus a `requiredKeys` entry.
- `CheckStitchTests/LocalizationTests.swift` covers `catalogsParseAndHaveNonEmptyEnglish`, `catalogsHaveAllSixLanguages`, `everyRequiredKeyIsPresent`, `watchCatalogCarriesEveryUIKey`, `nonEnglishValuesDifferFromEnglish`, plus bundle-embedding tests.
- `scripts/l10n-check.sh` mirrors those checks statically (no xcodebuild); run it before the full gate (per repo AGENTS.md).
- Run/destination suites: `ChecklistRunViewModelTests.swift` (destination-missing short-circuit at lines 64, 74-77), `RunChecklistIntentTests.swift` (partial/failed messages ~127-130), `ChecklistRemindersTests.swift`, `EventKitReminderDestinationTests.swift`, `ReminderListsSnapshotTests.swift`, `ChecklistMergeTests.swift`, `ChecklistSyncMessageTests.swift`, `WidgetRunStateStoreTests.swift`, `WatchChecklistStoreTests.swift`.
- Caveat found: the alert title `"Couldn't create reminders"` at `ContentView.swift:179` is hardcoded rather than resolved from a catalog key.

## Cross-Cutting Observations
- **One run funnel, many entry points**: app UI, App Intent, widget, and watch all converge on `ChecklistReminders.create(from:targeting:gate:multipleOverride:)`; destination resolution happens inside it via `ReminderListsSnapshot.resolve` (`ChecklistReminders.swift:50-54`). A new destination state must be understood by this funnel.
- **Destination is a bare optional string on `Checklist`** with whole-checklist coarse-clock semantics: encoded unconditionally, decoded absent-key-tolerantly, no version bump, merged only as part of the LWW winner (`Checklist.swift:212,268,314`; `ChecklistMerge.swift:150`).
- **Two independent gates precede EventKit**: `RunGate`/`RunCounter` purchase gate and OS Reminders permission; failure ordering is gate → permission → destination resolve (`ChecklistReminders.swift:39-54`).
- **Widget and App Intent share `RunChecklistIntent` and `WidgetRunStateStore`; watch uses a WatchConnectivity request/reply with a `runID` correlation and never carries destination data** (`ChecklistSyncCoordinator.swift:86-136`; `ChecklistSync.swift:303-337`).
- **Localization is enforced by both a static script and Swift tests**, with a per-catalog `requiredKeys` list that must be extended for new user-facing strings (`LocalizationFixtures.swift`; `scripts/l10n-check.sh`).

## Open Areas
- Exact `"checklists.v1"` load lines in `ChecklistStore` were not isolated by the readers (write path is `save()` `:799-815`); the load/init entry was only referenced indirectly.
- The `RunsChecklistDialogue.notDetermined`/`.denied` exact `IntentDialog` strings beyond their case names were not transcribed (`RunChecklistIntent.swift:78-121`).
- `hasRunnableItems` definition lives outside the areas traced (`Checklist.swift`); the run-time UI treats it as a given.
- `ChecklistEntityQuery` internals were not fully traced (out of Q5's scope; covered indirectly by Q6's id lookup).
- The watch `.failed`/`.notFound` user-visible strings and any destination-related copy on the watch were not enumerated.