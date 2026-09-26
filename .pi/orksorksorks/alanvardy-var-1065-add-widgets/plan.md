# Implementation Plan

## Overview

Ship an iOS-only CheckStitch widget extension that reads the existing App Group
`checklists.v1` payload and runs a checklist through the single live reminder
path (`ChecklistReminders.create`). Phase 0 moves the run seam and read model
into `CheckStitchCore` (extensions cannot link the app target); every later
phase is a vertical slice: real WidgetKit entry point → real Core logic →
rendered, tappable widget, gated when it lands.

**Repo root for all paths below**: `/Users/vardy/dev/alanvardy-var-1065-add-widgets`
(the ticket worktree). All shell commands run from there.

**Gate**: `./scripts/test.sh`. Fast loop: `make test-unit`. Build the extension:
`make widget-build` (new in Phase 1).

---

## Phase 0 — Core extraction (horizontal exception)

No user-visible change. Pure move + visibility: add the listed types to
`CheckStitchCore`, delete them from the app target, update consumers. Nothing
new is authored except the one purchase seam noted below (deviation, see end).

### Changes

#### 1. New `CheckStitchCore/Sources/CheckStitchCore/AppGroup.swift`
**Action**: create (move from `CheckStitch/AppGroup.swift`, delete the original).

```swift
import Foundation

public enum AppGroup {
    public static let suiteName = "group.app.alanvardy.CheckStitch"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
```

#### 2. New `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: create (move `CheckStitch/ChecklistStore.swift`; delete original).

- Remove the `import CheckStitchCore` line (self-import is illegal in the package).
- Annotate the type `@MainActor` to preserve its current app-target isolation
  (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target): `@MainActor @Observable public final class ChecklistStore`.
- Make public: the type, `init(defaults:key:textEditDelay:now:)`, `checklists`,
  `tombstones`, `onChange`, `deviceID`, `envelope`, `canAcceptRemoteChanges`,
  `checklist(id:)`, `RenameOutcome`, `SetDestinationOutcome`,
  `create(name:)`, `duplicateName(basedOn:)`, `duplicate(id:name:)`,
  `importInsert(_:as:)`, `importReplace(id:with:)`, `rename(id:to:)`,
  `setDestination(_:for:)`, `setPrefixesReminderNumbers(_:for:)`,
  `addItem(to:title:)`, `addItem(to:)`, `updateItem(checklistID:itemID:title:)`,
  `updateItemDescription(checklistID:itemID:description:)`,
  `updateItem(checklistID:itemID:relativeDate:)`,
  `updateItem(checklistID:itemID:priority:)`, `removeItems(from:at:)`,
  `removeChecklists(at:)`, `moveItems(checklistID:from:to:)`,
  `moveChecklists(from:to:)`, `delete(id:)`, `apply(remote:)`,
  `flushPendingSave()`.
- Keep `save()`, `scheduleSave()`, `uniqueName`, `sameName`, `moved`, `logger`,
  and all stored private state private. `@ObservationIgnored` annotations stay.
- `ChecklistStore(defaults: AppGroup.defaults)` must resolve inside Core — now it
  does (both are in the same module).

#### 3. New `CheckStitchCore/Sources/CheckStitchCore/ChecklistMerge.swift`
**Action**: create (move `CheckStitch/ChecklistMerge.swift`; delete original).

- Remove the `import CheckStitchCore` line.
- `public enum ChecklistMerge` and `public static func merge(local:remote:)`.
  Keep every private helper private. Nonisolated (pure) — no `@MainActor`.

#### 4. New `CheckStitchCore/Sources/CheckStitchCore/ChecklistReminders.swift`
**Action**: create (move `CheckStitch/ChecklistReminders.swift`; delete original).

- Remove the `import CheckStitchCore` line.
- `@MainActor public enum ChecklistReminders`, and make `create(from:)`,
  `productionGate()`, and `create(from:targeting:gate:)` public.
- Replace the app-target `PurchaseEnvironment.service` reference with the Core
  seam added in step 7 (`await purchases.start()` stays).

#### 5. New `CheckStitchCore/Sources/CheckStitchCore/EventKitReminderDestination.swift`
**Action**: create (move `CheckStitch/EventKitReminderDestination.swift`; delete original).

- Remove `import CheckStitchCore`; keep `import EventKit`.
- `@MainActor public final class EventKitReminderDestination: ReminderDestinationTargeting`,
  with `public static let shared`, `public init(eventStore:)`, and `public` on all
  four protocol methods. `enum ReminderDestinationError` stays internal.
- The `#if !os(watchOS)` guard around `save(commit:)` stays (Core still compiles
  for watchOS via `make watch-build`).

#### 6. New Core intents: `ChecklistEntity.swift`, `RunChecklistIntent.swift`, `ListChecklistsIntent.swift`
**Action**: create (move the three files from `CheckStitch/Intents/`; delete originals).

- Remove `import CheckStitchCore` from each; add `import AppIntents` where not present.
- `ChecklistEntity`: `public struct`, `public static let typeDisplayRepresentation`,
  `public static var defaultQuery`, `public let id/name`, `public init(id:name:)`,
  `public init(_ checklist:)`, `public var displayRepresentation`.
