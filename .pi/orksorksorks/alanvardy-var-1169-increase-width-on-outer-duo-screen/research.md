# Research Findings

Ticket context: widen the checklist content on the iPhone Duo *outer*
(folded) screen in portrait by halving side padding, scoped to that device +
orientation only. All findings are the current state of the code (no
proposals).

## Q1: How is the list card width computed/constrained, and how do the frame cap and literal padding combine?

### Findings
- `ChecklistWidth` is a `public enum` in Core:
  `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidth.swift:9`.
  - `maxContentWidth(viewportWidth:) -> min(340, viewportWidth * 0.6)`
    (`:10-12`) — the list/header card cap. Doc comment `:3-8` says it mirrors
    SingleThread's `CardWidth` (hug narrow, never balloon on iPad).
  - `editFormMaxWidth(viewportWidth:) -> min(680, viewportWidth)` (`:17-19`)
    — pushed edit forms only, not the list card.
  - Both `nonisolated public static`.
- `maxContentWidth` call sites (app target): `CheckStitch/ContentView.swift:495`
  (iOS-only header row) and `ContentView.swift:512` (the `LazyVStack` card).
- Modifier order at `ContentView.swift:512-523` is load-bearing:
  `.frame(maxWidth: maxContentWidth(...))` (`:512`) sizes the card so the plate
  background/overlay (`:515-522`) match the cap; then `.padding(.horizontal, 32)`
  (`:523`) is applied *outside* the frame. Visible plate stays capped; outer
  footprint is `min(340, 0.6×vw) + 64`.
- After the `VStack` closes the whole block is centred with
  `.frame(maxWidth: .infinity, alignment: .center)` (`ContentView.swift:533`),
  so the capped+padded card floats centred in the `ScrollView`.
- The same cap+32 pattern repeats on the iOS header row: `:495` (cap) then
  `:496` `.padding(.horizontal, 32)`, keeping header aligned to the card column.
- Both caps read `geometry.size.width` from the `GeometryReader` at
  `ContentView.swift:457` (the `ScrollView` viewport width).
- Implication: halving the literal `32` alone cannot widen the capped card once
  the viewport is wide enough that `0.6×vw` reaches 340 (i.e. `vw >= ~566`); on
  a narrow outer-screen portrait the `0.6` fraction is the active lever. This is
  the SPEC ambiguity named in classify.

## Q2: Where is horizontal padding applied, with what literal values, and is any derived?

### Findings
All padding values are literals; none derive from a shared constant, viewport,
or device trait. Padding lives only in `ContentView.swift` and
`ChecklistSelectionView.swift` (plus unrelated `PaywallView.swift:52`);
`CheckStitchWatch/`/`CheckStitchWidget/` have none.

Main list screen — `ContentView.swift`:
- `:496` `.padding(.horizontal, 32)` — iOS edit-toggle / "New Folder" header row.
- `:523` `.padding(.horizontal, 32)` — the checklist **card** outer margin.
- `:749` `.padding(.horizontal, 32)` — `emptyState` card.
- `:580` `.padding(.horizontal, 16)` — each `checklistRow`.
- `:667` `.padding(.horizontal, 16)` — `folderHeader`.
- `:640` `.padding(.leading, 24)` — nested folder-member rows.
- `:471`, `:484` `.padding(.horizontal, 14)` — iOS edit-mode chrome plates.
- `:151`, `:158` leading/trailing `12` — floating 52×52 create/settings overlays.
- `:925` `.padding(8)` — `syncStatusView` (all edges).

Selection sheet — `ChecklistSelectionView.swift`:
- `:71-72` `.padding(.horizontal, 18)`/`.vertical, 8)` — `actionButton`.
- `:95`, `:148` bare `.padding()` (SwiftUI default ≈16) — sheet header/footer.

Edit forms use **no** literal padding — `.checklistEditFormWidth(viewportWidth:)`
(`ChecklistEditFormWidth.swift:14-15`) = `editFormMaxWidth` cap + centring frame.

Derivation summary:
- Viewport-derived: `maxContentWidth` (card/header) and `editFormMaxWidth`
  (forms). The `.padding` literals themselves are not.
- `CardPlate.swift` supplies corner radius (`:15`), `checklistTopMargin` (`:27`),
  `checklistRowHeight` (`:34`), fills/borders — **no** padding constant.
