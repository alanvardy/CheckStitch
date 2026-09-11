# Implementation Plan

## Overview

Turn CheckStitch's single implicit checklist (view `@State`, nothing persisted)
into a persisted collection of checklists: an `@Observable ChecklistStore` over
an App Group `UserDefaults` suite, a `NavigationStack` list screen with a per-row
create-reminders action, and a `ChecklistDetailView` whose "Remove Checklist"
actually deletes and pops. Reminders are only ever created, never deleted.

Built bottom-up in five stages. Each stage ends with the gate
(`./scripts/test.sh`) green plus stage-specific checks.

## Deviations from `structure.md` (read first)

1. **`Makefile` gains a `test` target** (not in the Stage 1 file list). The SIM
   destination precedence lives in `Makefile:1-6`; duplicating it inside
   `scripts/test.sh` (and diverging later) is worse than one new phony target.
   `scripts/test.sh` then calls `make build` then `make test`.
2. **`CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme` is
   committed** (new file). The repo has no shared schemes today; schemes are
   auto-generated, and an auto-generated app scheme is not guaranteed to include
   a hand-added test target in its TestAction. A committed shared scheme makes
   `xcodebuild test -scheme CheckStitch` deterministic.
3. **Codec API**: `structure.md` names only `decode`; the store also needs
   `encode`, and the test file is `ChecklistCodecTests`, so both live on an
   `enum ChecklistCodec` (`encode`/`decode`) alongside `ChecklistEnvelope`.
4. **Test classes are `@MainActor`-annotated** rather than the test target
   setting `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The app target is
   MainActor-by-default, so the model/store/codec symbols are MainActor-isolated
   and tests must be too; leaving the test target nonisolated avoids the
   `XCTestCase.setUp()` nonisolated-override isolation trap entirely (no
   `setUp`/`tearDown` overrides — per-test `defer` cleanup instead).
5. `structure.md` says new checklists are "empty"; a default non-blank name is
   needed because the list row shows the name. Default is `"New checklist"`.
6. `RangeReplaceableCollection.remove(atOffsets:)` is a **SwiftUI** extension, so
   the Foundation-only store removes offsets with a descending-index loop.

---

## Phase 1: Model + App Group accessor (+ test target)

### Changes

#### 1. `CheckStitch/AppGroup.swift` — **create**

```swift
import Foundation

/// App Group storage shared with the planned watch app (VAR-963). Falls back to
/// `.standard` where the group is unavailable (unregistered simulators,
/// previews) so first launch can never crash.
enum AppGroup {
    static let suiteName = "group.app.alanvardy.CheckStitch"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
```

#### 2. `CheckStitch/Checklist.swift` — **create**

`ChecklistItem` moves out of `ContentView.swift` and gains `Codable`/`Hashable`
plus an explicit memberwise-equivalent init (`id` defaulted) so the existing
`ChecklistItem(title:)` call sites keep compiling.

```swift
import Foundation
import os

/// Editable row model for a checklist item. The ID is stable so rows can be
/// added, removed, and edited without conflating duplicate titles.
struct ChecklistItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

/// A named collection of items that can be turned into reminders.
struct Checklist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var items: [ChecklistItem]

