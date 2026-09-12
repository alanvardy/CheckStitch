# Research Findings

Paths: CheckStitch files are relative to `/Users/vardy/dev/alanvardy-var-976-add-backgrounds`; SingleThread files to `/Users/vardy/dev/SingleThread`.

## Q1: CheckStitch preference persistence & appearance flow

### Findings
- Single shared UserDefaults key `"appearanceMode"`, declared as `@AppStorage("appearanceMode") var appearanceMode = AppearanceMode.system` on `ContentView.swift:19-20`. `AppearanceMode: String, CaseIterable` (cases `system`/`light`/`dark`, `AppearanceMode.swift:16`) is RawRepresentable, so the persisted raw string equals the case string.
- `AppearanceModePreference` (`AppearanceMode.swift:90-118`) wraps `UserDefaults.standard` with the same `defaultsKey` (`:100-101`); `rawValue` validates the string and falls back to `"system"` (`:104-109`), `setRawValue` writes `defaults.set` (`:111-113`) but **has zero call sites** — the only writer is SwiftUI's `@AppStorage` setter.
- Non-SwiftUI reads go through `AppearanceMode.load(from:)` (`:77-82`), called by the window delegates on lifecycle events: iOS `applicationDidBecomeActive` → `applyAppearance` setting `window.overrideUserInterfaceStyle` (`AppDelegate.swift:23-25`, `:11-20`); macOS `applicationDidFinishLaunching` + `applicationDidBecomeActive` → `window.appearance` (`AppDelegate.swift:46-53`, `:41-44`).
- Sheet edit: gear button sets `isShowingSettings` (`ContentView.swift:63-65`); `.sheet(isPresented: $isShowingSettings) { SettingsView(appearanceMode: $appearanceMode) }` (`ContentView.swift:42-45`) — a `@Binding` into the `@AppStorage` property (`SettingsView.swift:7-8`); `Picker(selection: $appearanceMode)` over `AppearanceMode.allCases` (`SettingsView.swift:13-24`).
- Live reaction: `.onChange(of: appearanceMode)` on `ContentView` (`ContentView.swift:32-38`) pushes to the platform delegate so the window re-themes while the sheet is open.
- Pattern: one key, two readers (@AppStorage property + `AppearanceMode.load()` in delegates), one writer (@AppStorage). Push via `.onChange`, pull via `didBecomeActive`/`didFinishLaunching`. Ported from SingleThread as-is per `.pi/orksorksorks/alanvardy-var-970-add-settings-menu/done.md`.

## Q2: CheckStitch build & structure

### Findings
- Entry: `@main struct MyApp: App` (`MyApp.swift:9`) with `@UIApplicationDelegateAdaptor(AppDelegate.self)` (iOS, `:11`) and `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` (macOS, `:15`); body is `WindowGroup { ContentView() }` (`:19-22`), one scene, one window.
- ContentView body (`ContentView.swift:23-31`): `GeometryReader` → centered `HStack(spacing: 16)` of two buttons → `.frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width))` (`:28`) → `.padding(.horizontal, 32)` → outer `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)`. `ChecklistWidth.maxContentWidth = min(340, viewportWidth * 0.6)` (`:150-157`, `nonisolated`).
- Buttons are private view values (`settingsButton` `:53`, `createChecklistButton` `:70`, `editChecklistButton` `:109`) styled with `RoundedRectangle(cornerRadius: 14).stroke(.tint, lineWidth: 2)` + `.contentShape(Rectangle())`.
- Settings sheet (`SettingsView.swift:11-32`): `NavigationStack { Form { Section { Picker } } }`, `.navigationTitle("Settings")`, `.toolbarTitleDisplayMode(.inline)`, Done `ToolbarItem(placement: .confirmationAction)`. Second sheet `EditChecklistView` follows the same Form/Section shape (`ContentView.swift:167-205`).
- Build: `PBXFileSystemSynchronizedRootGroup` (`path = CheckStitch`) declared at `project.pbxproj:13-18`, wired to the sole target via `fileSystemSynchronizedGroups` (`:59-61`); **no per-file PBXFileReference entries** (`:70-84`) — any `.swift` dropped under `CheckStitch/` is compiled automatically.
- Dual-target: `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (`pbxproj:282, 324`), `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`:284, 326`), `ENABLE_PREVIEWS`/`ENABLE_APP_SANDBOX = YES` (`:258-259, 300-301`), deployment targets iOS 18.7 / macOS 27.0, bundle id `app.alanvardy.CheckStitch`.
- Platform-gated code uses `#if os(iOS)` / `#if os(macOS)` blocks (imports in `MyApp.swift:1-6`, `AppDelegate.swift:1,30`, `AppearanceMode.swift:4,7`); the only platform-specific view APIs in the app are SF Symbol images and the two window-style APIs. `ENABLE_PREVIEWS` makes `#Preview` blocks available (`SettingsView.swift:39-45` uses `.preferredColorScheme` + `.constant`).

