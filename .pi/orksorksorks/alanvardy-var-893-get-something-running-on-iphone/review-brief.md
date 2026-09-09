# Review Brief — CheckStitch "get something running on iPhone"

Branch: `alanvardy-var-893-get-something-running-on-iphone` (PR #1, draft).
Repo root: `/Users/vardy/dev/alanvardy-var-893-get-something-running-on-iphone`.

## Goal (from task.md)
CheckStitch is a brand-new Xcode 26.6 SwiftUI scaffold. Goal: get the app building,
signing, installing, and launching on a **physical iPhone** (not simulator). The
sibling repo `/Users/vardy/dev/SingleThread` carries a proven on-device setup that
this effort mirrors.

## Changed files (git diff main...HEAD)
Full diff: `.pi/orksorksorks/alanvardy-var-893-get-something-running-on-iphone/review-diff.patch`
(465 lines). Changed files:

1. `CheckStitch.xcodeproj/project.pbxproj` (modified, 12 lines) — bundle ID
   `devplaceholder.*` → `app.alanvardy.CheckStitch`; `IPHONEOS_DEPLOYMENT_TARGET`
   27.0 → 18.7 (2 project-level spots); added sdk-conditioned
   `CODE_SIGN_ENTITLEMENTS` (iphoneos*/iphonesimulator*) → `CheckStitch/AppGroup.entitlements`
   in Debug + Release target configs.
2. `CheckStitch/AppGroup.entitlements` (new) — `com.apple.security.application-groups`
   → `group.app.alanvardy.CheckStitch`. No trailing newline.
3. `CheckStitch/ContentView.swift` (modified) — removed `import Playgrounds` and the
   `#Playground { … }` block (dead, needs iOS 27 SDK).
4. `scripts/run-devices.sh` (new, 75 lines) — build → discover device → install → launch.
5. `linear-project.md` (new) — single line `CheckStitch`.
6. `.pi/orksorksorks/…/plan.md` (committed) — 277 lines of workflow doc. NOTE: the
   repo convention (AGENTS.md / implement.md) says `.pi/` workflow docs are
   "untracked by design", yet `plan.md` was committed.

## Relevant artifacts (read for context)
- `task.md`, `large.md`, `questions.md`, `research.md`, `design.md`,
  `structure.md`, `plan.md`, `implement.md`, `conventions.md` — all under
  `.pi/orksorksorks/alanvardy-var-893-get-something-running-on-iphone/`.

## Reference implementation (the "proven" pattern)
- `/Users/vardy/dev/SingleThread/scripts/run-devices.sh` (device discovery via
  `devicectl`, install, launch; uses Python JSON parsing).
- `/Users/vardy/dev/SingleThread/SingleThread.xcodeproj/project.pbxproj` (signing
  team, bundle ID, entitlements wiring).
- `/Users/vardy/dev/SingleThread/Makefile`, `scripts/test.sh` (its `check` gate).

## Mechanical checks run by the orchestrator (already verified)
- `bash -n scripts/run-devices.sh` → OK.
- `shellcheck scripts/run-devices.sh` → clean (exit 0, no findings).
- `plutil -lint CheckStitch/AppGroup.entitlements` → OK.
- `xcodebuild -scheme CheckStitch -destination 'generic/platform=iOS'
  -configuration Debug -derivedDataPath DerivedData build` → **BUILD SUCCEEDED**.
- `codesign -d --entitlements - …/CheckStitch.app` → application-groups entitlement
  embedded (group.app.alanvardy.CheckStitch); `codesign --verify --deep --strict` → valid.

## KEY FINDING already reproduced by the orchestrator (verify + extend)
The device-discovery step in `scripts/run-devices.sh` is broken two ways:

1. `xcrun devicectl list devices -j > "$DEVICES_JSON"` — `-j` **requires a value**
   (`-` or a path). As written, devicectl errors `Error: Missing value for '-j <path>'`
   and (with `set -euo pipefail`) the script aborts. Correct: `-j -` (stdout) or
   `-j "$DEVICES_JSON"`.
2. The jq filter uses wrong field paths. Real `devicectl list devices -j` output is
   `{ "info": …, "result": { "devices": [ … ] } }`, and each device nests under
   `hardwareProperties.platform`, `deviceProperties.developerModeStatus`,
   `deviceProperties.name`, `connectionProperties.tunnelState/transportType`. The
   script's filter reads `.devices[]`, `.platform`, `.developerModeStatus`,
   `.connectionProperties.reachable` — all wrong (jq: "Cannot iterate over null").
   Corrected filter returns the physical iPhone `6C1EA973-3762-58B4-B04E-062FE6C3EB9F`.

   So the script has never been exercised end-to-end: `implement.md` leaves
   "bash scripts/run-devices.sh exits 0" and "Hello, world! visible" as UNCHECKED
   manual items.

## What each reviewer must return
Concise, evidence-backed findings with `file:line` references and suggested fixes.
Do NOT edit files. Flag blockers (soundness/correctness that defeats the goal),
fixes-worth-doing-now, and optional nits. Verify claims against files and tool
output you can read directly — do not trust the orchestrator's summary blindly.