    init(id: UUID = UUID(), name: String = "New checklist", items: [ChecklistItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

/// Versioned wire format for the App Group payload. The version field exists so
/// VAR-963 can evolve decoding instead of silently mis-reading old data.
struct ChecklistEnvelope: Codable {
    var version: Int
    var checklists: [Checklist]
}

enum ChecklistCodec {
    static let currentVersion = 1

    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistCodec")

    static func encode(_ checklists: [Checklist]) throws -> Data {
        try JSONEncoder().encode(ChecklistEnvelope(version: currentVersion, checklists: checklists))
    }

    /// Corrupt payloads and unknown versions both yield `[]` plus a log line —
    /// never a crash and never a partial decode.
    static func decode(_ data: Data) -> [Checklist] {
        do {
            let envelope = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
            guard envelope.version == currentVersion else {
                logger.error("Unsupported checklist payload version \(envelope.version, privacy: .public); treating as empty")
                return []
            }
            return envelope.checklists
        } catch {
            logger.error("Failed to decode checklist payload: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
```

#### 3. `CheckStitch/ContentView.swift` — **modify (delete only)**

Delete the `ChecklistItem` struct (now `ContentView.swift:106-117`). Everything
else in this file is untouched until Phase 5.

#### 4. `CheckStitchTests/ChecklistCodecTests.swift` — **create**

```swift
import XCTest
@testable import CheckStitch

@MainActor
final class ChecklistCodecTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let checklists = [
            Checklist(name: "Groceries", items: [
                ChecklistItem(title: "Milk"),
                ChecklistItem(title: "Eggs"),
            ]),
            Checklist(name: "Chores"),
        ]

        let data = try ChecklistCodec.encode(checklists)

        XCTAssertEqual(ChecklistCodec.decode(data), checklists)
    }

    func testUnknownVersionDecodesAsEmpty() {
        let data = Data(#"{"version":99,"checklists":[{"id":"\#(UUID().uuidString)","name":"x","items":[]}]}"#.utf8)

        XCTAssertEqual(ChecklistCodec.decode(data), [])
    }

    func testEmptyEnvelopeDecodes() throws {
        XCTAssertEqual(ChecklistCodec.decode(try ChecklistCodec.encode([])), [])
    }
}
```

#### 5. `CheckStitch.xcodeproj/project.pbxproj` — **modify**

Hand-edit the OpenStep plist. Fixed 24-hex object IDs matching the existing
style. **All of the following blocks go in; existing content is only added to,
never rewritten.**

New IDs: test target `000000000000000200000000`, test config list
`000000000000000210000000`, test Debug/Release `000000000000000211000000` /
`000000000000000212000000`, test Sources/Frameworks/Resources
`000000000000000220000000` / `000000000000000230000000` /
`000000000000000240000000`, test product ref `000000000000000000000220`,
test sync root group `000000000000000000000210`, container proxy
`000000000000000250000000`, target dependency `000000000000000260000000`.

**(a)** `PBXFileReference` section — add after the `CheckStitch.app` line:

```
		000000000000000000000220 /* CheckStitchTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = CheckStitchTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

**(b)** `PBXFileSystemSynchronizedRootGroup` section — add after the `CheckStitch` group:

```
		000000000000000000000210 /* CheckStitchTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = CheckStitchTests;
			sourceTree = "<group>";
		};
```

**(c)** `PBXFrameworksBuildPhase` section — add:

```
		000000000000000230000000 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			files = (
			);
		};
```

**(d)** New sections `PBXContainerItemProxy` and `PBXTargetDependency` (place
after `PBXBuildFile`/before `PBXFileReference` alphabetically; anywhere is
valid):

```
/* Begin PBXContainerItemProxy section */
		000000000000000250000000 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 000000000000000000000000 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 000000000000000100000000;
			remoteInfo = CheckStitch;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
		000000000000000260000000 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 000000000000000100000000 /* CheckStitch */;
			targetProxy = 000000000000000250000000 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */
```

**(e)** Main `PBXGroup` — add the sync group to `children`:

```
				000000000000000000000210 /* CheckStitchTests */,
```

and the test product to the `Products` group:

```
				000000000000000000000220 /* CheckStitchTests.xctest */,
```

**(f)** `PBXNativeTarget` section — add the test target:

```
		000000000000000200000000 /* CheckStitchTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 000000000000000210000000 /* Build configuration list for PBXNativeTarget "CheckStitchTests" */;
			buildPhases = (
				000000000000000220000000 /* Sources */,
				000000000000000230000000 /* Frameworks */,
				000000000000000240000000 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				000000000000000260000000 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				000000000000000000000210 /* CheckStitchTests */,
			);
			name = CheckStitchTests;
			productName = CheckStitchTests;
			productReference = 000000000000000000000220 /* CheckStitchTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
```

**(g)** `PBXProject` — `TargetAttributes` gains a second entry and `targets`
gains the test target:

```
					000000000000000200000000 = {
						CreatedOnToolsVersion = 26.3;
						TestTargetID = 000000000000000100000000;
					};
```

```
				000000000000000200000000 /* CheckStitchTests */,
```

**(h)** `PBXResourcesBuildPhase` and `PBXSourcesBuildPhase` — add:

```
		000000000000000240000000 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			files = (
			);
		};
```

```
		000000000000000220000000 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			files = (
			);
		};
```

**(i)** `XCBuildConfiguration` — add both test configurations (Release is
identical except `name = Release;`):

```
		000000000000000211000000 /* Debug configuration for PBXNativeTarget "CheckStitchTests" */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 6NWX2DHB9Q;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitchTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = auto;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/CheckStitch.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CheckStitch";
			};
			name = Debug;
		};
```

Do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` here (deviation 4).
`ENABLE_TESTABILITY = YES` and `IPHONEOS_DEPLOYMENT_TARGET = 18.7` are inherited
from the project-level Debug configuration.

**(j)** `XCConfigurationList` — add:

```
		000000000000000210000000 /* Build configuration list for PBXNativeTarget "CheckStitchTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				000000000000000211000000 /* Debug configuration for PBXNativeTarget "CheckStitchTests" */,
				000000000000000212000000 /* Release configuration for PBXNativeTarget "CheckStitchTests" */,
			);
			defaultConfigurationName = Release;
		};
```

**Fallback if the hand-edit fails to load** (`xcodebuild -list` errors, or Xcode
refuses the project): create the target through Xcode — File → New → Target →
iOS → Unit Testing Bundle, product name `CheckStitchTests`, host application
`CheckStitch`, then commit the resulting `project.pbxproj` and the generated
`xcshareddata/xcschemes/CheckStitch.xcscheme`. If Xcode is unavailable/stale,
stop and ask the user; do not invent a substitute test runner.

#### 6. `CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme` — **create**

```
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "000000000000000100000000"
               BuildableName = "CheckStitch.app"
               BlueprintName = "CheckStitch"
               ReferencedContainer = "container:CheckStitch.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "000000000000000200000000"
               BuildableName = "CheckStitchTests.xctest"
               BlueprintName = "CheckStitchTests"
               ReferencedContainer = "container:CheckStitch.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "000000000000000100000000"
            BuildableName = "CheckStitch.app"
            BlueprintName = "CheckStitch"
            ReferencedContainer = "container:CheckStitch.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "000000000000000100000000"
            BuildableName = "CheckStitch.app"
            BlueprintName = "CheckStitch"
            ReferencedContainer = "container:CheckStitch.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

#### 7. `Makefile` — **modify** (deviation 1)

```make
.PHONY: build run test clean

test:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  test
```

#### 8. `scripts/test.sh` — **modify**

Replace the header comment and add `make test` after `make build`:

```bash
#!/bin/bash
# CheckStitch gate: simulator build, the CheckStitchTests unit suite, and
# static checks over the repo's shell scripts.
set -euo pipefail

cd "$(dirname "$0")/.."

make build
make test

if command -v shellcheck >/dev/null 2>&1; then
```

### Verification

#### Automated
- [x] `plutil -lint CheckStitch.xcodeproj/project.pbxproj` → `OK`
- [x] `xcodebuild -list -project CheckStitch.xcodeproj` lists targets `CheckStitch` **and** `CheckStitchTests`, and the `CheckStitch` scheme
- [x] `make test 2>&1 | grep -E "Executed 3 tests|error:"` → `Executed 3 tests, with 0 failures`
- [x] `./scripts/test.sh` prints `gate: ok`
- [x] `shellcheck scripts/*.sh` clean

#### Manual
- [ ] None for this phase.

---

## Phase 2: Persistence store

### Changes

#### 1. `CheckStitch/ChecklistStore.swift` — **create**

`load` is `static` so it can run from `init` with no partially-initialized
`self`. `remove(atOffsets:)` is not used (SwiftUI-only extension).

```swift
import Foundation

@Observable
final class ChecklistStore {
    private(set) var checklists: [Checklist]

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = AppGroup.defaults, key: String = "checklists.v1") {
        self.defaults = defaults
        self.key = key
        self.checklists = ChecklistStore.load(defaults: defaults, key: key)
    }

    func checklist(id: UUID) -> Checklist? {
        checklists.first { $0.id == id }
    }

    @discardableResult
    func create() -> Checklist {
        let checklist = Checklist()
        checklists.append(checklist)
        save()
        return checklist
    }

    func rename(id: UUID, to name: String) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        checklists[index].name = name
        save()
    }

    func addItem(to id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        checklists[index].items.append(ChecklistItem(title: "New item"))
        save()
    }

    func updateItem(checklistID: UUID, itemID: UUID, title: String) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        checklists[checklistIndex].items[itemIndex].title = title
        save()
    }

    func removeItems(from id: UUID, at offsets: IndexSet) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        for offset in offsets.sorted(by: >) {
            guard checklists[index].items.indices.contains(offset) else { continue }
            checklists[index].items.remove(at: offset)
        }
        save()
    }

    /// Local-only: reminders already created in Reminders are never touched.
    func delete(id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        checklists.remove(at: index)
        save()
    }

    private static func load(defaults: UserDefaults, key: String) -> [Checklist] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return ChecklistCodec.decode(data)
    }

    private func save() {
        do {
            defaults.set(try ChecklistCodec.encode(checklists), forKey: key)
        } catch {
            Self.logger.error("Failed to save checklists: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistStore")
}
```

Add `import os` for `Logger`.

#### 2. `CheckStitchTests/ChecklistStoreTests.swift` — **create**

Fresh UUID-named suite per test; `defer` cleanup runs even when an
`XCTAssert` fails (assertions don't unwind scope), so there is no
`setUp`/`tearDown` override.

```swift
import XCTest
@testable import CheckStitch

@MainActor
final class ChecklistStoreTests: XCTestCase {
    private let key = "checklists.v1"

    /// Fresh, uniquely-named suite per test so tests cannot bleed into each other.
    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create test UserDefaults suite \(suiteName)")
        }
        return (defaults, suiteName)
    }

    func testCreatePersistsAcrossReload() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = ChecklistStore(defaults: suite.defaults, key: key)
        let created = store.create()
        store.rename(id: created.id, to: "Groceries")

        let reloaded = ChecklistStore(defaults: suite.defaults, key: key)
        XCTAssertEqual(reloaded.checklists.count, 1)
        XCTAssertEqual(reloaded.checklists.first?.id, created.id)
        XCTAssertEqual(reloaded.checklists.first?.name, "Groceries")

        // The payload on disk is a versioned envelope, not a bare array.
        let data = try? XCTUnwrap(suite.defaults.data(forKey: key))
        XCTAssertEqual(ChecklistCodec.decode(data ?? Data()).count, 1)
    }

    func testRenamePersists() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = ChecklistStore(defaults: suite.defaults, key: key)
        let created = store.create()
        store.rename(id: created.id, to: "Chores")

        let reloaded = ChecklistStore(defaults: suite.defaults, key: key)
        XCTAssertEqual(reloaded.checklist(id: created.id)?.name, "Chores")
    }

    func testAddAndRemoveItemPersists() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = ChecklistStore(defaults: suite.defaults, key: key)
        let created = store.create()
        store.addItem(to: created.id)
        store.addItem(to: created.id)
        let items = try? XCTUnwrap(store.checklist(id: created.id)?.items)
        store.updateItem(checklistID: created.id, itemID: items?[1].id ?? UUID(), title: "Milk")
        store.removeItems(from: created.id, at: IndexSet(integer: 0))

        let reloaded = ChecklistStore(defaults: suite.defaults, key: key)
        let reloadedItems = reloaded.checklist(id: created.id)?.items
        XCTAssertEqual(reloadedItems?.count, 1)
        XCTAssertEqual(reloadedItems?.first?.title, "Milk")
    }

    func testDeleteRemovesOnlyTarget() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = ChecklistStore(defaults: suite.defaults, key: key)
        let first = store.create()
        let second = store.create()
        store.delete(id: first.id)

        let reloaded = ChecklistStore(defaults: suite.defaults, key: key)
        XCTAssertEqual(reloaded.checklists.count, 1)
        XCTAssertEqual(reloaded.checklists.first?.id, second.id)
        XCTAssertNil(reloaded.checklist(id: first.id))
    }

    func testDeleteUnknownIDIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = ChecklistStore(defaults: suite.defaults, key: key)
        let created = store.create()
        store.delete(id: UUID())

        let reloaded = ChecklistStore(defaults: suite.defaults, key: key)
        XCTAssertEqual(reloaded.checklists.map(\.id), [created.id])
    }

    func testCorruptDataYieldsEmpty() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        suite.defaults.set(Data("not json".utf8), forKey: key)

        let store = ChecklistStore(defaults: suite.defaults, key: key)
        XCTAssertTrue(store.checklists.isEmpty)
    }
}
```

### Verification

#### Automated
- [x] `make test 2>&1 | grep -E "Executed 9 tests|error:"` → `Executed 9 tests, with 0 failures` (3 codec + 6 store)
- [x] Run `make test` twice in a row — still green (no cross-run suite bleed)
- [x] `./scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] None for this phase.

---

## Phase 3: Reminders service

### Changes

#### 1. `CheckStitch/ChecklistReminders.swift` — **create**

Behavior is byte-for-byte the old `createChecklistReminders()` with a `Checklist`
parameter instead of view state; the `EKEventStore` stays a local `let` alive
until the last save.

```swift
import EventKit
import os

enum ChecklistReminders {
    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistReminders")

    /// Creates one reminder per non-blank item in the Reminders Inbox. Failures
    /// are logged, not thrown — the caller only needs to know when to stop its
    /// spinner.
    static func create(from checklist: Checklist) async {
        let eventStore = EKEventStore()
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            if !granted { return }
            for item in checklist.items {
                // Skip blank titles so an emptied row can't produce a meaningless reminder.
                guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let reminder = EKReminder(eventStore: eventStore)
                reminder.title = item.title
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
                try eventStore.save(reminder, commit: true)
            }
        } catch {
            logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

#### 2. `CheckStitch/ContentView.swift` — **modify (delete only)**

Delete `createChecklistReminders()` (now `ContentView.swift:81-104`) and the
`private static let logger` line (`ContentView.swift:5`). `import EventKit` and
`import os` are no longer needed in this file — remove both. Leave the
accessibility IDs and the spinner/checkmark UI in place for Phase 5 to reuse.

### Verification

#### Automated
- [x] `./scripts/test.sh` prints `gate: ok` (build + 9 tests)
- [x] `grep -rn "createChecklistReminders\|Self.logger" CheckStitch/` → no matches

#### Manual
- [ ] `make run`, open a checklist with 3 named items, Create reminders → 3 reminders appear in the Reminders **Inbox**
- [ ] Add a blank item row, Create reminders → no reminder for the blank row, no crash
- [ ] Deny Reminders access (Settings → CheckStitch → Reminders → off), Create reminders → no reminders, no crash, no visible error (log only)

---

## Phase 4: Detail screen

### Changes

#### 1. `CheckStitch/ChecklistDetailView.swift` — **create**

`TextField`s bind through custom `Binding(get:set:)` closures because the store
exposes value-type copies (`store.checklist(id:)`), not a bindable reference.

```swift
import SwiftUI

/// Detail screen for one checklist, keyed by id rather than a `@Binding` into a
/// parent view's `@State`, so mutations go through `ChecklistStore`.
struct ChecklistDetailView: View {
    let checklistID: UUID

    @Environment(ChecklistStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let checklist = store.checklist(id: checklistID) {
            Form {
                Section("Checklist name") {
                    TextField("Checklist name", text: nameBinding(for: checklistID))
                        .accessibilityIdentifier("checklistNameField")
                }
                Section("Items") {
                    ForEach(checklist.items) { item in
                        TextField("Item", text: titleBinding(checklistID: checklistID, itemID: item.id))
                    }
                    .onDelete { offsets in
                        store.removeItems(from: checklistID, at: offsets)
                    }
                }
                Section {
                    Button {
                        store.addItem(to: checklistID)
                    } label: {
                        Label("Add Item", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("addItemButton")

                    Button(role: .destructive) {
                        store.delete(id: checklistID)
                        dismiss()
                    } label: {
                        Label("Remove Checklist", systemImage: "trash")
                    }
                    .accessibilityIdentifier("removeChecklistButton")
                }
            }
            .navigationTitle("Edit checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        } else {
            // The checklist was deleted while this screen was on the stack.
            ContentUnavailableView("Checklist not found", systemImage: "trash")
        }
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.checklist(id: id)?.name ?? "" },
            set: { store.rename(id: id, to: $0) }
        )
    }

    private func titleBinding(checklistID: UUID, itemID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.checklist(id: checklistID)?.items.first { $0.id == itemID }?.title ?? ""
            },
            set: { store.updateItem(checklistID: checklistID, itemID: itemID, title: $0) }
        )
    }
}
```

"Done" pops without deleting; "Remove Checklist" deletes then pops (same
`dismiss()` call, which pops the pushed destination). The `else` branch guards
the stale-path case. No `#Preview` here — it would need an environment store
and the old `#Preview { ContentView() }` is handled in Phase 5.

#### 2. `CheckStitch/ContentView.swift` — **modify (delete only)**

Delete the `EditChecklistView` struct (now `ContentView.swift:119-166`) — it is
superseded by `ChecklistDetailView`. Leave the `#Preview` and create-button UI
in place; Phase 5 rewrites the remainder.

### Verification

#### Automated
- [x] `./scripts/test.sh` prints `gate: ok`
- [x] `grep -rn "EditChecklistView" CheckStitch/` → no matches

#### Manual
- [ ] `make run` → open a checklist, rename it, add items, edit item text, swipe-delete an item; `make run` again (relaunches) → all changes persisted
- [ ] Remove Checklist → the checklist disappears from the list **and** the screen pops (no "Checklist not found" left on screen)
- [ ] Create reminders for that checklist first, then Remove → reminders stay in Reminders
- [ ] Done (toolbar) → pops but the checklist is still in the list

---

## Phase 5: List screen + navigation wiring

### Changes

#### 1. `CheckStitch/MyApp.swift` — **modify (full rewrite)**

```swift
import SwiftUI

@main struct MyApp: App {
    @State private var store = ChecklistStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
```

#### 2. `CheckStitch/ContentView.swift` — **rewrite**

The whole file becomes:

```swift
import SwiftUI

struct ContentView: View {
    @Environment(ChecklistStore.self) private var store

    @State private var path: [UUID] = []
    /// Transient per-checklist reminder feedback, keyed by id — never persisted.
    @State private var creating: Set<UUID> = []
    @State private var created: Set<UUID> = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.checklists.isEmpty {
                    emptyState
                } else {
                    checklistList
                }
            }
            .navigationTitle("Checklists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createChecklist()
                    } label: {
                        Label("Create checklist", systemImage: "plus")
                    }
                    .accessibilityIdentifier("createChecklistButton")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ChecklistDetailView(checklistID: id)
            }
        }
    }

    private var checklistList: some View {
        List {
            ForEach(store.checklists) { checklist in
                HStack(spacing: 12) {
                    NavigationLink(checklist.name, value: checklist.id)
                    createRemindersButton(for: checklist.id)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No checklists", systemImage: "checklist")
        } description: {
            Text("Create a checklist to turn its items into reminders.")
        } actions: {
            Button("Create checklist") { createChecklist() }
                .accessibilityIdentifier("emptyStateCreateButton")
        }
    }

    @ViewBuilder
    private func createRemindersButton(for id: UUID) -> some View {
        Button {
            createReminders(for: id)
        } label: {
            if creating.contains(id) {
                ProgressView()
                    .controlSize(.small)
            } else if created.contains(id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "plus.circle")
            }
        }
        .buttonStyle(.borderless)
        .disabled(creating.contains(id))
        .accessibilityLabel("Create reminders from checklist")
        .accessibilityIdentifier("createRemindersButton")
    }

    private func createChecklist() {
        let checklist = store.create()
        path.append(checklist.id)
    }

    private func createReminders(for id: UUID) {
        guard let checklist = store.checklist(id: id) else { return }
        Task {
            creating.insert(id)
            // Hold the spinner for at least a second so saving quickly
            // doesn't flash the progress feedback past the user.
            async let minimumSpinner: Void = Task.sleep(for: .seconds(1))
            await ChecklistReminders.create(from: checklist)
            try? await minimumSpinner
            creating.remove(id)
            created.insert(id)
            try? await Task.sleep(for: .seconds(1))
            created.remove(id)
        }
    }
}

#Preview {
    ContentView()
        .environment(ChecklistStore())
}
```

Notes:
- `ChecklistReminders` requests access itself, so the button needs no
  permission plumbing in the view.
- The `path` is `[UUID]`; `ContentUnavailableView` and the toolbar create button
  are mutually exclusive, so the duplicated create affordance never renders
  twice at once (distinct accessibility IDs regardless).
- The old `checklistButton` / `editChecklistButton` / `checklistNameField` IDs on
  the list screen are intentionally gone; `checklistNameField`, `addItemButton`
  and `removeChecklistButton` moved to `ChecklistDetailView` unchanged.

### Verification

#### Automated
- [x] `./scripts/test.sh` prints `gate: ok` (build + 9 tests + shellcheck)
- [x] `xcodebuild -list -project CheckStitch.xcodeproj` still shows the `CheckStitch` scheme

#### Manual (the four design scenarios)
- [ ] (1) Create two checklists with distinct names and items, force-quit (`make run` terminates and relaunches the app), relaunch → both reappear with names and items intact
- [ ] (2) Create reminders from one checklist, see its row flash a spinner then a green checkmark, then Remove Checklist → the checklist is gone from the list and its reminders are still in Reminders
- [ ] (3) Create a checklist → it is pushed immediately; edit name/items, relaunch → edits persist
- [ ] (4) `./scripts/test.sh` → `gate: ok`
- [ ] Optional device proof of real App Group sharing: `bash scripts/run-devices.sh`, create a checklist, relaunch on device → checklist persists
- [ ] `git status` shows no `DerivedData/` or `.simulator_id` changes; scripts remain mode `100755`

---

## Testing Checkpoints (mirror of `structure.md`)

- [x] **After Phase 1** — `gate: ok` + codec suite green → model shape frozen for the store.
- [x] **After Phase 2** — store suite green against fresh `UserDefaults` domains → persistence proven before any UI relies on it.
- [ ] **After Phase 3** — gate green + 3 manual Reminders checks → creation flow unchanged from VAR-966.
- [ ] **After Phase 4** — detail screen manual checks pass → name/item/delete mutations proven through the store.
- [ ] **After Phase 5** — all four design scenarios pass → feature complete; optional device run confirms the App Group payload is real (not the `.standard` fallback).
