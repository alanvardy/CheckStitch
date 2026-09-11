# Implementation Plan

VAR-977 — add a test suite to CheckStitch.

**Desired end state**: a sources-only local Swift package `CheckStitchCore` holds all
non-view logic behind an injectable EventKit seam; `CheckStitchTests` (macOS-hosted,
Swift Testing) proves it; one XCTest UI smoke lives in `CheckStitchUITests`; and
`./scripts/test.sh` gates build + unit + UI + shellcheck.

## Pre-flight facts (resolved during planning — do not re-litigate)

- **`.defaultIsolation(MainActor.self)` is unavailable at `swift-tools-version: 6.0`**
  (it was introduced in PackageDescription 6.2). Verified by compiling a scratch package:
  `error: 'defaultIsolation' is unavailable`. **Decision: keep tools 6.0 and annotate the
  three main-actor types explicitly** (`@MainActor` on `EventKitReminderCreator`,
  `ChecklistCreator`'s collaborators, `ChecklistViewModel`). This resolves design Risk 2.
- **The full package below was compiled green** in a scratch package at tools 6.0 with
  Swift 6 strict concurrency. Two non-obvious requirements surfaced and are baked in:
  1. `ChecklistCreator` must be declared `: Sendable` (a `public` struct gets no inferred
     `Sendable`; without it `ChecklistViewModel` fails with *"sending 'self.creator' risks
     causing data races"*).
  2. `EventKitReminderCreator` must be `@MainActor` (a non-isolated class holding a
     non-`Sendable` `EKEventStore` cannot satisfy `ReminderCreating: Sendable`). A
     `@MainActor` class is implicitly `Sendable`, so the spy needs **no**
     `@unchecked Sendable` — structure Stage 3's `@unchecked Sendable` is superseded.
- **The real adapter is not permission-testable.** Unit tests must never call
  `requestFullAccessToReminders()` on the real store (it prompts and can write real
  reminders). Stage 3 therefore asserts the seam's *double* contract; permission and
  failure policy are asserted in Stage 4 through the injected double. Deviation from
  structure Stage 3's test names is called out at that stage.
- `xcodeproj` ruby gem 1.27.0 is installed but only supports object version 77 (this
  project is 90). Its round-trip is non-destructive (verified on a copy) but rewrites
  comments and key order. **The pbxproj is hand-edited with targeted `edit` calls**, and
  `xcodebuild -list` + `make build` are the correctness proof.
- Worktree `.simulator_id` = `845FFF19-2594-4198-8058-5068ADA48FA9`
  (`sim-alanvardy-var-977-add-tests`, currently Shutdown) — present and available.
- `.gitignore` already covers `DerivedData/` and `.build/`.

## Object IDs used in `project.pbxproj`

| ID | Object |
| --- | --- |
| `000000000000000000000030` | `XCLocalSwiftPackageReference "CheckStitchCore"` |
| `000000000000000000000031` | `XCSwiftPackageProductDependency CheckStitchCore` |
| `000000000000000000000040` | FS sync group `CheckStitchTests` |
| `000000000000000000000041` | `CheckStitchTests.xctest` file ref |
| `000000000000000000000050` | FS sync group `CheckStitchUITests` |
| `000000000000000000000051` | `CheckStitchUITests.xctest` file ref |
| `000000000000000000000060` | PBXBuildFile: CheckStitchCore in Frameworks (app) |
| `000000000000000000000061` | PBXBuildFile: CheckStitchCore in Frameworks (unit tests) |
| `000000000000000000000062` | PBXBuildFile: CheckStitchCore in Frameworks (UI tests) |
| `000000000000000200000000` | `CheckStitchTests` native target |
| `000000000000000210000000` | config list `CheckStitchTests` |
| `000000000000000211000000` / `000000000000000212000000` | Debug / Release configs |
| `000000000000000220000000` / `…0221000000` / `…0222000000` | Sources / Frameworks / Resources phases |
| `000000000000000200000001` / `000000000000000200000002` | target dependency / container proxy |
| `000000000000000300000000` | `CheckStitchUITests` native target |
| `000000000000000310000000` | config list `CheckStitchUITests` |
| `000000000000000311000000` / `000000000000000312000000` | Debug / Release configs |
| `000000000000000320000000` / `…0321000000` / `…0322000000` | Sources / Frameworks / Resources phases |
| `000000000000000300000001` / `000000000000000300000002` | target dependency / container proxy |

Existing IDs referenced: project `…000000000000000000000000`, main group `…000001`,
app FS sync group `…000010`, Products group `…000020`, app target `…0100000000`,
app Debug/Release configs `…0111000000`/`…0112000000`, app Frameworks phase
`…0130000000`, app file ref `…0120`.

---

## Phase 1: Test Harness Scaffolding

### Changes

#### 1. `CheckStitchCore/Package.swift` — **create**

```swift
// swift-tools-version: 6.0
import PackageDescription

// Sources only: the package is tested by the app-hosted CheckStitchTests target
// (@testable import CheckStitchCore), never by `swift test` — no Tests/ dir.
let package = Package(
    name: "CheckStitchCore",
    platforms: [
        .iOS("18.7"),
        .macOS("27.0"),
    ],
    products: [
        .library(name: "CheckStitchCore", targets: ["CheckStitchCore"])
    ],
    targets: [
        .target(name: "CheckStitchCore")
    ])
```

Do **not** add `.defaultIsolation(MainActor.self)` — invalid at tools 6.0 (Pre-flight).

#### 2. `CheckStitchCore/Sources/CheckStitchCore/Placeholder.swift` — **create (temporary)**

SwiftPM errors on a target with zero source files. This file only exists until Phase 2.

```swift
/// Temporary: SwiftPM requires at least one source file. Deleted in Phase 2.
public enum CheckStitchCore {}
```

#### 3. `CheckStitchTests/SmokeTests.swift` — **create**

```swift
@testable import CheckStitchCore
import Testing

/// Proves the app-hosted macOS unit target executes, discovers Swift Testing
/// suites, and links CheckStitchCore. Kept after Phase 2 as a permanent canary.
struct SmokeTests {
    @Test
    func harnessRuns() {
        #expect(Bool(true), "Swift Testing harness executes")
    }
}
```

#### 4. `CheckStitch.xcodeproj/project.pbxproj` — **modify**

Add the package reference, the local package product, the two test native targets with
build phases, file refs, FS sync groups, dependencies, build configurations and
configuration lists, and wire the app target to the package. Exact edits:

**4a. Insert a `PBXBuildFile` section** (it does not exist yet) immediately before
`/* Begin PBXFileReference section */`:

```
/* Begin PBXBuildFile section */
		000000000000000000000060 /* CheckStitchCore in Frameworks */ = {isa = PBXBuildFile; productRef = 000000000000000000000031 /* CheckStitchCore */; };
		000000000000000000000061 /* CheckStitchCore in Frameworks */ = {isa = PBXBuildFile; productRef = 000000000000000000000031 /* CheckStitchCore */; };
		000000000000000000000062 /* CheckStitchCore in Frameworks */ = {isa = PBXBuildFile; productRef = 000000000000000000000031 /* CheckStitchCore */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		000000000000000200000002 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 000000000000000000000000 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 000000000000000100000000;
			remoteInfo = CheckStitch;
		};
		000000000000000300000002 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 000000000000000000000000 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 000000000000000100000000;
			remoteInfo = CheckStitch;
		};
/* End PBXContainerItemProxy section */
```

**4b. `PBXFileReference`** — add after the `CheckStitch.app` reference:

```
		000000000000000000000041 /* CheckStitchTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = CheckStitchTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
		000000000000000000000051 /* CheckStitchUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = CheckStitchUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

**4c. `PBXFileSystemSynchronizedRootGroup`** — add two groups after the `CheckStitch` group:

```
		000000000000000000000040 /* CheckStitchTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = CheckStitchTests;
			sourceTree = "<group>";
		};
		000000000000000000000050 /* CheckStitchUITests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = CheckStitchUITests;
			sourceTree = "<group>";
		};
```

**4d. `PBXFrameworksBuildPhase`** — add the package product to the app phase and add two
phases:

```
		000000000000000130000000 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			files = (
				000000000000000000000060 /* CheckStitchCore in Frameworks */,
			);
		};
		000000000000000221000000 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			files = (
				000000000000000000000061 /* CheckStitchCore in Frameworks */,
			);
		};
		000000000000000321000000 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			files = (
				000000000000000000000062 /* CheckStitchCore in Frameworks */,
			);
		};
