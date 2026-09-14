# Research Findings

## Q1: View hierarchy composition and the macOS vs iOS NavigationStack paths

### Findings
- Root composition (`CheckStitch/ContentView.swift:25-33`): a `ZStack` with, bottom→top: `Color.systemBackground.ignoresSafeArea()` (:26), `BackgroundPhotoLayer(imageData:isEnabled:opacity:)` (:27-30), `NavigationStack(path:)` (:31). The photo layer sits **between** the systemBackground fill and the NavigationStack's content; its visibility depends entirely on what the NavigationStack's container paints.
- App entry is platform-neutral in structure: both macOS (`CheckStitch/MyApp.swift:36-55`) and iOS (:56-84) use `WindowGroup { ContentView() … }`; macOS adds `.restorationBehavior(.disabled)` (:48), iOS adds coordinator scaffolding (:61-74). No extra layer wraps ContentView on either platform.
- Complete `#if os(...)` inventory in ContentView (verified against source):
  - **A** :38-49 — macOS-only `.toolbar` (create in `.navigation` slot, settings gear as `.primaryAction`).
  - **B** :54-60 — iOS-only `.containerBackground(.clear, for: .navigation)` with comment :55-58: "iOS 26's NavigationStack paints an opaque container behind its content, so the ZStack photo is invisible on iPhone/iPad (macOS's stack is already transparent)." **This is the single conditional that restores photo visibility on iOS and is entirely absent on macOS.**
  - **C** :71-76 — appearance `onChange`: iOS calls `AppDelegate.applyAppearance`, macOS calls `MacAppDelegate.applyAppearance`.
  - **D** :78-84 — macOS-only `.preferredColorScheme(appearanceMode.colorScheme)` (canvas does not pick up window-level `NSWindow.appearance`; comment :79-81).
  - **E** :96-115 — iOS-only floating chrome overlays (`.topLeading`/`.topTrailing` 52×52 plates, `path.isEmpty`-guarded); comment :98-103 notes iOS 26's navigation toolbar paints a translucent chip plate behind toolbar buttons, so overlays are used instead.
  - **F** :129-135 — `createButtonPlacement`: `.topBarLeading` on iOS, `.navigation` otherwise.
  - **G** :137-172, 176-212 — `createButton`/`settingsButton`: iOS renders `CardPlate` 52×52 plates; macOS renders plain `Label(…, systemImage:)` glyphs (macOS title bar draws its own chrome).
  - **H** :234-242 — checklist top padding: iOS `CardPlate.checklistTopMargin` (starts below the floating plates), macOS `16`.
- Result: macOS's rendering path relies on **assumed** NavigationStack/window transparency with zero explicit clearing; iOS's path has the explicit transparency opt-out.

## Q2: How BackgroundPhotoLayer draws, and wrapper layout characteristics

### Findings
- Only platform split in `CheckStitch/BackgroundPhotoLayer.swift` is the decode: macOS `NSImage(data:).map(Image.init(nsImage:))` (:22-23), other platforms `UIImage(data:).map(Image.init(uiImage:))` (:24-25). No caching — decode re-runs in body each render (:21-27).
- Gate: `if isEnabled, let image = imageData.flatMap(Self.image(from:))` (:14) — disabled or undecodable yields `EmptyView` (zero size contribution). `imageData` is fed straight from `BackgroundImageStore.imageData` at `ContentView.swift:28`.
- The wrapper (:15-20): `Color.clear.overlay { image.resizable().scaledToFill() }.ignoresSafeArea().opacity(opacity).allowsHitTesting(false).accessibilityHidden(true)`.
  - `Color.clear` (:17) is proposal-greedy with **zero intrinsic size**; it accepts the full size the ZStack proposes (:31 proposes full bounds to every child; `Color.systemBackground.ignoresSafeArea()` at :26 makes the ZStack span safe-area-extended bounds). The proposal, not any explicit frame, sizes the layer.
  - `.overlay { … }` (:18) proposes the host's size to the scaled image and **never affects the host's layout size** — comment at :16 documents this: "the overlay wrapper pins the layer to its parent's size so `scaledToFill` can never expand the surrounding layout". This is the mechanism that prevents crop/overdraw from breaking layout; a zero intrinsic size cannot collapse it by construction — the wrapper does not depend on intrinsic size at all.
  - `.ignoresSafeArea()` (:19) extends edge-to-edge behind safe-area regions (title bar region on macOS).
  - `.opacity(opacity)` (:20) fades only the image (`Color.clear` is transparent).
- Opacity comes from `CheckStitch/BackgroundFade.swift`: `1 - percent/100`, clamped 0…90 (:24-26), `defaultValue = 50` → 0.5 (:17); call site `ContentView.swift:30`.
- No shared Image helpers anywhere; grep confirms `BackgroundPhotoLayer.swift` is the sole image-drawing site (the only other match is an SF-Symbol name in `CheckStitchCore/Sources/CheckStitchCore/AppearanceMode.swift:61`).
- Platform neutrality: no `#if os` inside the drawing wrapper; macOS behavior of the wrapper is identical by construction to iOS.

