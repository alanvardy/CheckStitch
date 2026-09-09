# Research Findings

Scaffold repo: `/Users/vardy/dev/alanvardy-var-893-get-something-running-on-iphone`
Reference repo: `/Users/vardy/dev/SingleThread`

## Q1: How is the scaffold app configured today?

Repo root contains only `.git`, `.gitignore`, `.pi/`, `CheckStitch/`,
`CheckStitch.xcodeproj/`, `linear-project.md`. `.gitignore:1-18` ignores
`xcuserdata/`, `DerivedData/`, `build/`, `*.ipa`. No scripts/, docs/,
Makefile, CI, README, or `.entitlements` files exist.

### Project identity
- `CheckStitch.xcodeproj/project.pbxproj:8` `objectVersion = 90`;
  `CreatedOnToolsVersion = 26.3` (pbxproj:104), `LastUpgradeCheck = 2700`
  (pbxproj:100-101) → Xcode 26.x scaffold.
- Single `PBXNativeTarget` (pbxproj:56-72): name `CheckStitch`,
  `productName = MyApp` (pbxproj:68),
  `productType = "com.apple.product-type.application"` (pbxproj:70),
  `productReference = CheckStitch.app` (pbxproj:67).
- `fileSystemSynchronizedGroups = (CheckStitch)` (pbxproj:65) → source and
  resource files are auto-discovered from the folder; the Sources/
  Frameworks/Resources build phases have empty `files` lists (pbxproj:74-78,
  85-90, 99-103).

### Build settings (target Debug pbxproj:246-281, Release pbxproj:283-318 — identical)
- `IPHONEOS_DEPLOYMENT_TARGET = 27.0` at project level (pbxproj:173, 237);
  every other platform deployment target also 27.0 (pbxproj:117-119,
  182-191, 241-243).
- `PROJECT_UNIQUE_VALUE = PL40N1FW` (pbxproj:179, 242).
- `SDKROOT = auto` (pbxproj:276, 314).
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`
  (pbxproj:278, 316); `TARGETED_DEVICE_FAMILY = "1,2,7"` (pbxproj:284,
  322) → iPhone (1), iPad (2), visionOS (7).
- `CODE_SIGN_STYLE = Automatic` (pbxproj:253, 291);
  `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (pbxproj:255, 293).
- `PRODUCT_BUNDLE_IDENTIFIER = "devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)"`
  (pbxproj:273, 311) → expands to `devplaceholder.PL40N1FW.CheckStitch` —
  a scaffold placeholder, not a real reverse-DNS id.
- `REGISTER_APP_GROUPS = YES` (pbxproj:275, 313) but there is **no backing
  `.entitlements` file**; `CODE_SIGN_ENTITLEMENTS` appears nowhere in the
  pbxproj.
- `GENERATE_INFOPLIST_FILE = YES` (pbxproj:262, 300); no Info.plist file on
  disk — keys are generated from sdk-conditioned `INFOPLIST_KEY_*` entries
  (pbxproj:263-270, 301-307, all `iphoneos*`/`iphonesimulator*`:
  UIApplicationSceneManifest_Generation, UILaunchScreen_Generation, etc.).
- macOS-only toggles present: `ENABLE_APP_SANDBOX = YES`,
  `ENABLE_USER_SELECTED_FILES = readonly` (pbxproj:260-261, 298-299);
  `LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks"` with
  `[sdk=macosx*]` variant (pbxproj:269, 307).
- Swift: `SWIFT_VERSION = 5.0`, actor isolation MainActor, etc.
  (pbxproj:275-281, 313-319); Debug adds `SWIFT_ACTIVE_COMPILATION_CONDITIONS
  = "DEBUG $(inherited)"` (pbxproj:177).

### Missing vs SingleThread
- **No** `ASSETCATALOG_COMPILER_APPICON_NAME` / AppIcon.appiconset (assets
  hold only `Contents.json` + `AccentColor.colorset`), **no**
  `CODE_SIGN_ENTITLEMENTS`, **no** `.entitlements` files, **no**
  `CODE_SIGN_IDENTITY`, **no** app icon.

