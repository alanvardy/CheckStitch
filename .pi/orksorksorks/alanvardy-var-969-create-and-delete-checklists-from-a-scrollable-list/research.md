# Research Findings

Sources: direct reads of the CheckStitch repo (repo), the SingleThread reference
repo at /Users/vardy/dev/SingleThread (ST), the spike worktree
alanvardy-var-766-spike-group-registered-watch-test-harness-for-cross (SPIKE),
and the local iOS/macOS SDK headers. Four of five research subagents hit the
30-minute cap and returned empty; q4 (build conventions) completed, and all
other findings below were gathered with targeted reads of the cited regions.

## Q1: Current app flow in MyApp.swift and ContentView.swift

### Findings
- Entry point: `MyApp.swift:4-9` defines `@main struct MyApp: App` whose body is
  `WindowGroup { ContentView() }` — a single scene, one screen.
- `ContentView.swift:6-16` holds all app state as `@State`:
  `checklistName = "checklist"`, `items = [ChecklistItem(title: "one"/"two"/"three")]`,
  `isShowingEditChecklist`, `isCreatingChecklist`, `isChecklistCreated`.
- Body (`ContentView.swift:17-26`): an `HStack(spacing: 16)` containing
  `createChecklistButton` and `editChecklistButton`, padded and centered, with a
  `.sheet(isPresented: $isShowingEditChecklist)` hosting
  `EditChecklistView(name: $checklistName, items: $items)`.
- `createChecklistButton` (`ContentView.swift:28-60`): a labeled button showing
  `checklistName` text plus a `ProgressView` spinner while `isCreatingChecklist`
  or a green `checkmark.circle.fill` image while `isChecklistCreated`. Its action
  is a `Task` that: sets `isCreatingChecklist = true`; starts a
  `minimumSpinner = Task.sleep(for: .seconds(1))` so fast saves don't flash past
  the user; `await createChecklistReminders()`; clears the spinner; sets the
  checkmark; sleeps 1s; clears the checkmark (`ContentView.swift:31-47`).
- `editChecklistButton` (`ContentView.swift:62-79`): pencil icon button that sets
  `isShowingEditChecklist = true`. Both buttons carry accessibility identifiers
  `checklistButton` / `editChecklistButton`.