## Q3: BackgroundImageStore load/persist/gating and reach to the view

### Findings
- Location (`CheckStitch/BackgroundImageStore.swift:188-192`): `defaultDirectory` = `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]` + `"CheckStitch"`. **No platform branching** — sandboxing is delegated to `FileManager` on each platform; the only `#if os` in the file is `isDecodableImage` (:202-209: `UIImage(data:) != nil` vs `NSImage(data:) != nil`).
- Files: `imageURL = directory/background.jpg`, `metadataURL = directory/background.json` (:82-90); sidecar `BackgroundMetadata { photographer, photographerURL, fetchedAt }` (:37-40), ISO-8601 JSON (:258-260).
- `refreshIfNeeded` gating (:98-114): `loadStoredImage()` first (:99), then `guard !isPinned || imageData == nil` (:100), `guard !isFresh(maxAge:)` (:101), `guard !isFetching` single-flight (:102); fetch `GET https://vardy.cc/unsplash` (:185-186); **re-checks the pin after the await** (:108-109) so a mid-flight re-pin never commits; error → log "Background refresh failed: …", prior state kept (:112). `isFresh` = 24 h via `defaultMaxAge = 86400` (:181-183, :229-233).
- `forceRefresh` (:122-133) always hits network (`GET …/unsplash/random`, :187-188), guarded by `!isRefreshing, !isFetching`.
- `loadStoredImage` (:145-165): synchronous main-actor disk I/O; any step fails ⇒ nils `imageData`/`photographer`/`photographerURL` (:156-159).
- `BackgroundImageFetching` protocol + `URLSession` extension (:17-31): built-in `data(from:)` wrapped; non-2xx → `URLError(.badServerResponse)`.
- Commit order (:217-227): **persist to disk first** (:224), then flip observable state — disk-before-state keeps photo + attribution consistent.
- Reach to the view: `@State private var backgroundImage = BackgroundImageStore()` (`ContentView.swift:21`, store is `@MainActor @Observable`); `.task` runs `setPinned(backgroundPinned)` **before** `refreshIfNeeded()` (:118-122); `.onChange(of: backgroundPinned)` re-pins (:124-126); layer receives `backgroundImage.imageData` (:28). Rendering is never gated on the network result — `imageData` is `nil` until first success (doc :93-97).

## Q4: Settings storage flow (backgroundEnabled / backgroundFadePercent / backgroundPinned)

### Findings
- Single source of truth: `@AppStorage` at `ContentView.swift:12-14` — `backgroundEnabled = true`, `backgroundFadePercent = BackgroundFade.defaultValue` (50), `backgroundPinned = false`. No `store:` parameter → **`UserDefaults.standard`** on both platforms. Identical keys, identical defaults; no `register(defaults:)` anywhere in the app target.
- App Group `AppGroup.defaults` (`CheckStitch/AppGroup.swift:9-11`) is consumed **only** by `ChecklistStore` (`ChecklistStore.swift:43`) — the three background keys never touch the App Group suite.
- KVS: `NSUbiquitousKeyValueStore` appears only in `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift:20-45` for the single key `"checklists.v1"`. **No background setting is synced anywhere.**
- Settings flow: gear button → `makeSettingsBag()` snapshots stored values into a staging `SettingsBindings` (`ContentView.swift:344-352`; reads `backgroundEnabled` from storage at settings-open time); `.sheet` renders `settingsSheetWritebacks(bag)` (:84-91, :325-334); `writeBack(bag)` (:337-342) copies staged values onto the `@AppStorage` properties on every staged change; sheet close nils the bag (:92-94).
- `SettingsBindings.swift:7-19`: `@MainActor @Observable final class` staging only the three keys (appearanceMode deliberately excluded, keeps a direct `@Binding`).
- Settings views bind the staged bag, not `@AppStorage` directly: `SettingsView.swift:29-38` pushes `BackgroundSettingsView`; only macOS difference in SettingsView is `.preferredColorScheme` (:49-51). `BackgroundSettingsView.swift` has no `#if os(...)` (Toggle :10-24, Picker :26-39, pin toggle :40-54, refresh :57-67).
- Consumption: `backgroundEnabled` re-read from `UserDefaults.standard` at every `body` evaluation for the photo gate (`ContentView.swift:27-30`) — **no platform-conditional read path exists**.
- Conclusion: there is no code path by which `backgroundEnabled` reads false differently on macOS; storage, sync, defaults, and the read point are identical across platforms. The only platform divergence is the rendering-side transparency mechanism (Q1-B).

## Q5: Test patterns for platform-specific behavior and view rendering

