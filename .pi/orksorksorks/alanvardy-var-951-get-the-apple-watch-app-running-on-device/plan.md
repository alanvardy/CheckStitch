# Implementation Plan

## Overview

Add a **companion** `CheckStitchWatch` target (`WKWatchOnly = NO`, embedded in
`CheckStitch.app`) that is a pure WatchConnectivity client: the phone owns
EventKit and the checklist store, pushes its set via
`updateApplicationContext`, and the watch lists checklists, shows their items
read-only, and offers one action — **"Create reminders"** — which runs the
existing phone-side reminder write. All new logic lands in `CheckStitchCore` as
plain host-testable types; the watch target, `WCSession` adapters and pbxproj
stay thin and are verified by compile + manual smoke.

**Confirmed decisions (asked and answered before this plan):**
- **D1** — keep the read-only item detail screen before the "Create reminders"
  button (`design.md` decision 6).
- **D2** — resolve the watchOS `save(_:commit:)` unavailability with a one-line
  `#if !os(watchOS)` guard inside the phone-only `EventKitReminderCreator`;
  do **not** split the package.

**Deviations from `structure.md` (see "Deviations" at the end for the full list):**
1. Stage 1 must add `import CheckStitchCore` to **five** app files (structure
   named only `ChecklistStore`/`ChecklistDetailView`) and to the two XCTest
   suites that import `@testable import CheckStitch`.
2. Stage 1 must add `#if !os(watchOS)` to `EventKitReminderCreator.create`
   (D2) — verified: it is the only symbol in the package unavailable on
   watchOS.
3. Stage 4 must add `CheckStitchWatch/WatchSyncAdapter.swift` — the
   watch-side transport the structure implies but never lists.
4. `ChecklistSyncCoordinator` takes `snapshot: () -> [Checklist]`, not
   `() -> ChecklistEnvelope` (the real `ChecklistCodec` API is
   `encode(_ checklists: [Checklist]) throws`).
5. `make watch-build` keeps `ASSETCATALOG_COMPILER_APPICON_NAME` unset until an
   asset catalog exists (avoids a missing-appicon warning/Release error).

---

## Phase 1: Shared model in `CheckStitchCore`

Green tests prove the merged envelope is still byte-compatible with the payload
`ChecklistStore` already persists under `checklists.v1`.

### Changes

#### 1. New `Checklist.swift` in Core

**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: create

Full contents (merged from `CheckStitch/Checklist.swift` + Core's
`ChecklistItem.swift`; `isBlank` is computed, so the wire format is unchanged):

```swift
import Foundation
import os

/// Editable row model for a checklist item. The ID is stable so rows can be
/// added, removed, and edited without conflating duplicate titles.
public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }

    public let id: UUID
    public var title: String

    /// A title that is empty or whitespace/newlines only. Creation skips these
    /// so an emptied row can't produce a meaningless reminder.
    public var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A named collection of items that can be turned into reminders.
public struct Checklist: Identifiable, Codable, Hashable, Sendable {
    public init(id: UUID = UUID(), name: String = "New checklist", items: [ChecklistItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }

    public let id: UUID
    public var name: String
    public var items: [ChecklistItem]
}

/// Versioned wire format for the App Group payload. The version field exists so
/// VAR-963 can evolve decoding instead of silently mis-reading old data.
public struct ChecklistEnvelope: Codable, Sendable {
    public init(version: Int, checklists: [Checklist]) {
        self.version = version
        self.checklists = checklists
    }

    public var version: Int
    public var checklists: [Checklist]
}

public enum ChecklistCodec {
    public static let currentVersion = 1

    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistCodec")

    /// How a stored payload relates to the version this build understands.
    public enum Outcome: Equatable {
        case loaded([Checklist])
        /// Written by a future version whose shape is unknown.
        case unsupportedVersion
        /// Garbage that is safe to replace.
        case unreadable
    }

    public static func encode(_ checklists: [Checklist]) throws -> Data {
        try JSONEncoder().encode(ChecklistEnvelope(version: currentVersion, checklists: checklists))
    }

    /// Classifies a payload — never a crash, never a partial decode.
    public static func classify(_ data: Data) -> Outcome {
        do {
            let envelope = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
            guard envelope.version == currentVersion else {
                logger.error("Unsupported checklist payload version \(envelope.version, privacy: .public); treating as empty")
                return .unsupportedVersion
            }
            return .loaded(envelope.checklists)
        } catch {
            logger.error("Failed to decode checklist payload: \(error.localizedDescription, privacy: .public)")
            return .unreadable
        }
    }

    /// Convenience for readers that only need the values.
    public static func decode(_ data: Data) -> [Checklist] {
        if case .loaded(let checklists) = classify(data) { return checklists }
        return []
    }
}
```

#### 2. Delete the two relocated files

**File**: `CheckStitch/Checklist.swift`
**Action**: delete (its four types now live in Core).

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistItem.swift`
**Action**: delete (merged into `Checklist.swift` above).

#### 3. `CheckStitchCore/Package.swift` — add watchOS

**File**: `CheckStitchCore/Package.swift`
**Action**: modify

```swift
    platforms: [
        .iOS("18.7"),
        .macOS("27.0"),
        .watchOS("27.0"),
    ],
```

#### 4. `EventKitReminderCreator` — watchOS guard (D2)

**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderCreating.swift`
**Action**: modify