## Q3: SingleThread BackgroundImageStore end to end

### Findings
- `@MainActor @Observable final class BackgroundImageStore` (`BackgroundImageStore.swift:53`), constructed at composition root `AppViewModel.swift:27`, threaded through `ContentViewModel.swift:19-20,51-52`; `ContentView`/`SettingsView` receive the same instance (`ContentView.swift:32,51`, `SettingsView.swift:19-20,183`).
- `init(client: any BackgroundImageFetching = URLSession.shared, directory: URL? = nil)` (`:57-63`); production directory = `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] + "/SingleThread"` (`:186-189`).
- Fetch protocol: `protocol BackgroundImageFetching` (`:14`) with `extension URLSession` (`:17-28`) that guards `response as? HTTPURLResponse` for status `200..<300`, else throws `URLError(.badServerResponse)` — noted because `URLSession.data(from:)` does not throw on non-2xx.
- Endpoints (`:179-181`): `GET https://vardy.cc/unsplash` — the cold-launch wallpaper, 6h-cached **server-side** (doc comment only, no client constant); `GET https://vardy.cc/unsplash/random` — explicit refresh.
- Decode validation: `UnsplashPayload: Decodable` with CodingKeys `url`, `photographer`, `photographer_url` (`:39-49`; `created_at` ignored); `fetchWallpaper` (`:200-211`) decodes payload → fetches image bytes → `guard isDecodableImage(data) else throw URLError(.cannotDecodeContentData)` → returns value struct `FetchedWallpaper` (data + photographer + photographerURL, `:163-168`).
- `isDecodableImage` gate (`:239-244`, `nonisolated`): iOS `UIImage(data: data) != nil`, macOS `NSImage(data: data) != nil`; the same split is mirrored in the renderer (`:283-288`).
- Freshness: `defaultMaxAge = 86400` (24h, `:177`); `isFresh` compares sidecar `fetchedAt` to now (`:226-230`); missing/corrupt sidecar ⇒ not fresh.
- `refreshIfNeeded(maxAge = defaultMaxAge)` (`:86-113`): `loadStoredImage()` → skip if `isPinned && imageData != nil` → skip if fresh → skip if `isFetching` (single-flight via `defer`) → fetch → **re-check pin after the await** (re-pin during fetch must not commit, `:104-106`) → `commit`; on failure `logger.error` and prior state retained.
- Pin: `isPinned` is `private(set)` (`:74`), driven from `@AppStorage("backgroundPinned", store: .standard)` in `ContentView.swift:92-93` via `.task` (`:258-266`) and `.onChange` (`:265-267`, dispatch `:614-618`). `setPinned` (`:139-145`): only a true→false transition triggers `refreshIfNeeded()`; pinned skips refetch except when no image is stored (`:91`).
- Persistence (`persist`, `:246-253`): `createDirectory(at: directory, withIntermediateDirectories: true)`, then `imageData.write(to: imageURL /* background.jpg */, options: .atomic)`, then `JSONEncoder` (iso8601) `.encode(metadata).write(to: metadataURL /* background.json */, options: .atomic)`. `commit` (`:215-224`) writes disk **before** flipping observable state, and one metadata write covers photo + credit so they never disagree. `loadStoredImage` (`:148-160`) clears all three observables on missing/corrupt sidecar or undecodable image.

## Q4: Background rendering & fade control

