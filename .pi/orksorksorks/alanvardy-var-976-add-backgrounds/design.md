# Design Discussion

## Current State

**CheckStitch** is one screen, one settings sheet, and UserDefaults-only
persistence:

- `ContentView.swift` renders a centered `HStack` of two stroked
  `RoundedRectangle` buttons inside a `GeometryReader` → outer
  `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)`
  (`ContentView.swift:23-31`). There is no card fill and no ZStack — the
  window background shows straight through.
- Settings is a single `Form` sheet with one `AppearanceMode` picker, opened
  by the gear button (`ContentView.swift:63-65`) and presented as
  `.sheet(isPresented:) { SettingsView(appearanceMode: $appearanceMode) }`
  (`ContentView.swift:42-45`). Pref state is one `@AppStorage("appearanceMode")`
  property on `ContentView` (`:19-20`) bound directly into the sheet
  (`SettingsView.swift:7-8,13-24`); live window re-theming is pushed from
  `.onChange(of: appearanceMode)` (`ContentView.swift:32-38`). There is no
  `NavigationStack`/`NavigationLink`, no subscreen, no bindings bag.
- Persistence precedents: `@AppStorage` only, plus `AppearanceModePreference`
  (`AppearanceMode.swift:90-118`) for non-SwiftUI reads by the window
  delegates. No `FileManager`, no `URLSession`, no `UIImage`/`NSImage`, no
  `Data` handling anywhere (research Q7). `Assets.xcassets` holds only
  `AccentColor.colorset`.
- Entitlements are an App Group only, and `CODE_SIGN_ENTITLEMENTS` is set for
  iOS SDKs alone — the macOS target is unsandboxed (`pbxproj:254-255,296-297`).
  Network and Application Support access need no new entitlements (research Q7).
- Build: `PBXFileSystemSynchronizedRootGroup` over `CheckStitch/`
  (`project.pbxproj:13-18,59-61`), so new app sources compile with no pbxproj
  edit. iOS 18.7 / macOS 27.0, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- **No test target exists.** The gate is `bash scripts/test.sh` = `make build`
  + `shellcheck scripts/*.sh` (conventions.md).

**SingleThread** already has the whole subsystem, and it is the port target:
`BackgroundImageStore.swift:53-293` (@MainActor @Observable store,
`BackgroundImageFetching` protocol, `UnsplashPayload`, atomic
`background.jpg` + `background.json` persistence under Application Support),
`BackgroundFade.swift:9-36`, `BackgroundSettingsView.swift:23-88`,
`SettingsSubscreenLayout.swift:15-22` (macOS-only fix), the
`SettingsBindings` bag + writeback (`SettingsBindings.swift:24-90`,
`ContentView+Settings.swift:8-66`), and the `ZStack` mount in
`SingleThread/ContentView.swift:164-199`.

## Desired End State

1. A fetched Unsplash wallpaper renders full-bleed behind the checklist
   buttons on both iOS and macOS, respecting an enable toggle and a fade
   percent.
2. Settings gains a **Background** row that pushes a `BackgroundSettingsView`
   subscreen with enable toggle, fade percent picker, pin toggle, refresh
   button, and Unsplash credit footer — SingleThread parity.
3. Cold launch refreshes the image when stale (24h client freshness; the
   server 6h-caches `https://vardy.cc/unsplash`), image + credit persist
   across launches in Application Support/CheckStitch, and the pin toggle
   freezes the image against refresh.
4. A test target exists and covers the store lifecycle, the fade mapping,
   the photo layer seam, and the settings writeback.

**Verification:** `bash scripts/test.sh` passes (now `make build` + shellcheck
+ `xcodebuild test`), and `make run` shows the background behind the card, the
pushed Background subscreen, working toggles/picker/refresh, and a tappable
credit link. Tests use fake fetchers — no network in the gate.

## Patterns to Follow

**CheckStitch patterns to match**

- New app sources need **no pbxproj edit** (`project.pbxproj:13-18,59-61`);
  one file per type under `CheckStitch/`.