`EKEventStore.save(_:commit:)` is `@available(watchOS, unavailable)`; this is
the **only** package symbol that fails to compile for watchOS (verified with
`swiftc -typecheck -target arm64-apple-watchos27.0`). The watch never
instantiates this phone-only adapter.

```swift
    public func create(title: String) async throws {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        // watchOS EventKit is read-only; the watch never reaches this adapter.
        #if !os(watchOS)
            try eventStore.save(reminder, commit: true)
        #endif
    }
```

#### 5. App consumers import the package

**Files** (action: modify — add `import CheckStitchCore`):
- `CheckStitch/ChecklistStore.swift` (uses `Checklist`, `ChecklistItem`, `ChecklistCodec.classify`)
- `CheckStitch/ChecklistDetailView.swift` (uses `checklist.items`)
- `CheckStitch/ChecklistReminders.swift` (takes `Checklist`)
- `CheckStitch/ContentView.swift` (takes `Checklist` in `checklistRow(for:)`)
- `CheckStitch/MyApp.swift` (`onChange(of: store.checklists)` needs `Checklist: Hashable` visible)

Safe despite the app target's own `AppearanceMode`/`ChecklistWidth`: verified by
experiment that a declaration in the current module **shadows** an imported
one, so `ContentView.swift`'s `AppearanceMode.system` and
`ChecklistWidth.maxContentWidth(...)` keep resolving to the app-local types.
No qualification or rename is needed.

#### 6. Test import updates

**Files** (action: modify — add `import CheckStitchCore` below the existing
`@testable import CheckStitch`):
- `CheckStitchTests/ChecklistCodecTests.swift`
- `CheckStitchTests/ChecklistStoreTests.swift`

(`ChecklistItemTests.swift`, `TestFixtures.swift` already import
`CheckStitchCore`.)

#### 7. Tests

**File**: `CheckStitchTests/ChecklistItemTests.swift`
**Action**: modify — add `isBlank` and Codable cases:

```swift
    @Test(arguments: ["", " ", "\t", "\n", "  \n "])
    func blankTitlesAreBlank(_ title: String) {
        #expect(ChecklistItem(title: title).isBlank)
    }

    @Test(arguments: ["x", " x ", "0"])
    func nonBlankTitlesAreNotBlank(_ title: String) {
        #expect(!ChecklistItem(title: title).isBlank)
    }

    @Test
    func codableRoundTripPreservesIdentity() throws {
        let item = ChecklistItem(title: "one")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ChecklistItem.self, from: data)
        #expect(decoded == item)
        #expect(decoded.id == item.id)
    }
```

**File**: `CheckStitchTests/ChecklistCodecTests.swift`
**Action**: modify — add the wire-compatibility regression case:

```swift
    func testV1PayloadWithoutIsBlankStillDecodes() {
        let id = UUID().uuidString
        let data = Data(#"{"version":1,"checklists":[{"id":"\#(UUID().uuidString)","name":"x","items":[{"id":"\#(id)","title":"Milk"}]}]}"#.utf8)

        let decoded = ChecklistCodec.decode(data)
        XCTAssertEqual(decoded.first?.items.first?.title, "Milk")
        XCTAssertFalse(decoded.first?.items.first?.isBlank ?? true)
    }
```

### Verification

#### Automated
- [x] `make test-unit` passes (existing `ChecklistCodecTests`, `ChecklistItemTests`, `ChecklistStoreTests` + the new cases)
- [x] `make build` passes — the iOS slice compiles with the package import added
- [x] `make build-mac` passes — proves the package still compiles off-iOS
- [x] `bash -c 'SDK=$(xcrun --sdk watchos --show-sdk-path); xcrun swiftc -typecheck -target arm64-apple-watchos27.0 -sdk "$SDK" CheckStitchCore/Sources/CheckStitchCore/*.swift'` reports no errors

#### Manual
- [ ] Run the app on the simulator, create a checklist with items, kill and relaunch: items and names persist (wire format unchanged)

---

## Phase 2: Sync contract + watch state machine (`CheckStitchCore`)

### Changes

#### 1. New `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: create

