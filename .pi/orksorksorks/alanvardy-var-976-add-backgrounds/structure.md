# Structure Outline

## Approach

Port SingleThread's background subsystem into CheckStitch as **five bottom-up
layers** — fade math → fetch/persist store → photo-layer seam → prefs bag →
settings surface & ContentView mount — each shipping its own Swift Testing
suite (fake fetchers, temp dirs, no network) green before the next starts.
Because CheckStitch has **no test target**, Stage 0 (the harness) comes first
and every later stage is verified with it.

---

## Stage 0: Test target & gate — the harness everything else stands on

Create a `CheckStitchTests` target so any later layer is testable at all. This
layer's green tests prove only that the harness builds, is wired to the scheme,
and survives the existing `make build`.

**Files**: `CheckStitchTests/HarnessTests.swift` (new),
`CheckStitch.xcodeproj/project.pbxproj`,
`CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme` (new shared
scheme), `scripts/test.sh`

**Key changes**:
- New `PBXNativeTarget` `CheckStitchTests` (`com.apple.product-type.bundle.unit-test`)
  with its **own** `PBXFileSystemSynchronizedRootGroup` (`path = CheckStitchTests`)
  wired through `fileSystemSynchronizedGroups`; `TEST_HOST`/`BUNDLE_LOADER`
  point at the app target. Do **not** touch the app target's group.
- Shared scheme `CheckStitch` with a `TestAction` listing `CheckStitchTests`
  (autocreated schemes are not reliable for `xcodebuild test`).