- Preference declaration + sheet binding idiom: `@AppStorage("key") var x = default`
  on `ContentView` (`ContentView.swift:19-20`) with a `@Binding` into the sheet.
  New background prefs use `.standard` and the same style.
- `Form`/`Section`/`NavigationStack` shape with a Done
  `ToolbarItem(placement: .confirmationAction)` and
  `.toolbarTitleDisplayMode(.inline)` (`SettingsView.swift:11-32`).
- Error handling is `do/catch` + `logger.error` (`ContentView.swift:126-141`);
  there is no central error type in this repo, so the ported fetch path keeps
  SingleThread's `URLError(.badServerResponse)` / `.cannotDecodeContentData`.
- Dual-platform code is `#if os(iOS)` / `#if os(macOS)` blocks
  (`MyApp.swift:1-6`), and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means
  new types are MainActor unless marked `nonisolated`.

**SingleThread patterns to port verbatim** (all are the reference contract)

- `BackgroundFade`: `defaultValue = 50`, `step = 10`, `allValues = stride(0…90)`,
  `opacity = 1 - clamped/100` (`BackgroundFade.swift:9-36`).
- `BackgroundImageStore` surface: `refreshIfNeeded`/`forceRefresh`/`setPinned`,
  single-flight via `isFetching`, **re-check pin after the await**
  (`BackgroundImageStore.swift:104-106`), write disk **before** flipping
  observable state in `commit` (`:215-224`), one metadata sidecar covering
  photo + credit so they cannot disagree.
- `BackgroundPhotoLayer` chain: `Color.clear.overlay { image.resizable().scaledToFill() }`
  → `.ignoresSafeArea()` → `.opacity(opacity)` → `.allowsHitTesting(false)` →
  `.accessibilityHidden(true)` (`BackgroundImageStore.swift:263-293`). The
  `Color.clear` overlay wrapper is load-bearing — it stops `scaledToFill`
  from expanding layout.
- Atomic persistence with `Data.write(to:, options: .atomic)` into
  `Application Support/CheckStitch`, filenames `background.jpg` /
  `background.json` (`:246-253`).
- Settings lifecycle: `makeSettingsBag()` snapshot on open, staged `.onChange`
  writebacks, bag nil'd on dismiss (`ContentView.swift:178-180,288-297`;
  `ContentView+Settings.swift:8-66`).
- Test style: Swift Testing `@MainActor @Suite(.serialized)`, fake fetcher
  injection (`BackgroundImageFetching`), fresh `temporaryDirectory/UUID`
  per store, `#expect`, no network (`BackgroundImageStoreTests.swift:11,443-459`).

**Anti-patterns — do NOT follow**

- Do **not** assume the app target's `PBXFileSystemSynchronizedRootGroup`
  covers the test target. The test target needs its own group/file wiring (or
  explicit refs) and its own `TestAction` in the scheme.
- Do **not** put the image in the App Group container or an app-group
  `UserDefaults` suite; SingleThread and every CheckStitch precedent use
  `.standard` + Application Support. The App Group stays unused.
- Do **not** copy SingleThread's `SettingsBindings` verbatim — CheckStitch has
  no `excludedLists`, no App-Group tier, and one fewer settings screen.
- Do **not** port SingleThread's `ContentViewModel`/`AppViewModel` wiring;
  CheckStitch has no view-model layer and the store can be owned at
  `ContentView` scope.
- Do **not** port `BackgroundCardTests`' `rowChromeBackground` seam — that
  assertion is about SingleThread's reminder-row chrome, which CheckStitch
  does not have.

## Design Decisions

1. **Settings surface: pushed subscreen** — a `NavigationStack` +
   `NavigationLink` Background row (`SettingsView.swift:108-119` parity) into
   a ported `BackgroundSettingsView`. Five controls with captions do not fit
   gracefully appended to a one-picker sheet, and "match SingleThread's
   surface" is explicit in the task.
2. **Bindings bag: port `SettingsBindings` for the background prefs** — the
   sheet snapshots on open and writes back on change, matching SingleThread.
   Scope is deliberately narrower than the reference: the bag carries
   `backgroundEnabled`, `backgroundFadePercent`, `backgroundPinned` only.
   `appearanceMode` keeps its existing direct `@Binding` + `.onChange` window
   push, because its side effect lives in `ContentView` and migrating it adds
   risk with no feature value.