### Findings
- **No suite renders the full ContentView composite** and there are no screenshot/snapshot assertions anywhere. `ContentView()` is instantiated only indirectly: `SettingsBindingsTests.swift:28` (`snapshotReadsCurrentUserDefaults`) and `:40` (`writeBackPersistsEachKey`) call `ContentView().makeSettingsBag()` / `writeBack(bag)`. `ViewRenderTests.swift` constructs `SettingsView` (:12) and `SyncStatusView` (:25-52), never ContentView.
- `BackgroundPhotoLayerTests.swift`: pure-construction assertions — `imageFromValidJPEGDataIsNonNil` (:8), `imageFromInvalidDataIsNil` (:11), `constructsWithValidAndNilData` (:14); all `@MainActor`, no SwiftUI render.
- `SettingsBindingsTests.swift`: `@Suite(.serialized)`, mutates `UserDefaults.standard` with deferred cleanup (:58); `defaultsMatchPreferenceDefaults` (:18), `stagedMutationDoesNotTouchUserDefaults` (:23), plus the snapshot/writeBack round-trips above.
- `BackgroundImageStoreTests.swift`: `@Suite(.serialized)`, ~17 tests; pin gating (`pinBlocksRefreshIfNeeded` :162, `pinnedStoreWithNoImageStillFetches` :190, `repinDuringFetchDoesNotCommit` :205, `forceRefreshBypassesPin` :238, `unpinTriggersRefreshWhenStale` :254, `unpinDoesNotRefreshWhenFresh` :273, `unpinOnlyTriggersOnTrueToFalseTransition` :294), single-flight (`isRefreshingToggledDuringForceRefresh` :151).
- `BackgroundFadeTests.swift`: opacity inversion/clamping used by the layer wrapper.
- Platform gating: only `MacWindowFrameTests.swift:1` wraps a whole file in `#if os(macOS)`. macOS-vs-iOS divergence is otherwise handled by Makefile destination selection (unit tests run macOS-hosted) and by `CheckStitchUITests.swift:30` (`#if os(iOS)` swaps the XCUI accessibility audit category list because the macOS test phase compiles this bundle too).
- Fakes/seams (`BackgroundTestFixtures.swift`): `jpegData` 1×1 base64 JPEG (:9) that passes the store's `isDecodableImage` gate with no network; `FakeBackgroundFetcher: BackgroundImageFetching` with `stubbedData[URL: Result<Data, Error>]` + recorded `requestedURLs` (:39); `FetchGate` actor (:56) and `GatedBackgroundFetcher` (:88) park fetches in flight for race tests; temp-directory injection via `BackgroundImageStore(client:directory:)` (`makeStore` helper, `BackgroundImageStoreTests.swift:317`); isolated storage via `TestFixtures.swift:12` `makeIsolatedDefaults()`.
- UI smoke (`CheckStitchUITests/CheckStitchUITests.swift`): one XCTest `testLaunchAndAccessibilitySmoke` (:14); asserts button existence, accepts either empty-state or list create button, then XCUI accessibility audit; deliberate avoidance of `.dynamicType`/`.hitRegion` categories (hang risk, comment :27).

## Cross-Cutting Observations
- **The entire macOS/iOS divergence lives in ContentView.swift view-structure conditionals (Q1) plus a single decode branch in BackgroundPhotoLayer.swift (Q2).** The data layer (Q3) and settings layer (Q4) are platform-neutral: same code, same storage, same defaults on both platforms.
- Of the four candidate causes: (1) the navigation-container path is the only one with a platform branch — iOS deliberately clears it (ContentView.swift:59), macOS has no equivalent (comment asserts the macOS stack is already transparent); (2) the photo wrapper is platform-neutral by construction and cannot collapse on zero intrinsic size (Q2 wrapper analysis, BackgroundPhotoLayer.swift:15-20); (3) the store has no macOS-specific load/fetch gate (only decode differs, BackgroundImageStore.swift:202-209); (4) the settings storage path is identical on both platforms — no KVS/App-Group/platform branch exists for the three keys (Q4 grep across the tree).
- Comment/assumption coupling: the macOS transparency "guarantee" is a code comment (ContentView.swift:55-58), not a runtime measurement — the code contains no macOS-side defense if the toolchain paints an opaque container.
- iOS-opaque-container precedent: the same fix pattern (`.containerBackground(.clear, for: .navigation)`) was already applied for iOS 26 in this codebase; macOS's stack transparency is treated as the pre-26 default.

## Open Areas
- **Runtime confirmation**: whether the macOS NavigationStack/window actually paints an opaque container needs a signed macOS run (`make build-mac-signed`); source alone shows only what the code relies on, not what the toolchain does. The ticket's prime hypothesis (macOS opaque container) is consistent with the code structure but not provable from it.
- **Test seam gap**: no existing test renders the ContentView tree or asserts layer visibility; reproducing the broken macOS branch in a test has no existing harness (no snapshot infra, no view-tree render helpers, no container-condition seam).
- Window-resize behavior on macOS across the photo layer is untested anywhere in the repo.
- The `CardPlate` constants (`checklistTopMargin`, `plateFill`, …) referenced by ContentView padding were not toured (out of Q1 budget); not needed for the photo-layer question but noted for completeness.