```swift
import Foundation

/// `WCSession` dictionary keys. Shared so both adapters and the tests agree.
public enum ChecklistSyncKey {
    public static let context = "checklists"
    public static let runChecklist = "runChecklist"
    public static let requestChecklists = "requestChecklists"
}

/// The two directions of the watch protocol. `UUID` is not a plist type, so it
/// travels as its `uuidString`.
public enum ChecklistSyncMessage: Equatable, Sendable {
    /// Phone → watch, via `updateApplicationContext` (latest state wins).
    case context(Data)
    /// Watch → phone, via `transferUserInfo` (queued command).
    case runChecklist(UUID)
    /// Watch → phone, via `transferUserInfo` (cold launch re-push request).
    case requestChecklists

    public init?(userInfo: [String: Any]) {
        if let data = userInfo[ChecklistSyncKey.context] as? Data {
            self = .context(data)
        } else if let raw = userInfo[ChecklistSyncKey.runChecklist] as? String,
                  let id = UUID(uuidString: raw) {
            self = .runChecklist(id)
        } else if userInfo[ChecklistSyncKey.requestChecklists] as? Bool == true {
            self = .requestChecklists
        } else {
            return nil
        }
    }

    public var userInfo: [String: Any] {
        switch self {
        case .context(let data):
            [ChecklistSyncKey.context: data]
        case .runChecklist(let id):
            [ChecklistSyncKey.runChecklist: id.uuidString]
        case .requestChecklists:
            [ChecklistSyncKey.requestChecklists: true]
        }
    }
}

/// The seam both adapters (phone and watch) implement and the tests fake.
@MainActor
public protocol ChecklistSyncTransport: AnyObject {
    var onMessage: ((ChecklistSyncMessage) -> Void)? { get set }
    func activate()
    func sendContext(_ data: Data)
    func sendUserInfo(_ message: ChecklistSyncMessage)
}

/// The watch's observable state: a mirror of the phone's checklist set, plus
/// the last run requested. It never touches EventKit.
@MainActor
@Observable
public final class WatchChecklistStore {
    public init(transport: ChecklistSyncTransport) {
        self.transport = transport
    }

    public private(set) var checklists: [Checklist] = []
    public private(set) var pendingRunID: UUID?

    /// Activates the transport and starts listening. Safe to call repeatedly.
    public func start() {
        transport.onMessage = { [weak self] in self?.receive($0) }
        transport.activate()
    }

    /// Asks the phone to create reminders for `checklist` and remembers it.
    public func run(_ checklist: Checklist) {
        pendingRunID = checklist.id
        transport.sendUserInfo(.runChecklist(checklist.id))
    }

    /// Cold launch: the phone re-pushes its context on receipt.
    public func requestRefresh() {
        transport.sendUserInfo(.requestChecklists)
    }

    private func receive(_ message: ChecklistSyncMessage) {
        switch message {
        case .context(let data):
            // Malformed or future-version payloads leave the previous list intact.
            if case .loaded(let decoded) = ChecklistCodec.classify(data) {
                checklists = decoded
            }
        case .runChecklist, .requestChecklists:
            break // phone-only directions
        }
    }

    private let transport: ChecklistSyncTransport
}
```

#### 2. Test fixture transport

**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify — append:

```swift
/// Records everything the store/coordinator sends and lets tests inject inbound
/// messages, standing in for `WCSession`.
@MainActor
final class FakeChecklistSyncTransport: ChecklistSyncTransport {
    var onMessage: ((ChecklistSyncMessage) -> Void)?
    private(set) var activateCount = 0
    private(set) var sentContexts: [Data] = []
    private(set) var sentMessages: [ChecklistSyncMessage] = []

    func activate() { activateCount += 1 }
    func sendContext(_ data: Data) { sentContexts.append(data) }
    func sendUserInfo(_ message: ChecklistSyncMessage) { sentMessages.append(message) }

    func deliver(_ message: ChecklistSyncMessage) { onMessage?(message) }
}
```

#### 3. Tests

**File**: `CheckStitchTests/ChecklistSyncMessageTests.swift`
**Action**: create — Swift Testing struct (no `@MainActor` needed; the enum is
`Sendable` and `init?`/`userInfo` are nonisolated):

```swift
@testable import CheckStitchCore
import Foundation
import Testing

struct ChecklistSyncMessageTests {
    @Test
    func contextRoundTripsThroughUserInfo() {
        let data = Data("hello".utf8)
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.context(data).userInfo) == .context(data))
    }

    @Test
    func runChecklistRoundTripsThroughUserInfo() {
        let id = UUID()
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.runChecklist(id).userInfo) == .runChecklist(id))
    }

    @Test
    func requestChecklistsRoundTripsThroughUserInfo() {
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.requestChecklists.userInfo) == .requestChecklists)
    }

    @Test
    func unknownKeyIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: ["nonsense": true]) == nil)
    }

    @Test
    func wrongValueTypeIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.runChecklist: 42]) == nil)
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.context: "not data"]) == nil)
    }
}
```

**File**: `CheckStitchTests/WatchChecklistStoreTests.swift`
**Action**: create — `@MainActor` on the suite (touches the `@MainActor` store):

```swift
@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct WatchChecklistStoreTests {
    @Test
    func startActivatesTransport() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        #expect(transport.activateCount == 1)
    }

    @Test
    func contextReplacesTheChecklistList() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        let expected = [Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")])]
        transport.deliver(.context(try ChecklistCodec.encode(expected)))

        #expect(store.checklists == expected)
    }

    @Test
    func malformedContextLeavesThePreviousListIntact() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        let expected = [Checklist(name: "Groceries")]
        transport.deliver(.context(try ChecklistCodec.encode(expected)))
        transport.deliver(.context(Data("not json".utf8)))

        #expect(store.checklists == expected)
    }

    @Test
    func runSendsExactlyOneRunRequestAndRecordsIt() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")

        store.run(checklist)

        #expect(transport.sentMessages == [.runChecklist(checklist.id)])
        #expect(store.pendingRunID == checklist.id)
    }

    @Test
    func requestRefreshAsksThePhoneToResend() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)

        store.requestRefresh()

        #expect(transport.sentMessages == [.requestChecklists])
    }
}
```

### Verification

#### Automated
- [x] `make test-unit` passes — the whole sync contract is proven on the macOS host before any watch target exists
- [x] `make build-mac` passes (Core compiles off-iOS with the new file)

#### Manual
- [ ] None — pure host-tested logic

---

## Phase 3: Watch target + build scaffolding

The riskiest layer (hand-edited pbxproj) lands alone, with a minimal shell app.
Verification is a compile of every affected target.

### Changes

#### 1. Minimal watch app shell

**File**: `CheckStitchWatch/CheckStitchWatchApp.swift`
**Action**: create