- `EditChecklistView` (`ContentView.swift:119-166`): a sheet struct with
  `@Binding name: String` and `@Binding items: [ChecklistItem]` (writes go back
  to the caller's `@State`), an `@Environment(\.dismiss)` handle, and a
  `NavigationStack { Form { ... } }`.
  - Section "Checklist name": `TextField` bound to `$name`
    (`ContentView.swift:124-127`).
  - Section "Items": `ForEach($items)` rendering one `TextField` per item with
    `.onDelete(perform: remove)`; `remove(at offsets: IndexSet)` deletes rows
    (`ContentView.swift:128-132, 160-163`).
  - Section with two buttons (`ContentView.swift:133-140`): "Add Item" appends
    `ChecklistItem(title: "New item")`; "Remove Checklist" calls `dismiss()`.
  - Toolbar "Done" button also calls `dismiss()` (`ContentView.swift:141-143`).
    So Remove Checklist and Done are byte-for-byte the same behavior today —
    the Remove button only closes the sheet; the checklist state survives.
- `ChecklistItem` (`ContentView.swift:106-117`): `struct ChecklistItem: Identifiable`
  with `let id = UUID()` (stable identity, per the doc comment, so duplicate
  titles don't conflate rows) and mutable `var title: String`. Constructed inline
  as `ChecklistItem(title: ...)`.

## Q2: Reminders/EventKit integration

### Findings
- CheckStitch's creation flow is entirely in `createChecklistReminders()`
  (`ContentView.swift:81-104`):
  1. `let eventStore = EKEventStore()` (`ContentView.swift:83`).
  2. `let granted = try await eventStore.requestFullAccessToReminders()`; returns
     early if not granted (`ContentView.swift:85-87`).
  3. One `EKReminder(eventStore: eventStore)` per non-blank item; blanks skipped
     via `guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
     else { continue }` (`ContentView.swift:90-96`).
  4. Sets `reminder.title = item.title` and
     `reminder.calendar = eventStore.defaultCalendarForNewReminders()`
     (`ContentView.swift:97-98`) — the Reminders Inbox, not a custom calendar.
  5. `try eventStore.save(reminder, commit: true)` — `commit: true` per save
     (`ContentView.swift:99`).
  6. Any failure is caught once around the loop and logged via
     `Self.logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")`
     (`ContentView.swift:101-103`). Note: `Self.logger` is declared statically at
     `ContentView.swift:5`.
  - The trigger Task also enforces a minimum 1s spinner (`ContentView.swift:33-36`)
    so the created-state is visible before the checkmark clears.
- SingleThread uses the same EventKit vocabulary: `EKReminder(eventStore:)`
  construction (`ST SingleThreadWatch/WatchReminderView.swift:383, 392`;
  `WatchAppViewModel.swift:110`), with the doc note that `EKReminder` holds a weak
  reference to the event store which must outlive the reminders
  (`WatchReminderView.swift:378-380`, `TestFixtures.swift:8-10`).
- Usage-description keys are required because `GENERATE_INFOPLIST_FILE = YES`.
  CheckStitch already defines both:
  `INFOPLIST_KEY_NSRemindersUsageDescription` and
  `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription`, in both build
  configurations (`CheckStitch.xcodeproj/project.pbxproj:261-263, 303-305`).
  SingleThread defines the same keys in its pbxproj
  (`ST SingleThread.xcodeproj/project.pbxproj:752-754, 950, 978, 1008, 1039`) and
  in per-locale `InfoPlist.strings` files
  (`ST SingleThreadWatch/en.lproj/InfoPlist.strings:1`, same in de/ja/zh-Hans/
  es/fr.lproj).
- Known pitfall precedent: `ST docs/SimulatorManualVerification.md:92` records
  that a missing `NSRemindersFullAccessUsageDescription` in the app target's
  Info.plist is a latent real-install issue (was out of scope there).
- Reminder deletion: no code in CheckStitch creates, finds, or deletes existing
  reminders — the app only ever appends new ones. `CompletionCounterStore.swift:6-8`
  (ST) references `ReminderStore.completeReminder` in SingleThread's store (the
  completion flow), the closest thing to mutation-after-save anywhere in either
  repo. Nothing removes reminders from Reminders in either codebase.

## Q3: App Group container storage available on this machine

### Findings
- Entitlement: `CheckStitch/AppGroup.entitlements:1-10` registers the
  `com.apple.security.application-groups` array with exactly one group,
  `group.app.alanvardy.CheckStitch`; referenced as `CODE_SIGN_ENTITLEMENTS` for
  both configurations (`project.pbxproj`, per q4 report).
- Low-level SDK surface (on-disk headers,
  `MacOSX.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSFileManager.h`):
  - `containerURLForSecurityApplicationGroupIdentifier:` — "Returns the container
    directory associated with the specified security application group ID",
    `API_AVAILABLE(macos(10.8), ios(7.0), watchos(2.0), tvos(9.0))`
    (`NSFileManager.h:452-454`).
  - `URLForUbiquityContainerIdentifier:` and the ubiquity identity token
    (`NSFileManager.h:315, 321-323`) — a *different* container feature (user-
    shared ubiquitous files), not the App Group container.
  - No container-session / container-for-requirement API appears in this
    NSFileManager.h; nothing matches `containerSession`, `containerForRequirement`,
    or `FileSystemContainer` in any Swift source under /Users/vardy/dev.
- The Swift layer actually used for App Group state is `UserDefaults` with a
  suite name, not NSFileManager:
  - `ST SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8-19`:
    `public enum AppGroup { public static let suiteName = "group.app.alanvardy.SingleThread";
    public static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard } }` —
    the suite must match the registered App Group; falls back to `.standard` when
    the group is unavailable (watchOS, unregistered simulators, previews).
  - Store pattern: every persistent value is a struct taking
    `defaults: UserDefaults = AppGroup.defaults, key: String = <defaultsKey>`
    (`CompletionCounterStore.swift:12-18`, `SkipCountStore.swift:23-28`,
    `ExcludedListStore.swift:7`, `DailyCompletionStore.swift:18`,
    `BoolPreferenceStore.swift:9-15`, `SortOption.swift:25`, `PendingCompletionStore.swift:8-21`).
  - `UserDefaults` key/value API in use: reads `integer(forKey:)` /
    `bool(forKey:)` (`CompletionCounterStore.swift:29-31`,
    `ShowEnableActionButtonsState.swift:15`), writes `defaults.set(value, forKey:)`
    (`CompletionCounterStore.swift:33`, `ShowEnableActionButtonsState.swift:24`),
    deletion via `removeObject(forKey:)` (watch tests
    `WatchSyncPipelineTests.swift:395, 410`; `ShowEnableActionButtonsStateTests.swift:19, 60`).
  - Direct in-place use without a store struct exists too:
    `WatchAppViewModel.swift:27, 133, 198` writes `AppGroup.defaults.set(...)` for
    `completionCount` / `skipCounts`.
- App Group semantics on watch: SPIKE `docs/WatchAppGroupHarness.md` (worktree
  var-766) asserts (1) `UserDefaults(suiteName: AppGroup.suiteName) != nil` after
  group registration, (2) group != `.standard` (writes diverge), (3) `.standard`
  writes don't leak into the group. The doc's procedure records negative findings
  (e.g. "watchOS sim does not support App Groups") rather than failing silently.
- Watch-app/project context: `alanvardy-var-951-get-the-apple-watch-app-running-on-device`
  is a CheckStitch worktree (same AGENTS.md, CheckStitch/ long-list); its step
  artifact `design.md:124` notes shared-container code (`UserDefaults(suiteName:)`
  "or shared container code") is a planned addition. `WatchOS.platform`/
  `WatchSimulator.platform` SDKs exist in the local Xcode install.
- CheckStitch itself has zero persistence code today: no file I/O, no
  NSFileManager, no App Group usage anywhere in CheckStitch/ (locator recon).

## Q4: Build/verify/test conventions

### Findings
- Gate: `scripts/test.sh:1-15` runs `make build`, then `shellcheck scripts/*.sh`
  when shellcheck exists, else `bash -n` per script; prints `gate: ok`.
- Makefile: `build` → `xcodebuild -scheme CheckStitch -destination '$(SIM)'
  -configuration Debug -derivedDataPath DerivedData build`; `run` →
  `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'`; `clean`. Variables:
  SCHEME/CheckStitch, CONFIGURATION/Debug, DERIVED_DATA/DerivedData,
  APP=DerivedData/Build/Products/Debug-iphonesimulator/CheckStitch.app.
- Destination precedence (`Makefile:4-6`): explicit `SIM=` > worktree
  `.simulator_id` → `platform=iOS Simulator,id=<UUID>` > shared default
  `platform=iOS Simulator,name=iPhone 17`. This worktree pins
  `.simulator_id` = `A5A9A41C-472B-4D6A-9262-9784ED28E8FE` (verified).
- run-simulator.sh (50 lines): extracts UDID from the destination (id= or
  name lookup via `xcrun simctl list devices available`), validates the app
  bundle, `simctl boot`, `bootstatus -b`, `install`, `launch
  --terminate-running-process` with `BUNDLE_ID=app.alanvardy.CheckStitch`.
- run-devices.sh (86 lines): builds for `generic/platform=iOS` with
  `-allowProvisioningUpdates`, discovers devices via
  `xcrun devicectl list devices -j` (requires jq), filters
  iOS/iPhone-or-iPad/developerModeStatus enabled/tunnelState != unavailable,
  prefers iPhone, installs and launches via devicectl. Requires Developer Mode.
- Identity: DEVELOPMENT_TEAM `6NWX2DHB9Q`, PRODUCT_BUNDLE_IDENTIFIER
  `app.alanvardy.CheckStitch`, IPHONEOS_DEPLOYMENT_TARGET 18.7,
  ONLY_ACTIVE_ARCH YES in Debug (q4 report of project.pbxproj).
- No CI configuration of any kind exists in the repo (no .github/, .circleci/,
  Jenkinsfile, or .yml/.yaml; q4 report).
- No test target: the Xcode project contains no CheckStitchTests; the gate is
  build + script linting. New source files under CheckStitch/ need no
  project.pbxproj edit (`PBXFileSystemSynchronizedRootGroup`).

## Q5: Git history and checklist-concept evolution

### Findings
- Setup era: 256d9d0/03c8a69 (run-devices.sh rename; 12 files, 1484 insertions —
  project scaffold), 595297e "Add a checklist" (single button), 0f26d7f
  (simulator build/run with per-worktree destination), d610360 (AGENTS.md +
  build-based test gate).
- Reminder creation: b136ade "Add centered checklist button that creates three
  reminders" (ContentView grew to ~25 lines, 2 files), eb4036a "Log failures
  when creating checklist reminders", 10ddd1e "Skip blank item titles when
  creating checklist reminders", 3ddc395 "Make checklist button larger with
  edit overlay for name and items" (ContentView +105 lines: edit overlay,
  EditChecklistView), 56d3046 "Edit items on checklist".