### Source files (auto-synced)
- `CheckStitch/MyApp.swift:1-10` — `@main struct MyApp: App` with
  `WindowGroup { ContentView() }`.
- `CheckStitch/ContentView.swift:1-17` — `import SwiftUI` + `import
  Playgrounds`; `Text("Hello, world!")`; `#Preview` and `#Playground { _ = 1
  + 2 }` blocks.

## Q2: How does SingleThread configure signing and device deployment?

`SingleThread.xcodeproj/project.pbxproj` (objectVersion 77, pbxproj:4);
seven native targets (pbxproj:494-576). Signing is **project-level
inherited + per-target**, never passed via scripts.

### Project-level
- `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (pbxproj:652 Debug, 715 Release).
- No project-level `CODE_SIGN_*` — those are per-target.

### Main app target (Debug pbxproj:730-798, Release pbxproj:788-836)
- `CODE_SIGN_STYLE = Automatic` (pbxproj:744, 794);
  `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (pbxproj:746, 796).
- **sdk-conditioned entitlements**:
  `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] = SingleThread/AppGroup.entitlements`
  (pbxproj:740, 790), `[sdk=iphonesimulator*]` same (pbxproj:741, 791),
  `[sdk=macosx*] = SingleThread/SingleThread.entitlements` (pbxproj:742, 792).
- `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"` (pbxproj:743,
  793) — **iOS builds have no explicit identity; Automatic + team resolves
  it from the Apple Development keychain**.
- `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThread` (pbxproj:770,
  820). `SDKROOT = auto` (773, 823);
  `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (775, 825);
  `TARGETED_DEVICE_FAMILY = "1,2"` (781, 831).
- `IPHONEOS_DEPLOYMENT_TARGET = 18.7` (765, 815); `MACOSX_DEPLOYMENT_TARGET
  = 26.5` (768, 818).
- `REGISTER_APP_GROUPS = YES` (772, 822); `ENABLE_APP_SANDBOX = YES` (747,
  797); `ENABLE_HARDENED_RUNTIME = YES` (748, 798).
- Icon: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (738, 788),
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor` (739, 789)
  → `Assets.xcassets/AppIcon.appiconset/Contents.json`.

### Other targets (pattern)
- Tests targets: `CODE_SIGN_STYLE = Automatic`, team `6NWX2DHB9Q`, bundle
  `app.alanvardy.SingleThreadTests` (pbxproj:846, 875) /
  `...UITests` (pbxproj:903, 927), `TEST_HOST` → built app (886-887),
  `TEST_TARGET_NAME = SingleThread` (914, 938). No entitlements file.
- Watch: bundle `app.alanvardy.SingleThread.watchkitapp` (954, 982),
  `SDKROOT = watchos`, `SUPPORTED_PLATFORMS = "watchos watchsimulator"`,
  family 4, `WATCHOS_DEPLOYMENT_TARGET = 26.5` (956-965, 984-993); **no
  entitlements**; companion-app key `INFOPLIST_KEY_WKCompanionAppBundleIdentifier
  = app.alanvardy.SingleThread` (951-952, 979-980).
- Widget: `CODE_SIGN_ENTITLEMENTS = SingleThread/AppGroup.entitlements`
  **unconditional** (pbxproj:1000, 1031), bundle
  `app.alanvardy.SingleThread.widget` (1015, 1046),
  `INFOPLIST_FILE = SingleThreadWidget/Info.plist` (1002, 1033),
  `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"` (1018, 1050) — no
  macosx.

### Entitlements files
- `SingleThread/AppGroup.entitlements` — `com.apple.security.application-groups`
  → `group.app.alanvardy.SingleThread`.
- `SingleThread/SingleThread.entitlements` — macOS: app-sandbox,
  application-groups (same group), audio-input, calendars,
  in-app-purchases.