```swift
import SwiftUI

@main
struct CheckStitchWatchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("CheckStitch")
        }
    }
}
```

#### 2. `CheckStitch.xcodeproj/project.pbxproj`

**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify

Uses new synthetic IDs in the project's existing `000…` scheme. Add each block
to its section (locations are noted), then wire the three cross-references.

New IDs used below:
`target=…0400000000`, `configList=…0410000000`, `Debug=…0411000000`,
`Release=…0412000000`, `sources=…0420000000`, `frameworks=…0421000000`,
`resources=…0422000000`, `embed=…0150000000`, `group=…0000000070`,
`product=…0000000071`, `frameworkBuildFile=…0063`, `embedBuildFile=…0064`,
`proxy=…0400000002`, `dependency=…0400000001`.

**PBXBuildFile** (after `…0062`):

```
		000000000000000000000063 /* CheckStitchCore in Frameworks */ = {isa = PBXBuildFile; productRef = 000000000000000000000031 /* CheckStitchCore */; };
		000000000000000000000064 /* CheckStitchWatch.app in Embed Watch Content */ = {isa = PBXBuildFile; fileRef = 000000000000000000000071 /* CheckStitchWatch.app */; platformFilter = ios; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
```

**PBXContainerItemProxy** (after `…0300000002`):

```
		000000000000000400000002 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 000000000000000000000000 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 000000000000000400000000;
			remoteInfo = CheckStitchWatch;
		};
```

**PBXCopyFilesBuildPhase** (new section, before PBXFileReference):

```
/* Begin PBXCopyFilesBuildPhase section */
		000000000000000150000000 /* Embed Watch Content */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
			dstSubfolderSpec = 16;
			files = (
				000000000000000000000064 /* CheckStitchWatch.app in Embed Watch Content */,
			);
			name = "Embed Watch Content";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */
```

**PBXFileReference** (after `…0051`):

```
		000000000000000000000071 /* CheckStitchWatch.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = CheckStitchWatch.app; sourceTree = BUILT_PRODUCTS_DIR; };
```

**PBXFileSystemSynchronizedRootGroup** (after `…0050`):

```
		000000000000000000000070 /* CheckStitchWatch */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = CheckStitchWatch;
			sourceTree = "<group>";
		};
```

**PBXFrameworksBuildPhase** (after `…0321000000`):

```
		000000000000000421000000 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			files = (
				000000000000000000000063 /* CheckStitchCore in Frameworks */,
			);
		};
```

**PBXGroup** — add `000000000000000000000070 /* CheckStitchWatch */,` to the
main group's `children` (after `CheckStitchUITests`), and
`000000000000000000000071 /* CheckStitchWatch.app */,` to the `Products`
group's `children`.

**PBXNativeTarget** — inside the existing `CheckStitch` target add
`dependencies = (000000000000000400000001 /* PBXTargetDependency */,);`
before `buildConfigurationList`, and append
`000000000000000150000000 /* Embed Watch Content */` to its `buildPhases`.
Then add the new target after `CheckStitchUITests`:

```
		000000000000000400000000 /* CheckStitchWatch */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 000000000000000410000000 /* Build configuration list for PBXNativeTarget "CheckStitchWatch" */;
			buildPhases = (
				000000000000000420000000 /* Sources */,
				000000000000000421000000 /* Frameworks */,
				000000000000000422000000 /* Resources */,
			);
			buildRules = (
			);
			fileSystemSynchronizedGroups = (
				000000000000000000000070 /* CheckStitchWatch */,
			);
			name = CheckStitchWatch;
			packageProductDependencies = (
				000000000000000000000031 /* CheckStitchCore */,
			);
			productName = CheckStitchWatch;
			productReference = 000000000000000000000071 /* CheckStitchWatch.app */;
			productType = "com.apple.product-type.application";
		};
```

**PBXProject** — add to `TargetAttributes`:

```
					000000000000000400000000 = {
						CreatedOnToolsVersion = 26.3;
					};
```

and add `000000000000000400000000 /* CheckStitchWatch */,` to `targets`.

**PBXResourcesBuildPhase** / **PBXSourcesBuildPhase** — add empty phases
`…0422000000 /* Resources */` and `…0420000000 /* Sources */` (both
`files = ();`).

**PBXTargetDependency** (after `…0300000001`):

```
		000000000000000400000001 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			platformFilter = ios;
			target = 000000000000000400000000 /* CheckStitchWatch */;
			targetProxy = 000000000000000400000002 /* PBXContainerItemProxy */;
		};
```

**XCBuildConfiguration** — append the watch Debug (`…0411000000`) and Release
(`…0412000000`) configs, identical settings, name set per config. No
`CODE_SIGN_ENTITLEMENTS`, and no `ASSETCATALOG_COMPILER_APPICON_NAME` until an
asset catalog exists (deviation 5):

```
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 6NWX2DHB9Q;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = CheckStitch;
				INFOPLIST_KEY_WKCompanionAppBundleIdentifier = app.alanvardy.CheckStitch;
				INFOPLIST_KEY_WKWatchOnly = NO;
				LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitch.watchkitapp;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "watchos watchsimulator";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 27.0;
```

**XCConfigurationList** — append:

```
		000000000000000410000000 /* Build configuration list for PBXNativeTarget "CheckStitchWatch" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				000000000000000411000000 /* Debug configuration for PBXNativeTarget "CheckStitchWatch" */,
				000000000000000412000000 /* Release configuration for PBXNativeTarget "CheckStitchWatch" */,
			);
			defaultConfigurationName = Release;
		};
```