3. **Store ownership: one `@State`-held `BackgroundImageStore` on
   `ContentView`** — constructed with production defaults, passed to both the
   ZStack layer and the settings subscreen. No view-model layer is introduced.
4. **Rendering mount: `ZStack` back-to-front** — `Color.systemBackground`
   (`.ignoresSafeArea()`), then `BackgroundPhotoLayer`, then the existing
   centered checklist content. The solid base keeps the stroked buttons
   legible when a photo is absent and prevents the photo from showing through
   system chrome.
5. **Preferences: `.standard` `@AppStorage` with SingleThread's keys and
   defaults** — `backgroundEnabled = true`, `backgroundFadePercent = 50`,
   `backgroundPinned = false` (`SingleThread/ContentView.swift:86-93`).
6. **Failure UX: silent, parity** — `logger.error`, retain the prior stored
   image (render nothing if none), refresh button is the retry affordance. No
   alert or toast.
7. **Fetch trigger: `.task` on `ContentView` calls `refreshIfNeeded()`; pin
   changes flow through `.onChange` into `setPinned`** — matches
   `SingleThread/ContentView.swift:258-267` seams.
8. **Test target is created in this ticket** (option 3B), with targeted
   suites rather than a wholesale copy: store lifecycle + freshness + pin,
   `BackgroundFade` mapping, the photo-layer line limit/disabled seam, and
   bag snapshot/writeback. The gate `scripts/test.sh` gains
   `xcodebuild test`; the app target keeps its own group untouched.
9. **Directory namespacing: `Application Support/CheckStitch/`** with
   `background.jpg` / `background.json` — mirrors SingleThread's
   `/SingleThread` subdirectory, which research flagged as the only file-layout
   precedent.

## What We're NOT Doing

- No migration of `appearanceMode` (or any existing pref) into the bag.
- No bundled fallback/placeholder wallpaper and no `Assets.xcassets` additions.
- No new entitlements, signing changes, ATS keys, or app-group container use.
- No changes to the Unsplash endpoints, server behavior, or a client-side 6h
  constant (the server owns the 6h cache; the client's is 24h,
  `BackgroundImageStore.swift:177`).
- No custom error UI, retry backoff, or offline detection.
- No UI/snapshot/integration test automation of the live network fetch.
- No refactor of `AppDelegate` appearance plumbing or `SettingsView`'s
  existing picker row.
- No Live Activity/Widget, no additional settings subscreens beyond Background.

## Open Risks

- **Test-target pbxproj surgery is the highest-risk mechanical step.** A
  malformed target/scheme breaks `make build` too. Mitigation: add the target
  and verify `make build` still passes before writing any test, and keep the
  app target's synchronized group untouched.
- **EventKit prompts in tests.** `ContentView.swift:127-141` requests Reminders
  access; any test that instantiates `ContentView` or triggers its tasks can
  prompt for permission. Mitigation: keep suites at the store/fade/layer/bag
  level, seed `UserDefaults` directly, and avoid launching the app in tests.
- **macOS test destination.** The repo default destination is the iOS
  simulator; macOS 27.0 tests may need a separate run and the settings
  subscreen fix (`SettingsSubscreenLayout`) is macOS-gated. Decide whether the
  gate tests iOS only in this ticket.
- **Fetch path is untested against the real endpoint** in CI, and CheckStitch
  has never made a network request (research Q7) — real-server behavior,
  ATS, and `vardy.cc/unsplash` reachability are only exercised by manual
  `make run`.
- **`@Observable` store + `@AppStorage` writeback ordering**: the bag writes
  back on `.onChange`, so a pin flipped in the subscreen may round-trip
  through `@AppStorage` before `setPinned` runs; a missed `true→false`
  transition would skip the intended refresh.
- **Bag scoping.** Porting a partial bag (background only) may look
  inconsistent next to the direct `appearanceMode` binding; if reviewers want
  full parity, that becomes a follow-up ticket, not a silent expansion.