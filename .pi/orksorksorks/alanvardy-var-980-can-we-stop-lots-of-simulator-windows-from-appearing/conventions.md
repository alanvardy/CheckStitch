# Conventions

Shared factual appendix for the CheckStitch repo. Research-derived; Design/Structure/Plan should rely on this instead of re-reading the source tree.

## Canonical commands

| Command | What it does | Where defined |
| --- | --- | --- |
| `make build` | Simulator build: `xcodebuild -scheme CheckStitch -destination '$(SIM)' -configuration Debug -derivedDataPath DerivedData build` | `Makefile:14-18` |
| `make run` | `build` then `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'` (simctl boot/install/launch) | `Makefile:21-22` |
| `make test` | `test-unit test-ui` | `Makefile:25` |
| `make test-unit` | macOS-hosted unit tests: `xcodebuild … -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests test` (no sim, no signing) | `Makefile:26-35` |
| `make test-ui` | One XCTest smoke: `build-for-testing` then `-only-testing:CheckStitchUITests test-without-building`, both on `$(SIM)` | `Makefile:37-50` |
| `make clean` | `xcodebuild … -destination '$(SIM)' clean` | `Makefile:53-54` |
| `./scripts/test.sh` | **The gate**: `make build` → `make test` → `shellcheck scripts/*.sh` (or `bash -n` fallback) → `gate: ok` | `scripts/test.sh:8-15` |
| `bash scripts/run-devices.sh` | Real devices (devicectl) + host Mac; not the iOS Simulator | `scripts/run-devices.sh:1-153` |

- Gate verification: `make test-unit` (fast) before `bash scripts/test.sh` (full gate) — `AGENTS.md:29-30`.
- Scripts are `#!/bin/bash` with `set -euo pipefail`, committed mode `100755` — `AGENTS.md:31-32`.

## Simulator destination precedence

1. Explicit `SIM=` (command line or environment) wins — `?=` never overrides — `Makefile:1-3, 5`.
2. Worktree `.simulator_id` → `platform=iOS Simulator,id=<UDID>` — `Makefile:4` (file is the raw UDID, git-excluded via dotfiles `info/exclude`, `worktree_sim.fish:111-127`).
3. Shared fallback `platform=iOS Simulator,name=iPhone 17` — `Makefile:5`.

**Constraint**: never leave a bare `name=` destination in a script — it selects a shared device and wedges parallel agents (`AGENTS.md:35-37`, `Makefile:38-39`, `run-simulator.sh:9-11`, `addworktree.fish:22-24`). Destination resolution lives in `scripts/run-simulator.sh:20-28` (`,id=` direct, else `name=` via `xcrun simctl list devices available` + grep).

## Test-suite inventory

| Suite | Path | Framework | Platform/Gating | Coverage |
| --- | --- | --- | --- | --- |
| CheckStitchTests | `CheckStitchTests/` (Swift Testing, macOS-hosted) | `@Test` / `#expect`, behaviour-named functions (never `test`-prefixed), `@Test(arguments:)` for cases, `@MainActor` on any suite touching EventKit or the view model | `make test-unit` (`-destination 'platform=macOS'`, `CODE_SIGNING_ALLOWED=NO`) | Models, EventKit seam, checklist creator, view model; imports `@testable import CheckStitchCore` |
| CheckStitchUITests | `CheckStitchUITests/` (one XCTest smoke case) | XCTest | `make test-ui` — `build-for-testing` + `test-without-building` on the worktree's `.simulator_id` simulator | UI smoke |
| Fakes | `CheckStitchTests/TestFixtures.swift` | — | unit only | Shared test doubles |

- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in with `@MainActor` — never restore the app's default there (`Makefile:27-28`, `AGENTS.md:25-26`).
- Unit tests run on macOS host with `CODE_SIGNING_ALLOWED=NO` (no sim, no signing) — `Makefile:27-35`.

## Installed toolchain facts (Xcode 26.6, build 17F113) — from research Q2

- `xcrun simctl boot --help` does not work (`--help` is parsed as a device). Use `xcrun simctl help <subcommand>`.
- `simctl help boot`: `simctl boot <device> [--arch=<arch>] [--disabledJob=<job>] [--enabledJob=<job>] [--checked-allocations]` — **no headless/graphics/background option**. Child env via `SIMCTL_CHILD_` prefix.
- `simctl help launch`: `--wait-for-debugger --arch --console --console-pty --stdout=<path> --stderr=<path> --terminate-running-process --checked-allocations`.
- `simctl bootstatus <device> [-bcd]`: `-b` boot if not booted (used at `run-simulator.sh:41`), `-d` data-migration, `-c` continuous.
- Simulators on this host are iOS 26.5 devices (e.g. `iPhone 17 Pro (UDID) (Shutdown)`).

## Build/verify gotchas

- **Destination pinning**: the worktree's `.simulator_id` is the default sim for `build`/`test-ui`/`run`/`clean` — do not bypass with a bare `name=` (parallel-agent wedge).
- **`hx` (git editor) panics without a TTY** — commit with `git commit -m "…"` and `git -c core.editor=true rebase --continue` (`AGENTS.md:46-47`).
- **Signing**: `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (`project.pbxproj:405`), bundle id `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch`; on a machine without the profile add `-allowProvisioningUpdates`; do not re-derive the team from `~/Library/Developer/Xcode` (`AGENTS.md:18-20`).
- `GENERATE_INFOPLIST_FILE = YES` requires the `NSReminders*UsageDescription` keys (reference: `/Users/vardy/dev/SingleThread`) — `AGENTS.md:33-34`.
- New files under `CheckStitch/` need no `project.pbxproj` edit (`PBXFileSystemSynchronizedRootGroup`); SDK/platform settings live at `project.pbxproj:403-461, 430-570` (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`).
- `run-devices.sh` honours `SCHEME`, `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA` overrides; requires Developer Mode; prefers an iPhone — `AGENTS.md:23-24`.
- The `r` fish alias runs `./scripts/run-devices.sh` — keep the plural name — `AGENTS.md:32`.
- xcodebuild-managed sim boot is implicit: only `test-without-building` on an iphonesimulator destination actually boots/runs the sim; `build`/`build-for-testing`/`clean` only select the platform.