**Critical:** set `platformFilter = ios` on **both** the embed `PBXBuildFile`
(`…0064`) and the `PBXTargetDependency` (`…0400000001`) — this is what keeps the
watch out of `make build-mac` (verified against
`SingleThread.xcodeproj/project.pbxproj:16`, `:592-597`).

#### 3. Shared scheme

**File**: `CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitchWatch.xcscheme`
**Action**: create — copy `CheckStitch.xcscheme`, replacing every
`BlueprintIdentifier = "000000000000000100000000"` with `…0400000000`, every
`BuildableName = "CheckStitch.app"` with `"CheckStitchWatch.app"`, and every
`BlueprintName = "CheckStitch"` with `"CheckStitchWatch"`; drop the
`<Testables>` entries (no watch test target).

#### 4. Makefile

**File**: `Makefile`
**Action**: modify — add to the variable block and targets, and extend `.PHONY`:

```make
WATCH_SIM := generic/platform=watchOS Simulator
WATCH_SCHEME := CheckStitchWatch
```

```make
# The watch target compiles the same package for watchOS. `generic/platform=watchOS
# Simulator` keeps this unsigned and sim-free; the real-watch build is run-watch.sh.
watch-build:
	xcodebuild -scheme '$(WATCH_SCHEME)' \
	  -destination '$(WATCH_SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  build
```

```make
.PHONY: build build-mac run clean test test-unit test-ui watch-build
```

### Verification

#### Automated
- [ ] `make watch-build` passes
- [ ] `make build` passes (the iOS scheme now builds + embeds the watch)
- [ ] `make build-mac` passes (the `platformFilter = ios` guard keeps the watch out)
- [ ] `make test-unit` passes
- [ ] `plutil -lint CheckStitch.xcodeproj/project.pbxproj` reports `OK`

#### Manual
- [ ] `xcrun simctl list devices available | grep "Apple Watch Series 11"`, boot one, `xcrun simctl install <UDID> DerivedData/Build/Products/Debug-watchsimulator/CheckStitchWatch.app`, `xcrun simctl launch <UDID> app.alanvardy.CheckStitch.watchkitapp`, confirm it launches showing "CheckStitch"

---

## Phase 4: Watch UI — list → detail → run

### Changes

#### 1. Watch-side transport

**File**: `CheckStitchWatch/WatchSyncAdapter.swift`
**Action**: create (deviation 3 — the watch half of the Stage-2 seam)

```swift
import CheckStitchCore
import Foundation
import WatchConnectivity

/// Watch half of the sync seam. The watch only ever sends run requests; the
/// phone owns the checklist payload, so `sendContext` is deliberately empty.
@MainActor
final class WatchSyncAdapter: NSObject, ChecklistSyncTransport {
    var onMessage: ((ChecklistSyncMessage) -> Void)?

    init(session: WCSession = .default) {
        self.session = session
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func sendContext(_: Data) {}

    func sendUserInfo(_ message: ChecklistSyncMessage) {
        guard session.activationState == .activated else { return }
        session.transferUserInfo(message.userInfo)
    }

    private let session: WCSession
}

extension WatchSyncAdapter: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        // `receivedApplicationContext` is already populated when activation
        // completes, so a cold launch still sees the phone's last push.
        guard let message = ChecklistSyncMessage(userInfo: session.receivedApplicationContext) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: applicationContext) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }
}
```

If Swift 6 rejects the `nonisolated` witnesses, keep the `nonisolated` marker
and extract `ChecklistSyncMessage(userInfo:)` **before** the `Task` hop (as
above) so no non-`Sendable` `[String: Any]` crosses an actor boundary.

#### 2. Watch root

**File**: `CheckStitchWatch/CheckStitchWatchApp.swift`
**Action**: modify — replace the Stage-3 shell:

```swift
import CheckStitchCore
import SwiftUI

@main
struct CheckStitchWatchApp: App {
    @State private var store = WatchChecklistStore(transport: WatchSyncAdapter())

    var body: some Scene {
        WindowGroup {
            WatchChecklistListView()
                .environment(store)
        }
    }
}
```

#### 3. List screen

**File**: `CheckStitchWatch/WatchChecklistListView.swift`
**Action**: create

```swift
import CheckStitchCore
import SwiftUI

struct WatchChecklistListView: View {
    @Environment(WatchChecklistStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.checklists.isEmpty {
                    ContentUnavailableView(
                        "No checklists",
                        systemImage: "checklist",
                        description: Text("Open CheckStitch on your iPhone."))
                } else {
                    List(store.checklists) { checklist in
                        NavigationLink(checklist.name) {
                            WatchChecklistDetailView(checklist: checklist)
                        }
                    }
                }
            }
            .navigationTitle("Checklists")
        }
        .task {
            store.start()
            store.requestRefresh()
        }
    }
}
```

#### 4. Detail screen (D1) — read-only items + one action

**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: create

```swift
import CheckStitchCore
import SwiftUI

struct WatchChecklistDetailView: View {
    let checklist: Checklist
    @Environment(WatchChecklistStore.self) private var store
    @State private var sent = false

    /// Blank rows are never turned into reminders, so the watch hides them too.
    private var visibleItems: [ChecklistItem] {
        checklist.items.filter { !$0.isBlank }
    }