- VAR-966 (green checkmark): f801827 "Show a green checkmark" (+29/-10),
  4d42c04 step artifacts for the green checkmark ticket, 340928e "addressed
  comments".
- VAR-967 (no-op Remove): f8fe712 "Add and remove checklists" (+1), ce0b479
  "Add Remove Checklist button to edit view" (4 files, +26/-1) — the Remove
  button that only `dismiss()`es; superseded by VAR-969 (large.md, ticket).
- 1df4dfd "chore: start alanvardy-var-969-..." — this branch's starting point.
- Concept naming: the checklist is a name string plus an item array held in
  ContentView `@State`; the model type is `ChecklistItem` with stable `UUID`
  identity (`ContentView.swift:106-117`); there is no checklist-level type — no
  struct holds name+items together, and nothing persists.

## Cross-Cutting Observations
- The entire app is one 166-line file; all state is `@State` on the view, and the
  only mutation seams are the Task block of the create button, the sheet's
  `@Binding`s, and `editChecklistButton`. Any checklist-collection feature will
  touch every one of these (lines 6-16, 28-60, 62-79, 81-104, 119-166).
- Everything in the EventKit flow is one-shot forward (request access → create →
  save); the app never queries or mutates previously created reminders.
- The App Group idiom is established in SingleThread (stores over
  `UserDefaults(suiteName: AppGroup.suiteName)` with `.standard` fallback and
  injectable `defaults` for tests), is proven on watch by the SPIKE, and is the
  only cross-app persistence pattern available on this machine; the raw
  `NSFileManager.containerURLForSecurityApplicationGroupIdentifier` URL API
  exists in the SDK but is unused by any Swift here.
- The codebase is dependency-free; persistence would be the first subsystem of
  its kind in this project.

## Open Areas
- Whether the watch app (VAR-963) already expects a specific wire format for the
  shared state could not be confirmed — the var-951 worktree's artifacts mention
  shared-container code only in a design note (`var-951/.pi/.../design.md:124`),
  and var-766 spike was about SingleThread (its own suite
  `group.app.alanvardy.SingleThread`), not CheckStitch's.
- SingleThread's `ReminderStore` (completion/undo internals) was not read in
  full; only its existence via `CompletionCounterStore.swift:6-9`.
- The iOS-device SDK (iPhoneOS.platform) Foundation headers were not opened
  directly; the MacOSX.sdk header's API_AVAILABLE annotations already cover
  ios/watchos availability, so this is a build-time detail rather than an
  availability question.
- Four of five research subagents timed out at the 30-minute cap and returned
  empty artifacts; those questions were answered by direct targeted reads of the
  same regions. No question went unanswered.