```

**4e. `PBXGroup`** — root group children become:

```
			children = (
				000000000000000000000010 /* CheckStitch */,
				000000000000000000000040 /* CheckStitchTests */,
				000000000000000000000050 /* CheckStitchUITests */,
				000000000000000000000020 /* Products */,
			);
```

Products children gain:

```
				000000000000000000000041 /* CheckStitchTests.xctest */,
				000000000000000000000051 /* CheckStitchUITests.xctest */,
```

**4f. `PBXNativeTarget`** — add the app's `packageProductDependencies` and two new targets:

```
		000000000000000100000000 /* CheckStitch */ = {
			…existing keys unchanged…
			packageProductDependencies = (
				000000000000000000000031 /* CheckStitchCore */,
			);
			…
		};
		000000000000000200000000 /* CheckStitchTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 000000000000000210000000 /* Build configuration list for PBXNativeTarget "CheckStitchTests" */;
			buildPhases = (
				000000000000000220000000 /* Sources */,
				000000000000000221000000 /* Frameworks */,
				000000000000000222000000 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				000000000000000200000001 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				000000000000000000000040 /* CheckStitchTests */,
			);
			name = CheckStitchTests;
			packageProductDependencies = (
				000000000000000000000031 /* CheckStitchCore */,
			);
			productName = CheckStitchTests;
			productReference = 000000000000000000000041 /* CheckStitchTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		000000000000000300000000 /* CheckStitchUITests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 000000000000000310000000 /* Build configuration list for PBXNativeTarget "CheckStitchUITests" */;
			buildPhases = (
				000000000000000320000000 /* Sources */,
				000000000000000321000000 /* Frameworks */,
				000000000000000322000000 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				000000000000000300000001 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				000000000000000000000050 /* CheckStitchUITests */,
			);
			name = CheckStitchUITests;
			packageProductDependencies = (
				000000000000000000000031 /* CheckStitchCore */,
			);
			productName = CheckStitchUITests;
			productReference = 000000000000000000000051 /* CheckStitchUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		};
```

**4g. `PBXProject`** — `TargetAttributes` gains both test targets, `packageReferences`
and `targets` gain entries:

```
				TargetAttributes = {
					000000000000000100000000 = {
						CreatedOnToolsVersion = 26.3;
					};
					000000000000000200000000 = {
						CreatedOnToolsVersion = 26.3;
						TestTargetID = 000000000000000100000000;
					};
					000000000000000300000000 = {
						CreatedOnToolsVersion = 26.3;
					};
				};
				…
				packageReferences = (
					000000000000000000000030 /* XCLocalSwiftPackageReference "CheckStitchCore" */,
				);
				…
				targets = (
					000000000000000100000000 /* CheckStitch */,
					000000000000000200000000 /* CheckStitchTests */,
					000000000000000300000000 /* CheckStitchUITests */,
				);
```

**4h. `PBXResourcesBuildPhase` and `PBXSourcesBuildPhase`** — two empty phases each:

```
		000000000000000222000000 /* Resources */ = {isa = PBXResourcesBuildPhase; files = ( ); };
		000000000000000322000000 /* Resources */ = {isa = PBXResourcesBuildPhase; files = ( ); };
		000000000000000220000000 /* Sources */ = {isa = PBXSourcesBuildPhase; files = ( ); };
		000000000000000320000000 /* Sources */ = {isa = PBXSourcesBuildPhase; files = ( ); };