    var body: some View {
        List(visibleItems) { item in
            Text(item.title)
        }
        .navigationTitle(checklist.name)
        .safeAreaInset(edge: .bottom) {
            Button(sent ? "Sent" : "Create reminders") {
                store.run(checklist)
                sent = true
            }
            .disabled(sent || visibleItems.isEmpty)
        }
    }
}
```

No `import EventKit`, no edit/delete affordance. "Sent" — never "created" —
because queued `transferUserInfo` is not proof of execution.

### Verification

#### Automated
- [ ] `make watch-build` passes
- [ ] `make build` passes

#### Manual
- [ ] On the watch simulator: launch shows the empty state ("Open CheckStitch on your iPhone."); with the phone not running there is no data, which is the expected cold state
- [ ] In Xcode Previews (or with a temporary fixture), a checklist shows its non-blank items and the "Create reminders" button; tapping it flips the label to "Sent"

---

## Phase 5: Phone-side coordinator + `WCSession` adapter

### Changes

#### 1. Coordinator (Core)

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
**Action**: create

```swift
import Foundation

/// Phone side of the sync seam: pushes the checklist set on start and on every
/// change, and turns run requests into the app's existing reminder creation.
@MainActor
public final class ChecklistSyncCoordinator {
    public init(
        transport: ChecklistSyncTransport,
        snapshot: @escaping () -> [Checklist],
        createReminders: @escaping (Checklist) async -> Void
    ) {
        self.transport = transport
        self.snapshot = snapshot
        self.createReminders = createReminders
    }

    public func start() {
        transport.onMessage = { [weak self] in self?.handle($0) }
        transport.activate()
        pushContext()
    }

    public func checklistsDidChange() {
        pushContext()
    }

    private func pushContext() {
        guard let data = try? ChecklistCodec.encode(snapshot()) else { return }
        transport.sendContext(data)
    }

    private func handle(_ message: ChecklistSyncMessage) {
        switch message {
        case .requestChecklists:
            pushContext()
        case .runChecklist(let id):
            guard let checklist = snapshot().first(where: { $0.id == id }) else { return }
            Task { await createReminders(checklist) }
        case .context:
            break // watch-only direction
        }
    }

    private let transport: ChecklistSyncTransport
    private let snapshot: () -> [Checklist]
    private let createReminders: (Checklist) async -> Void
}
```

#### 2. Phone `WCSession` adapter

**File**: `CheckStitch/PhoneSyncAdapter.swift`
**Action**: create — the app target's **only** `WatchConnectivity` import,
wrapped in `#if os(iOS)` because WatchConnectivity does not exist on macOS:

```swift
#if os(iOS)
import CheckStitchCore
import Foundation
import WatchConnectivity

/// Phone half of the sync seam. It owns no EventKit store — reminder creation
/// stays on the coordinator's `createReminders` closure, so the process keeps a
/// single `EKEventStore` (EKCADErrorDomain 1021).
@MainActor
final class PhoneSyncAdapter: NSObject, ChecklistSyncTransport {
    var onMessage: ((ChecklistSyncMessage) -> Void)?

    init(session: WCSession = .default) {
        self.session = session
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func sendContext(_ data: Data) {
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(ChecklistSyncMessage.context(data).userInfo)
    }

    func sendUserInfo(_ message: ChecklistSyncMessage) {
        guard session.activationState == .activated else { return }
        session.transferUserInfo(message.userInfo)
    }

    private let session: WCSession
}

extension PhoneSyncAdapter: WCSessionDelegate {
    nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: userInfo) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: applicationContext) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }
}
#endif
```

`ChecklistReminders.create(from:)` is unchanged and passed in as a closure.

#### 3. Wire it in `MyApp`

**File**: `CheckStitch/MyApp.swift`
**Action**: modify — add the iOS-only coordinator state and hook it to the
store. (Avoids a custom `init()` so the `@UIApplicationDelegateAdaptor`
initialisation is untouched.)

```swift
    @State private var store = ChecklistStore()
    #if os(iOS)
        @State private var coordinator: ChecklistSyncCoordinator?
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                #if os(iOS)
                    .task {
                        if coordinator == nil {
                            let coordinator = ChecklistSyncCoordinator(
                                transport: PhoneSyncAdapter(),
                                snapshot: { store.checklists },
                                createReminders: { await ChecklistReminders.create(from: $0) })
                            self.coordinator = coordinator
                            coordinator.start()
                        }
                    }
                    .onChange(of: store.checklists) { _, _ in
                        coordinator?.checklistsDidChange()
                    }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushPendingSave() }
        }
    }
```

#### 4. Tests

**File**: `CheckStitchTests/ChecklistSyncCoordinatorTests.swift`
**Action**: create — `@MainActor` suite with a fake transport plus a spy
create-closure. Add this spy to `TestFixtures.swift`:

```swift
@MainActor
final class SpyChecklistRunner {
    private(set) var created: [Checklist] = []
    func run(_ checklist: Checklist) async { created.append(checklist) }
}
```