### Interlock
- Watch/widget depend on app with `platformFilter = ios` (pbxproj:372-383);
  app embeds them via copy phases `Embed Watch Content` (43-54) /
  `Embed Foundation Extensions` (57-67) on the app target (214-219).

## Q3: What does scripts/run-devices.sh do?

`/Users/vardy/dev/SingleThread/scripts/run-devices.sh` (181 lines) is the
only physical-device installer.

### Setup
- `set -euo pipefail` (run-devices.sh:1-2). Env overrides: `SCHEME=SingleThread`,
  `BUNDLE_ID=app.alanvardy.SingleThread`, `CONFIGURATION=Debug`,
  `DERIVED_DATA=DerivedData`, `RUN_MAC=1` default on (25-29). Temp files +
  EXIT trap (30-32). Product paths:
  `$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/SingleThread.app`
  (34-35). `cd` to repo root (37).

### Discovery + filtering
- `xcrun devicectl list devices -j` (41); command failure → ❌ guidance
  (plug in/unlock/Trust) and `exit 1` (42-44).
- Python heredoc (55-87) emits `identifier|name` per qualifying device:
  platform must be `iOS` (66), deviceType `iPhone`/`iPad` (68),
  `developerModeStatus = enabled` (71-72); reachability filter (82-85)
  routes locked/asleep/off-network devices to an unreachable log.
- Zero-qualifying-device guards (95-107): unreachable > 0 → exit 1 with
  unlock/Wi-Fi guidance; else if `RUN_MAC=1` continue macOS-only; else exit 1.

### Build + install + launch (114-148)
- Single iOS build for all devices:
  `xcodebuild -scheme $SCHEME -destination 'generic/platform=iOS'
  -configuration $CONFIGURATION -derivedDataPath $DERIVED_DATA build`
  (116-122); validates APP_PATH exists (123-126).
- Per-device loop (129-139): `xcrun devicectl device install app --device
  $device_id $APP_PATH` (136-140) — takes the **.app path, not a bundle
  id**; then `xcrun devicectl device process launch --terminate-existing
  --activate --device $device_id $BUNDLE_ID` (143-144) — takes the **bundle
  id** (`app.alanvardy.SingleThread`).
- macOS host step, default on (149-171): `platform=macOS` build with
  `CODE_SIGNING_ALLOWED=NO` (153-159), `open` the app (167-169). Failure
  increments `failures`, no hard exit.
- Summary: `failures==0` → ✅ "Installed and launched on N device(s) and
  macOS"; else ❌ and `exit 1` (174-180).
- **Signing material never appears in this script** — no team, identity, or
  password args; signing comes entirely from the Xcode project
  (116-122, 153-159).

## Q4: Build/verify/test commands in SingleThread

### Makefile (`/Users/vardy/dev/SingleThread/Makefile`, 118 lines)
- Telemetry vars (1-8): `SIM` (iPhone 17 iOS sim), `WATCH_SIM`,
  `WATCH_TEST_SIM`, `MAC_SIM`, `DERIVED_DATA=DerivedData`.
- `build` (13-14): iOS Simulator Debug `build-for-testing`.
- `watch-build` (16-17): watchOS sim Debug `build`.
- `mac-build` (19-21): `platform=macOS` Debug `build` **with
  `CODE_SIGNING_ALLOWED=NO`**.
- `mac-test` (23-24): macOS unit tests, `CODE_SIGNING_ALLOWED=NO`.
- `mac-run` (26-29): macOS build + `open`.
- `mac-distribute` (31-32): `scripts/distribute-macos.sh`.
- `coverage*` (37-61): iOS sim tests + `xcrun xccov view`.
- `test` (63-64): `./scripts/test.sh --unit-only`.
- `ui-test` (66-67): `./scripts/test.sh --ui-only`.
- `simverify` (69-70): `./scripts/simverify.sh`.
- `watch-test`/`watch-ui-test` (72-85): watchOS sim tests.
- `check` (87-88): `./scripts/test.sh` (full pipeline). `clean` (90-91),
  `lint` (93-97: swiftformat --lint + swiftlint --strict), `format`
  (99-103), `periphery` (105-106).