```

(Expand to the normal multi-line form used in the file.)

**4i. `PBXTargetDependency`** — new section before `PBXFileReference`:

```
/* Begin PBXTargetDependency section */
		000000000000000200000001 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 000000000000000100000000 /* CheckStitch */;
			targetProxy = 000000000000000200000002 /* PBXContainerItemProxy */;
		};
		000000000000000300000001 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 000000000000000100000000 /* CheckStitch */;
			targetProxy = 000000000000000300000002 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */
```

**4j. `XCBuildConfiguration`** — four new configurations. `CheckStitchTests` Debug
(mirror for Release):

```
		000000000000000211000000 /* Debug configuration for PBXNativeTarget "CheckStitchTests" */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 6NWX2DHB9Q;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.7;
				MACOSX_DEPLOYMENT_TARGET = 27.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitchTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = auto;
				STRING_CATALOG_GENERATE_SYMBOLS = NO;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/CheckStitch.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CheckStitch";
			};
			name = Debug;
		};
```

`CheckStitchUITests` Debug (mirror for Release) — no `BUNDLE_LOADER`/`TEST_HOST`, instead:

```
				PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitchUITests;
				TEST_TARGET_NAME = CheckStitch;
```

> **Critical (design Risk 3):** do **not** add `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
> to either test target. The app target sets it (`project.pbxproj:284, 326`); the test
> targets must not, so suites opt in per-suite and cannot pass vacuously.

**4k. `XCConfigurationList`** — two new lists, and add to the tail of the section:

```
		000000000000000210000000 /* Build configuration list for PBXNativeTarget "CheckStitchTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				000000000000000211000000 /* Debug configuration for PBXNativeTarget "CheckStitchTests" */,
				000000000000000212000000 /* Release configuration for PBXNativeTarget "CheckStitchTests" */,
			);
			defaultConfigurationName = Release;
		};
		000000000000000310000000 /* Build configuration list for PBXNativeTarget "CheckStitchUITests" */ = { …311000000/312000000… };
```

**4l. New sections at the end** (before the closing `};`):

```
/* Begin XCLocalSwiftPackageReference section */
		000000000000000000000030 /* XCLocalSwiftPackageReference "CheckStitchCore" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = CheckStitchCore;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		000000000000000000000031 /* CheckStitchCore */ = {
			isa = XCSwiftPackageProductDependency;
			productName = CheckStitchCore;
		};
/* End XCSwiftPackageProductDependency section */
```

#### 5. `CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme` — **create**

No scheme file exists today; `xcodebuild -scheme CheckStitch … test` needs a committed
TestAction. Model on `SingleThread.xcscheme:1-96`: `BuildAction` with the app entry
(`buildForTesting="YES"`), `TestAction` `shouldAutocreateTestPlan="YES"` with two
`TestableReference`s (`skipped="NO" parallelizable="YES"`) pointing at
`000000000000000200000000` / `CheckStitchTests.xctest` and
`000000000000000300000000` / `CheckStitchUITests.xctest`, plus the standard
Launch/Profile/Analyze/Archive actions for the app (`ReferencedContainer =
"container:CheckStitch.xcodeproj"`).

### Verification

#### Automated
- [x] `xcodebuild -list -project CheckStitch.xcodeproj` lists three targets
      (`CheckStitch`, `CheckStitchTests`, `CheckStitchUITests`) and scheme `CheckStitch`
- [x] `bash -c 'cd CheckStitchCore && swift build'` succeeds (package stands alone on macOS)
- [x] `xcodebuild -scheme CheckStitch -destination 'platform=macOS' -configuration Debug -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests test` is green (proves the macOS-hosted `.xctest` is viable — design Risk 6)
- [x] `make build` unchanged and green
- [x] `git diff --stat` shows only the pbxproj, the new package/tests files and the scheme

#### Manual
- [ ] `git stash` the package reference temporarily is **not** needed — instead confirm
      `xcodebuild -list` output shows the package in `xcodebuild -showBuildSettings`
      (`grep -c CheckStitchCore`) — cheaper sanity check than opening Xcode
- [ ] Open `CheckStitch.xcodeproj` in Xcode **only if** `xcodebuild -list` fails; if it
      does fail, the fallback is `ruby -e 'require "xcodeproj"; Xcodeproj::Project.open(...)'`
      on a copy to compare structure (gem only supports objectVersion 77)

---

## Phase 2: Pure Models

### Changes

#### 1. `CheckStitchCore/Sources/CheckStitchCore/ChecklistItem.swift` — **create**

```swift
import Foundation

/// Editable row model for a checklist item. The ID is stable so rows can be
/// added, removed, and edited without conflating duplicate titles.
public struct ChecklistItem: Identifiable, Equatable, Sendable {
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
```

> Note: `Equatable` is added so tests can compare values; `Sendable` for Swift 6.

#### 2. `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidth.swift` — **create**

```swift
import CoreGraphics

/// Viewport-relative cap for the checklist content, mirroring SingleThread's
/// CardWidth. Returns `min(ceiling, fraction)` so the content hugs narrow
/// screens but never balloons on wide (iPad) screens.
///
/// `nonisolated` keeps the pure math callable outside the app target's
/// `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
public enum ChecklistWidth {
    nonisolated public static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat {
        min(340, viewportWidth * 0.6)
    }
}
```

#### 3. `CheckStitchCore/Sources/CheckStitchCore/AppearanceMode.swift` — **create**

Move the existing file verbatim (`CheckStitch/AppearanceMode.swift:1-120`) into the
package, with: `import Foundation`, `import SwiftUI`, the `#if os(iOS) import UIKit` /
`#if os(macOS) import AppKit` guards, `public enum AppearanceMode: String, CaseIterable,
Sendable`, and `public struct AppearanceModePreference`. Every member gets `public`:
`windowOverrideStyle`, `appKitAppearance`, `colorScheme`, `systemImage`, `title`,
`static func load(from:)`, `static let defaultsKey`, `var rawValue`, `func setRawValue`,
`init(defaults:key:)`. Bodies are unchanged from the current file.