- Net literals in use: 32, 24, 18, 16, 14, 12, 8 (plus default ≈16).
  `32` at three sites (`:496`, `:523`, `:749`); `16` at two (`:580`, `:667`).

## Q3: How do viewport geometry, size classes, and orientation reach Core?

### Findings
- Width reaches Core **only** as a raw `CGFloat` from SwiftUI `GeometryReader`:
  `ContentView.swift:457` → `geometry.size.width` → `ChecklistWidth` (`:495`,
  `:512`). Edit forms: own `GeometryReader` (`ChecklistDetailView.swift:38`,
  `ChecklistOptionsView.swift:27`, `ItemEditView.swift:21`) →
  `.checklistEditFormWidth` (`ChecklistEditFormWidth.swift:12`) →
  `editFormMaxWidth`. No `UIScreen.main.bounds`, no scene-geometry read.
- **Size classes are unused repo-wide.** `horizontalSizeClass`,
  `verticalSizeClass`, `SizeClass`, `UIDevice` have zero hits across `*.swift`.
- **Orientation never reaches Core.** It is app-target-only:
  - `OrientationPreference` (`CheckStitch/OrientationPreference.swift:14-40`)
    wraps `UserDefaults`, key `"allowsLandscape"` (`:24`), default `true`
    (`:27-29`).
  - `OrientationPolicy` enum (`:48-63`), `init(allowsLandscape:)` → `.portrait`
    / `.allButUpsideDown` (`:52-54`); the UIKit `mask` mapping is an iOS-only
    extension (`:58-66`) kept out of the cross-platform enum so logic is
    unit-testable on macOS (`:44-46`).
  - `AppDelegate.swift:55-60` reads it in `supportedInterfaceOrientationsFor`;
    `applyLock(allowsLandscape:)` (`:38-52`) calls
    `setNeedsUpdateOfSupportedInterfaceOrientations()` (`:46`) then
    `scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))` (`:47-48`).
  - Forwarding: `AppearanceViewModel.swift:17-21` under `#if os(iOS)`.
  - `@AppStorage("allowsLandscape")` is the ContentView binding
    (`ContentView.swift:24`).
- Core has **no** orientation/size-class parameter — it sees only `CGFloat`.
- macOS device identity: `MacAppDelegate` uses `NSScreen.screens`
  (`AppDelegate.swift:91,121`) only to re-frame off-screen windows, never Core
  layout.

## Q4: What platform-conditional patterns exist, and how are they structured?

### Findings
- Targets: `CheckStitch/` (iOS+macOS app), `CheckStitchWatch/`,
  `CheckStitchWidget/`, `CheckStitchCore` (sources-only SPM).
  - App/test config: `SDKROOT = auto`, `SUPPORTED_PLATFORMS =
    "iphoneos iphonesimulator macosx"`, `TARGETED_DEVICE_FAMILY = "1,2"`
    (`CheckStitch.xcodeproj/project.pbxproj:634-688`).
  - Watch: `SDKROOT = watchos`, `TARGETED_DEVICE_FAMILY = 4`,
    `WATCHOS_DEPLOYMENT_TARGET = 26.0` (`:806-844`).
  - `MACOSX_DEPLOYMENT_TARGET = 27.0` throughout (`:521`, `:701`, …).
  - `CheckStitchCore/Package.swift:8-12`: iOS 18.7, macOS 27.0, watchOS 26.0.
- Shared-code convention: one Core source set; platform split by `#if` **inside**
  files, not target-specific copies.
  - Cross-platform colour shim `CheckStitch/Color+CrossPlatform.swift:3-17`
    (`#if os(macOS) import AppKit #else import UIKit`).
  - `AppearanceMode.swift:3,6,23,35` (app) and Core duplicate `:3,6,23,35` use
    `#if os(iOS) import UIKit` / `#if os(macOS) import AppKit` branches.
- Whole-file gating: `PhoneSyncAdapter.swift:1` (`#if os(iOS)`),
  `AppDelegate.swift:1`/`:72`, `SettingsSubscreenLayout.swift:3-21`
  (`#if os(macOS)` with an `#else self` no-op), `ChecklistShare.swift:4,31`,
  `OrientationPreference.swift:2,57`; Core `ReminderCreating.swift:38` /
  `EventKitReminderDestination.swift:56` (`#if !os(watchOS)`).