- `ChecklistEntityQuery`: `public struct`, `public init()`, `public init(store:)`,
  `public func entities(for:)`, `public func entities(matching:)`,
  `public func suggestedEntities()`.
- `RunChecklistIntent`: `public struct`, `public static let title`,
  `public static let openAppWhenRun`, `public var checklist`,
  `public init()`, `public init(store:targeting:gate:)`,
  `public static var parameterSummary`, `@MainActor public func perform()`.
  Keep `RunChecklistIntentError` and `enum RunChecklistDialogue` internal;
  `RunChecklistDialogue`'s `LocalizedStringResource(..., bundle: .main)` calls are
  unchanged (app/Siri resolve against the app catalog; the widget never renders
  them).
- `ListChecklistsIntent`: `public struct`, public `title`/`openAppWhenRun`,
  `public init()`, `public init(store:)`, `@MainActor public func perform()`.

#### 7. New `CheckStitchCore/Sources/CheckStitchCore/PurchaseEnvironment.swift` (deviation)
**Action**: create.

`ChecklistReminders.productionGate()` needs a purchase service, and the current
`PurchaseEnvironment` lives in the app target with a StoreKit-backed provider
that must stay out of Core (Core also compiles for watchOS). Move the holder to
Core with a StoreKit-free default and let the app target inject the real one.

```swift
import Foundation

/// The process-wide purchase service. The app target replaces `service` at
/// launch with the StoreKit-backed instance; out-of-app processes (widgets,
/// Siri) keep the StoreKit-free default.
@MainActor
public enum PurchaseEnvironment {
    public static var service: PurchaseService = PurchaseService(
        provider: CachedEntitlementProvider(),
        cache: PurchaseEntitlementCache(defaults: AppGroup.defaults))
}

/// StoreKit-free provider for cold extension processes: reports the durable
/// verified-entitlement cache and never starts a StoreKit session.
@MainActor
public struct CachedEntitlementProvider: PurchaseProviding {
    public init() {}
    public func offer() async -> PurchaseOffer? { nil }
    public func currentEntitlement() async -> Bool {
        PurchaseEntitlementCache(defaults: AppGroup.defaults).isVerified
    }
    public func purchase() async throws -> Bool { false }
    public func restore() async throws -> Bool { false }
    public func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void) {}
}
```

#### 8. App-target consumer updates
**Action**: modify.

- `CheckStitch/MyApp.swift`
  - Delete `enum PurchaseEnvironment` (now in Core).
  - In `init()`, before building view models, inject the StoreKit-backed service:
    ```swift
    PurchaseEnvironment.service = PurchaseService(
        provider: StoreKitPurchaseService(),
        cache: PurchaseEntitlementCache(defaults: AppGroup.defaults))
    ```
  - `_purchaseService = State(initialValue: PurchaseEnvironment.service)` is unchanged.
  - The watch-coordinator closure `ChecklistReminders.create(from: $0)` and
    `ChecklistStore()` call keep working via `import CheckStitchCore` (already present).