#### 4. Delete `CheckStitch/AppearanceMode.swift`

The file is fully superseded by the package copy.

#### 5. `CheckStitch/ContentView.swift` — **modify**

- Delete the `enum ChecklistWidth { … }` block (currently `:152-156`) and the
  `struct ChecklistItem { … }` block (currently `:158-163`).
- Add `import CheckStitchCore` (keep `import SwiftUI`; `import EventKit` and `import os`
  stay until Phase 5 removes their remaining uses — Phase 2 leaves them, Phase 6 prunes).

#### 6. `CheckStitchTests/TestFixtures.swift` — **create**

```swift
import CheckStitchCore
import Foundation

/// Builds an item without saving anything anywhere.
func makeItem(_ title: String) -> ChecklistItem {
    ChecklistItem(title: title)
}

/// A `UserDefaults` isolated from `.standard`, wiped so appearance suites can
/// never read or write the real app preference.
func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "CheckStitchTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

#### 7. `CheckStitchTests/ChecklistWidthTests.swift` — **create**

```swift
@testable import CheckStitchCore
import Testing

struct ChecklistWidthTests {
    @Test
    func maxContentWidthScalesBelowCeiling() {
        #expect(ChecklistWidth.maxContentWidth(viewportWidth: 200) == 120)
    }

    @Test
    func maxContentWidthClampsAtCeiling() {
        #expect(ChecklistWidth.maxContentWidth(viewportWidth: 1000) == 340)
    }

    @Test
    func maxContentWidthHitsCeilingAtBoundary() {
        #expect(ChecklistWidth.maxContentWidth(viewportWidth: 340 / 0.6) == 340)
    }
}
```

#### 8. `CheckStitchTests/ChecklistItemTests.swift` — **create**

```swift
@testable import CheckStitchCore
import Testing

struct ChecklistItemTests {
    @Test
    func checklistItemStableIdentityForDuplicateTitles() {
        let first = makeItem("one")
        let second = makeItem("one")
        #expect(first.id != second.id, "duplicate titles must not share identity")
        #expect(first == ChecklistItem(id: first.id, title: "one"))
    }
}
```

#### 9. `CheckStitchTests/AppearanceModeTests.swift` — **create**

```swift
@testable import CheckStitchCore
import Foundation
import Testing

struct AppearanceModeTests {
    @Test(arguments: ["system", "light", "dark"])
    func appearanceModeLoadsValidRawValue(_ raw: String) {
        let defaults = makeIsolatedDefaults()
        AppearanceModePreference(defaults: defaults).setRawValue(raw)
        #expect(AppearanceMode.load(from: defaults) == AppearanceMode(rawValue: raw))
    }

    @Test(arguments: [nil, "", " ", "\n", ".light", "bogus"] as [String?])
    func invalidRawValueFallsBackToSystem(_ raw: String?) {
        let defaults = makeIsolatedDefaults()
        if let raw { AppearanceModePreference(defaults: defaults).setRawValue(raw) }
        #expect(AppearanceMode.load(from: defaults) == .system)
    }
}
```

#### 10. `CheckStitchTests/AppearanceModePreferenceTests.swift` — **create**

```swift
@testable import CheckStitchCore
import Foundation
import Testing

struct AppearanceModePreferenceTests {
    @Test
    func preferenceSetThenReadRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let preference = AppearanceModePreference(defaults: defaults)
        preference.setRawValue("dark")
        #expect(preference.rawValue == "dark")
        #expect(AppearanceMode.load(from: defaults) == .dark)
    }

    @Test
    func preferenceIgnoresUnknownStoredValue() {
        let defaults = makeIsolatedDefaults()
        defaults.set("sepia", forKey: AppearanceModePreference.defaultsKey)
        #expect(AppearanceModePreference(defaults: defaults).rawValue == "system")
    }
}
```

### Verification

#### Automated
- [x] macOS `-only-testing:CheckStitchTests` run green (four new suites + `SmokeTests`)
- [x] `make build` green — proves the app compiles against the package types
- [x] `rg -n "struct ChecklistItem|enum ChecklistWidth" CheckStitch/` returns nothing

> **Deviation (implementation)**: `ChecklistWidthTests.swift` additionally imports
> `CoreGraphics` — without it the `CGFloat` literal conversions (`viewportWidth: 200`,
> `340 / 0.6`) fail with *"missing import of defining module 'CoreFoundation'"*.
> SingleThread's `CardWidthTests.swift` carries the same `import CoreGraphics`.

#### Manual
- [ ] `make run` launches the app; the checklist screen renders as before (no behaviour
      change in this phase)

---

## Phase 3: EventKit Seam (protocol + real adapter + spy)

### Changes

#### 1. `CheckStitchCore/Sources/CheckStitchCore/ReminderCreating.swift` — **create**

```swift
import EventKit

/// Seam over the EventKit surface the checklist flow needs: permission and
/// per-item reminder creation. Injected via `Environment` so tests can drive
/// denial and failure without touching EventKit.
public protocol ReminderCreating: Sendable {
    func requestAccess() async throws -> Bool
    func create(title: String) async throws
}

/// Real adapter over one long-lived `EKEventStore`.
///
/// `EKReminder` holds a weak reference to its store, so a single store must
/// outlive every reminder it creates — never construct a store per call.
///
/// `@MainActor` is what makes this class implicitly `Sendable`; a non-isolated
/// class storing a non-`Sendable` `EKEventStore` cannot satisfy
/// `ReminderCreating: Sendable`.
@MainActor
public final class EventKitReminderCreator: ReminderCreating {
    public init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    public func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    public func create(title: String) async throws {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        try eventStore.save(reminder, commit: true)
    }

    private let eventStore: EKEventStore
}
```

#### 2. `CheckStitchTests/TestFixtures.swift` — **modify** (append)

```swift
import EventKit

