# Design Discussion

## Current State

CheckStitch builds and tests entirely locally. There is **no integration surface
of any kind**: no `.github/`, no `ci_scripts/`, no `.ipa`/archive path, no
`exportOptions.plist`, and no TestFlight or App Store Connect reference anywhere
in the repo (`research.md` Cross-Cutting Observations). The remote is
`https://github.com/alanvardy/CheckStitch.git`.

**Build surface** — every target is Debug and local:

- `Makefile:17-23` `build` (iOS Simulator, unsigned), `:30-36` `build-mac`
  (unsigned compile), `:40-46` `build-mac-signed` (signed macOS), `:50-56`
  `watch-build` (watchOS Simulator, unsigned), `:57-58` `run`, `:64-86` `test-unit`/`test-ui`,
  `:88-89` `clean`.
- `scripts/test.sh` is the gate: `make build` → simulator lock → pre-boot →
  `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh`
  → shellcheck (test.sh:33-121).
- Device/watch runs exist but are Debug + devicectl, not distribution:
  `scripts/run-devices.sh:79-104`, `scripts/run-watch.sh:83-105`.

**Signing** is declarative and already archive-compatible:

- `CODE_SIGN_STYLE = Automatic` + `DEVELOPMENT_TEAM = 6NWX2DHB9Q`
  (project.pbxproj:490-496 Debug, :535-541 Release) — exactly what Xcode Cloud
  requires.
- One entitlements file only: `CheckStitch/AppGroup.entitlements:5-10` (App Group
  `group.app.alanvardy.CheckStitch` + KVS `$(TeamIdentifierPrefix)app.alanvardy.CheckStitch`),
  wired per-SDK at project.pbxproj:491-493/:536-538.
- **No `PROVISIONING_PROFILE*` anywhere**; signed legs rely on
  `-allowProvisioningUpdates` (Makefile:44, run-devices.sh:125, run-watch.sh:87).
- Watch target is signed (Automatic + team, project.pbxproj:679-681) but has **no**
  `CODE_SIGN_ENTITLEMENTS` and no App Group.

**Project shape** — four targets, one shared local SPM package
`CheckStitchCore` (project.pbxproj:779-789), no external dependencies, so no
dependency fetch step is needed. The watch app embeds into the iOS app via
`Embed Watch Content` (project.pbxproj:42). Two shared schemes exist; the
`CheckStitch` scheme's `ArchiveAction` is already **Release** (`research.md` Q3),
so the scheme is archive-ready with no edit.

**Versions are static**: `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 1`
on every target config (project.pbxproj:495-516 etc.). Bundle id
`app.alanvardy.CheckStitch`, watch `app.alanvardy.CheckStitch.watchkitapp`.

**Reference app**: `/Users/vardy/dev/SingleThread` proves a local macOS
App Store Connect path (`scripts/distribute-macos.sh` +
`exportOptions.plist` `method = app-store-connect`) and has a CI that
deliberately *neutralizes* signing (`echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV`,
ci.yml:21-32) because it only runs tests. There is **no iOS distribution
precedent in either repo**, and SingleThread's macOS ASC profile is documented
as not yet fixed (its `docs/TestFlight-macOS.md`).

**Key external facts driving this design** (web research, sources below):
Xcode Cloud assigns its own per-app `CI_BUILD_NUMBER` and App Store Connect
uses that number — not `CFBundleVersion`; Xcode Cloud requires automatic
signing; it **cannot fix misconfigured entitlements**; it supports Archive
actions for iOS, watchOS and macOS; and since 28 April 2026 uploads require the
iOS 26 / watchOS 26 SDK or later.

## Desired End State

An Xcode Cloud workflow, configured entirely through Xcode's GUI, that archives
the `CheckStitch` scheme for iOS and delivers the result to TestFlight internal
testing — so that a build of CheckStitch appears in App Store Connect, is
installable from the TestFlight app on a real device, and the process can be
repeated by pressing a button rather than by editing build scripts.

Concretely, done means:

1. Xcode Cloud is enabled for the app (one-time, Account Holder/Admin).
2. A workflow exists with a start condition, an **Archive** action for iOS with
   App Store Connect deployment preparation, and a **TestFlight (Internal
   Testing)** post-action.