- `scripts/test.sh`: after `make build`, run
  `xcodebuild -scheme 'CheckStitch' -destination "$SIM_DEST" -derivedDataPath DerivedData test`
  (reuse the Makefile's `SIM` precedence — never a bare `name=`).

**Tests**: `HarnessTests.harnessRuns()` — one `@Test` `#expect(true)` (sad path:
an intentionally failing assertion run once locally, then removed).
**Verify**: `bash scripts/test.sh` green (build + shellcheck + `xcodebuild test`);
`make build` and `make run` unchanged. If the target/scheme is malformed `make build`
fails too — fix before any app code.

---

## Stage 1: `BackgroundFade` — pure fade math

The percent→opacity mapping and the picker's value set, with no dependencies.

**Files**: `CheckStitch/BackgroundFade.swift` (new),
`CheckStitchTests/BackgroundFadeTests.swift` (new)

**Key changes**:
- `enum BackgroundFade { static let defaultValue = 50; static let step = 10; static let allValues: [Int]; static func opacity(for percent: Int) -> Double }`
- Private `extension Int { func clamped(to: ClosedRange<Int>) -> Int }` — bounds corrupt persisted values.

**Tests**: `BackgroundFadeTests` — `allValues == [0,10,…,90]`, `opacity(0)==1.0`,
`opacity(50)==0.5`, `opacity(90)==0.1` (happy); `opacity(-10)==1.0`,
`opacity(200)==0.1` (sad/clamping).
**Verify**: `bash scripts/test.sh`.

---

## Stage 2: `BackgroundImageStore` — fetch, decode, persist, pin

The data layer the whole feature reads from: fetch protocol + payload decode +
atomic disk persistence + freshness/pin/single-flight state.

**Files**: `CheckStitch/BackgroundImageStore.swift` (new),
`CheckStitchTests/BackgroundImageStoreTests.swift` (new),
`CheckStitchTests/BackgroundTestFixtures.swift` (new, ports
`SingleThread/SingleThreadTests/BackgroundTestFixtures.swift`)

**Key changes**:
- `protocol BackgroundImageFetching { func data(from url: URL) async throws -> (Data, URLResponse) }` + `extension URLSession: BackgroundImageFetching` (guards `HTTPURLResponse` 200..<300 → `URLError(.badServerResponse)`).
- `struct UnsplashPayload: Decodable { let url: URL; let photographer: String; let photographerURL: URL? }`; `struct BackgroundMetadata: Codable` (photographer, photographerURL, `fetchedAt`); `struct FetchedWallpaper`.
- `@MainActor @Observable final class BackgroundImageStore`:
  `init(client: any BackgroundImageFetching = URLSession.shared, directory: URL? = nil)` — production dir `Application Support/CheckStitch`, files `background.jpg`/`background.json`;
  `private(set) var imageData/photographer/photographerURL/isPinned/isRefreshing`;
  `static let defaultMaxAge: TimeInterval = 86400`;
  `func loadStoredImage()`, `func refreshIfNeeded(maxAge:) async`, `func forceRefresh() async`, `func setPinned(_:) async`;
  private `commit` (disk **before** observable state), `persist` (`Data.write(to:, options: .atomic)` + ISO-8601 JSON), `fetchWallpaper(from:)`;
  `nonisolated static func isDecodableImage(_:) -> Bool` (`#if os(iOS) UIImage / #if os(macOS) NSImage`).
- Endpoints `https://vardy.cc/unsplash` (cold) and `/unsplash/random` (refresh).

**Tests**: `BackgroundImageStoreTests` — port the 19-case set: success persists bytes+sidecar; non-image rejected; failure retains prior; 23h fresh / 25h stale; fresh skips network; corrupt/missing sidecar clears image+credit; credit/URL pairing; `forceRefresh` bypasses freshness and pin; retains prior on failure; `isRefreshing` mid-flight; pin blocks except when no image; **re-pin during fetch does not commit**; unpin refreshes only when stale; true→false-only transition. Sad paths include non-2xx, undecodable payload, non-image bytes.
**Verify**: `bash scripts/test.sh` (fake fetchers only — no network).

---

## Stage 3: `BackgroundPhotoLayer` — the render seam

The full-bleed image view, with the `Color.clear.overlay` wrapper that keeps
`scaledToFill` from expanding layout.

**Files**: `CheckStitch/BackgroundPhotoLayer.swift` (new),
`CheckStitchTests/BackgroundPhotoLayerTests.swift` (new)

**Key changes**:
- `struct BackgroundPhotoLayer: View { let imageData: Data?; var isEnabled = true; var opacity = BackgroundFade.opacity(for: .defaultValue) }` — body guards `isEnabled && decodable`, then `Color.clear.overlay { image.resizable().scaledToFill() }.ignoresSafeArea().opacity(opacity).allowsHitTesting(false).accessibilityHidden(true)`.
- `static func image(from data: Data) -> Image?` (`#if os(iOS)` / `#if os(macOS)`).

**Tests**: `BackgroundPhotoLayerTests` — the line-height seam (`#expect` the layer's own body does not expand its parent when `scaledToFill`); `image(from:)` returns non-nil for the fixture JPEG and `nil` for garbage (sad).
**Verify**: `bash scripts/test.sh`.

---

## Stage 4: `SettingsBindings` — prefs snapshot & writeback

The staged settings bag for the three new prefs (background only;
`appearanceMode` keeps its direct binding).

**Files**: `CheckStitch/SettingsBindings.swift` (new),
`CheckStitchTests/SettingsBindingsTests.swift` (new)

**Key changes**:
- `@MainActor @Observable final class SettingsBindings { var backgroundEnabled = true; var backgroundFadePercent = BackgroundFade.defaultValue; var backgroundPinned = false }` — `.standard`-suite surface only, no App-Group tier, no `excludedLists`.
- ContentView-owned helpers (declared here, wired in Stage 6): `makeSettingsBag() -> SettingsBindings` (snapshot from `@AppStorage`) and `settingsSheetWritebacks(_:)` `.onChange` chain → `@AppStorage` setters.

**Tests**: `SettingsBindingsTests` — defaults match `true`/`50`/`false`; snapshot copies current `UserDefaults` values; staged mutation of the bag does **not** write `UserDefaults` until the writeback fires; writeback persists each key (sad: mutating then discarding the bag leaves the store unchanged).
**Verify**: `bash scripts/test.sh`.

---

## Stage 5: Settings surface — pushed Background subscreen

The `NavigationStack` row and subscreen with the five controls. UI has no
automatable seam in this repo — it is verified by build + the suites below
staying green + manual `make run` (a UI-test target is out of scope, per design).

**Files**: `CheckStitch/BackgroundSettingsView.swift` (new),
`CheckStitch/SettingsSubscreenLayout.swift` (new), `CheckStitch/SettingsView.swift`,
`CheckStitch/ContentView.swift`

**Key changes**:
- `struct BackgroundSettingsView: View { @Binding var backgroundEnabled: Bool; @Binding var backgroundFadePercent: Int; @Binding var backgroundPinned: Bool; var backgroundImage: BackgroundImageStore }` — enable toggle, fade `Picker` over `BackgroundFade.allValues`, pin toggle (own Section, visible when disabled), `Button { Task { await backgroundImage.forceRefresh() } }` disabled while `isRefreshing`, credit `Link`/`Text` footer; `.navigationTitle("Background").settingsSubscreenLayout()`.
- `extension View { func settingsSubscreenLayout() -> some View }` — `#if os(macOS)` top-alignment frame fix, identity on iOS.
- `SettingsView` gains `backgroundImage` + `bindings` params and a `NavigationLink { BackgroundSettingsView(…) } label: { Label("Background", systemImage: "photo.on.rectangle") }` row inside the existing `NavigationStack`/`Form`.
- `ContentView`: `@State private var backgroundImage = BackgroundImageStore()`, `@State private var settingsBag: SettingsBindings?`; gear sets `settingsBag = makeSettingsBag()`; sheet renders `settingsSheetWritebacks(bag) { SettingsView(… backgroundImage:, bindings: bag) }`; dismiss nils the bag.

**Tests**: no new suite. Existing `SettingsBindingsTests` + all prior suites stay green.
**Verify**: `bash scripts/test.sh`; manual `make run` — open Settings, push Background, exercise toggle/picker/pin/refresh; confirm the macOS-build fix by building the macOS scheme in Xcode.
**Note (cross-cutting)**: this is the first stage whose deliverable is not fully unit-testable; it is deliberately thin over the Stage 4 bag so the untested surface is presentation only.

---

## Stage 6: `ContentView` mount — ZStack, fetch trigger, pin wiring

Paint the photo behind the checklist and drive the store from the view
lifecycle. Top layer; verified by build + manual run.

**Files**: `CheckStitch/ContentView.swift`

**Key changes**:
- Body wraps the existing centered content in `ZStack { Color.systemBackground.ignoresSafeArea(); BackgroundPhotoLayer(imageData: backgroundImage.imageData, isEnabled: backgroundEnabled, opacity: BackgroundFade.opacity(for: backgroundFadePercent)); existingContent }`.
- `@AppStorage("backgroundEnabled") var backgroundEnabled = true` / `@AppStorage("backgroundFadePercent") var backgroundFadePercent = BackgroundFade.defaultValue` / `@AppStorage("backgroundPinned") var backgroundPinned = false`.
- `.task { await backgroundImage.refreshIfNeeded(); await backgroundImage.setPinned(backgroundPinned) }` and `.onChange(of: backgroundPinned) { _, pin in Task { await backgroundImage.setPinned(pin) } }`.

**Tests**: no new suite (`#Preview` in the existing files still compiles). Prior suites stay green.
**Verify**: `bash scripts/test.sh`; manual `make run` — background renders behind the card on cold launch, stale image refreshes, pin freezes it, unpin refreshes.

---

## Testing Checkpoints

After each stage, `bash scripts/test.sh` must be green before the next stage
starts. Resume points if context resets: **after Stage 0** the harness + gate
work; **after Stage 1** fade math; **after Stage 2** store lifecycle; **after
Stage 3** photo seam; **after Stage 4** prefs bag. Stages 0–4 are independently
landable (code + tests). Stages 5–6 are presentation and land together;
their checkpoint is build + the manual `make run` checklist above.

**Residual, not gated**: the real `vardy.cc/unsplash` endpoint (ATS,
reachability) and macOS behaviour are manual-only this ticket; the gate runs
the iOS simulator destination.