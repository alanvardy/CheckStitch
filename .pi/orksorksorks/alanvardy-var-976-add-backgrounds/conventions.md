# Conventions — CheckStitch

Shared factual appendix for Design/Structure/Plan. Paths relative to the repo
root `/Users/vardy/dev/alanvardy-var-976-add-backgrounds` unless noted.

## Canonical commands

- **Gate** (there is no test target): `bash scripts/test.sh` — runs `make build`,
  then `shellcheck scripts/*.sh` (falls back to `bash -n` if shellcheck is
  missing) (`scripts/test.sh:1-17`, `AGENTS.md:14-18`).
- **Build**: `make build` = `xcodebuild -scheme 'CheckStitch' -destination
  '$(SIM)' -configuration 'Debug' -derivedDataPath 'DerivedData' build`
  (`Makefile:20-26`).
- **Run on simulator**: `make run` = build + `bash scripts/run-simulator.sh
  '$(SIM)' '$(APP)'` (`Makefile:28-30`); APP =
  `DerivedData/Build/Products/Debug-iphonesimulator/CheckStitch.app`
  (`Makefile:11-12`).
- **Run on real device**: `bash scripts/run-devices.sh` (requires Developer
  Mode; prefers an iPhone). Honours `SCHEME`, `BUNDLE_ID`, `CONFIGURATION`,
  `DERIVED_DATA` overrides (`AGENTS.md:18-20`).
- **Destination precedence** (`Makefile:5-9`, `AGENTS.md:20-21`): explicit
  `SIM=` > this worktree's `.simulator_id` (created by addworktree/takeoff
  fish functions) > shared default `platform=iOS Simulator,name=iPhone 17`.
  Never leave a bare `name=` destination in a script — it selects a shared
  device and wedges parallel agents.
- **Test-suite inventory**: CheckStitch has **no test target** — a test target
  is explicitly out of scope for small tasks (`AGENTS.md:14-17`). The only
  test corpus for this feature lives in the reference repo
  `/Users/vardy/dev/SingleThread/SingleThreadTests/`
  (`BackgroundImageStoreTests.swift`, `BackgroundCardTests.swift` — iOS-only,
  `BackgroundPhotoLayerTests.swift`, `BackgroundFadeTests.swift`,
  `BackgroundTestFixtures.swift`, all Swift Testing `@Suite(.serialized)`).

## Build conventions & gotchas

- Every `scripts/*.sh` is `#!/bin/bash` with `set -euo pipefail`, committed
  mode `100755` (`AGENTS.md:23-24`).
- **New source files need no pbxproj edit**: the sole target uses
  `PBXFileSystemSynchronizedRootGroup` (`path = CheckStitch`, wired via
  `fileSystemSynchronizedGroups`) — anything dropped under `CheckStitch/`
  compiles automatically (`project.pbxproj:13-18, 59-61`, `AGENTS.md:38-40`).
- Platforms: `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`
  (`pbxproj:282, 324`); `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; iOS 18.7 /
  macOS 27.0. `ENABLE_PREVIEWS = YES` → `#Preview` blocks compile.
- **Info.plist**: `GENERATE_INFOPLIST_FILE = YES` and
  `NSReminders*UsageDescription` keys are declared for the reminders feature
  (`pbxproj:261-263, 303-305`) — SingleThread reference for these keys:
  `/Users/vardy/dev/SingleThread` (required when Info.plist is generated).
- **Signing/entitlements**: `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id
  `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch`
  (`CheckStitch/AppGroup.entitlements`). `CODE_SIGN_ENTITLEMENTS` is set only
  for `[sdk=iphoneos*]` and `[sdk=iphonesimulator*]`; the macOS target signs
  with no entitlements (unsandboxed) (`pbxproj:254-255, 296-297`). On a
  machine without the profile, add `-allowProvisioningUpdates`. Do not
  re-derive the team from `~/Library/Developer/Xcode` (`AGENTS.md:26-28`).
- **Prefs**: UserDefaults via `@AppStorage("key") var … = default` on the view
  (`ContentView.swift:19-20`), read outside SwiftUI via an explicit helper
  (`AppearanceModePreference`, `AppearanceMode.swift:90-118`); writes flow
  through `@AppStorage` only. `.standard` suite is the in-repo precedent; no
  `suiteName:` (app-group) keys are used anywhere.
- Conventions confirmands: `hx` panics without TTY → commit via
  `git commit -m "…"` and `git -c core.editor=true rebase --continue`;
  merge PRs with `gh pr merge <n> --rebase --delete-branch`; never push to
  main directly (`AGENTS.md`).
- Errors flow through the app's own error handling (e.g. `do/catch` +
  `logger.error` in `ContentView.swift:126-141`); no central error type
  exists in this repo — SingleThread's `URLError(.badServerResponse)` /
  `.cannotDecodeContentData` pattern is the reference for the fetch path.