3. The Apple Watch app rides along inside the iOS artifact (no separate workflow).
4. The Xcode Cloud build reports **Succeeded**, the build transitions to
   *Ready to Test* in App Store Connect, Apple's processing email arrives, and an
   internal tester can install it from TestFlight.
5. `make build` and `bash scripts/test.sh` behave byte-identically to today, and
   the repo diff for this work is documentation only.

macOS distribution is explicitly a fast-follow (see *What We're NOT Doing*).

## Patterns to Follow

- **Automatic signing, team-scoped, no profile specifiers**
  (project.pbxproj:490-496/:535-541; no `PROVISIONING_PROFILE*` in the file).
  Xcode Cloud issues its own distribution certificate and profile, so nothing
  new should be added here.
- **Single entitlements source**: any capability must be added to
  `CheckStitch/AppGroup.entitlements:5-10` and mirrored in the Developer portal;
  never inline entitlements into the project (Xcode Cloud cannot repair a
  mismatch here — it must be correct before the first Archive).
- **Shared scheme + explicit actions**: `CheckStitch.xcscheme` already fixes the
  buildable set, testables and `ArchiveAction = Release`; the workflow should
  consume the scheme as-is.
- **Local SPM package, no fetch step**: `CheckStitchCore` is a file-system
  reference (project.pbxproj:779-789), so no `ci_post_clone.sh` is needed and
  none should be added.
- **Source control hygiene**: `DerivedData/`, `build/`, `*.ipa`,
  `xcuserdata/` are already ignored, so Xcode Cloud artifacts have nowhere to
  leak into git.
- **Bundle id + `MARKETING_VERSION` are the ASC join keys**: the app record and
  the uploaded build are matched on `app.alanvardy.CheckStitch` and `1.0`.

Patterns found in the codebase that must **not** be followed here:

- **SingleThread's signing neutralization** (`.github/workflows/ci.yml:21-32`) —
  correct for its test-only CI, wrong for a distributing archive; a build
  without `DEVELOPMENT_TEAM` cannot reach TestFlight.
- **SingleThread's `exportOptions.plist` + `xcodebuild archive` script** — that
  is the local Organizer path for macOS; Xcode Cloud constructs its own export
  options, so copying this would create a second, divergent release mechanism.
- **Static `CURRENT_PROJECT_VERSION` as a release control** — ineffective under
  Xcode Cloud, which overrides it at upload time.
- **Bare `name=` destinations** (Makefile:4-5, enforced by
  `resolve-sim-udid.sh --require-id` at test.sh:24) — never reintroduce this in
  a release workflow.

## Design Decisions

1. **Delivery route: Xcode Cloud, configured via Xcode's GUI** — Apple-hosted
   build, sign and submit; no CI files, no credentials, no upload scripts in the
   repository. Chosen because it is the only route that reaches TestFlight
   without a committed credential-holding surface, and because the repo has zero
   release precedent to reuse on the CI side.
2. **No committed release surface**: no `ci_scripts/`, no `.github/`, no
   `fastlane`, no `altool` wrapper, no `make ios-distribute` target. The only
   repo change is a runbook under `docs/` recording the portal prerequisites and
   the click-path, matching SingleThread's `docs/TestFlight-macOS.md` precedent.
3. **No credentials of any kind**: no App Store Connect API key `.p8`, no
   `~/.appstoreconnect/` key, no app-specific password in the repo or in any
   script. Xcode Cloud authenticates as the developer account.
4. **Build numbers belong to Xcode Cloud; humans own `MARKETING_VERSION`** — the
   per-build number is `CI_BUILD_NUMBER` (starts at 1, per-app, monotonic across
   marketing versions) and is what App Store Connect records. A release therefore
   means bumping `MARKETING_VERSION`, not `CURRENT_PROJECT_VERSION`; the starting
   build number, if it ever needs adjusting, is set in App Store Connect →
   Xcode Cloud → Settings → Build Number, not in the repo.
5. **iOS first, watch embedded, macOS deferred** — one Archive action produces
   the iOS app with the watch app inside it (`Embed Watch Content`,
   project.pbxproj:42), giving one artifact and one TestFlight entry. Proven
   first, then repeated for macOS.
6. **Verification is Apple's own signal, not a committed check**: the workflow's
   Succeeded status, App Store Connect processing state, the processing email,
   and a manual internal-tester install. No verification script is added, so the
   gate stays provisioning-free and unmodified.
7. **Workflow Xcode version pinned explicitly to an Xcode 26+ image** — the
   project targets iOS 18.7 / watchOS 26.0 (project.pbxproj:420-428) and the
   28 April 2026 upload rule requires the iOS 26+ SDK, so the default image must
   not be left to chance.
8. **TestFlight internal testing only** — internal testers need no Beta App
   Review, so the first build reaches a device without an Apple review cycle.
   External testers are a later, separate decision.

## What We're NOT Doing

- **No GitHub Actions / `.github/workflows`** — Xcode Cloud is the CI.
- **No `ci_scripts/`** (no `ci_post_clone.sh`, `ci_pre_xcodebuild.sh`); no
  dependency fetch is needed and no version stamping is being done.
- **No App Store Connect API key, no Transporter/`altool` scripting, no
  `exportOptions.plist`** — nothing uploads from anywhere but Xcode Cloud.
- **No macOS TestFlight workflow in this ticket** — deferred as a fast-follow
  because it needs separate portal capability work and a different
  always-increasing build-number policy; the macOS App ID/capability state is
  unverified.
- **No changes to `Makefile`, `scripts/*.sh`, `scripts/test.sh`,
  `scripts/tests/run.sh`, the schemes, `project.pbxproj`, or
  `CheckStitch/AppGroup.entitlements`** — the gate and all local dev targets
  must behave identically. If a portal capability is missing, the fix belongs in
  the Developer portal, not in these files.
- **No build-number automation** (no `agvtool`, no timestamp stamping, no
  `CURRENT_PROJECT_VERSION = $(CI_BUILD_NUMBER)` — which does not work anyway).
- **No external TestFlight testers, no App Store submission, no release train
  management beyond bumping `MARKETING_VERSION` for the next version.**
- **No new tests.** There is nothing testable in the repo under this design; the
  existing shell suite (`scripts/tests/run.sh`) is unaffected and stays green.

## Open Risks

1. **App Store Connect app record existence is unverified.** If
   `app.alanvardy.CheckStitch` has no app record, one must be created (requires
   Admin/App Manager/Account Holder); Xcode Cloud can create it only if the name
   and bundle id are unique and the account role permits it.
2. **App Group + KVS capabilities on the iOS App ID are unverified.** Xcode Cloud
   cannot fix a mismatched entitlement — the first Archive fails if the portal
   capability is absent. This is the most likely first failure.
3. **Xcode Cloud enablement requires Account Holder or Admin** and is a one-time
   act; a Developer-only role blocks setup entirely.
4. **Builder image availability.** `MACOSX_DEPLOYMENT_TARGET = 27.0` and
   `WATCHOS_DEPLOYMENT_TARGET = 26.0` (project.pbxproj:420-428) may exceed what
   Xcode Cloud's newest image ships; iOS is safer than macOS here, which
   reinforces decision 5.
5. **Uncommitted verification means no regression signal.** If the workflow
   silently starts failing (signing drift, capability revocation, portal change),
   nothing in `scripts/test.sh` catches it; the failure surfaces only when someone
   looks at Xcode Cloud.
6. **The watch app carries no entitlements** (project.pbxproj:679-681) while the
   iOS app does; the embedded watch slice must survive archive signing, and a
   watch-capability mismatch would only appear at Archive time.
7. **Invalid pre-release train.** Because `MARKETING_VERSION` has been `1.0`
   throughout development, if a `1.0` train was ever opened and closed in App
   Store Connect, the first upload may be rejected until the version is bumped.
8. **Compute quota.** Xcode Cloud's included hours are finite; an
   Archive+TestFlight workflow that runs on every push consumes them quickly, so
   the start condition should be narrow (tag or manual) rather than every commit.
9. **Local fallback is risky.** If the GUI path stalls, archiving on this machine
   from Xcode 27.0 (a beta host) risks an `ITMS-90111` upload rejection, so
   "just do it locally" is not a clean escape hatch.