/// A single `EKEventStore` kept alive for the test session. `EKReminder` holds
/// a weak reference to its store, so a deallocated store crashes (SIGTRAP) on
/// any property read — this global must outlive every reminder built from it.
@MainActor
let sharedTestEventStore = EKEventStore()

/// Test double for `ReminderCreating`: records created titles and can be told
/// to deny access or throw. `@MainActor` makes it implicitly `Sendable`.
@MainActor
final class SpyReminderCreator: ReminderCreating {
    var accessGranted = true
    var accessError: Error?
    var createError: Error?
    /// Invoked at the start of every `create(title:)` — lets a suite observe
    /// view-model state while the work is in flight.
    var onCreate: (() -> Void)?
    private(set) var createdTitles: [String] = []

    func requestAccess() async throws -> Bool {
        if let accessError { throw accessError }
        return accessGranted
    }

    func create(title: String) async throws {
        if let createError { throw createError }
        onCreate?()
        createdTitles.append(title)
    }
}

/// Deterministic error for failure-path assertions.
enum TestError: Error, Equatable {
    case boom
}
```

#### 3. `CheckStitchTests/EventKitReminderCreatorTests.swift` — **create**

> **Deviation from structure** (flagged): the real adapter's permission call cannot be
> exercised in a unit test without prompting and writing real reminders. This suite
> asserts the seam *double* and the adapter's construction contract; the
> permission/creation policy is asserted in Phase 4.

```swift
import EventKit
@testable import CheckStitchCore
import Testing

@MainActor
struct EventKitReminderCreatorTests {
    @Test
    func eventKitCreatorIsConstructibleWithInjectedStore() {
        // Proves the adapter is a thin pass-through over the injected store and
        // never constructs a store of its own. No EventKit API is called.
        let creator = EventKitReminderCreator(eventStore: sharedTestEventStore)
        #expect(String(describing: type(of: creator)) == "EventKitReminderCreator")
    }

    @Test
    func creatorRequestsAccessBeforeCreating() async throws {
        let spy = SpyReminderCreator()
        #expect(try await spy.requestAccess() == true, "access must be requested first")
        try await spy.create(title: "one")
        #expect(spy.createdTitles == ["one"])
    }

    @Test
    func spyRecordsCreatedTitlesInOrder() async throws {
        let spy = SpyReminderCreator()
        try await spy.create(title: "one")
        try await spy.create(title: "two")
        #expect(spy.createdTitles == ["one", "two"])
    }

    @Test
    func creatorSurfacesThrownAccessError() async {
        let spy = SpyReminderCreator()
        spy.accessError = TestError.boom
        await #expect(throws: TestError.boom) { _ = try await spy.requestAccess() }
    }
}
```

> `#expect(throws:)` is not used elsewhere in SingleThread but is the idiomatic Swift
> Testing form; if the runner rejects it, substitute
> `do { _ = try await spy.requestAccess(); Issue.record("expected throw") } catch { #expect(error as? TestError == .boom) }`.

### Verification

#### Automated
- [x] macOS `-only-testing:CheckStitchTests` run green
- [x] The run does **not** present a Reminders permission dialog (manual watch of the run)
- [x] `rg -n "EKEventStore\(\)" CheckStitchCore/ CheckStitchTests/` shows only
      `sharedTestEventStore` (no per-call store construction)

#### Manual
- [ ] Confirm `grep -n SWIFT_DEFAULT_ACTOR_ISOLATION CheckStitch.xcodeproj/project.pbxproj`
      still returns exactly two hits (the app target only)

---

## Phase 4: ChecklistCreator (business logic)

### Changes

#### 1. `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift` — **create**

```swift
import Foundation

/// Outcome of a checklist creation attempt. `permissionDenied` replaces the old
/// silent `return`, so denial is observable rather than a no-op.
public enum ChecklistCreationOutcome: Equatable, Sendable {
    case created(count: Int)
    case permissionDenied
    case failed(String)
}

/// Owns the reminder-creation policy: ask permission, drop blank titles, create
/// one reminder per remaining item.
///
/// Declared `Sendable` explicitly — a `public` struct gets no inferred
/// conformance, and `ChecklistViewModel` would otherwise fail to send it.
public struct ChecklistCreator: Sendable {
    public init(reminders: ReminderCreating) {
        self.reminders = reminders
    }

    public func create(from items: [ChecklistItem]) async -> ChecklistCreationOutcome {
        do {
            guard try await reminders.requestAccess() else { return .permissionDenied }
            var created = 0
            for item in items where !item.isBlank {
                try await reminders.create(title: item.title)
                created += 1
            }
            return .created(count: created)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private let reminders: ReminderCreating
}
```

#### 2. `CheckStitchTests/ChecklistCreatorTests.swift` — **create**

```swift
@testable import CheckStitchCore
import Testing

@MainActor
struct ChecklistCreatorTests {
    @Test(arguments: [nil, "", "   ", "\n\n"] as [String?])
    func createSkipsBlankTitles(_ blank: String?) async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [
            makeItem("one"), makeItem(blank ?? ""), makeItem("two"),
        ])
        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["one", "two"])
    }

    @Test(arguments: ["t", "t "])
    func createReturnsCountForNonBlankItems(_ title: String) async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem(title)])
        #expect(outcome == .created(count: 1))
        #expect(spy.createdTitles == [title], "identical title must be preserved untrimmed")
    }

    @Test
    func allBlankItemsCreateNothing() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem(""), makeItem("  ")])
        #expect(outcome == .created(count: 0))
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func permissionDeniedReturnsOutcomeWithoutCreating() async {
        let spy = SpyReminderCreator()
        spy.accessGranted = false
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem("one")])
        #expect(outcome == .permissionDenied)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func createStopsAndReportsFailureWhenSaveThrows() async {
        let spy = SpyReminderCreator()
        spy.createError = TestError.boom
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem("one"), makeItem("two")])
        #expect(outcome == .failed(TestError.boom.localizedDescription))
        #expect(spy.createdTitles.isEmpty)
    }
}
```