- Dense inline cluster: `ContentView.swift:56,88,114,138,261,363,375,411,460,525`
  (`#if os(macOS)`/`#if os(iOS)` toolbar/header branches). `MyApp.swift`
  `:3,6,11,15,29,79,127` handles app-vs-mac delegates and `WindowGroup`.
- Capability gating: `WidgetRunState.swift:2,148` uses `#if canImport(WidgetKit)`
  (not `#if os`), so the same file links in app/watch targets.
- **No `@available(...)` anywhere** in the four source roots; platform
  differences use target selection + `#if os` / `#if !os` / `#if canImport`.
- Test-side gating: `CheckStitchUITests/CheckStitchUITests.swift:31-34`,
  whole-file `#if os(macOS)` in `CheckStitchTests/MacWindowFrameTests.swift:1`,
  `InterfaceSettingsViewTests.swift:12,29`.

## Q5: How are Core APIs and view/layout behaviours pinned by tests?

### Findings
- Width math is covered only at the Core level: `ChecklistWidthTests.swift:5`
  (plain `struct`, no `@MainActor`, `@testable import CheckStitchCore`) pins
  `maxContentWidth(200)==120` (`:8`), `==340` at 1000 (`:13`), boundary at
  `340/0.6` (`:18`), `editFormMaxWidth(390)==390` (`:25`), `==680` at 1366
  (`:32`). `ScalingTests.swift:5` uses `@Test(arguments:)` for core clamping.
- **App-side call sites are not width-asserted**: `ContentView.swift:495,512`,
  `ChecklistDetailView.swift:197`, `ItemEditView.swift:83`,
  `ChecklistOptionsView.swift:84`, `ChecklistEditFormWidth.swift:12` have no
  width-value test; only the Core functions they delegate to are covered.
- Render oracle pattern: `ViewRenderTests.swift:18-30` private `renders(_:)`
  returns `ImageRenderer(content:).nsImage != nil` (macOS) / `.uiImage != nil`
  (`#else`). Same helper duplicated in `ChecklistOptionsViewTests.swift:20,35`,
  `ExportChecklistsViewTests.swift:111-114`, `PurchaseSettingsViewTests.swift:66-69`,
  `AboutViewTests.swift:23`; inline `#if os(macOS) … #else` variant in
  `ChecklistDetailViewTests.swift:72,165,181,213,283,305,321,356`.
- When rendering cannot reach a value, tests pin view value slots via
  `String(describing:)` (`ChecklistDetailViewTests.swift:19,60-65`;
  `ViewRenderTests.swift:34-54`) or pin driving constants directly:
  `CardPlateTests.swift:5` states the rationale (`:6-8`) and asserts
  `checklistTopMargin == 100` (`:30`), mirroring `ChecklistWidthTests`.
- Fixtures: `CheckStitchTests/TestFixtures.swift` (`@MainActor`), with
  `makeIsolatedDefaults()` for store-backed render tests.
- `@MainActor` convention: test targets deliberately don't inherit
  `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites touching view model/EventKit/render
  opt in (`ViewRenderTests.swift:6`, `ChecklistDetailViewTests.swift:13`,
  ~40 suites). Pure-core suites don't (`ChecklistWidthTests`, `ScalingTests`).
  `BackgroundImageStoreTests.swift:8`, `SettingsBindingsTests.swift:6` add
  `@Suite(.serialized)`.
- Platform gating: whole-file `#if os(macOS)` in `MacWindowFrameTests.swift`
  (open `:1`, close `:63`) and `ColorCrossPlatformTests.swift:5`; per-case
  `#if os(iOS)/#else` in `InterfaceSettingsViewTests.swift:12-19,29-39`.
- **No test asserts a literal horizontal padding value** (14/16/18/32 at the
  ContentView/ChecklistSelectionView sites); padding is only exercised
  indirectly through render canaries. No UI-test coverage of width/padding.

## Q6: What platform APIs exist for identifying a foldable's cover/outer screen and its orientation?

### Findings (web research — external APIs, cite sources)
- No public API labels a display "cover"/"outer"/"inner", and there is no
  foldable-specific product type.
