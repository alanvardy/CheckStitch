# VAR-976 Add backgrounds - Recon Report

## A) CheckStitch (cwd: /Users/vardy/dev/alanvardy-var-976-add-backgrounds)

Source list (8 files, all under CheckStitch/):
- CheckStitch/MyApp.swift - @main; WindowGroup { ContentView() }
- CheckStitch/ContentView.swift - the sole screen. The checklist card is an HStack of two stroked buttons (createChecklistButton, editChecklistButton) centered via ChecklistWidth.maxContentWidth (ContentView.swift:100-107), an explicit mirror of SingleThread CardWidth. No separate card file; EditChecklistView (the card content sheet) lives in this same file.
- CheckStitch/SettingsView.swift - modal .sheet with one Form section: the AppearanceMode picker (settingsPresented at ContentView.swift:33-38).
- CheckStitch/AppearanceMode.swift - enum + AppearanceModePreference helper (UserDefaults key appearanceMode, AppearanceMode.swift:93).
- CheckStitch/AppDelegate.swift - iOS/macOS appearance bridging.
- AppGroup.entitlements; Assets.xcassets contains only AccentColor - no background assets.

Persistence: UserDefaults via @AppStorage(appearanceMode) owned by ContentView and passed as @Binding into SettingsView (ContentView.swift:31-33). Same pattern will carry background prefs.

Backgrounds: none present.

Targets: SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx (iOS 18.7 / macOS 27.0, Swift 6.0). No test target; gate = scripts/test.sh = make build + shellcheck (AGENTS.md:14-18). New files under CheckStitch/ need no pbxproj edit (PBXFileSystemSynchronizedRootGroup, AGENTS.md:38-40).

Files to change for this ticket: ContentView.swift (ZStack with background layer behind the button row, 3 new @AppStorage prefs), SettingsView.swift (new Background section/row), plus 2-3 new files (fade/percent enum like BackgroundFade, a BackgroundPhotoLayer-style view, and a BackgroundImageStore if network-backed).

## B) SingleThread reference (/Users/vardy/dev/SingleThread)

Feature spans ~9 app-target files (all in SingleThread/ app target, not SingleThreadCore; explicitly phone-local, does NOT touch App Group or sync payloads):
- ContentView.swift:164-171 - ZStack { Color.systemBackground.ignoresSafeArea(); BackgroundPhotoLayer(imageData:isEnabled:opacity:); list }. Prefs at :86-93: @AppStorage backgroundEnabled (default true), backgroundFadePercent (50), backgroundPinned (false). Pin change routed to store at :259-266, refresh via .task in ContentViewModel.swift:138.
- BackgroundImageStore.swift (295 lines) - @MainActor @Observable store; GET https://vardy.cc/unsplash (6h cached, cold launch) and /unsplash/random (explicit refresh); validates decodable image; persists background.jpg + background.json (photographer credit, fetchedAt) atomically in Application Support; injectable BackgroundImageFetching protocol. Defines BackgroundPhotoLayer view: Color.clear.overlay(image.resizable().scaledToFill()).ignoresSafeArea().opacity(fade).allowsHitTesting(false).accessibilityHidden(true).
- BackgroundFade.swift - fade 0-90% step 10; opacity = 1 - percent/100.
- BackgroundSettingsView.swift - Form: enable Toggle, fade Picker, Pin toggle, Refresh button with ProgressView, Unsplash credit Link footer.
- SettingsView.swift:107-119 - NavigationLink row (settingsBackgroundRow) into BackgroundSettingsView.
- SettingsBindings.swift, ContentView+Settings.swift (bindings bag), AppViewModel.swift:27,54 (owns store), ContentViewModel.swift (injection, rowChromeBackground).

Settings UI: Background is a subscreen row under Settings, not inline. Tests exist: BackgroundImageStoreTests, BackgroundCardTests, BackgroundTestFixtures + UI tests.

## C) Verdict inputs

- CheckStitch files touched: ~4-6 (2 existing + 2-3 new). No schema/migration risk - UserDefaults keys only, mirroring backgroundEnabled/FadePercent/Pinned.
- Cross-cutting: yes - new UI surface (full-bleed background layer), new settings subscreen, and (for exact parity) a new network/API contract (vardy.cc/unsplash endpoints, Unsplash payload decode) plus first disk persistence outside UserDefaults. That is a new subsystem for CheckStitch (first network fetch, first image storage), though the app already copies SingleThread idioms (CardWidth/plate styling, AppStorage+sheet settings).
- Pattern carry-over: @AppStorage + SettingsView sheet covers pref plumbing end to end; the image pipeline (fetch, validate, disk, observable state) has no CheckStitch precedent.
- New-technology risk: no background assets exist in CheckStitch (must fetch at runtime or generate); must handle both UIImage (iOS) and NSImage (macOS) since the target builds for macosx; Unsplash attribution footers needed to match reference.