### Findings
- `struct BackgroundPhotoLayer: View` (`BackgroundImageStore.swift:263-293`): fields `let imageData: Data?`, `var isEnabled = true`, `var opacity = BackgroundFade.opacity(for: .defaultValue)` (`:264-268`); body guards `isEnabled && decodable image`, renders `Color.clear.overlay { image.resizable().scaledToFill() }` (`:274-278`) then chains `.ignoresSafeArea()` (`:280`) `.opacity(opacity)` (`:281`) `.allowsHitTesting(false)` (`:282`) `.accessibilityHidden(true)` (`:283`). The overlay wrapper pins the layer to its parent size so `scaledToFill` can't expand layout (comment `:272-273`).
- `image(from data:) -> Image?` (`:286-293`): macOS `NSImage(data:).map(Image.init(nsImage:))`, iOS `UIImage(data:).map(Image.init(uiImage:))`; nil ⇒ the layer renders nothing.
- `enum BackgroundFade` (`BackgroundFade.swift:9-36`): `defaultValue = 50` (`:13`), `step = 10` (`:16`), `allValues = stride(min 0 … max 90, by step)` (`:19`); `opacity(for percent) = 1 - Double(percent.clamped(to: 0...90)) / 100` (`:24-25`) so 0% → 1.0, 90% → 0.1; clamp via private `Int.clamped` (`:33-36`) bounds corrupt persisted values. Persisted as Int percent in UserDefaults.
- Mounting (`SingleThread/ContentView.swift:164-199`): `ZStack` back-to-front — `Color.systemBackground.ignoresSafeArea()` (`:165`), `BackgroundPhotoLayer(imageData: viewModel.backgroundImage.imageData, isEnabled: backgroundEnabled, opacity: BackgroundFade.opacity(for: backgroundFadePercent))` (`:167-170`), then the reminder content branch (`:172-174`). Scrolling/reflowing content lives in later ZStack siblings (`authGatedContent` `:362-369`, `reminderList` `:376+` with `ScrollView`), painted above the static full-bleed layer.
- Prefs (`:86-93`): `@AppStorage("backgroundEnabled", store: .standard) = true`, `backgroundFadePercent = BackgroundFade.defaultValue`, `backgroundPinned = false`.
- Tests pinning this: `BackgroundPhotoLayerTests.swift:11-34`, `BackgroundFadeTests.swift:10-28` (allValues `[0..90]`, opacity 1/0.5/0.1, clamping).

## Q5: SingleThread settings UI for backgrounds

### Findings
- Row: `SettingsView.swift:108-117` — a `NavigationLink` constructing `BackgroundSettingsView(backgroundEnabled: $bindings.backgroundEnabled, backgroundFadePercent: $bindings.backgroundFadePercent, backgroundPinned: $bindings.backgroundPinned, backgroundImage: backgroundImage)` with `SettingsLinkLabel(title: "Background", systemImage: "photo.on.rectangle", caption: …)`, `.accessibilityIdentifier("settingsBackgroundRow")` (`:118`). Rows sit in `List > Section` inside a `NavigationStack` (`:75-77`); Done toolbar dismisses (`:126-132`).
- `BackgroundSettingsView.swift:9-20`: three `@Binding` fields (`backgroundEnabled: Bool`, `backgroundFadePercent: Int`, `backgroundPinned: Bool`) + live `var backgroundImage: BackgroundImageStore`; root is a `Form` (`:23`).
  1. Enable `Toggle(isOn: $backgroundEnabled)` + label/caption, icon `photo`, id `backgroundToggle` (`:24-30`).
  2. Fade `Picker(selection: $backgroundFadePercent)` over `BackgroundFade.allValues` → `Text("\(percent)%").tag(percent)`, id `backgroundFadePicker` (`:31-42`).
  3. Pin `Toggle(isOn: $backgroundPinned)` in its own `Section`, icon `pin`, id `pinWallpaperToggle` — deliberately visible when Background is off (`:46-57`).
  4. Refresh `Button { Task { await backgroundImage.forceRefresh() } }` with `ProgressView()` while `backgroundImage.isRefreshing`, `.disabled(isRefreshing)`, id `refreshWallpaperButton` (`:59-73`); progress state `private(set) var isRefreshing` (`BackgroundImageStore.swift:76`).
  5. Credit footer: `if let photographer …` → `"Photo by \(photographer) on Unsplash"`; `Link(credit, destination:)` when `photographerURL` present else `Text` (`:75-85`).
