# Design Discussion

## Current State

CheckStitch is a bare Xcode 26.6 scaffold (objectVersion 90, pbxproj:8)
with:

- **One source target**: `MyApp.swift` + `ContentView.swift`, file-system
  synchronized (pbxproj:65), no test targets, no scripts, no CI.
- **Placeholder identity**: `PRODUCT_BUNDLE_IDENTIFIER =
  "devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)"`
  → `devplaceholder.PL40N1FW.CheckStitch` (pbxproj:273, 311).
- **Scaffold signing**: `CODE_SIGN_STYLE = Automatic`,
  `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (pbxproj:253,255,291,293),
  `REGISTER_APP_GROUPS = YES` (pbxproj:275,313), but **no entitlements
  file** and no `CODE_SIGN_ENTITLEMENTS` setting anywhere.
- **Deployment**: `IPHONEOS_DEPLOYMENT_TARGET = 27.0` at project level
  (pbxproj:173,237); `TARGETED_DEVICE_FAMILY = "1,2,7"` (pbxproj:284,322).
- **Build infrastructure**: None. No `scripts/`, no `Makefile`, no CI.
  `.gitignore` ignores `DerivedData/` and `build/`.

## Desired End State

A minimal iOS-only app that **builds, signs, installs, and launches on the
developer's physical iPhone** (iPhone 16 Pro Max, UDID
`00008140-000569890CD2801C`, iOS 27.0, Developer Mode enabled).

Verification: run one script; the app appears on the iPhone home screen and
launches showing "Hello, world!".

## Patterns to Follow

All patterns drawn from SingleThread; file:line refs are to
`/Users/vardy/dev/SingleThread`.

| Pattern | Source | Apply to CheckStitch |
|---|---|---|
| **Signing is fully declarative** — `CODE_SIGN_STYLE = Automatic` + `DEVELOPMENT_TEAM`; no identity or password in scripts | Cross-cutting #1, run-devices.sh:116-122 | Use Automatic + team `6NWX2DHB9Q` |
| **Entitlements file** — `AppGroup.entitlements` with `com.apple.security.application-groups`, wired via sdk-conditioned `CODE_SIGN_ENTITLEMENTS`, paired with `REGISTER_APP_GROUPS = YES` | Cross-cutting #3, pbxproj:740-742,790-792 | Add `CheckStitch/AppGroup.entitlements` + `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` |
| **Real reverse-DNS bundle ID** — `app.alanvardy.<AppName>` | pbxproj:770,820; run-devices.sh:26 | Use `app.alanvardy.CheckStitch` |
| **iOS deployment target floor at 18.7** | pbxproj:765,815; test.sh:117 | Set `IPHONEOS_DEPLOYMENT_TARGET = 18.7` |
| **`xcodebuild -destination 'generic/platform=iOS'`** for device builds | run-devices.sh:116-122 | Use same destination |
| **`devicectl device install app --device <udid> <app-path>`** — `.app` path, not bundle ID | conventions.md gotchas, run-devices.sh:136-140 | Same |
| **`devicectl device process launch --terminate-existing --activate --device <udid> <bundle-id>`** — bundle ID for launch | conventions.md gotchas, run-devices.sh:143-144 | Same |
| **`devicectl list devices -j` for discovery** — filter platform=iOS, developerModeStatus=enabled, reachable | run-devices.sh:41,55-87 | Same |
| **`set -euo pipefail`** in scripts | run-devices.sh:1-2 | Same |

Patterns explicitly **NOT** followed:
- **No macOS/watch/widget complexity** — SingleThread targets 4 platforms
  and 7 native targets; CheckStitch is a single iOS app.
- **No `test.sh` deployment-target drift guard** — SingleThread's
  `verify_deployment_target` (test.sh:120-203) expects 20 pbxproj literals
  plus 3 Package.swift literals; CheckStitch has no Package.swift and far
  fewer targets. Not worth building until there are tests.
- **No CI** — out of scope; SingleThread's CI (ci.yml:29,97,154) blanks
  `DEVELOPMENT_TEAM=` anyway and never builds for physical devices.

## Design Decisions

1. **Signing team: keep `6NWX2DHB9Q`** — matches SingleThread. The
   signability gap (machine has cert only for `55PGY6DK44`) is documented
   under Open Risks; the design preserves the correct team identity and
   treats cert acquisition as a pre-flight step, not a design change.

2. **Bundle ID: `app.alanvardy.CheckStitch`** — follows SingleThread's
   `app.alanvardy.<AppName>` convention (pbxproj:770). A real reverse-DNS
   ID is required for `devicectl device process launch` and provisioning.
   The scaffold `devplaceholder.*` is replaced.

3. **Entitlements: match SingleThread's pattern** — add
   `CheckStitch/AppGroup.entitlements` with
   `com.apple.security.application-groups` →
   `group.app.alanvardy.CheckStitch`, wire it into the pbxproj as
   `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] =
   CheckStitch/AppGroup.entitlements` and
   `CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*] =
   CheckStitch/AppGroup.entitlements` (pbxproj:740-742 pattern). The
   existing `REGISTER_APP_GROUPS = YES` stays. The app doesn't use app
   groups at runtime yet, but the entitlement plumbing mirrors
   SingleThread and avoids future migration cost.

4. **Deployment target: lower to 18.7** — matches SingleThread's floor
   (pbxproj:765). Change `IPHONEOS_DEPLOYMENT_TARGET = 27.0` → `18.7` at
   the two project-level slots (pbxproj:173,237); the target config blocks
   have no key of their own and inherit. No drift guard yet (no `test.sh`).

5. **Build/run script: minimal iOS-only** — `scripts/run-devices.sh`
   with:
   - Env: `SCHEME=CheckStitch`, `BUNDLE_ID=app.alanvardy.CheckStitch`,
     `CONFIGURATION=Debug`, `DERIVED_DATA=DerivedData`
   - Build: `xcodebuild -scheme $SCHEME -destination
     'generic/platform=iOS' -configuration $CONFIGURATION
     -derivedDataPath $DERIVED_DATA build`
   - Discover: `xcrun devicectl list devices -j` → filter platform=iOS,
     developerModeStatus=enabled, reachable
   - Install: `xcrun devicectl device install app --device $device_id
     $APP_PATH`
   - Launch: `xcrun devicectl device process launch --terminate-existing
     --activate --device $device_id $BUNDLE_ID`
   - Single-device path (no loop), `set -euo pipefail`, temp cleanup trap.
     No macOS step, no watch, no widgets.

6. **No `CODE_SIGN_IDENTITY` override** — SingleThread sets it only for
   macOS (`[sdk=macosx*] = "Apple Development"`, pbxproj:743,793). iOS
   relies on `Automatic` + team to resolve the cert. CheckStitch follows
   the same: no explicit identity for iOS.

7. **No Info.plist file** — the scaffold uses `GENERATE_INFOPLIST_FILE =
   YES` (pbxproj:262,300) with `INFOPLIST_KEY_*` entries. This stays; no
   reason to add a static plist.

## What We're NOT Doing

- **No macOS, watchOS, or visionOS targets** — the app is iOS-only.
  `TARGETED_DEVICE_FAMILY` stays `"1,2,7"` for now (reducing it requires
  project-level changes that can break the scaffold's auto-sync; the build
  destination `generic/platform=iOS` is the real constraint).
- **No test targets, CI, Makefile, or linting** — out of scope. The goal is
  on-device launch, not a full pipeline.
- **No App Icon** — SingleThread has `ASSETCATALOG_COMPILER_APPICON_NAME =
  AppIcon` (pbxproj:738,788); CheckStitch has no app icon assets. Not
  adding one — the app launches fine without it.
- **No runtime app-group usage** — the entitlement is plumbed, but no
  `UserDefaults(suiteName:)` or shared container code is added.
- **No TestFlight / distribution** — debug install only.

## Open Risks

1. **Team `6NWX2DHB9Q` has no valid cert on this machine.** The only valid
   Apple Development cert belongs to team `55PGY6DK44`
   (`23554912B86E3B6D56DF96599B0FF2F4DF3FB2E5`). A build signed under
   `6NWX2DHB9Q` will fail at `xcodebuild` unless:
   - A cert for `6NWX2DHB9Q` is obtained (Xcode Accounts → download
     provisioning profiles), or
   - The team is changed to `55PGY6DK44` as a fallback.
   **Mitigation**: the script will fail fast at the build step with a clear
   Xcode signing error; this is a pre-flight issue, not a design flaw.

2. **`devicectl device install` may reject the app** if provisioning
   doesn't cover the device UDID. The device is in Developer Mode and
   paired, but without `iprofile` we can't inspect provisioning state. The
   proven path (`run-devices.sh` installs SingleThread successfully) gives
   confidence but doesn't guarantee the new bundle ID + team combination.

3. **App Group entitlement is dead plumbing.** `REGISTER_APP_GROUPS = YES`
   + `AppGroup.entitlements` add an entitlement the app never exercises.
   This is harmless at runtime but adds two files and a pbxproj setting
   that have no functional purpose yet. If the app group provisioning fails
   during signing, it could block the build for a feature that isn't used.

4. **iOS 27.0 device + 18.7 deployment target** — expected to work (the
   minimum ≤ device OS), but the scaffold was authored for 27.0 and there
   may be API surface the scaffold references that requires >18.7. The
   build will catch this at compile time.

5. **Scaffold auto-sync may silently add files.** The
   `fileSystemSynchronizedGroups = (CheckStitch)` setting (pbxproj:65) means
   any file dropped into `CheckStitch/` becomes part of the target. The
   `AppGroup.entitlements` file added there will be automatically picked up
   as a resource unless excluded — but entitlements files are referenced
   via `CODE_SIGN_ENTITLEMENTS`, not the resources phase, so this should
   not cause a collision.