- **No Makefile target builds for a physical device** — only
  `scripts/run-devices.sh` does.

### scripts/test.sh (322 lines, the full gate)
- Modes (86-101): `full` (default), `--unit-only`, `--ui-only`.
- Pre-steps: resolve+pre-boot iOS sim (38-51); clean XCTest runtimes >1h old
  in `~/Library/Developer/XCTestDevices` (65-98).
- `verify_deployment_target` (120-203) — always runs; floors iOS 18.7 /
  macOS+watchOS 26.5 (117-119); asserts every
  `IPHONEOS/MACOSX/WATCHOS_DEPLOYMENT_TARGET` literal in pbxproj matches
  (expects 20 literals: 8+6+6, line 121) and `Package.swift` floors (3
  literals, line 122), plus literal-count drift guard (182-183). Mismatch →
  exit 1 (192-195).
- Full pipeline (206-274): format+`swiftlint --fix` (209-211) → lint
  (215, 221) → iOS sim Debug `build-for-testing` (224-228) → watch sim
  build (230-233) → `periphery scan --strict` (235) → iOS UI tests
  `test-without-building` (237-242) → watch UI tests with a local
  `lib_TestingInterop.dylib` embedding fix (244-266) → watch unit tests
  (268-279) → macOS unit tests `CODE_SIGNING_ALLOWED=NO` (281-287).
- `--unit-only` (289-296): macOS native tests, `CODE_SIGNING_ALLOWED=NO`.
- `--ui-only` (298-311): iOS sim build + UI tests.

### scripts/simverify.sh (40 lines)
- Boots iOS sim (`simctl boot` + `bootstatus -b`, 22-25), builds UI-test
  target (30-35), runs `test-without-building` (37-42), best-effort
  screenshot to `build/simverify-cold-launch.png` (45-47).

### scripts/distribute-macos.sh (8 lines) + exportOptions.plist
- `xcodebuild archive -destination generic/platform=macOS -configuration
  Release` (4), `-exportArchive -exportOptionsPlist exportOptions.plist`
  (6). Plist: `method=app-store-connect`, `signingStyle=automatic`,
  `teamID=6NWX2DHB9Q`.

### CI — `.github/workflows/ci.yml` (309 lines; macos-26, setup-xcode 26.6)
- All Xcode-using jobs override `DEVELOPMENT_TEAM=` (blank) (ci.yml:29,
  97, 154) to keep cloud builds unsigned.
- `unit-tests` (15-63): sim matrix iPhone 17 / iPad; build-for-testing
  `-only-testing:SingleThreadTests` (60-66); `-parallel-testing-enabled NO
  -maximum-concurrent-test-simulator-destinations 1` (68-82) to avoid
  EventKit SIGTRAP clones; DerivedData cache keyed on pbxproj+source
  (47-53).
- `ui-tests-smoke` (92-146): iPhone 17; `-only-testing:SingleThreadUITests`,
  `-retry-tests-on-failure` (112-144).
- `mac-tests` (148-190): build+test with `CODE_SIGNING_ALLOWED=NO`
  (181-187, 189-198).
- `lint` (207+): mise install, swiftformat/swiftlint --strict, watch sim
  build, `periphery scan --strict`.
- `watch-ui-tests`: fresh standalone watch sim (291-301).
- **No CI job builds for a physical device.**

## Q5: Machine environment for building/signing to a physical iOS device

### Host and toolchain
- macOS 27.0 (arm64), `Alans-MacBook-Pro.local`.
- Xcode **26.6**, build 17F113; `xcode-select -p` →
  `/Applications/Xcode.app/Contents/Developer` (a second install exists:
  `/Applications/Xcode-beta.app`). Apple clang 21.0.0.
- `com.apple.pkg.MobileDeviceDevelopment` receipt present
  (`/Library/Apple/System/Library/Receipts`).

