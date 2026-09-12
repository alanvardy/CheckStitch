# Implementation Plan

## Overview

Port SingleThread's background subsystem into CheckStitch as five bottom-up
layers (fade math → fetch/persist store → photo-layer seam → prefs bag →
settings surface & `ContentView` mount). Because CheckStitch has no test
target, Stage 0 lands the `CheckStitchTests` target and widens the gate; every
later stage ships its own Swift Testing suite and must leave
`bash scripts/test.sh` green before the next starts.

Reference files (all read-only, on this machine):

- `/Users/vardy/dev/SingleThread/SingleThread/{BackgroundImageStore,BackgroundFade,BackgroundSettingsView,SettingsSubscreenLayout,SettingsBindings,ContentView+Settings}.swift`
- `/Users/vardy/dev/SingleThread/SingleThreadTests/{BackgroundImageStoreTests,BackgroundPhotoLayerTests,BackgroundFadeTests,BackgroundTestFixtures,TestFixtures}.swift`

Repo root: `/Users/vardy/dev/alanvardy-var-976-add-backgrounds`.
Destination precedence is owned by the `Makefile` (`.simulator_id` =
`D270AE57-041E-4634-8BC4-1489FDF1E3E6`); never hardcode a bare `name=`.

---

## Stage 0: Test target & gate

### Changes

#### 1. Test harness file

**File**: `CheckStitchTests/HarnessTests.swift`
**Action**: create

```swift
import Testing

@Suite
struct HarnessTests {
    @Test
    func harnessRuns() {
        #expect(true)
    }
}
```

#### 2. Test target in the project

**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify

Add the following objects (UUIDs are free; these are new and unused). Insert
each into its matching `/* Begin … section */`:

- `PBXFileReference`:

```text
		CC0000000000000000000002 /* CheckStitchTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = CheckStitchTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

- `PBXFileSystemSynchronizedRootGroup` (tests get their **own** root group;
  the app target's `CheckStitch` group is untouched):

```text
		CC0000000000000000000003 /* CheckStitchTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = CheckStitchTests;
			sourceTree = "<group>";
		};
```

- Build phases (`PBXSourcesBuildPhase`, `PBXFrameworksBuildPhase`,
  `PBXResourcesBuildPhase`) — all three with empty `files = ( );` and
  `runOnlyForDeploymentPostprocessing = 0;`, using
  `CC0000000000000000000004` (Sources), `CC0000000000000000000005`
  (Frameworks), `CC0000000000000000000006` (Resources).

- `PBXContainerItemProxy` + `PBXTargetDependency` (test target depends on the
  app target):

```text
		CC0000000000000000000008 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 000000000000000000000000 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 000000000000000100000000;
			remoteInfo = CheckStitch;
		};
		CC0000000000000000000007 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 000000000000000100000000 /* CheckStitch */;
			targetProxy = CC0000000000000000000008 /* PBXContainerItemProxy */;
		};