```swift
@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ChecklistSyncCoordinatorTests {
    private func makeCoordinator(
        transport: FakeChecklistSyncTransport,
        checklists: [Checklist],
        runner: SpyChecklistRunner
    ) -> ChecklistSyncCoordinator {
        ChecklistSyncCoordinator(
            transport: transport,
            snapshot: { checklists },
            createReminders: { await runner.run($0) })
    }

    @Test
    func startPushesTheEncodedChecklistContext() {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let checklists = [Checklist(name: "Groceries")]
        let coordinator = makeCoordinator(transport: transport, checklists: checklists, runner: runner)

        coordinator.start()

        #expect(transport.activateCount == 1)
        #expect(transport.sentContexts.count == 1)
        #expect(ChecklistCodec.decode(transport.sentContexts[0]) == checklists)
    }

    @Test
    func storeChangePushesAgain() {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let coordinator = makeCoordinator(transport: transport, checklists: [], runner: runner)

        coordinator.start()
        coordinator.checklistsDidChange()

        #expect(transport.sentContexts.count == 2)
    }

    @Test
    func runRequestForKnownIDCreatesRemindersOnce() async {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")])
        let coordinator = makeCoordinator(transport: transport, checklists: [checklist], runner: runner)
        coordinator.start()

        transport.deliver(.runChecklist(checklist.id))
        for _ in 0..<50 where runner.created.isEmpty { await Task.yield() }

        #expect(runner.created == [checklist])
    }

    @Test
    func runRequestForUnknownIDCreatesNothing() async {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let coordinator = makeCoordinator(transport: transport, checklists: [], runner: runner)
        coordinator.start()

        transport.deliver(.runChecklist(UUID()))
        await Task.yield()

        #expect(runner.created.isEmpty)
    }

    @Test
    func requestChecklistsPushesAgain() {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let coordinator = makeCoordinator(transport: transport, checklists: [], runner: runner)
        coordinator.start()

        transport.deliver(.requestChecklists)

        #expect(transport.sentContexts.count == 2)
    }
}
```

### Verification

#### Automated
- [ ] `make test-unit` passes (all five coordinator cases)
- [ ] `make build` passes — the adapter compiles against `WatchConnectivity`
- [ ] `make build-mac` passes — `#if os(iOS)` keeps `WatchConnectivity` out of the macOS slice
- [ ] `bash -c 'grep -rn "EKEventStore()" CheckStitch CheckStitchCore/Sources'` shows exactly one construction site outside tests

#### Manual
- [ ] Phone app on the simulator starts without a crash with no watch paired (`WCSession.isSupported()`/activation no-ops)

---

## Phase 6: Tooling, gate and real-watch run

### Changes

#### 1. Real-watch runner

**File**: `scripts/run-watch.sh`
**Action**: create (`#!/bin/bash`, `set -euo pipefail`, `chmod +x`, mode `100755`)

```bash
#!/bin/bash
set -euo pipefail

# scripts/run-watch.sh — build CheckStitchWatch for the watchOS device and
# install + launch it on the paired Apple Watch via devicectl.
#
#   ./scripts/run-watch.sh
#
# Overrides (same env-override pattern as the Makefile):
#   SCHEME=… WATCH_SCHEME=… BUNDLE_ID=… CONFIGURATION=… DERIVED_DATA=…
#   WATCH_NAME="Alan's Apple Watch"
#
# The watch device is resolved to an identifier through `devicectl list
# devices -j` — never a bare name in a build destination. If devicectl cannot
# reach the watch it usually reports usage-assertion error 4016 (device
# offline / Remote Device Services off); that is reported explicitly.

SCHEME="${SCHEME:-CheckStitch}"
WATCH_SCHEME="${WATCH_SCHEME:-CheckStitchWatch}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch.watchkitapp}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"
WATCH_NAME="${WATCH_NAME:-Alan's Apple Watch}"
DEVICES_JSON="${TMPDIR:-/tmp}/run-watch-$$.json"
trap 'rm -f "$DEVICES_JSON"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WATCH_APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-watchos/${WATCH_SCHEME}.app"

cd "$REPO_ROOT"

echo "==> Resolving ${WATCH_NAME}…"
if ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
    echo "❌ devicectl could not list devices." >&2
    exit 1
fi

WATCH_ID="$(
    python3 - "$DEVICES_JSON" "$WATCH_NAME" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

wanted = sys.argv[2]
for device in payload["result"]["devices"]:
    props = device.get("deviceProperties", {})
    if props.get("name") != wanted:
        continue
    conn = device.get("connectionProperties", {}) or {}
    if conn.get("transportType") is None or conn.get("tunnelState") == "unavailable":
        print("unreachable", file=sys.stderr)
        sys.exit(2)
    print(device["identifier"])
    break
else:
    sys.exit(3)
PY
)" || {
    echo "❌ Could not resolve '${WATCH_NAME}' (unpaired, unreachable, or Developer Mode off)." >&2
    echo "   Unlock the watch, keep it on this Mac's Wi-Fi, then retry. devicectl error 4016 means the same." >&2
    exit 1
}

echo "==> Building ${WATCH_SCHEME} (${CONFIGURATION}) for watchOS…"
xcodebuild -scheme "$WATCH_SCHEME" \
  -destination 'generic/platform=watchOS' \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

if [[ ! -d "$WATCH_APP" ]]; then
    echo "❌ Built watch app not found at $WATCH_APP" >&2
    exit 1
fi

echo "==> Installing on ${WATCH_NAME}…"
if ! xcrun devicectl device install app --device "$WATCH_ID" "$WATCH_APP"; then
    echo "❌ Install failed (is the watch unlocked and is Remote Device Services on?)." >&2
    exit 1
fi

echo "==> Launching on ${WATCH_NAME}…"
xcrun devicectl device process launch \
  --terminate-existing --activate \
  --device "$WATCH_ID" \
  "$BUNDLE_ID"

