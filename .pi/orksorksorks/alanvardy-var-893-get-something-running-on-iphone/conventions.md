# Conventions — build/verify/test reference

Source of truth for command and test-suite facts so Design/Structure/Plan
don't re-read the trees. **SingleThread** (`/Users/vardy/dev/SingleThread`)
is the mature project with a full gate; **CheckStitch (scaffold)** has
**none** — no Makefile, scripts/, CI, or tests.

## Canonical commands (SingleThread)

| Command | What it runs | Lines |
|---|---|---|
| `make build` | iOS Simulator (iPhone 17) Debug `build-for-testing` | Makefile:13-14 |
| `make test` | `./scripts/test.sh --unit-only` (macOS native, unsigned) | Makefile:63-64 |
| `make ui-test` | `./scripts/test.sh --ui-only` (iOS sim UI tests) | Makefile:66-67 |
| `make check` | `./scripts/test.sh` full pipeline (format→lint→build→periphery→UI→unit) | Makefile:87-88, test.sh:206-287 |
| `make simverify` | `./scripts/simverify.sh` iOS sim boot + UI tests + screenshot | Makefile:69-70 |
| `make lint` / `make format` | swiftformat --lint + swiftlint --strict / swiftformat + swiftlint --fix | Makefile:93-103 |
| `make periphery` | `periphery scan --skip-build --strict` | Makefile:105-106 |
| `make mac-build` / `mac-test` / `mac-run` | macOS build/test/run, **`CODE_SIGNING_ALLOWED=NO`** | Makefile:19-29 |
| `make mac-distribute` | `scripts/distribute-macos.sh` (archive + export, signs team 6NWX2DHB9Q) | Makefile:31-32 |
| `make watch-build` / `watch-test` / `watch-ui-test` | watchOS simulator build/tests | Makefile:16-17, 72-85 |
| `./scripts/run-devices.sh` | Physical-device install+launch (iOS build → `devicectl device install` → `process launch`); macOS step default on | run-devices.sh:114-180 |
| `./scripts/test.sh` (`full`/`--unit-only`/`--ui-only`) | Full gate / macOS-only / iOS-ui-only | test.sh:86-101 |

### The `check` gate (scripts/test.sh `full`, test.sh:206-287)
1. Format + `swiftlint --fix` (209-211) → `swiftformat --lint` (215) →
   `swiftlint lint --strict` (221)
2. iOS Sim Debug `build-for-testing` (224-228) → watch sim build (230-233)
3. `periphery scan --skip-build --strict` (235)
4. iOS UI tests `test-without-building` (237-242)
5. Watch: build-for-testing (244-250), embed `lib_TestingInterop.dylib`
   into the test runner (local-only fix, 252-266), UI tests (268-273),
   unit tests (275-279)
6. macOS unit tests `CODE_SIGNING_ALLOWED=NO` (281-287)
Always: iOS-sim UDID resolve + pre-boot (38-51); XCTest runtime cleanup
>1h in `~/Library/Developer/XCTestDevices` (65-98).

### Deployment-target consistency guard (test.sh:120-203, always runs)
- Floors: iOS 18.7, macOS/watchOS 26.5 (test.sh:117-119).
- Every `IPHONEOS/MACOSX/WATCHOS_DEPLOYMENT_TARGET` literal in pbxproj must
  equal its floor; expects **20 literals** (8 iOS + 6 macOS + 6 watchOS,
  test.sh:121) and **3 literals** in `SingleThreadCore/Package.swift`
  (test.sh:122). Literal-count drift fails (182-183). Mismatch → `exit 1`
  (192-195). *Note: CheckStitch's scaffold pins all deployment targets to
  27.0 (pbxproj:173, 237) — a divergence from the SingleThread floor.*

## Test-suite inventory

### SingleThread — platform gating via xcodebuild destinations, not `#if`
Unit tests run as **macOS native** (`platform=macOS`) and **iOS/watches on
simulators**; UI tests run on iOS/watchOS simulators via `test-without-building`.