```

- `PBXNativeTarget`:

```text
		CC0000000000000000000001 /* CheckStitchTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CC0000000000000000000009 /* Build configuration list for PBXNativeTarget "CheckStitchTests" */;
			buildPhases = (
				CC0000000000000000000004 /* Sources */,
				CC0000000000000000000005 /* Frameworks */,
				CC0000000000000000000006 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				CC0000000000000000000007 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				CC0000000000000000000003 /* CheckStitchTests */,
			);
			name = CheckStitchTests;
			productName = CheckStitchTests;
			productReference = CC0000000000000000000002 /* CheckStitchTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
```

- `PBXGroup`: append `CC0000000000000000000003 /* CheckStitchTests */,` to the
  main group's `children` (after the `CheckStitch` group) and
  `CC0000000000000000000002 /* CheckStitchTests.xctest */,` to the `Products`
  group's `children`.
- `PBXProject.attributes.TargetAttributes`: add
  `CC0000000000000000000001 = { CreatedOnToolsVersion = 26.3; };`
  and append `CC0000000000000000000001 /* CheckStitchTests */,` to `targets`.

- Two `XCBuildConfiguration` blocks (`CC000000000000000000000A` Debug,
  `CC000000000000000000000B` Release, identical settings) and one
  `XCConfigurationList` (`CC0000000000000000000009`, default `Release`):

```text
		CC000000000000000000000A /* Debug */ = {
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

(Release block identical, `name = Release;`.) **Do not** set
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the test target — the reference
test target omits it, and the fake fetchers are `nonisolated @unchecked
Sendable`; test funcs opt into `@MainActor` explicitly.

#### 3. Shared scheme

**File**: `CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme`
**Action**: create (the folder `xcshareddata/xcschemes` does not exist yet).
Model on `SingleThread.xcscheme`; blueprint ids are
`000000000000000100000000` (app) and `CC0000000000000000000001`
(CheckStitchTests):

- `BuildAction` entry for `CheckStitch.app` (`buildForTesting/Running/
  Profiling/Archiving/Analyzing = YES`).
- `TestAction` with `shouldAutocreateTestPlan = "YES"` and one
  `TestableReference` (`skipped = "NO"`, `parallelizable = "YES"`) for
  `CheckStitchTests.xctest`.
- `LaunchAction`/`ProfileAction`/`AnalyzeAction`/`ArchiveAction` as in the
  reference (no StoreKit reference file).

#### 4. Makefile: test target reusing `$(SIM)`

**File**: `Makefile`
**Action**: modify — add `test` to `.PHONY` and:

```make
test: build
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  $(if $(FILTER),-only-testing:$(FILTER)) \
	  test
```

#### 5. Gate script

**File**: `scripts/test.sh`
**Action**: modify — replace the `make build` line with `make test` (the
target depends on `build`, so the build still gates), keep the shellcheck
block, update the header comment:

```bash
#!/bin/bash
# CheckStitch gate: simulator build + unit tests (CheckStitchTests) + shellcheck.
set -euo pipefail

cd "$(dirname "$0")/.."

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
- [x] `make build` still succeeds (proves the pbxproj edit did not break the
      app target)
- [x] `bash scripts/test.sh` green (build + `xcodebuild test` + shellcheck)
- [x] `make test FILTER=CheckStitchTests/HarnessTests` green
- [x] Negative check, run once locally: change `#expect(true)` to
      `#expect(false)`, confirm `bash scripts/test.sh` fails, then revert.

#### Manual
- [ ] `make run` still builds, installs, and launches unchanged.

---

## Stage 1: `BackgroundFade`

### Changes

#### 1. Fade enum

**File**: `CheckStitch/BackgroundFade.swift`
**Action**: create — copy
`/Users/vardy/dev/SingleThread/SingleThread/BackgroundFade.swift` verbatim
(38 lines): `enum BackgroundFade` with `defaultValue = 50`, `step = 10`,
`allValues = Array(stride(from: 0, through: 90, by: step))`,
`opacity(for:) = 1 - Double(percent.clamped(to: 0...90)) / 100`, and the
private `Int.clamped(to:)` extension.

#### 2. Tests

**File**: `CheckStitchTests/BackgroundFadeTests.swift`
**Action**: create — copy `BackgroundFadeTests.swift` verbatim except
`@testable import SingleThread` → `@testable import CheckStitch`.

### Verification

#### Automated
- [x] `bash scripts/test.sh` green
- [x] `make test FILTER=CheckStitchTests/BackgroundFadeTests` green

#### Manual
- [ ] None — pure math.

---

## Stage 2: `BackgroundImageStore`

### Changes

#### 1. Store (fetch, decode, persist, pin)

**File**: `CheckStitch/BackgroundImageStore.swift`
**Action**: create — copy
`/Users/vardy/dev/SingleThread/SingleThread/BackgroundImageStore.swift`
**verbatim except** these deltas:

1. **Drop** the whole trailing `struct BackgroundPhotoLayer` (Stage 3 owns it).
2. Logger subsystem: `app.alanvardy.SingleThread` → `app.alanvardy.CheckStitch`.
3. `defaultDirectory` appends `"CheckStitch"` (not `"SingleThread"`).
4. Keep the fetch protocol exactly as the reference — `fetchData(from:) async
   throws -> Data` plus the `URLSession` conformance that guards
   `HTTPURLResponse` status `200..<300` and throws
   `URLError(.badServerResponse)`. (Note: the structure outline wrote a
   `data(from:) -> (Data, URLResponse)` signature; the SingleThread reference
   contract — which the design mandates as verbatim — is `fetchData`. Using
   `fetchData` avoids a name collision with `URLSession.data(from:)` and is
   what the 19 ported tests exercise.)

Everything else is unchanged: `@MainActor @Observable final class`,
`init(client:directory:)`, `private(set) imageData/photographer/
photographerURL/isRefreshing/isPinned`, `imageURL`/`metadataURL`,
`refreshIfNeeded(maxAge:)` with the post-await pin re-check,
`forceRefresh()`, `setPinned(_:)`, `loadStoredImage()`, private
`FetchedWallpaper`/`BackgroundMetadata`/`UnsplashPayload`, `commit`
(disk **before** observable state), `persist` (atomic writes), `isFresh`,
`isDecodableImage` (`#if os(iOS) UIImage / #elseif os(macOS) NSImage`),
endpoints `https://vardy.cc/unsplash` and `.../unsplash/random`,
`defaultMaxAge = 86400`.

#### 2. Test fixtures and fakes

**File**: `CheckStitchTests/BackgroundTestFixtures.swift`
**Action**: create — contains:
- `enum BackgroundTestFixtures` with the `jpegData` 1×1-JPEG base64 constant,
  copied verbatim from
  `/Users/vardy/dev/SingleThread/SingleThreadTests/BackgroundTestFixtures.swift`.
- The three fakes copied verbatim from
  `/Users/vardy/dev/SingleThread/SingleThreadTests/TestFixtures.swift`
  (`// MARK: - Background-fetcher fakes` section):
  `FakeBackgroundFetcher`, `actor FetchGate`, `GatedBackgroundFetcher`.
  (`SeededFetcher` is unused by the ported suites — omit it.)

#### 3. Store tests

**File**: `CheckStitchTests/BackgroundImageStoreTests.swift`
**Action**: create — copy
`/Users/vardy/dev/SingleThread/SingleThreadTests/BackgroundImageStoreTests.swift`
verbatim, changing only `@testable import SingleThread` →
`@testable import CheckStitch`. This is the full 19-case set: success
persists bytes+sidecar, non-image rejected, failure retains prior, 23h fresh
vs 25h stale under the 24h default, fresh skips network, corrupt/missing
sidecar clears image+credit, credit/URL pairing, `forceRefresh` bypasses
freshness and pin, forceRefresh failure resets `isRefreshing`, attribution
update, `isRefreshing` mid-flight, pin blocks except when no image, re-pin
during fetch does not commit, unpin refreshes only when stale, unpin no-op
when fresh, true→false-only transition. Sad paths include non-2xx, undecodable
payload, and non-image bytes. No network: all fetchers are injected fakes.

### Verification

#### Automated
- [ ] `bash scripts/test.sh` green
- [ ] `make test FILTER=CheckStitchTests/BackgroundImageStoreTests` green
- [ ] No network in the gate — the suite runs against injected fakes only.

#### Manual
- [ ] None — the live endpoint is exercised in Stage 6's `make run` checklist.

---

## Stage 3: `BackgroundPhotoLayer`

### Changes

#### 1. Layer

**File**: `CheckStitch/BackgroundPhotoLayer.swift`
**Action**: create — the `struct BackgroundPhotoLayer` extracted from the
SingleThread `BackgroundImageStore.swift` trailing block, unchanged:

```swift
struct BackgroundPhotoLayer: View {
    let imageData: Data?
    var isEnabled = true
    var opacity = BackgroundFade.opacity(for: BackgroundFade.defaultValue)

    var body: some View {
        if isEnabled, let image = imageData.flatMap(Self.image(from:)) {
            Color.clear
                .overlay { image.resizable().scaledToFill() }
                .ignoresSafeArea()
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    static func image(from data: Data) -> Image? {
        #if os(macOS)
            NSImage(data: data).map(Image.init(nsImage:))
        #else
            UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }
}
```

Imports: `import SwiftUI` plus the platform-gated `#if os(iOS) import UIKit /
#elseif os(macOS) import AppKit`. `Color.clear.overlay { … }` is
load-bearing: it pins the layer to the parent's size so `scaledToFill` can
never expand the surrounding layout.

#### 2. Tests

**File**: `CheckStitchTests/BackgroundPhotoLayerTests.swift`
**Action**: create — copy the three reference tests verbatim, changing the
import to `@testable import CheckStitch`: `imageFromValidJPEGDataIsNonNil`,
`imageFromInvalidDataIsNil` (sad path), and `constructsWithValidAndNilData`
(covers the nil-data and `isEnabled == false` construction paths).

### Verification

#### Automated
- [ ] `bash scripts/test.sh` green
- [ ] `make test FILTER=CheckStitchTests/BackgroundPhotoLayerTests` green

#### Manual
- [ ] In the Stage 6 `make run` check, confirm the centered buttons do **not**
      stretch or shift when the background photo is enabled (this is the
      layout-non-expansion property the `Color.clear.overlay` wrapper exists
      for; it has no renderable seam and is verified visually, not asserted).

---

## Stage 4: `SettingsBindings`

### Changes

#### 1. Narrowed prefs bag

**File**: `CheckStitch/SettingsBindings.swift`
**Action**: create

```swift
import SwiftUI

/// Snapshot of the background preferences, staged while the Settings sheet is
/// open. Only the three background keys live here; `appearanceMode` keeps its
/// direct `@Binding` because its side effect lives on `ContentView`.
@MainActor
@Observable
final class SettingsBindings {
    init(
        backgroundEnabled: Bool = true,
        backgroundFadePercent: Int = BackgroundFade.defaultValue,
        backgroundPinned: Bool = false) {
        self.backgroundEnabled = backgroundEnabled
        self.backgroundFadePercent = backgroundFadePercent
        self.backgroundPinned = backgroundPinned
    }

    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var backgroundPinned: Bool
}
```

No App-Group tier, no `excludedLists`, no store-backed computed properties.

> **Deviation from structure**: the `ContentView` helpers
> (`makeSettingsBag`/`settingsSheetWritebacks`) are declared in Stage 5, not
> here. They read `ContentView`'s `@AppStorage` properties and construct the
> new `SettingsView` signature, neither of which exists until Stage 5; adding
> them here would not compile.

#### 2. Tests

**File**: `CheckStitchTests/SettingsBindingsTests.swift`
**Action**: create

```swift
import Foundation
@testable import CheckStitch
import Testing

@MainActor
@Suite(.serialized)
struct SettingsBindingsTests {
    @Test
    func defaultsMatchPreferenceDefaults() {
        let bag = SettingsBindings()
        #expect(bag.backgroundEnabled)
        #expect(bag.backgroundFadePercent == BackgroundFade.defaultValue)
        #expect(!bag.backgroundPinned)
    }

    @Test
    func stagedMutationDoesNotTouchUserDefaults() {
        let original = UserDefaults.standard.object(forKey: "backgroundEnabled")
        defer { UserDefaults.standard.set(original, forKey: "backgroundEnabled") }

        let bag = SettingsBindings()
        bag.backgroundEnabled = false
        bag.backgroundFadePercent = 80
        bag.backgroundPinned = true

        #expect(UserDefaults.standard.object(forKey: "backgroundEnabled") as? Bool != false)
    }

    @Test
    func snapshotReadsCurrentUserDefaults() {
        UserDefaults.standard.set(false, forKey: "backgroundEnabled")
        UserDefaults.standard.set(70, forKey: "backgroundFadePercent")
        UserDefaults.standard.set(true, forKey: "backgroundPinned")
        defer { Self.clearPreferences() }

        let view = ContentView()
        let bag = view.makeSettingsBag()

        #expect(!bag.backgroundEnabled)
        #expect(bag.backgroundFadePercent == 70)
        #expect(bag.backgroundPinned)
    }

    @Test
    func writeBackPersistsEachKey() {
        defer { Self.clearPreferences() }
        let view = ContentView()
        let bag = SettingsBindings(
            backgroundEnabled: false,
            backgroundFadePercent: 70,
            backgroundPinned: true)

        view.writeBack(bag)

        #expect(UserDefaults.standard.bool(forKey: "backgroundEnabled") == false)
        #expect(UserDefaults.standard.integer(forKey: "backgroundFadePercent") == 70)
        #expect(UserDefaults.standard.bool(forKey: "backgroundPinned") == true)
    }

    private static func clearPreferences() {
        for key in ["backgroundEnabled", "backgroundFadePercent", "backgroundPinned"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
```

(`writeBack(_:)` is added to `ContentView` in Stage 5 — see below.)

### Verification

#### Automated
- [ ] `bash scripts/test.sh` green
- [ ] `make test FILTER=CheckStitchTests/SettingsBindingsTests` green

#### Manual
- [ ] None.

---

## Stage 5: Settings surface (pushed Background subscreen)

> Stages 5 and 6 land together; the `ContentView` sheet wiring in this stage is
> required to keep the app compiling once `SettingsView`'s signature grows.

### Changes

#### 1. macOS subscreen layout fix

**File**: `CheckStitch/SettingsSubscreenLayout.swift`
**Action**: create — copy
`/Users/vardy/dev/SingleThread/SingleThread/SettingsSubscreenLayout.swift`
verbatim (macOS-only `ViewModifier` + `extension View.settingsSubscreenLayout()`,
identity on iOS).

#### 2. Background subscreen

**File**: `CheckStitch/BackgroundSettingsView.swift`
**Action**: create

```swift
import SwiftUI

struct BackgroundSettingsView: View {
    @Binding var backgroundEnabled: Bool
    @Binding var backgroundFadePercent: Int
    @Binding var backgroundPinned: Bool
    var backgroundImage: BackgroundImageStore

    var body: some View {
        Form {
            Toggle(isOn: $backgroundEnabled) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Background")
                        caption("Show a wallpaper behind the checklist.")
                    }
                } icon: {
                    Image(systemName: "photo")
                }
            }
            .accessibilityIdentifier("backgroundToggle")

            Picker(selection: $backgroundFadePercent) {
                ForEach(BackgroundFade.allValues, id: \.self) { percent in
                    Text("\(percent)%").tag(percent)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Background Fade")
                    caption("How much the wallpaper fades for readability.")
                }
            }
            .accessibilityIdentifier("backgroundFadePicker")

            Section {
                Toggle(isOn: $backgroundPinned) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Pin wallpaper")
                            caption("Prevents the background from refreshing automatically.")
                        }
                    } icon: {
                        Image(systemName: "pin")
                    }
                }
                .accessibilityIdentifier("pinWallpaperToggle")
            }

            Section {
                Button {
                    Task { await backgroundImage.forceRefresh() }
                } label: {
                    HStack {
                        Label("Refresh wallpaper", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if backgroundImage.isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(backgroundImage.isRefreshing)
                .accessibilityIdentifier("refreshWallpaperButton")
            }

            Section {} footer: {
                if let photographer = backgroundImage.photographer {
                    let credit = "Photo by \(photographer) on Unsplash"
                    if let url = backgroundImage.photographerURL {
                        Link(credit, destination: url)
                    } else {
                        Text(credit)
                    }
                }
            }
        }
        .navigationTitle("Background")
        .settingsSubscreenLayout()
    }

    @ViewBuilder
    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        BackgroundSettingsView(
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(BackgroundFade.defaultValue),
            backgroundPinned: .constant(false),
            backgroundImage: BackgroundImageStore())
    }
}
```

Captions are inlined with the `caption` helper because CheckStitch has no
`SettingsCaption`/`SettingsLinkLabel` types (structure's file list does not add
them).

#### 3. Settings root gains the Background row

**File**: `CheckStitch/SettingsView.swift`
**Action**: modify

Header becomes:

```swift
struct SettingsView: View {
    @Binding var appearanceMode: AppearanceMode
    @Bindable var bindings: SettingsBindings
    var backgroundImage: BackgroundImageStore
    @Environment(\.dismiss) private var dismiss
```

Add inside the existing `Form`, after the appearance `Section`:

```swift
                Section {
                    NavigationLink {
                        BackgroundSettingsView(
                            backgroundEnabled: $bindings.backgroundEnabled,
                            backgroundFadePercent: $bindings.backgroundFadePercent,
                            backgroundPinned: $bindings.backgroundPinned,
                            backgroundImage: backgroundImage)
                    } label: {
                        Label("Background", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("settingsBackgroundRow")
                }
```

Update both `#Preview`s to the new signature:

```swift
#Preview {
    SettingsView(
        appearanceMode: .constant(AppearanceMode.system),
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore())
}
```

#### 4. `ContentView`: prefs, store, bag, and sheet wiring

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add stored properties next to the existing `@State` block:

```swift
    @State private var backgroundImage = BackgroundImageStore()
    @State private var settingsBag: SettingsBindings?

    @AppStorage("backgroundEnabled") var backgroundEnabled = true
    @AppStorage("backgroundFadePercent") var backgroundFadePercent = BackgroundFade.defaultValue
    @AppStorage("backgroundPinned") var backgroundPinned = false
```

> **Deviation from structure**: the three `@AppStorage` properties move from
> Stage 6 into Stage 5 because `makeSettingsBag()` reads them. Stage 6 only
> adds the ZStack mount and the fetch/pin triggers.

Gear action snapshots the bag before presenting:

```swift
    private var settingsButton: some View {
        Button {
            settingsBag = makeSettingsBag()
            isShowingSettings = true
        } label: { … }
    }
```

Settings sheet renders through the writeback helper and nils the bag on
dismiss:

```swift
        .sheet(isPresented: $isShowingSettings) {
            if let bag = settingsBag {
                settingsSheetWritebacks(bag)
            }
        }
        .onChange(of: isShowingSettings) { _, showing in
            if !showing { settingsBag = nil }
        }
```

Helpers (add at file scope, e.g. below `ContentView`):

```swift
extension ContentView {
    /// Renders the Settings sheet over the staged bag and writes each staged
    /// change back to the `@AppStorage`-backed property so it survives relaunch.
    func settingsSheetWritebacks(_ bag: SettingsBindings) -> some View {
        SettingsView(
            appearanceMode: $appearanceMode,
            bindings: bag,
            backgroundImage: backgroundImage)
            .onChange(of: bag.backgroundEnabled) { _, _ in writeBack(bag) }
            .onChange(of: bag.backgroundFadePercent) { _, _ in writeBack(bag) }
            .onChange(of: bag.backgroundPinned) { _, _ in writeBack(bag) }
    }

    /// Persists every staged background preference. Extracted so it is
    /// exercisable without a live SwiftUI hierarchy (see SettingsBindingsTests).
    func writeBack(_ bag: SettingsBindings) {
        backgroundEnabled = bag.backgroundEnabled
        backgroundFadePercent = bag.backgroundFadePercent
        backgroundPinned = bag.backgroundPinned
    }

    /// Fresh bag snapshotted from the current stored preferences on sheet open.
    func makeSettingsBag() -> SettingsBindings {
        SettingsBindings(
            backgroundEnabled: backgroundEnabled,
            backgroundFadePercent: backgroundFadePercent,
            backgroundPinned: backgroundPinned)
    }
}
```

### Verification

#### Automated
- [ ] `bash scripts/test.sh` green (all suites; no new suite)
- [ ] `make build` green for the iOS simulator destination

#### Manual
- [ ] `make run`: gear opens Settings; a **Background** row is present and
      pushes a subscreen titled "Background" with toggle, fade picker, pin
      toggle, refresh button, and (once an image has loaded) a credit footer.
- [ ] Toggle / picker / pin / refresh all respond; refresh shows a spinner and
      is disabled while refreshing.
- [ ] `SettingsBindingsTests` still measures the snapshot/writeback contract
      added in Stage 4.
- [ ] macOS check (out of gate): open the project in Xcode, build and run the
      macOS destination, and confirm the pushed Background subscreen is
      top-aligned, not vertically centered.

---

## Stage 6: `ContentView` mount — ZStack, fetch trigger, pin wiring

### Changes

#### 1. Paint the photo behind the checklist and drive the store

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Wrap the existing `GeometryReader { … }` (unchanged) in a ZStack and attach
the lifecycle triggers:

```swift
    var body: some View {
        ZStack {
            Color.systemBackground.ignoresSafeArea()
            BackgroundPhotoLayer(
                imageData: backgroundImage.imageData,
                isEnabled: backgroundEnabled,
                opacity: BackgroundFade.opacity(for: backgroundFadePercent))
            GeometryReader { geometry in
                // …existing centered HStack, untouched…
            }
        }
        .task {
            // Pin BEFORE the first refresh so a pinned cold launch never
            // refetches a stale stored image (mirrors SingleThread's ordering).
            await backgroundImage.setPinned(backgroundPinned)
            await backgroundImage.refreshIfNeeded()
        }
        .onChange(of: backgroundPinned) { _, pin in
            Task { await backgroundImage.setPinned(pin) }
        }
        .onChange(of: appearanceMode) { … existing … }
        .sheet(isPresented: $isShowingEditChecklist) { … existing … }
        .sheet(isPresented: $isShowingSettings) { … existing … }
        .onChange(of: isShowingSettings) { … existing … }
        .overlay(alignment: .topTrailing) { settingsButton … }
    }
```

> **Deviation from structure**: the structure's `.task` snippet called
> `refreshIfNeeded()` *before* `setPinned(backgroundPinned)`. That order lets a
> pinned cold launch with a stale stored image refetch before the pin is
> applied (a pin violation). Ordering `setPinned` first matches
> `SingleThread/ContentView.swift:258-267` and keeps pin semantics correct.

Existing behaviour is otherwise untouched: centered content frame, spinner
timing, Edit-checklist sheet, `ChecklistWidth`, `#Preview`. `Color.systemBackground`
is the same base-layer style used by the reference mount.

### Verification

#### Automated
- [ ] `bash scripts/test.sh` green (build + all suites; `#Preview` blocks still
      compile)
- [ ] `make build` green

#### Manual
- [ ] `make run` (cold launch): the wallpaper renders full-bleed behind the
      checklist card; windows/resize keep the buttons centered and unstretched.
- [ ] Toggle Background off → photo hidden, base colour remains; on → photo
      returns without a refetch.
- [ ] Fade picker at 0% shows the photo strongest, 90% barely; the change is
      immediate.
- [ ] Pin on: relaunch after >24h (or delete/mutate the sidecar timestamp) does
      **not** refetch. Unpin with a stale image: image refreshes.
- [ ] Refresh button: spinner appears, is disabled mid-flight, and on success a
      new photo/credit appears; a tap while pinned still refreshes.
- [ ] Credit footer link opens the Unsplash photographer page.
- [ ] Kill and relaunch: the last photo + credit persist (Application
      Support/CheckStitch) and are shown before/without a fresh fetch.

---

## Testing Checkpoints

After each stage `bash scripts/test.sh` must be green before the next starts.
Resume points if context resets:

- **After Stage 0** — `CheckStitchTests` target, shared scheme, `make test`,
  widened gate.
- **After Stage 1** — fade math.
- **After Stage 2** — store lifecycle (19 cases).
- **After Stage 3** — photo-layer seam.
- **After Stage 4** — prefs bag.
- **Stages 5–6** land together and checkpoint on build + the manual `make run`
  list above.

**Residual, not gated**: the real `vardy.cc/unsplash` endpoint (ATS,
reachability), the macOS settings-subscreen alignment, and the
layout-non-expansion property of the photo layer are manual-only this ticket;
the gate runs the iOS simulator destination.

## Deviations from `structure.md`

1. **`BackgroundImageFetching` uses `fetchData(from:) async throws -> Data`**,
   not `data(from:) async throws -> (Data, URLResponse)`. The design mandates
   the SingleThread reference contract verbatim, and the 19 ported tests assume
   it. Resolved, not open.
2. **`@AppStorage` background keys are declared in Stage 5**, not Stage 6,
   because the Stage 5 sheet helpers read them.
3. **`SettingsBindings.swift` holds only the bag**; the `ContentView` helpers
   (`makeSettingsBag`, `settingsSheetWritebacks`, plus a small `writeBack`) are
   added in Stage 5 once their dependencies exist.
4. **`Makefile` gains a `test` target** (structure listed only `scripts/test.sh`);
   this is the only way to reuse the `SIM` precedence without duplicating it.
5. **Stage 3 layout seam is manual-only**: CheckStitch has no renderable
   `rowChromeBackground`-style seam, and the design explicitly forbids porting
   that seam, so the `Color.clear.overlay` non-expansion is verified visually.
6. **`.task` calls `setPinned` before `refreshIfNeeded`** to preserve pin
   semantics on cold launch (see Stage 6 note).