- Device model: `UIDevice.model` returns only the family string ("iPhone");
  there is no `productType` on iOS. The model identifier comes from POSIX
  `uname`/`sysctl hw.machine` (undocumented trick): `struct utsname`,
  `uname(&info).machine` → e.g. `"iPhone17,1"`. Both displays of one device
  share the same identifier, so it cannot distinguish outer vs inner.
  [UIDevice](https://developer.apple.com/documentation/uikit/uidevice),
  [UIDevice.model](https://developer.apple.com/documentation/uikit/uidevice/model).
- Screen dimensions: `UIScreen.bounds` (points), `nativeBounds` (pixels),
  `scale`/`nativeScale`, `coordinateSpace`; aspect ratio derived from bounds.
  `UIScreen.main` is deprecated and ambiguous on a two-display device; read via
  `window?.windowScene?.screen`, scale via `traitCollection.displayScale`.
  [UIScreen](https://developer.apple.com/documentation/uikit/uiscreen),
  [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo).
- Scene geometry: `UIWindowScene.effectiveGeometry` (`UIWindowScene.Geometry`,
  iOS 16+, KVO-compliant) → `coordinateSpace.bounds`, `interfaceOrientation`;
  delegate callback `windowScene(_:didUpdateEffectiveGeometry:)` fires on screen
  moves. Changes requested via `UIWindowScene.GeometryPreferences.iOS(
  interfaceOrientations:)` + `requestGeometryUpdate(_:errorHandler:)` (may be
  denied).
- Duo pose APIs (iOS 27.1 beta): `UIHinge` / `UIHingeInteraction` /
  `UIHinge.Status` (`.closed`/`.partiallyOpen`/`.fullyOpen`/`.unknown`) with a
  continuous `angle`; SwiftUI `onHingeChange`. Reserved regions:
  `UIView.reservedRegionsOfKind:options:` / SwiftUI
  `GeometryProxy.reservedRegions(kind:)` with `.occlusion` and `.division`
  kinds — `.division` locates the fold and is active only when partially open
  or closed. Arrangement views (`ArrangementView` /
  `UIArrangementViewController`) contain panes across poses.
  [UIHinge](https://developer.apple.com/documentation/uikit/uihinge),
  [UIViewReservedRegion](https://developer.apple.com/documentation/uikit/uiviewreservedregion),
  [ReservedRegion](https://developer.apple.com/documentation/swiftui/reservedregion).
- Interface orientation is **not** a reliable signal on the Duo inner display
  (Apple: it ignores `supportedInterfaceOrientations`); branch on size classes
  instead. Outer display behaves ≈ a normal iPhone (compact×regular portrait).
- Gap: no public API returns a per-display role (outer/inner); Duo pose APIs
  are beta and names/availability may change.

## Cross-Cutting Observations
- **Single width lever:** the card's visible width is fully determined by
  `ChecklistWidth.maxContentWidth`; the `32` padding is gutter *outside* the
  cap. On a narrow outer-screen portrait (`0.6×vw < 340`) the fraction is the
  active term.
- **No device/orientation input exists in Core.** Core is pure `CGFloat` math;
  any device-conditional behaviour must be decided in the app target and passed
  through the existing `viewportWidth`-style seam (mirroring how
  `OrientationPolicy` keeps UIKit out of testable cross-platform code).
- **Padding literals are duplicated, not centralised** (`32` ×3, `16` ×2), and
  no test pins them — only the Core width functions are pinned.
- **Platform differences are `#if`-inside-one-file**, never target-specific Core
  copies; watchOS/Widget are guarded by `#if os`/`#if canImport`.
- **Test seam convention:** pure Core math → plain `struct` suite; anything
  touching rendering/EventKit → `@MainActor` suite + `ImageRenderer` canary;
  unrenderable constants → direct `#expect` on the constant (CardPlate model).

## Open Areas
- Whether `geometry.size.width` at `ContentView.swift:457` is safe-area adjusted
  was not traced; only the raw read was confirmed.
- Whether the outer-screen portrait viewport width actually makes `0.6×vw`
  or the `340` ceiling the active term was not measured on a device; no Duo
  simulator/device evidence exists in the repo.
- No precedent for reading device model, hinge, or reserved regions anywhere in
  the repo; the Duo APIs in Q6 are external documentation only.
- The `project.pbxproj:868-908` third config block (`SDKROOT = iphoneos`) was
  noted but its owning target was not identified.