| Path | Covers | Platform |
|---|---|---|
| `SingleThreadTests/` (macOS unit) | Core macOS unit tests, incl. AppGroupTests.swift:10 (suite name guard), AppInfoTests.swift:18,30,64 (display-name stubs), AboutViewTests.swift:47-48, LocalizationTests.swift:240-249 (18 InfoPlist.strings catalogs) | macOS native (`make test`/`mac-test`), iOS sim (CI unit-tests) |
| `SingleThreadUITests/` | iOS simulator UI smoke (testLaunchAndRenderSmoke) | iOS Sim (ci.yml:92-146) |
| `SingleThreadWatchTests/`, `SingleThreadWatchUITests/` | watchOS unit + UI on simulator | watchOS sim (test.sh:244-279, ci.yml watch job) |
| XCTest test runtimes | runtimes in `~/Library/Developer/XCTestDevices` auto-rotated (>1h) | host (test.sh:65-98) |

### CheckStitch — none
No test files, no test targets, no CI, no scripts. Only Swift sources:
`CheckStitch/MyApp.swift`, `CheckStitch/ContentView.swift`.

## CI (`.github/workflows/ci.yml`, SingleThread)
- Runner `macos-26`, `setup-xcode` 26.6. Jobs: `unit-tests` (sim matrix
  iPhone 17 / iPad, ci.yml:15-63), `ui-tests-smoke` (92-146), `mac-tests`
  (148-190, `CODE_SIGNING_ALLOWED=NO`), `lint` (207+), `watch-ui-tests`
  (fresh standalone watch sim, 291-301).
- **Signing neutralization**: every Xcode job overrides `DEVELOPMENT_TEAM=`
  (blank) (ci.yml:29,97,154); macOS build/test add `CODE_SIGNING_ALLOWED=NO`
  (181-187, 189-198). Nothing in CI signs; no physical-device job exists.
- DerivedData cache key hashes pbxproj + sources (ci.yml:47-53, 105, 175).

## Build/verify gotchas
- **Signing is the only place team IDs matter**: `CODE_SIGN_STYLE=Automatic`
  + `DEVELOPMENT_TEAM` in pbxproj; Automatic signing resolves the cert from
  the Apple Development keychain (single valid cert on this machine is team
  **55PGY6DK44**, not the pinned 6NWX2DHB9Q — see research.md Q5).
- **`CODE_SIGNING_ALLOWED=NO` is required for macOS builds** (no macOS
  signing identity is set up); used in Makefile:21,24, test.sh:286,294,
  run-devices.sh:158.
- **CI parallel clones disabled** (`-parallel-testing-enabled NO
  -maximum-concurrent-test-simulator-destinations 1`, ci.yml:68-82) to
  avoid EventKit/EKReminder SIGTRAP crashes.
- **Deployment targets are drift-guarded** — adding/removing
  `IPHONEOS/MACOSX/WATCHOS_DEPLOYMENT_TARGET` literals or changing 18.7/26.5
  fails `test.sh`.
- **Device install uses the `.app` path, launch uses the bundle id**
  (run-devices.sh:136-144); devices need Developer Mode + reachable
  (unlocked/on Wi-Fi).
- **XCTest simulator runtimes are auto-deleted when older than 1h** — a
  shared, timing-sensitive host resource.
- `xcodebuild` device builds use `-destination 'generic/platform=iOS'` and
  output to `DerivedData/Build/Products/${CONFIGURATION}-iphoneos/`
  (run-devices.sh:34-35, 116-122).

## Scaffold-specific facts (CheckStitch)
- No `./scripts/test.sh` exists in the scaffold repo — the "project gate"
  for this repo is not yet established.
- `.gitignore` (scaffold .gitignore:1-18) ignores `xcuserdata/`,
  `DerivedData/`, `build/`, `*.ipa`.
- Xcode 26.6 is the active install; project is objectVersion 90, target
  product name `MyApp` (pbxproj:68), product `CheckStitch.app` (pbxproj:67).