### Verification

#### Automated
- [ ] macOS `-only-testing:CheckStitchTests` run green
- [ ] Blank-title parametrization covers all four blank shapes and both non-blank shapes

#### Manual
- [ ] None (pure logic)

---

## Phase 5: Environment + ChecklistViewModel

### Changes

#### 1. `CheckStitchCore/Sources/CheckStitchCore/Environment.swift` — **create**

```swift
/// Minimal dependency container: a small struct of services, not a framework.
public struct Environment: Sendable {
    public init(reminderCreator: ReminderCreating) {
        self.reminderCreator = reminderCreator
    }

    public let reminderCreator: ReminderCreating
}
```

#### 2. `CheckStitchCore/Sources/CheckStitchCore/ChecklistViewModel.swift` — **create**

```swift
import Foundation
import Observation
import os

/// Drives the checklist screen: owns the editable rows, the checklist name, and
/// the create/spinner/success flags.
@Observable
@MainActor
public final class ChecklistViewModel {
    /// `spinnerDuration` is the minimum time the spinner stays visible once
    /// creation finishes; suites inject `.zero` to keep tests instant.
    public init(environment: Environment, spinnerDuration: Duration = .seconds(1)) {
        creator = ChecklistCreator(reminders: environment.reminderCreator)
        self.spinnerDuration = spinnerDuration
    }

    public var checklistName = "checklist"
    public var items = [
        ChecklistItem(title: "one"),
        ChecklistItem(title: "two"),
        ChecklistItem(title: "three"),
    ]
    public private(set) var isCreatingChecklist = false
    public private(set) var isChecklistCreated = false

    /// Creates one reminder per non-blank item. Denial and failure leave the
    /// success flag false instead of silently returning.
    public func createChecklist() async {
        isCreatingChecklist = true
        // Hold the spinner for at least `spinnerDuration` so saving quickly
        // doesn't flash the progress feedback past the user.
        async let minimumSpinner: Void = Task.sleep(for: spinnerDuration)
        let outcome = await creator.create(from: items)
        try? await minimumSpinner
        isCreatingChecklist = false
        switch outcome {
        case .created:
            isChecklistCreated = true
        case .permissionDenied:
            break
        case .failed(let message):
            Self.logger.error(
                "Failed to create checklist reminders: \(message, privacy: .public)")
        }
    }

    /// Clears the success checkmark once the view's flash window elapses.
    public func dismissCreatedFeedback() {
        isChecklistCreated = false
    }

    private static let logger = Logger(
        subsystem: "app.alanvardy.CheckStitch", category: "Checklist")

    private let creator: ChecklistCreator
    private let spinnerDuration: Duration
}
```

> **Deviation from structure** (flagged): `init` gains a defaulted `spinnerDuration`, and
> `dismissCreatedFeedback()` is added. Without them the 1-second spinner hold either
> lives in the view (untestable flags) or makes every suite sleep ~2 s and makes
> `isChecklistCreated` unobservable after `await`. Visible behaviour is unchanged.

#### 3. `CheckStitchTests/ChecklistViewModelTests.swift` — **create**

```swift
@testable import CheckStitchCore
import Testing

@MainActor
struct ChecklistViewModelTests {
    private func makeViewModel(_ spy: SpyReminderCreator) -> ChecklistViewModel {
        ChecklistViewModel(
            environment: Environment(reminderCreator: spy), spinnerDuration: .zero)
    }

    @Test
    func viewModelStartsWithSeededItems() {
        let viewModel = makeViewModel(SpyReminderCreator())
        #expect(viewModel.items.map(\.title) == ["one", "two", "three"])
        #expect(viewModel.checklistName == "checklist")
        #expect(!viewModel.isCreatingChecklist)
        #expect(!viewModel.isChecklistCreated)
    }

    @Test
    func createChecklistSetsCreatedFlagOnSuccess() async {
        let spy = SpyReminderCreator()
        let viewModel = makeViewModel(spy)
        viewModel.items = [makeItem("one")]
        await viewModel.createChecklist()
        #expect(viewModel.isChecklistCreated)
        #expect(!viewModel.isCreatingChecklist)
        #expect(spy.createdTitles == ["one"])
    }

    @Test
    func createChecklistTogglesSpinnerAroundWork() async {
        let spy = SpyReminderCreator()
        let viewModel = makeViewModel(spy)
        viewModel.items = [makeItem("one")]
        var spinnerDuringWork = false
        spy.onCreate = { spinnerDuringWork = viewModel.isCreatingChecklist }
        await viewModel.createChecklist()
        #expect(spinnerDuringWork, "spinner must be on while reminders are being created")
        #expect(!viewModel.isCreatingChecklist)
    }

    @Test
    func permissionDeniedLeavesCreatedFlagFalse() async {
        let spy = SpyReminderCreator()
        spy.accessGranted = false
        let viewModel = makeViewModel(spy)
        viewModel.items = [makeItem("one")]
        await viewModel.createChecklist()
        #expect(!viewModel.isChecklistCreated)
        #expect(!viewModel.isCreatingChecklist)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func failedCreationLeavesCreatedFlagFalse() async {
        let spy = SpyReminderCreator()
        spy.createError = TestError.boom
        let viewModel = makeViewModel(spy)
        viewModel.items = [makeItem("one")]
        await viewModel.createChecklist()
        #expect(!viewModel.isChecklistCreated)
        #expect(!viewModel.isCreatingChecklist)
    }
}
```

### Verification

#### Automated
- [ ] macOS `-only-testing:CheckStitchTests` run green; total suite wall time stays well under ~10 s (no real sleeps)
- [ ] `rg -n "spinnerDuration" CheckStitchTests/` shows only `.zero` injections

#### Manual
- [ ] None

---

## Phase 6: App Rewiring (presentational layer)

### Changes

#### 1. `CheckStitch/ContentView.swift` — **modify**