- Root chain: `.navigationTitle("Background").settingsSubscreenLayout()` (`:86-88`). `SettingsSubscreenLayout.swift` is a macOS-only modifier (`frame(maxHeight: .infinity, alignment: .top)`, `:7-13`) exposed as `extension View.settingsSubscreenLayout()` gated `#if os(macOS)` (`:15-22`) — fixes the macOS sheet centering bug for pushed views; mandated for every navigation destination (`SettingsView.swift:12-15`), used by all seven subscreens.
- Bindings bag: `SettingsBindings` (`SettingsBindings.swift:24`, `@MainActor @Observable`); snapshot defaults include `backgroundEnabled = true`, `backgroundFadePercent = 50`, `backgroundPinned = false` (`:31-59`, `:47-49`). Two tiers (`:61-90`): ~12 standard-suite in-memory fields (persisted via writeback) vs. 7 App-Group computed props that read/write store types directly. iOS-only fields declared unconditionally (`:14-21`); `excludedLists` deliberately outside the bag.
- Lifecycle: gear → `settingsBag = makeSettingsBag(); isShowingSettings = true` (`ContentView.swift:178-180`); `@State settingsBag` stable across body re-evaluations (`:338`); `.sheet { settingsSheetContent }` (`:296-297`) → `settingsSheetWritebacks(bag)` (`ContentView+Settings.swift:8-42`) wraps `SettingsView` in staged `.onChange(of: bag.X)` chains writing back to the `@AppStorage` properties (background writebacks `:39-41`); dismiss nils the bag (`:288-295`) so the next open re-snapshots. `makeSettingsBag()` (`:45-66`) copies current `@AppStorage` values.

## Q6: SingleThread background test patterns

### Findings
- `BackgroundImageStoreTests.swift:11` — `@MainActor @Suite(.serialized)`; Swift Testing style (`import Testing`, async `@Test` funcs, `#expect`), no XCTest.
- Injection: `makeStore(client:)` (`:443`) pairs a `BackgroundImageFetching` fake with a fresh `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)` dir (`:445`). Fakes (`TestFixtures.swift`): `FakeBackgroundFetcher` (`:135`) records `requestedURLs` and serves `stubbedData: [URL: Result<Data, Error>]` (unstubbed URL force-crashes); `FetchGate`/`GatedBackgroundFetcher` (`:144-203`) park fetches in-flight to observe `isRefreshing`; `SeededFetcher` (`:204-229`) serves endpoint payload + JPEG with no network.
- 19 test cases (`:18-405`): success stores bytes+sidecar, non-image rejected, failure retains prior, 23h/25h sidecar freshness, fresh skips network, corrupt/missing sidecar ⇒ no image, credit/URL pairing, credit cleared, forceRefresh bypass (freshness + pin), retains prior on failure, updates attribution, `isRefreshing` mid-flight, pin blocks/except-no-image, re-pin during fetch doesn't commit, unpin-triggers-when-stale, no-refresh-when-fresh, true→false-only transition.
- Patterns: freshness by counting endpoint hits (`fake.requestedURLs.filter`), on-disk assertions via `Data(contentsOf:)` + `JSONDecoder` `.iso8601` decode, `payloadJSON()`/`sidecarJSON(fetchedAt:)` builders (`:451`, `:459`).
- `BackgroundCardTests.swift` — `#if os(iOS)` (`:8`), `@Suite(.serialized)` (`:44`); asserts the seam `ContentViewModel.rowChromeBackground == Color.clear` in both photo states (`:52-67`) plus plate fill colors/corner radius (`:69-85`), because rendered chrome can't be distinguished via reflected body descriptions (doc `:27-38`). Seeding: `seededBackgroundImage()` (`:122`) writes the fixture JPEG + hand-built sidecar atomically; `UserDefaults.standard.set(..., forKey: "backgroundEnabled")` with `defer` cleanup for pref-driven tests (`:102-121`).
- Fixtures: `BackgroundTestFixtures.swift:7` — `jpegData`, base64 of a 1×1 JPEG chosen to pass `isDecodableImage` on both platforms.

## Q7: CheckStitch network / image / disk precedents and entitlements