### Code-signing identities — **team mismatch is real**
- `security find-identity -v -p codesigning`:
  1. `F2C8A94336D18CB57FCC5B069396E72A60A043E1` — "Apple Development:
     alanvardy@gmail.com (55PGY6DK44)" — **CSSMERR_TP_CERT_REVOKED**.
  2. `23554912B86E3B6D56DF96599B0FF2F4DF3FB2E5` — "Apple Development: ALAN
     THOMAS VARDY (55PGY6DK44)" — **valid**.
- Exactly **one valid Apple Development cert**, for team **55PGY6DK44**.
- Both projects pin `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (scaffold
  pbxproj:255, 293; SingleThread pbxproj:652, 746). **Team 6NWX2DHB9Q is
  not represented in this machine's keychain.** No `.p12`/`.pem`/`.crt`
  signing material exists anywhere under `/Users/vardy/dev/SingleThread`.
- With `CODE_SIGN_STYLE = Automatic`, a build signed under team
  `6NWX2DHB9Q` would have no matching cert locally; team `55PGY6DK44` is
  the only cert available to Automatic signing.

### Provisioning / iprofile
- `xcrun iprofile` **does not exist** on this machine (exit 72); no
  `iprofile*` files under /Library, /Applications, /usr, /opt.
  `DeviceOnlyTrust.tlib` absent (`/System/Library/Security/DeviceOnlyTrust`
  missing).
- Provisioning *infrastructure* exists: `/Library/Apple/usr/bin/rvictl`,
  `/Library/Apple/usr/libexec/rpmuxd` (launchd unit
  `com.apple.rpmuxd.plist`), `/Library/Apple/usr/libexec/oah`,
  AirTrafficHost / DeviceInterface / DeviceLink / Mercury / MobileDevice /
  RemotePairing private frameworks, `com.apple.deviceinterfaced` +
  `com.apple.usbmuxd` launchd units.
- `/var/db/Provisioning`, `/var/db/RemotePairing` do not exist. Team/
  account provisioning state is **not enumerable via CLI** here.

### Connected devices (all Developer Mode enabled)
- **"Alan's iPhone"** — iPhone 16 Pro Max (iPhone17,2), UDID
  `00008140-000569890CD2801C`, **available (paired)**, localNetwork, iOS
  27.0 (build 24A5430a).
- **"Alan's adorable little iPad"** — iPad Pro 12.9" 4th gen (iPad8,11),
  UDID `00008027-001125911E31802E`, **connected (wired)**, iOS 27.0.
- "Alan's Apple Watch" — Watch Ultra (Watch6,18), watchOS 26.6 —
  developer mode enabled but **not iOS**.
- 8 simulated devices present but `shutdown` / no developer mode.

## Q6: Where identifiers live outside the pbxproj

### Scaffold repo
- Only the placeholder bundle id in pbxproj (273, 311). No identifiers in
  source/resources: `ContentView.swift:4` hardcodes `Text("Hello, world!")`;
  `MyApp.swift` is an empty App shell. No Info.plist, no `.lproj`/string
  catalogs, no entitlements files, no identifier-bearing scripts.

### SingleThread — one shared identity set threaded everywhere
- **Bundle id `app.alanvardy.SingleThread`**:
  `scripts/run-devices.sh:26,143,166` (default + launch target),
  `SingleThread/Products.storekit:10` (`hostBundleID`),
  `docs/TestFlight-macOS.md:16,34,41`, `docs/SimulatorManualVerification.md:73`.
- **App group `group.app.alanvardy.SingleThread`**:
  `SingleThreadCore/.../AppGroup.swift:11` (`suiteName`), used at
  `AppGroup.swift:17` as `UserDefaults(suiteName:)`;
  `SingleThread/AppGroup.entitlements:7`;
  `SingleThread/SingleThread.entitlements:11`;
  `SingleThreadTests/AppGroupTests.swift:10` (guard); `AGENTS.md:57` (rule:
  shared persistence must use `AppGroup.defaults`).
- **Display name `SingleThread`**: 18 `InfoPlist.strings` catalogs across
  app/watch/widget targets × 6 locales (e.g.
  `SingleThread/en.lproj/InfoPlist.strings:4`);
  runtime read `SingleThreadCore/.../AppInfo.swift:28-31`
  (`CFBundleDisplayName` ?? `CFBundleName` ?? fallback);
  rendered in `SingleThread/AboutView.swift:24`; pinned by tests
  (`AppInfoTests.swift:18,30,64`, `AboutViewTests.swift:47-48`,
  `LocalizationTests.swift:240-249`).
- **Team `6NWX2DHB9Q`** (docs only): `docs/TestFlight-macOS.md:39,66,89`,
  `exportOptions.plist`.
- **Product id `app.alanvardy.SingleThread.unlimited`**:
  `SingleThreadCore/.../EntitlementStore.swift:50,106`;
  `SingleThread/Products.storekit:7,18`; `PurchaseSettingsView.swift:72,140`;
  `docs/TestFlight-macOS.md:44-46` (portal product id must match).
- **Widget marker**: `SingleThreadWidget/Info.plist`
  (`NSExtensionPointIdentifier = com.apple.widgetkit-extension`).
- CI/scripts neutralize the team rather than sign: ci.yml:29,97,154,253
  (`DEVELOPMENT_TEAM=`), test.sh:281,296 and run-devices.sh:158
  (`CODE_SIGNING_ALLOWED=NO`).

## Cross-Cutting Observations

1. **Signing is fully declarative.** Both projects use
   `CODE_SIGN_STYLE = Automatic` + `DEVELOPMENT_TEAM`; the build system
   resolves the team's Apple Development cert itself. No script or CI job
   passes an identity or password anywhere.
2. **Team `6NWX2DHB9Q` vs the machine's only valid cert (team
   `55PGY6DK44`).** Both pbxproj files pin 6NWX2DHB9Q (scaffold pbxproj:255,
   293 — in a stock scaffold; SingleThread pbxproj:652, 746). The only
   valid signing cert on this machine belongs to team 55PGY6DK44. This
   touches every signed build path.
3. **Entitlements pattern:** an `AppGroup.entitlements` file with
   `com.apple.security.application-groups` = the suite group string, wired
   in via `CODE_SIGN_ENTITLEMENTS` (sdk-conditioned on the main target,
   unconditional on widgets); `REGISTER_APP_GROUPS = YES` accompanies it.
4. **Identifiers are threaded and guarded.** Bundle id, group, display
   name, product id and team each have a single source of truth (pbxproj,
   Swift constant, plist/string catalog, docs) plus tests asserting them
   (AppGroupTests, AppInfoTests, LocalizationTests).
5. **Platform conditioning is per-sdk.** Deployment targets (18.7 iOS /
   26.5 macOS/watchOS), entitlements files and identities vary by
   `[sdk=...]`; the scaffold instead sets everything to 27.0 unconditionally.
6. **CI never signs for real** — `DEVELOPMENT_TEAM=` + `CODE_SIGNING_ALLOWED=NO`
   neutralize signing; only `distribute-macos.sh` signs (team 6NWX2DHB9Q).

## Open Areas

- Whether a cert for team `6NWX2DHB9Q` exists anywhere not surveyed (other
  keychains, CI secrets, another Mac); not found on this machine.
- Provisioning/team state (`iprofile list provisioning`) is unanswerable
  here — the tool is not installed.
- Whether the scaffold's `devplaceholder.*` bundle id would be accepted by
  `devicectl device install`; untried — nothing has been installed from the
  scaffold repo. The proven path installs a real reverse-DNS id
  (`app.alanvardy.SingleThread`).
- Relationship between the scaffold's `DEVELOPMENT_TEAM = 6NWX2DHB9Q`
  (present in the "stock" scaffold) and the device-deployment workflow is
  unexplained by the repo itself.
- Whether iOS 27.0 devices accept an app built with SingleThread's 18.7
  floor (the minimum is ≤ device OS, so expected fine) — untested.