- Imports: `import CheckStitchCore`, `import SwiftUI` (drop `import EventKit` and
  `import os` — the logger and EventKit work moved to the package).
- State becomes:

```swift
struct ContentView: View {
    @State private var viewModel: ChecklistViewModel
    @State private var isShowingEditChecklist = false
    @State private var isShowingSettings = false

    @AppStorage(AppearanceModePreference.defaultsKey)
    var appearanceMode = AppearanceMode.system

    init(environment: Environment) {
        _viewModel = State(initialValue: ChecklistViewModel(environment: environment))
    }
```

- `body` destructures a bindable view model for the sheets:

```swift
    var body: some View {
        @Bindable var viewModel = viewModel
        GeometryReader { geometry in
            HStack(spacing: 16) {
                createChecklistButton
                editChecklistButton
            }
            .frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width))
            …
        }
        .onChange(of: appearanceMode) { _, new in
            #if os(iOS)
                AppDelegate.applyAppearance(new)
            #endif
            #if os(macOS)
                MacAppDelegate.applyAppearance(new)
            #endif
        }
        .sheet(isPresented: $isShowingEditChecklist) {
            EditChecklistView(name: $viewModel.checklistName, items: $viewModel.items)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(appearanceMode: $appearanceMode)
        }
        .overlay(alignment: .topTrailing) { … }
    }
```

- The create button loses the persistence code and delegates to the view model:

```swift
    private var createChecklistButton: some View {
        Button {
            Task {
                await viewModel.createChecklist()
                if viewModel.isChecklistCreated {
                    // Flash the checkmark for a beat.
                    try? await Task.sleep(for: .seconds(1))
                    viewModel.dismissCreatedFeedback()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.checklistName).font(.title2.weight(.semibold))
                if viewModel.isCreatingChecklist {
                    ProgressView().controlSize(.small)
                } else if viewModel.isChecklistCreated {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            …unchanged…
        }
        .accessibilityLabel("Create checklist named \(viewModel.checklistName)")
        .accessibilityIdentifier("checklistButton")
    }
```

- **Delete** `func createChecklistReminders() async` (`:126-143`) and
  `private static let logger` (`:6`).
- `EditChecklistView` stays in this file unchanged except that it now uses the package's
  `ChecklistItem`; the `+` button constructs `ChecklistItem(title: "New item")` (same call,
  now the package initializer).
- `#Preview { ContentView() }` → `#Preview { ContentView(environment: Environment(reminderCreator: EventKitReminderCreator(eventStore: EKEventStore()))) }`
  (a preview-only store; never saved through).

#### 2. `CheckStitch/MyApp.swift` — **modify**

```swift
import CheckStitchCore
import SwiftUI
#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

@main
struct MyApp: App {
    // One long-lived store for the app: EKReminder weakly references it, and a
    // fresh store per creation would be deallocated underneath the reminders.
    private let environment = Environment(
        reminderCreator: EventKitReminderCreator(eventStore: EKEventStore()))

    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    #if os(macOS)
        @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var macAppDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
        }
    }
}
```

#### 3. `CheckStitch/AppDelegate.swift` — **modify**

Add `import CheckStitchCore` at the top (above the `#if os(iOS)` block). No other change:
`AppearanceMode`, `AppearanceMode.load`, `windowOverrideStyle` and `appKitAppearance` now
resolve to the package.

#### 4. `CheckStitch/SettingsView.swift` — **modify**

Add `import CheckStitchCore`. Body unchanged; the `#Preview` blocks keep using
`AppearanceMode.dark.colorScheme`.

#### 5. `CheckStitchTests/ViewRenderTests.swift` — **create**

```swift
@testable import CheckStitch
@testable import CheckStitchCore
import SwiftUI
import Testing

@MainActor
struct ViewRenderTests {
    private func makeEnvironment() -> Environment {
        Environment(reminderCreator: SpyReminderCreator())
    }

    @Test
    func contentViewBodyEvaluates() {
        let view = ContentView(environment: makeEnvironment())
        #expect(String(describing: view.body).isEmpty == false)
    }

    @Test
    func settingsViewListsAllAppearanceModes() {
        let view = SettingsView(appearanceMode: .constant(.system))
        #expect(String(describing: view.body).isEmpty == false)
        #expect(AppearanceMode.allCases.map(\.title) == ["System", "Light", "Dark"])
        #expect(AppearanceMode.allCases.map(\.systemImage).allSatisfy { !$0.isEmpty })
    }
}
```

> `ContentView(environment:)` is used directly here, so `SpyReminderCreator` must be
> visible to this file: it is declared in the same target (`TestFixtures.swift`), so no
> import is needed beyond `@testable import`.

### Verification

#### Automated
- [ ] macOS `-only-testing:CheckStitchTests` run green (all suites)
- [ ] `make build` green
- [ ] `rg -n "createChecklistReminders|EKEventStore\(\)" CheckStitch/` returns nothing
- [ ] `rg -n "@AppStorage" CheckStitch/` shows only the `AppearanceModePreference.defaultsKey` form

#### Manual
- [ ] `make run` on the worktree simulator (`845FFF19-…`): tap the checklist button —
      spinner shows ≥1 s, then the green checkmark flashes for ~1 s; Reminders permission
      prompt appears on first tap; denying leaves the button unchanged
- [ ] Open Settings, switch to Dark then back to System; the window follows (macOS) /
      override clears (iOS)
- [ ] Edit the checklist: add, rename, reorder, delete rows; add a blank row and confirm
      creation skips it

---

## Phase 7: UI Smoke Target + Gate

### Changes

#### 1. `CheckStitchUITests/CheckStitchUITests.swift` — **create**