### Findings
- **No network code exists**: zero hits for `URLSession`/`URLRequest`/`http`/`fetch` across all Swift sources. Imports are only SwiftUI, Foundation, os, EventKit (+ UIKit/AppKit conditionally).
- **No image pipeline**: all imagery is SF Symbol `Image(systemName:)` (`ContentView.swift:57,92,113,189,196`, `AppearanceMode.swift:60`, `SettingsView.swift:16`); no `UIImage`/`NSImage`/`Data` handling anywhere; `Assets.xcassets` contains only `AccentColor.colorset` + `Contents.json`.
- **Disk persistence is UserDefaults only**: `@AppStorage("appearanceMode")` (`ContentView.swift:19`) + `AppearanceMode.defaultStore` (`AppearanceMode.swift:77-118`); no `suiteName:`/`containerURL`/`FileManager`/`Application Support`/`write(to` usage. Only external persistence is EventKit reminders (`EKEventStore`, `requestFullAccessToReminders`, `ContentView.swift:127-141`).
- Entitlements (`CheckStitch/AppGroup.entitlements`): exactly one key `com.apple.security.application-groups = ["group.app.alanvardy.CheckStitch"]`; **no** app-sandbox, network client/server, or file-access entitlements. Signed only for iOS SDKs (`CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` / `[sdk=iphonesimulator*]` → `pbxproj:254-255, 296-297`); **no `[sdk=macosx*]` entry** — the macOS target is signed with no entitlements, i.e. unsandboxed (no entitlement-gated restriction on file/network access).
- App-group capability (shared `UserDefaults(suiteName:)` / `FileManager.containerURL(...)` for `group.app.alanvardy.CheckStitch`) exists but is used by nothing today. `GENERATE_INFOPLIST_FILE = YES` with only NSReminders usage keys (`pbxproj:262-263, 304-305`). No ATS keys configured.
- Practical reading: `FileManager` Application Support persistence and `URLSession` HTTP are available to CheckStitch without new entitlements (macOS unsandboxed; iOS App Groups don't gate network; default ATS applies).

## Cross-Cutting Observations

- **SingleThread parity is the design document**: CheckStitch already mirrors SingleThread idioms (`ChecklistWidth.maxContentWidth` ↔ `CardWidth`, `@AppStorage` + sheet settings, `AppearanceMode` port with shared key). The background feature ports its exact store surface, layer chain, fade enum, settings subscreen, and its three `.standard` UserDefaults keys.
- **A new subsystem with no precedent in-repo**: network fetch, decodable-payload contract, `UIImage`/`NSImage` decode gating, atomic disk persistence (`Data.write(to:, options: .atomic)`), Application Support directory — all absent from CheckStitch today (Q7).
- **Dual-platform seam runs through everything**: store validation and renderer decode each do the `#if os(iOS) UIImage / #if os(macOS) NSImage` split (`BackgroundImageStore.swift:239-244`, `:283-288`); the macOS settings fix is also gated (`SettingsSubscreenLayout.swift:15-22`).
- **Settings architecture differs**: SingleThread uses a `NavigationStack` + `NavigationLink` subscreen + bindings bag snapshot/writeback; CheckStitch's `SettingsView` is a single Form sheet with a direct `@Binding` into one `@AppStorage` property — there is no bag, no subscreen, and no `NavigationLink` precedent in CheckStitch.
- **Pref plumbing has one proven CheckStitch pattern** (Q1): `@AppStorage` property + direct `@Binding` into the sheet + `.onChange` side effects; SingleThread's bag approach is the alternative after the sheet scales past one row.
- **Tests exist in SingleThread, not CheckStitch**; SingleThread's `@Suite(.serialized)` + fake-fetcher + temp-dir + seam-assertion style is the only test corpus for this feature.

## Open Areas

- Whether CheckStitch's settings sheet will grow a navigation push/substack (no `NavigationLink`/subscreen precedent exists in CheckStitch) or keep everything inline in one Form.
- SingleThread `ContentView.setBackgroundPinned` dispatch (`ContentView.swift:614-618`) and the full `.task` composition weren't fully read; only the seams at `:258-267` were confirmed.
- No in-repo evidence for iOS-simulator URLSession behavior (cert handling, ATS), since CheckStitch has never fetched anything; SingleThread's `urf`/URLSession usage is the only reference.
- Directory/namespace decisions (SingleThread uses a `/SingleThread` subdirectory of Application Support and credit sidecar naming `background.jpg`/`background.json`); CheckStitch has no existing file-layout convention.
- `UnsplashPayload.created_at` is ignored by the decoder; the sidecar's `fetchedAt` is set client-side at commit time (`BackgroundImageStore.swift:215-224`).