echo "✅ ${WATCH_SCHEME} installed and launched on ${WATCH_NAME}."
```

If the watch bundle refuses to install without its companion, install the
phone app first (`bash scripts/run-devices.sh`) — the script's install command
is the only ordering-sensitive step.

#### 2. Gate

**File**: `scripts/test.sh`
**Action**: modify — after `make build-mac`, before the shellcheck block:

```bash
# The watch target compiles the same package for watchOS and catches a broken
# pbxproj/watch-scheme edit that the iOS and macOS slices would miss.
make watch-build
```

#### 3. Documentation

**File**: `AGENTS.md`
**Action**: modify — correct the gate line to the real sequence and mention the
watch tooling: `./scripts/test.sh` = `make build` → `make test` →
`make build-mac` → `make watch-build` → `shellcheck scripts/*.sh`, printing
`gate: ok`; add `bash scripts/run-watch.sh` (real watch) and `make watch-build`
(watch simulator) to the build/run section.

### Verification

#### Automated
- [ ] `bash scripts/test.sh` prints `gate: ok` (build + `make test` + build-mac + watch-build + shellcheck)
- [ ] `shellcheck scripts/run-watch.sh` is clean
- [ ] `bash -n scripts/run-watch.sh` is clean

#### Manual
- [ ] `bash scripts/run-watch.sh` installs and launches `CheckStitchWatch` on `Alan's Apple Watch` (`00008301-209B793C010BC02E`)
- [ ] Design check 3: create/edit a checklist on the iPhone (`make run`), leave both apps active; the checklist appears in the watch list
- [ ] Design check 4: tap the checklist on the watch, confirm its non-blank items render, tap **Create reminders**; one new reminder per non-blank item appears in Inbox on the phone
- [ ] Design check 5: the watch performs no other write, edits nothing, and shows no Reminders permission prompt

---

## Testing checkpoints

- After Phase 1: `make test-unit` + `make build` + `make build-mac` green before touching sync.
- After Phase 2: `make test-unit` green — the entire sync contract is proven on the host before any watch target exists.
- After Phase 3: `make watch-build` **plus** `make build`/`make build-mac`/`make test-unit` green (a malformed pbxproj breaks every target).
- After Phase 4: `make watch-build` green; manual watch-simulator smoke.
- After Phase 5: `make test-unit` + `make build` + `make build-mac` green; exactly one `EKEventStore()` outside tests.
- After Phase 6: full `./scripts/test.sh` prints `gate: ok`, then the real-watch manual checks.

## Deviations from `structure.md`

1. **Extra app files need `import CheckStitchCore`** (Step 1.5): the structure
   listed only `ChecklistStore`/`ChecklistDetailView`. `ContentView.swift`,
   `ChecklistReminders.swift` and `MyApp.swift` also name/observe the moved
   types; without the import they won't compile. The app-local
   `AppearanceMode`/`ChecklistWidth` duplicates are **not** touched — verified
   that the current module shadows the imported name, so `ContentView.swift`
   keeps using the app copies and no rename/qualification is required.
2. **`#if !os(watchOS)` in `EventKitReminderCreator`** (Step 1.4, decision D2):
   `save(_:commit:)` is `@available(watchOS, unavailable)` and is the only such
   symbol in the package (verified by type-checking against the watchOS 26.5
   SDK). Without it, adding `.watchOS("27.0")` cannot compile. The design's "no
   `#if os(watchOS)`" rule targeted threading conditionals through a *shared
   store*; this is a single guard in a phone-only adapter the watch never
   reaches.
3. **Watch-side transport added** (`CheckStitchWatch/WatchSyncAdapter.swift`,
   Phase 4): the structure's Stage 2 promised "both the watch and phone
   adapters", but Stage 4's file list omitted the watch one; without it the
   watch never connects.
4. **`ChecklistSyncCoordinator.snapshot` is `() -> [Checklist]`**, not
   `() -> ChecklistEnvelope` (Phase 5): the real codec is
   `ChecklistCodec.encode(_ checklists: [Checklist]) throws`, and the wire
   `ChecklistSyncMessage.context` carries the codec's `Data`. The coordinator
   encodes internally with `try?`, so the failure path is "skip this push".
5. **No `ASSETCATALOG_COMPILER_APPICON_NAME`** on the watch configs until an
   asset catalog exists (Phase 3) — an `AppIcon` setting with no matching
   catalog warns in Debug and can error in Release.
6. **`AGENTS.md` gate-line fix folded into Phase 6** (the structure listed it
   as a precondition/housekeeping item): the line now names the real
   `build` → `test` → `build-mac` → `watch-build` → `shellcheck` sequence.

## Risks carried into implementation

- **Real-watch `devicectl` install of a watch bundle is unprecedented here.**
  Budget a deploy loop in Phase 6; 4016 = offline/RDS off, and the phone app may
  need installing first for the companion relationship.
- **`updateApplicationContext` reachability**: a cold-launched watch shows the
  empty state until activation reads `receivedApplicationContext` or the
  `.requestChecklists` round-trip lands.
- **Queued runs**: `transferUserInfo` can't distinguish sent from executed, so
  the button says "Sent" only.
- **Payload size** (~65 KB cap on `updateApplicationContext`): fine for normal
  checklists; if it ever overflows, `sendContext` silently fails
  (`try? updateApplicationContext`) and the watch keeps the last context.