```swift
import XCTest

final class CheckStitchUITests: XCTestCase {

    // `class` is required to override XCTestCase's class property.
    override class var runsForEachTargetApplicationUIConfiguration: Bool { false }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndAccessibilitySmoke() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.buttons["checklistButton"].waitForExistence(timeout: 5),
            "Create-checklist button should render")
        XCTAssertTrue(app.buttons["editChecklistButton"].exists, "Edit button should render")
        XCTAssertTrue(app.buttons["settingsButton"].exists, "Settings button should render")

        // Cheap, non-rendering categories only: .dynamicType/.hitRegion can hang
        // virtualized runners and are covered by unit suites (mirrors
        // SingleThreadUITests).
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
    }
}
```

> Scoped `#if os(iOS)` is unnecessary: the scheme's `-only-testing:CheckStitchUITests` run
> is always against `$(SIM)` (an iOS simulator), never macOS.
>
> **Contingency**: if the audit surfaces a pre-existing violation unrelated to this
> ticket, fix the offending label only if it is a one-line accessibity modifier;
> otherwise narrow the category list and record the omission in the PR description.
> Do **not** expand scope into a UI redesign.

#### 2. `Makefile` — **modify**

Add `MAC_SIM := platform=macOS` next to the existing destination variables, extend
`.PHONY`, and add three targets after `run`:

```make
.PHONY: build run clean test test-unit test-ui

test: test-unit test-ui

# Unit suites run on the macOS host: unsigned, no simulator boot, no App Group gap.
# `SWIFT_DEFAULT_ACTOR_ISOLATION` is not set on test targets, so suites opt in per-suite.
test-unit:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(MAC_SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  CODE_SIGNING_ALLOWED=NO \
	  -only-testing:CheckStitchTests \
	  test

# Exactly one UI smoke case, on this worktree's dedicated simulator (never a
# bare `name=` destination).
test-ui:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  build-for-testing
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  -only-testing:CheckStitchUITests \
	  test-without-building
```

#### 3. `scripts/test.sh` — **modify**

Replace the header comment and insert `make test` between the build and shellcheck:

```bash
#!/bin/bash
# CheckStitch gate: build, unit + UI tests, then static checks over the shell scripts.
set -euo pipefail

cd "$(dirname "$0")/.."

make build
make test

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
else
  echo "warning: shellcheck not installed — skipping script lint" >&2
  for f in scripts/*.sh; do bash -n "$f"; done
fi

echo "gate: ok"
```

### Verification

#### Automated
- [ ] `make test-unit` green
- [ ] `make test-ui` green (boots `845FFF19-…` itself)
- [ ] `bash scripts/test.sh` prints `gate: ok`
- [ ] `shellcheck scripts/*.sh` clean
- [ ] `git diff scripts/run-devices.sh` is empty (untouched)

#### Manual
- [ ] Confirm the UI smoke ran on the worktree simulator, not a shared device:
      `xcrun simctl list devices | grep -i 845FFF19` shows Recent/Booted activity

---

## Phase 8: Documentation Contract

### Changes

#### 1. `AGENTS.md` — **modify**

- **Layout** section: replace "Swift/SwiftUI, one app target, no dependencies." with the
  package + two test targets:

```
Swift/SwiftUI. `CheckStitch/` is the thin app target (views + platform delegates only);
`CheckStitchCore/` is a local sources-only SPM package holding models, the EventKit
seam, the checklist creator and the view model; `CheckStitchTests/` (Swift Testing,
macOS-hosted) and `CheckStitchUITests/` (one XCTest smoke) test them.
```

- **Build, run, gate** section: replace

```
- **There is no test target — the gate is `./scripts/test.sh`**, which runs the
  build plus `shellcheck` over `scripts/`. Do not add a test target as part of a small task; that is a ticket of its own.
```

with

```
- **The gate is `./scripts/test.sh`** — `make build` (simulator) → `make test` →
  `shellcheck scripts/*.sh`, printing `gate: ok`.
- `make test-unit` runs `CheckStitchTests` on `platform=macOS` with
  `CODE_SIGNING_ALLOWED=NO` (no sim, no signing). `make test-ui` runs exactly one
  `CheckStitchUITests` smoke case via `build-for-testing` →
  `test-without-building` on this worktree's `.simulator_id` simulator.
- Unit tests import `@testable import CheckStitchCore`; the UI smoke stays XCTest.
  Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`, so
  suites opt in with `@MainActor` — never restore the app's default there.
```

- **Testing** section: append the naming/parametrization/verification contract:

```
- Unit suites: `struct <Thing>Tests` in Swift Testing (`@Test`, `#expect`), behaviour-named
  functions (never `test`-prefixed), `@Test(arguments:)` for cases, `@MainActor` on any
  suite touching EventKit or the view model. Fakes live in `CheckStitchTests/TestFixtures.swift`.
- Verify with `make test-unit` (fast) before `bash scripts/test.sh` (full gate).
```

- Do not touch `linear-project.md`, `scripts/run-devices.sh`, entitlements or signing.

### Verification

#### Automated
- [ ] `bash scripts/test.sh` still prints `gate: ok` after the edit
- [ ] `rg -n "no test target" AGENTS.md` returns nothing

#### Manual
- [ ] Read the edited sections once for accuracy: every claimed command actually exists
      in `Makefile` / `scripts/test.sh`

---

## Cross-phase notes

- **pbxproj is the highest-risk edit** (design Risk 5). After Phase 1 only, run
  `xcodebuild -list` and `make build` before touching any Swift file. If `xcodebuild -list`
  fails, restore `project.pbxproj` from git and use the `xcodeproj` gem on a **copy** to
  diff structural intent — do not commit a gem-rewritten pbxproj.
- **If the macOS unit run proves non-viable** (design Risk 6), the only change is the
  `test-unit` destination and `TEST_HOST` handling: fall back to
  `-destination '$(SIM)'` with `build-for-testing` + `test-without-building
  -only-testing:CheckStitchTests`. Layout changes nothing.
- **Files never touched**: `scripts/run-devices.sh`, `scripts/run-simulator.sh`,
  `CheckStitch/AppGroup.entitlements`, `linear-project.md`, signing values, bundle id,
  deployment targets.
- Every new `scripts/*.sh` would need mode `100755`; this plan adds no new script.