- `CheckStitch/Intents/CheckStitchShortcuts.swift` — add `import CheckStitchCore`
  (it now references Core's `RunChecklistIntent`/`ListChecklistsIntent`).
- All other app files already `import CheckStitchCore`; no edits.
- Delete `CheckStitch/AppGroup.swift`, `CheckStitch/ChecklistStore.swift`,
  `CheckStitch/ChecklistMerge.swift`, `CheckStitch/ChecklistReminders.swift`,
  `CheckStitch/EventKitReminderDestination.swift`,
  `CheckStitch/Intents/{ChecklistEntity,RunChecklistIntent,ListChecklistsIntent}.swift`.

#### 9. Test import fixups
**Action**: modify.

- `CheckStitchTests/AppGroupTests.swift` — add `import CheckStitchCore`.
- `CheckStitchTests/EventKitReminderDestinationTests.swift` — add `import CheckStitchCore`.
- No other suite changes: every other file touching a moved symbol already
  carries `@testable import CheckStitchCore` / `import CheckStitchCore`.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make build-mac` passes (Core still compiles without iOS-only API)
- [x] `make watch-build` passes (Core's EventKit/AppIntents additions are watchOS-safe)
- [x] `bash scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Launch the app (`make run`); the checklist list, run button, Siri shortname
      entry and import/export still behave as before (pure move).

---

## Phase 1 — Walking skeleton: small widget runs a checklist

User places a `systemSmall` widget; it loads the first checklist from the App
Group, shows its name, and a tap creates its reminders with no app foregrounding.
Configuration is hard-coded via the display model's `configuration` argument.

### Changes

#### 1. `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidgetDisplayModel.swift`
**Action**: create.

```swift
import Foundation

/// Row the widget renders: one configured checklist, resolved against the store.
public struct ChecklistWidgetRow: Identifiable, Equatable, Sendable {
    public let id: Checklist.ID
    public let name: String
    public let entityID: String        // ChecklistEntity.ID == checklist.id.uuidString
    public let isRunnable: Bool
    public let needsAccess: Bool

    public init(id: Checklist.ID, name: String, entityID: String,
                isRunnable: Bool, needsAccess: Bool) {
        self.id = id
        self.name = name
        self.entityID = entityID
        self.isRunnable = isRunnable
        self.needsAccess = needsAccess
    }
}

public enum ChecklistWidgetAccessState: Equatable, Sendable {
    case ready
    case needsAccess
    case needsPurchase
}

/// Pure mapping from the store's checklists + the widget configuration to the
/// rows the widget renders. No EventKit, no WidgetKit: unit-testable in the gate.
public struct ChecklistWidgetDisplayModel: Equatable, Sendable {
    /// Cap for the multi-row (large) widget; extra configured rows are dropped.
    public static let rowLimit = 6

    public init(checklists: [Checklist], configuration: [ChecklistEntity],
                access: ChecklistWidgetAccessState) {
        let byID = Dictionary(checklists.map { ($0.id.uuidString, $0) },
                              uniquingKeysWith: { first, _ in first })
        self.rows = Array(configuration.prefix(Self.rowLimit).compactMap { entity in
            guard let checklist = byID[entity.id] else { return nil }
            return ChecklistWidgetRow(
                id: checklist.id,
                name: checklist.name,
                entityID: entity.id,
                isRunnable: access == .ready,
                needsAccess: access != .ready)
        })
    }

    public let rows: [ChecklistWidgetRow]
}
```

#### 2. `CheckStitchWidget/ChecklistWidgetBundle.swift`
**Action**: create.

```swift
import SwiftUI
import WidgetKit

@main
struct ChecklistWidgetBundle: WidgetBundle {
    var body: some Widget {
        SingleChecklistWidget()
    }
}
```

#### 3. `CheckStitchWidget/SingleChecklistWidget.swift`
**Action**: create.

```swift
import AppIntents
import CheckStitchCore
import SwiftUI
import WidgetKit

struct ChecklistEntry: TimelineEntry {
    let date: Date
    let model: ChecklistWidgetDisplayModel
}

@MainActor
enum ChecklistWidgetLoader {
    /// Reads the App Group store and folds access state. Phase 1 hard-codes the
    /// first checklist; later phases pass the intent's configuration.
    static func load(configuration: [ChecklistEntity]) -> ChecklistWidgetDisplayModel {
        let checklists = ChecklistStore(defaults: AppGroup.defaults).checklists
        let resolved = configuration.isEmpty
            ? checklists.first.map { [ChecklistEntity($0)] } ?? []
            : configuration
        return ChecklistWidgetDisplayModel(
            checklists: checklists, configuration: resolved, access: accessState())
    }

    static func accessState() -> ChecklistWidgetAccessState {
        EventKitReminderDestination.shared.accessStatus() == .fullAccess
            ? .ready : .needsAccess
    }
}

struct SingleChecklistProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry {
        ChecklistEntry(
            date: .now,
            model: ChecklistWidgetDisplayModel(
                checklists: [Checklist(name: "Groceries")],
                configuration: [ChecklistEntity(id: UUID().uuidString, name: "Groceries")],
                access: .ready))
    }

    func getSnapshot(in context: Context, completion: @escaping (ChecklistEntry) -> Void) {
        Task { @MainActor in
            completion(ChecklistEntry(date: .now, model: ChecklistWidgetLoader.load(configuration: [])))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChecklistEntry>) -> Void) {
        Task { @MainActor in
            let entry = ChecklistEntry(date: .now, model: ChecklistWidgetLoader.load(configuration: []))
            completion(Timeline(entries: [entry],
                                policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct SingleChecklistWidget: Widget {
    static let kind = "SingleChecklistWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SingleChecklistProvider()) { entry in
            SingleChecklistWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CheckStitch Checklist")
        .description("Run a checklist without opening the app.")
        .supportedFamilies([.systemSmall])
    }
}

struct SingleChecklistWidgetView: View {
    let entry: ChecklistEntry

    var body: some View {
        if let row = entry.model.rows.first {
            VStack(alignment: .leading, spacing: 8) {
                Text(row.name).font(.headline).lineLimit(2)
                if row.isRunnable {
                    Button(intent: runIntent(for: row)) {
                        Label("Create reminders", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("Open CheckStitch to enable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("No checklists").font(.caption)
        }
    }

    /// `RunChecklistIntent` has no memberwise init (its `@Parameter` is set by the
    /// system / here). Build it and assign the parameter.
    @MainActor
    private func runIntent(for row: ChecklistWidgetRow) -> RunChecklistIntent {
        var intent = RunChecklistIntent()
        intent.checklist = ChecklistEntity(id: row.entityID, name: row.name)
        return intent
    }
}
```

> If the compiler synthesizes `RunChecklistIntent(checklist:)` (it does not today —
> the macro cannot see the private stored properties), the smaller form
> `RunChecklistIntent(checklist: ChecklistEntity(...))` may be used instead.
> Verify with `make widget-build`.

#### 4. `CheckStitchWidget/CheckStitchWidget.entitlements`
**Action**: create.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.app.alanvardy.CheckStitch</string>
	</array>
</dict>
</plist>
```

(No KVS ubiquity entitlement: the widget reads the App Group store, not iCloud.)

#### 5. `CheckStitchWidget/Info.plist`
**Action**: create. Needed because `NSExtension` is a dict that
`INFOPLIST_KEY_*` cannot generate.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

#### 6. `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify. Add a `PBXNativeTarget` for the extension, a
`PBXFileSystemSynchronizedRootGroup` for `CheckStitchWidget/`, embed the `.appex`
in the app, and add the target to the project. Follow the existing
hand-numbered-ID convention; pick fresh unique IDs (illustrative IDs below).

- `PBXBuildFile`:
  ```
  000000000000000000000065 /* CheckStitchCore in Frameworks */ = {isa = PBXBuildFile; productRef = 000000000000000000000031 /* CheckStitchCore */; };
  000000000000000000000066 /* CheckStitchWidget.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = 000000000000000000000081 /* CheckStitchWidget.appex */; platformFilter = ios; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
  ```
- `PBXContainerItemProxy`:
  ```
  000000000000000500000002 /* PBXContainerItemProxy */ = {
      isa = PBXContainerItemProxy;
      containerPortal = 000000000000000000000000 /* Project object */;
      proxyType = 1;
      remoteGlobalIDString = 000000000000000500000000;
      remoteInfo = CheckStitchWidget;
  };
  ```
- `PBXCopyFilesBuildPhase` (PlugIns = `dstSubfolderSpec = 13`):
  ```
  000000000000000160000000 /* Embed Foundation Extensions */ = {
      isa = PBXCopyFilesBuildPhase;
      buildActionMask = 2147483647;
      dstPath = "";
      dstSubfolderSpec = 13;
      files = (000000000000000000000066 /* CheckStitchWidget.appex in Embed Foundation Extensions */,);
      name = "Embed Foundation Extensions";
      runOnlyForDeploymentPostprocessing = 0;
  };
  ```
- `PBXFileReference`:
  ```
  000000000000000000000081 /* CheckStitchWidget.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = CheckStitchWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; };
  ```
- `PBXFileSystemSynchronizedRootGroup`:
  ```
  000000000000000000000080 /* CheckStitchWidget */ = {
      exceptions = (0000000000000000000000A2 /* Exceptions for "CheckStitchWidget" folder in "CheckStitchWidget" target */,);
      isa = PBXFileSystemSynchronizedRootGroup;
      path = CheckStitchWidget;
      sourceTree = "<group>";
  };
  ```
- `PBXFileSystemSynchronizedBuildFileExceptionSet` (keep `Info.plist` from being
  copied as a resource; mirrors the app's `Info.plist` exception):
  ```
  0000000000000000000000A2 /* Exceptions for "CheckStitchWidget" folder in "CheckStitchWidget" target */ = {
      isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
      membershipExceptions = (Info.plist,);
      target = 000000000000000500000000 /* CheckStitchWidget */;
  };
  ```
- `PBXFrameworksBuildPhase`: new `000000000000000521000000` with
  `000000000000000000000065`.
- `PBXGroup` (root `...000001`) children: add `000000000000000000000080`.
  `Products` group children: add `000000000000000000000081`.
- `PBXNativeTarget`:
  ```
  000000000000000500000000 /* CheckStitchWidget */ = {
      isa = PBXNativeTarget;
      buildConfigurationList = 000000000000000510000000 /* Build configuration list for PBXNativeTarget "CheckStitchWidget" */;
      buildPhases = (
          000000000000000520000000 /* Sources */,
          000000000000000521000000 /* Frameworks */,
          000000000000000522000000 /* Resources */,
      );
      buildRules = ();
      dependencies = ();
      fileSystemSynchronizedGroups = (000000000000000000000080 /* CheckStitchWidget */,);
      name = CheckStitchWidget;
      packageProductDependencies = (000000000000000000000031 /* CheckStitchCore */,);
      productName = CheckStitchWidget;
      productReference = 000000000000000000000081 /* CheckStitchWidget.appex */;
      productType = "com.apple.product-type.app-extension";
  };
  ```
  Add empty `PBXSourcesBuildPhase` `...520000000` and `PBXResourcesBuildPhase`
  `...522000000` (both `files = ();`).
- App target (`...100000000`): add `000000000000000160000000` to `buildPhases`
  (after `Embed Watch Content`) and `000000000000000500000001` to `dependencies`.
- `PBXProject.TargetAttributes`: add
  `000000000000000500000000 = { CreatedOnToolsVersion = 26.3; };`.
- `PBXProject.targets`: append `000000000000000500000000 /* CheckStitchWidget */`.
- `XCBuildConfiguration` Debug `...511000000` and Release `...512000000` for the
  widget target (same body both):
  ```
  CODE_SIGN_STYLE = Automatic;
  "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]" = CheckStitchWidget/CheckStitchWidget.entitlements;
  "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = CheckStitchWidget/CheckStitchWidget.entitlements;
  CURRENT_PROJECT_VERSION = 1;
  DEVELOPMENT_TEAM = 6NWX2DHB9Q;
  GENERATE_INFOPLIST_FILE = YES;
  INFOPLIST_FILE = CheckStitchWidget/Info.plist;
  INFOPLIST_KEY_CFBundleDisplayName = CheckStitch;
  INFOPLIST_KEY_NSRemindersFullAccessUsageDescription = "CheckStitch needs access to create reminders.";
  INFOPLIST_KEY_NSRemindersUsageDescription = "CheckStitch needs access to create reminders.";
  IPHONEOS_DEPLOYMENT_TARGET = 18.7;
  LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
  LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
  MARKETING_VERSION = 1.0;
  PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitch.widget;
  PRODUCT_NAME = "$(TARGET_NAME)";
  REGISTER_APP_GROUPS = YES;
  SDKROOT = iphoneos;
  SKIP_INSTALL = YES;
  STRING_CATALOG_GENERATE_SYMBOLS = YES;
  SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
  SWIFT_APPROACHABLE_CONCURRENCY = YES;
  SWIFT_EMIT_LOC_STRINGS = YES;
  SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
  SWIFT_VERSION = 6.0;
  TARGETED_DEVICE_FAMILY = "1,2";
  ```
  Do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` on this target: WidgetKit's
  `TimelineProvider`/`AppIntentTimelineProvider` requirements are nonisolated and
  a MainActor default would make conformances fail. Use explicit `@MainActor` in
  the extension code instead.
- `XCConfigurationList` `000000000000000510000000` referencing the two configs.

> `REGISTER_APP_GROUPS = YES` may require `-allowProvisioningUpdates` for device
> builds; the unsigned simulator `widget-build` leg and `make build` are not
> affected (same as the app target today).

#### 7. `CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitchWidget.xcscheme`
**Action**: create. Copy `CheckStitchWatch.xcscheme` verbatim and substitute the
blueprint:
- `BlueprintIdentifier = "000000000000000500000000"`
- `BuildableName = "CheckStitchWidget.appex"`
- `BlueprintName = "CheckStitchWidget"`

#### 8. `Makefile`
**Action**: modify.

- Add `WIDGET_SCHEME := CheckStitchWidget` and `WIDGET_SIM := generic/platform=iOS Simulator`
  near `WATCH_SCHEME`.
- Add `widget-build` to `.PHONY`.
- Add the recipe (mirrors `watch-build`):
  ```make
  widget-build:
  	xcodebuild -scheme '$(WIDGET_SCHEME)' \
  	  -destination '$(WIDGET_SIM)' \
  	  -configuration '$(CONFIGURATION)' \
  	  -derivedDataPath '$(DERIVED_DATA)' \
  	  $(WARNINGS_AS_ERRORS) \
  	  build
  ```

#### 9. `scripts/test.sh`
**Action**: modify. After `make watch-build`, add:
```bash
# The widget extension is a second iOS-only product; compile it here so a broken
# pbxproj/widget scheme edit fails the gate.
make widget-build
```

#### 10. `scripts/tests/run.sh`
**Action**: modify the pin only (comment says "Later phases append their leg here"):
```bash
WARNINGS_AS_ERRORS_LEGS=(build-mac build test-unit test-ui watch-build widget-build)
```
The existing `warnings_as_errors_reaches_compiling_legs` case drives
`make widget-build` with a stubbed `xcodebuild`, so the Makefile recipe must keep
`$(WARNINGS_AS_ERRORS)`.

#### 11. `CheckStitchTests/ChecklistWidgetDisplayModelTests.swift`
**Action**: create.

```swift
import CheckStitchCore
import Foundation
import Testing

struct ChecklistWidgetDisplayModelTests {
    @Test
    func configuredChecklistBecomesARunnableRow() {
        let checklist = Checklist(name: "Groceries")
        let model = ChecklistWidgetDisplayModel(
            checklists: [checklist],
            configuration: [ChecklistEntity(checklist)],
            access: .ready)
        #expect(model.rows.map(\.name) == ["Groceries"])
        #expect(model.rows.first?.isRunnable == true)
        #expect(model.rows.first?.needsAccess == false)
    }

    @Test
    func emptyChecklistsProduceNoRows() {
        let model = ChecklistWidgetDisplayModel(
            checklists: [], configuration: [], access: .ready)
        #expect(model.rows.isEmpty)
    }
}
```

### Verification
#### Automated
- [x] `make test-unit` passes (`ChecklistWidgetDisplayModelTests` green)
- [x] `make widget-build` passes with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`
- [x] `make build` passes and `DerivedData/Build/Products/Debug-iphonesimulator/CheckStitch.app/PlugIns/CheckStitchWidget.appex` exists
- [x] `make build-mac` passes (extension skipped on macOS via `platformFilter = ios`)
- [x] `bash scripts/tests/run.sh` passes (`warnings_as_errors_reaches_compiling_legs` includes `widget-build`)

#### Manual
- [ ] `make run`; press the simulator Home button, long-press the Home Screen,
      tap **+** → **CheckStitch** → add the small widget. It shows the first
      checklist's name.
- [ ] Tap the run button. Reminders should appear in Reminders → CheckStitch
      **without CheckStitch coming to the foreground** (foreground the app only
      afterwards to confirm, and check the free-run counter is not stuck).

---

## Phase 2 — Choose which checklist (small widget config)

The small widget gets an `AppIntentConfiguration`; the user picks the checklist
in the widget's edit UI.

### Changes

#### 1. `CheckStitchCore/Sources/CheckStitchCore/ChecklistConfigurationIntent.swift`
**Action**: create.

```swift
import AppIntents

public struct ChecklistConfigurationIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Checklist"
    public static let description = IntentDescription("Pick the checklist this widget runs.")

    @Parameter(title: "Checklist")
    public var checklist: ChecklistEntity?

    public init() {}
}
```

#### 2. `CheckStitchWidget/SingleChecklistWidget.swift`
**Action**: modify.

- `SingleChecklistProvider` changes from `TimelineProvider` to
  `AppIntentTimelineProvider`:
  ```swift
  struct SingleChecklistProvider: AppIntentTimelineProvider {
      func placeholder(in context: Context) -> ChecklistEntry { /* as Phase 1 */ }

      func snapshot(for configuration: ChecklistConfigurationIntent, in context: Context) async -> ChecklistEntry {
          let model = await MainActor.run {
              ChecklistWidgetLoader.load(configuration: configuration.checklist.map { [$0] } ?? [])
          }
          return ChecklistEntry(date: .now, model: model)
      }

      func timeline(for configuration: ChecklistConfigurationIntent, in context: Context) async -> Timeline<ChecklistEntry> {
          let model = await MainActor.run {
              ChecklistWidgetLoader.load(configuration: configuration.checklist.map { [$0] } ?? [])
          }
          return Timeline(entries: [ChecklistEntry(date: .now, model: model)],
                          policy: .after(.now.addingTimeInterval(15 * 60)))
      }
  }
  ```
- `SingleChecklistWidget` switches `StaticConfiguration` →
  `AppIntentConfiguration(kind:intent:provider:)` with
  `intent: ChecklistConfigurationIntent.self`.

#### 3. `CheckStitchTests/ChecklistWidgetDisplayModelTests.swift`
**Action**: modify — add:

```swift
@Test
func selectedEntityResolvesToItsRowWhateverTheStoreOrder() {
    let groceries = Checklist(name: "Groceries")
    let packing = Checklist(name: "Packing")
    let model = ChecklistWidgetDisplayModel(
        checklists: [groceries, packing],
        configuration: [ChecklistEntity(packing)],
        access: .ready)
    #expect(model.rows.map(\.name) == ["Packing"])
}

@Test
func ghostEntityProducesNoRows() {
    let model = ChecklistWidgetDisplayModel(
        checklists: [Checklist(name: "Groceries")],
        configuration: [ChecklistEntity(id: UUID().uuidString, name: "Deleted")],
        access: .ready)
    #expect(model.rows.isEmpty)
}
```

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make widget-build` passes

#### Manual
- [ ] `make run`; long-press the placed small widget → **Edit Widget** → choose a
      checklist; it renders that checklist and its run button creates its
      reminders.

---

## Phase 3 — Large widget with per-row run buttons

A `systemLarge` widget picks several checklists; each row runs independently
(one run-gate slot per tap).

### Changes

#### 1. `CheckStitchCore/Sources/CheckStitchCore/MultiChecklistConfigurationIntent.swift`
**Action**: create.

```swift
import AppIntents

public struct MultiChecklistConfigurationIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Checklists"
    public static let description = IntentDescription("Pick the checklists this widget runs.")

    @Parameter(title: "Checklists")
    public var checklists: [ChecklistEntity]

    public init() {}
}
```

#### 2. `CheckStitchWidget/MultiChecklistWidget.swift`
**Action**: create.

```swift
import CheckStitchCore
import SwiftUI
import WidgetKit

struct MultiChecklistProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry { /* Phase 1 preview */ }

    func snapshot(for configuration: MultiChecklistConfigurationIntent, in context: Context) async -> ChecklistEntry {
        let model = await MainActor.run {
            ChecklistWidgetLoader.load(configuration: configuration.checklists)
        }
        return ChecklistEntry(date: .now, model: model)
    }

    func timeline(for configuration: MultiChecklistConfigurationIntent, in context: Context) async -> Timeline<ChecklistEntry> {
        let model = await MainActor.run {
            ChecklistWidgetLoader.load(configuration: configuration.checklists)
        }
        return Timeline(entries: [ChecklistEntry(date: .now, model: model)],
                        policy: .after(.now.addingTimeInterval(15 * 60)))
    }
}

struct MultiChecklistWidget: Widget {
    static let kind = "MultiChecklistWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: MultiChecklistConfigurationIntent.self,
                               provider: MultiChecklistProvider()) { entry in
            MultiChecklistWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CheckStitch Checklists")
        .description("Run any of your checklists without opening the app.")
        .supportedFamilies([.systemLarge])
    }
}

struct MultiChecklistWidgetView: View {
    let entry: ChecklistEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entry.model.rows) { row in
                HStack {
                    Text(row.name).font(.body).lineLimit(1)
                    Spacer()
                    if row.isRunnable {
                        Button(intent: runIntent(for: row)) {
                            Image(systemName: "play.circle.fill")
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "exclamationmark.triangle").font(.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor
    private func runIntent(for row: ChecklistWidgetRow) -> RunChecklistIntent {
        var intent = RunChecklistIntent()
        intent.checklist = ChecklistEntity(id: row.entityID, name: row.name)
        return intent
    }
}
```

`ChecklistWidgetDisplayModel` already caps `configuration` to `rowLimit` (Phase 1)
and preserves configuration order — no Core change needed.

#### 3. `CheckStitchWidget/ChecklistWidgetBundle.swift`
**Action**: modify — add `MultiChecklistWidget()` to `body`.

#### 4. `CheckStitchTests/ChecklistWidgetDisplayModelTests.swift`
**Action**: modify — add:

```swift
@Test
func configurationOrderIsPreservedAndMissingEntitiesAreDropped() {
    let a = Checklist(name: "A")
    let b = Checklist(name: "B")
    let c = Checklist(name: "C")
    let model = ChecklistWidgetDisplayModel(
        checklists: [a, b, c],
        configuration: [ChecklistEntity(c), ChecklistEntity(id: UUID().uuidString, name: "Ghost"), ChecklistEntity(a)],
        access: .ready)
    #expect(model.rows.map(\.name) == ["C", "A"])
}

@Test
func rowsAreCappedToTheRowBudget() {
    let checklists = (0..<9).map { Checklist(name: "List \($0)") }
    let model = ChecklistWidgetDisplayModel(
        checklists: checklists,
        configuration: checklists.map(ChecklistEntity.init),
        access: .ready)
    #expect(model.rows.count == ChecklistWidgetDisplayModel.rowLimit)
    #expect(model.rows.map(\.name) == (0..<ChecklistWidgetDisplayModel.rowLimit).map { "List \($0)" })
}
```

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make widget-build` passes

#### Manual
- [ ] `make run`; add the large widget, edit it to select three checklists —
      three ordered rows render.
- [ ] Tap each row's button in turn; each tap creates only that checklist's
      reminders, and no other row's reminders.
- [ ] Confirm a 7th/8th selected checklist is not rendered (row budget).

---

## Phase 4 — Access and purchase states

When Reminders access is not `.fullAccess` (or the free-run limit is reached
without a license), the widget renders a non-interactive "open app to enable"
state whose `widgetURL` launches CheckStitch. The interactive button never shows
the intent's dialog.

### Changes

#### 1. `CheckStitchWidget/SingleChecklistWidget.swift` and `MultiChecklistWidget.swift`
**Action**: modify.

- Extend `ChecklistWidgetLoader.accessState()` to fold purchase state:
  ```swift
  static func accessState() -> ChecklistWidgetAccessState {
      switch EventKitReminderDestination.shared.accessStatus() {
      case .fullAccess:
          let unlocked = PurchaseEntitlementCache(defaults: AppGroup.defaults).isVerified
          let used = RunCounter(defaults: AppGroup.defaults).count
          return (!unlocked && used >= RunGate.freeRunLimit) ? .needsPurchase : .ready
      case .notDetermined, .denied:
          return .needsAccess
      }
  }
  ```
- Views: when `entry.model.rows` contains a non-runnable row, render the row with
  the enable copy and attach `.widgetURL(URL(string: "checkstitch://"))` to the
  row/widget; the runnable path keeps `Button(intent:)` only. Example (single):
  ```swift
  if row.isRunnable {
      Button(intent: runIntent(for: row)) { ... }
  } else {
      Label(enableCopy, systemImage: "exclamationmark.triangle")
          .font(.caption)
  }
  ```
  and on the widget's root view: `.widgetURL(row.needsAccess ? URL(string: "checkstitch://") : nil)`.
- The `ChecklistWidgetDisplayModel` already forces `isRunnable = false` /
  `needsAccess = true` for any non-`.ready` state — no Core change needed.

#### 2. `CheckStitch/Info.plist`
**Action**: modify. `widgetURL("checkstitch://")` only opens the app if the scheme
is registered. Add:
```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>app.alanvardy.CheckStitch</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>checkstitch</string>
			</array>
		</dict>
	</array>
```
`ContentView`'s existing `.onOpenURL` forwards it to `SharedImportInbox`, which
ignores non-file URLs — no code change required.

#### 3. `CheckStitchTests/ChecklistWidgetDisplayModelTests.swift`
**Action**: modify — add:

```swift
@Test(arguments: [ChecklistWidgetAccessState.needsAccess, .needsPurchase])
func nonReadyAccessMakesEveryRowNonRunnable(_ access: ChecklistWidgetAccessState) {
    let checklist = Checklist(name: "Groceries")
    let model = ChecklistWidgetDisplayModel(
        checklists: [checklist],
        configuration: [ChecklistEntity(checklist)],
        access: access)
    #expect(model.rows.allSatisfy { !$0.isRunnable && $0.needsAccess })
}

@Test
func readyAccessMakesRowsRunnable() {
    let checklist = Checklist(name: "Groceries")
    let model = ChecklistWidgetDisplayModel(
        checklists: [checklist],
        configuration: [ChecklistEntity(checklist)],
        access: .ready)
    #expect(model.rows.allSatisfy { $0.isRunnable && !$0.needsAccess })
}
```

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make widget-build` passes

#### Manual
- [ ] `make run`; Settings → Privacy & Security → Reminders → turn CheckStitch
      off. The widget renders the "open app" state on both sizes.
- [ ] Tap the widget body: CheckStitch launches to the foreground.
- [ ] Re-enable access; the widget returns to a runnable state (may need a
      timeline refresh — remove/re-add or wait).

---

## Phase 5 — Hardening, empty states, localization

Unconfigured/empty widgets, refresh policy, gallery metadata and previews, and
complete localization so the gate's l10n and shellcheck legs stay green.

### Changes

#### 1. `CheckStitchWidget/*` (views + bundle)
**Action**: modify.

- Empty/unconfigured state: when `entry.model.rows.isEmpty`, render a hint
  ("No checklists" or "Edit this widget to pick a checklist") instead of an empty
  container, on both widgets. Both strings come from the widget catalog.
- Gallery metadata: `configurationDisplayName` / `description` keys live in the
  widget catalog (already used in Phases 1/3); ensure they are the catalog keys.
- Previews: add `#Preview(as: .systemSmall)` / `#Preview(as: .systemLarge)`
  blocks with a `ChecklistEntry` built from a `ChecklistWidgetDisplayModel` over
  sample checklists (no store/EventKit).
- Refresh policy: keep `.after(.now.addingTimeInterval(15 * 60))` on both
  providers.

#### 2. `CheckStitchWidget/Localizable.xcstrings`
**Action**: create. Add every extension-facing key, all six languages
(`en`, `de`, `es`, `fr`, `ja`, `zh-Hans`) — see the `localization` skill; a new
key needs all languages before `scripts/l10n-check.sh` passes:

| Key |
|---|
| `CheckStitch Checklist` |
| `CheckStitch Checklists` |
| `Run a checklist without opening the app.` |
| `Run any of your checklists without opening the app.` |
| `Checklist` |
| `Checklists` |
| `Pick the checklist this widget runs.` |
| `Pick the checklists this widget runs.` |
| `Create reminders` |
| `Open CheckStitch to enable` |
| `Open CheckStitch to buy a license` |
| `No checklists` |
| `Edit this widget to pick a checklist` |

#### 3. `scripts/l10n-check.sh`
**Action**: modify — add the widget catalog to `CATALOGS`:
```python
    "Widget": Path("CheckStitchWidget/Localizable.xcstrings"),
```

#### 4. `CheckStitchTests/LocalizationTestHelpers.swift`
**Action**: modify — add to `Catalogs.all`:
```swift
        ("Widget", repoRoot.appendingPathComponent("CheckStitchWidget/Localizable.xcstrings")),
```

#### 5. `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify.
- `guardedCatalogs`: add `"Widget"`.
- `requiredKeys`: add a `("Widget", [...])` entry listing every key from step 2.

#### 6. `scripts/tests/run.sh`
**Action**: modify — the `WARNINGS_AS_ERRORS_LEGS` list already contains
`widget-build` from Phase 1; no further edit unless a shell-space pin is added.
Run `shellcheck scripts/*.sh scripts/tests/*.sh` to confirm the script edits parse.

### Verification
#### Automated
- [x] `scripts/l10n-check.sh` prints `ok` with the Widget catalog included
- [x] `make test-unit` passes (`LocalizationTests` + all widget display-model tests)
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` clean
- [x] `bash scripts/tests/run.sh` passes
- [x] `./scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Add an unconfigured widget: the empty-state hint renders, no crash.
- [ ] Widget gallery shows the display name, description, and previews for both
      sizes.
- [ ] Delete all checklists in the app; the widget shows the empty state within
      the refresh window.
- [ ] Switch the app language (Settings → Language); the widget strings follow on
      the next timeline refresh.

---

## Deviations from `structure.md` (and why)

1. **`PurchaseEnvironment` seam added to Core (Phase 0).** `ChecklistReminders.productionGate()`
   and the moved `RunChecklistIntent` depend on the app-target `PurchaseEnvironment.service`
   (StoreKit). Structure's move list did not account for it. Resolved by moving the
   holder to Core with a StoreKit-free `CachedEntitlementProvider` default and
   injecting the StoreKit-backed service from `MyApp.init()` — the app/Siri path
   keeps its current behaviour; a cold extension process resolves the durable
   `PurchaseEntitlementCache` without linking StoreKit (preserving
   `CheckStitchCore`'s deliberate StoreKit-free watchOS compile).
2. **`CheckStitchWidget/Info.plist` added (Phase 1).** `NSExtension` is a nested
   dict that `INFOPLIST_KEY_*` cannot generate; the widget target needs it and a
   synchronized-group exception to keep it out of the resources phase.
3. **Widget target deliberately omits `SWIFT_DEFAULT_ACTOR_ISOLATION`.** The app
   target sets `MainActor`, but `TimelineProvider`/`AppIntentTimelineProvider`
   requirements are nonisolated; the extension opts into `@MainActor` explicitly
   (same convention as the test targets).
4. **`ChecklistWidgetDisplayModel` is nonisolated/pure**, not `@MainActor` as the
   design text suggested: it takes already-loaded `[Checklist]` (Sendable) and is
   therefore testable without a main actor. Only `ChecklistWidgetLoader` (which
   reads the store/EventKit) is `@MainActor`.
5. **Test import fixups limited to two files** (`AppGroupTests`,
   `EventKitReminderDestinationTests`) — the only suites touching moved symbols
   without an existing `CheckStitchCore` import.
6. **Widget catalog wired into `l10n-check.sh` and `LocalizationTestHelpers.Catalogs.all`**
   (structure only said "extension `Localizable.xcstrings` + `LocalizationFixtures`"):
   every other catalog is guarded by both, and an unguarded new catalog would let
   a missing translation ship.