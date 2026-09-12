# Research Findings

## Q1: How does the xcodebuild-managed simulator lifecycle work in the gate path?

### Findings
- Destination resolution is the single computation point, `Makefile:1-5`:
  - `Makefile:4` — `SIM_FROM_WORKTREE := $(shell test -f .simulator_id && printf 'platform=iOS Simulator,id=%s' "$$(cat .simulator_id)")` — reads the worktree `.simulator_id` (currently `D82898D5-C8E0-4C92-8989-EE599C30FEA4`) into an `id=` destination.
  - `Makefile:5` — `SIM ?= $(if $(SIM_FROM_WORKTREE),…,platform=iOS Simulator,name=iPhone 17)` — explicit `SIM=` wins (also env via `?=`), else worktree id, else shared `name=iPhone 17` fallback.
  - `Makefile:6` — `MAC_SIM := platform=macOS` (host unit-test destination).
  - `Makefile:10` — `APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app` — the simulator artifact path.
- `build` target `Makefile:14-18`: `xcodebuild -scheme 'CheckStitch' -destination '$(SIM)' -configuration 'Debug' -derivedDataPath 'DerivedData' build`. Selects the worktree simulator and compiles the iphonesimulator platform; does not boot a window itself. No `-allowProvisioningUpdates` here (only `scripts/run-devices.sh:124` for physical devices).
- `run` target `Makefile:21-22`: `run: build` then `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'` — boot here is handed to the simctl lifecycle, not xcodebuild.
- `test` target `Makefile:25`: `test: test-unit test-ui`.
- `test-unit` `Makefile:26-35`: `xcodebuild … -destination '$(MAC_SIM)' CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests test` — macOS host only, comment `Makefile:27-28`: "no simulator boot", suites opt into `@MainActor` per-suite (actor isolation deliberately unset on test targets).
- `test-ui` `Makefile:37-50`: exactly one UI smoke case on the worktree's dedicated simulator (comment `Makefile:38-39`: "never a bare `name=` destination"):
  - Phase 1 `Makefile:40-44`: `xcodebuild … -destination '$(SIM)' … build-for-testing` — builds app + test bundle for the simulator destination.
  - Phase 2 `Makefile:45-50`: `xcodebuild … -destination '$(SIM)' … -only-testing:CheckStitchUITests test-without-building` — the invocation that actually selects/boots the simulator and runs the smoke case.
- `clean` `Makefile:53-54`: `xcodebuild … -destination '$(SIM)' clean`.
- Gate orchestration `scripts/test.sh:8-9`: `make build` then `make test`, then `shellcheck scripts/*.sh` (or `bash -n` fallback) `scripts/test.sh:10-14`, `gate: ok` at `:15`. The gate's whole simulator exposure is the `build` + `test-ui` invocations.
- Summary of which invocations touch a simulator: all with `-destination '$(SIM)'` — `build` (`Makefile:16`), `test-ui` phase 1 (`:40-44`), phase 2 (`:45-50`), `clean` (`:54`). Only `test-without-building` (phase 2) actually boots/runs on the simulator; the others select the platform.
- `-destination '<spec>'` is the sole selector; forms: `platform=iOS Simulator,id=<UDID>`, `platform=iOS Simulator,name=iPhone 17`, `platform=macOS`, `generic/platform=iOS` (`run-devices.sh:123`).
- `project.pbxproj` iphonesimulator context: `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (`project.pbxproj:430, 472, 497, 522, 546, 570`); `[sdk=iphonesimulator*]`-scoped settings `CODE_SIGN_ENTITLEMENTS` (`:403, 445`), `INFOPLIST_KEY_UIApplication…`/`UILaunchScreen`/`UIStatusBarStyle` (`:413-419, 455-461`); `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (`:405`).
- **Not findable in budget**: the exact internal mechanism xcodebuild uses to boot a simulator for a `-destination` — no headless/background flag exists anywhere in the repo; booting behavior is xcodebuild's built-in handling of iphonesimulator destinations.

## Q2: How does the simctl-managed lifecycle in scripts/run-simulator.sh work?

### Findings
- Script frame: `#!/usr/bin/env bash`, `set -euo pipefail` (`scripts/run-simulator.sh:1-2`); usage header `:4-12` documents `<destination> <app-path>` and that the Makefile passes the per-worktree `.simulator_id` simulator so parallel agents don't share a device.
- Args: `SIM="${1:?usage: …}"` `:14`, `APP="${2:?usage: …}"` `:15`, `BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch}"` `:16` (env-overridable); `cd "$(dirname "$0")/.."` `:18`.
- Destination-to-UDID resolution `:20-28`: `,id=` form → `UDID="${SIM##*id=}"` (`:22`); `,name=` form → strip `name=` and trailing `,…`, then `UDID="$(xcrun simctl list devices available | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')"` (`:26-28`) — matches first available-device line starting `"<NAME> ("`.
- Error handling `:30-37`: un-resolvable UDID → stderr `ERROR: could not resolve a simulator for '$SIM'` + `exit 1`; missing app dir → `ERROR: app bundle not found at $APP (run 'make build' first)` + `exit 1`; `set -e` aborts on any failing xcrun step, except the tolerated boot failure.
- Boot sequence `:39-41`:
  1. `echo "==> Booting simulator $UDID…"` `:39`
  2. `xcrun simctl boot "$UDID" 2>/dev/null || true` `:40` — errors swallowed; booting an already-booted device is expected to fail.
  3. `xcrun simctl bootstatus "$UDID" -b` `:41` — `-b` boots if not booted, then blocks until boot completes (per `simctl help bootstatus`).
- Install/launch `:43-47`: `xcrun simctl install "$UDID" "$APP"` `:44`; `xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"` `:47`; success banner `:49-50`.
- **Installed `xcrun simctl` surface (Xcode 26.6, build 17F113)** — the key evidence for this ticket:
  - `xcrun simctl --help`: usage `simctl [--set <path>] [--profiles <path>] <subcommand> …`; devices may be a UDID or literal `booted`; subcommands include boot, bootstatus, create, delete, install, launch, list, shutdown, spawn, terminate, ui, clone, reboot, upgrade.
  - `xcrun simctl boot --help` does **not** work — simctl treats `--help` as a device argument (`Invalid device or device pair: --help`). The help mechanism is `xcrun simctl help <subcommand>`.
  - `simctl help boot`: `Usage: simctl boot <device> [--arch=<arch>] [--disabledJob=<job>] [--enabledJob=<job>] [--checked-allocations]` — arch (arm64/x86_64), launchd job enable/disable, checked allocations. **No headless/graphics/background option exists on `boot`.** Child environment is passed via the `SIMCTL_CHILD_` prefix.
  - `simctl help launch`: `--wait-for-debugger`, `--arch`, `--console`, `--console-pty`, `--stdout=<path>`, `--stderr=<path>`, `--terminate-running-process`, `--checked-allocations`; `SIMCTL_CHILD_` env prefix.
  - `simctl help bootstatus`: `bootstatus <device> [-bcd]` — `-b` boot if not booted, `-d` data-migration info, `-c` continuous monitor; "You can safely call this before you attempt to start booting the device."
  - `simctl help ui`: only device UI *appearance* options (light/dark, increase_contrast, …) — nothing about host-side windowing/headless.
  - `xcrun simctl list devices available` shows iOS 26.5 devices, e.g. `iPhone 17 Pro (9BD6777A-…) (Shutdown)` and `Gate iPhone 17 (A1918821-…)` — matching the script's `grep -F "$NAME ("` pattern.
- **Not findable in budget**: semantics of the global `--set`/`--profiles` flags; no headless-related option anywhere in the simctl help surface that was read. Whether a `SIMCTL_*`/other env var (outside the documented `SIMCTL_CHILD_` prefix) or `Simulator.app` preferences control windowing was not established.

## Q3: What are the simulator destination conventions?

### Findings
- **Makefile is the single computation point** `Makefile:1-5`: explicit `SIM=` wins (the `?=` never overrides), else worktree `.simulator_id` → `platform=iOS Simulator,id=<UDID>`, else shared fallback `platform=iOS Simulator,name=iPhone 17`. `SIM` feeds `build` (`:16`), `run` (`:22`), `test-ui` (`:40-50`), `clean` (`:54`); `test-unit` uses separate `MAC_SIM` (`:6`).
- `.simulator_id` (repo root, untracked/git-excluded): bare UDID `D82898D5-C8E0-4C92-8989-EE599C30FEA4`, no destination syntax. Read by the Makefile (`Makefile:4`) and dotfiles (`worktree_sim.fish:135, 160-164`); **not** read by `scripts/run-simulator.sh` — that script consumes the already-computed destination as `$1` from `make run`.
- `scripts/run-simulator.sh` does resolution, not computation: `,id=` direct (`:20-22`), else `name=` via `simctl list devices available` + grep (`:24-28`).
- Dotfiles writer side: `_worktree_sim_create` reuses an existing `.simulator_id` if the UDID still exists (`worktree_sim.fish:138-143`), else `xcrun simctl create <name> <device> [runtime]` and `printf` the UDID into `.simulator_id` (`:158-164`); `_worktree_sim_gitignore` appends `.simulator_id` to git `info/exclude` (`:111-127`); device precedence `.simulator-device` line 1 → parsed from the repo's own Makefile/scripts/test.sh destination (`:44-88`) → hardcoded `iPhone 17` (`:82`).
- Documented constraints on bare `name=` and parallel agents:
  - `Makefile:38-39` (test-ui comment): "Exactly one UI smoke case, on this worktree's dedicated simulator (never a bare `name=` destination)."
  - `AGENTS.md:35-37`: "Destination precedence is documented in the Makefile: explicit `SIM=` > this worktree's `.simulator_id` > shared default. Never leave a bare `name=` destination in a script — it selects a shared device and wedges parallel agents."
  - `~/dev/dotfiles/fish/functions/addworktree.fish:22-24` and `takeoff.fish:116-118`: "Give this worktree its own simulator UDID so parallel test runs cannot collide (see worktree_sim.fish). No-op for non-Swift checkouts."
  - `run-simulator.sh:9-11` — per-worktree sim so parallel agents do not share one device.
  - Prior artifacts restate it, e.g. `.pi/orksorksorks/alanvardy-var-894-run-on-ipad-and-mac/small.md:32`.
- `scripts/test.sh` (the gate) never references SIM — it just runs `make build` + `make test`.
- Note: dotfiles do not read the Makefile's `name=iPhone 17` fallback verbatim; `_worktree_sim_device` re-derives a device name at creation time.

## Q4: How does the per-worktree simulator creation pipeline in ~/dev/dotfiles work?

### Findings
- Entry point `worktree_sim.fish:1-20`: public `worktree_sim create|delete <worktree-dir>`; resolves the path and dispatches to `_worktree_sim_create`/`_worktree_sim_delete`; `_worktree_sim_is_swift` (`:26-34`) makes non-Swift checkouts a no-op (finds `*.xcodeproj`/`*.xcworkspace`/`Package.swift` at maxdepth 2, excluding `.build`, `.swiftpm`, `DerivedData`).
- Create path `_worktree_sim_create` (`:130-165`):
  1. Early-return if not Swift (`:131-133`).
  2. Reuse check (`:134-141`): if `.simulator_id` present, non-empty, and matched by `xcrun simctl list devices`, print "Reusing simulator" and return — no boot, no re-create. (Checks registration only, not booted state.)
  3. Name = `sim-<worktree-basename>` with non-`[A-Za-z0-9._-]` → `-` (`_worktree_sim_name` :39).
  4. Device (`_worktree_sim_device` :44-99): `.simulator-device` line 1 → parsed from repo Makefile/scripts/test.sh (`_worktree_sim_parse_device` :68-88) → `'iPhone 17'` (:82); optional line 2 is a runtime (`_worktree_sim_runtime` :90-99).
  5. Stale-sim cleanup by derived name (`_worktree_sim_delete_by_name` :102): `simctl shutdown` then `simctl delete` each matching UDID via `simctl list devices --json` + `jq`.
  6. Create (`:151-158`): `xcrun simctl create <sim-name> <device-type> [runtime]` with stderr suppressed. **No `--connect`/UDID-parent, no boot arguments.**
  7. Writes the returned UDID to `<worktree>/.simulator_id` (`:160`). The simulator is created **not booted** — `simctl create` only registers it; booting is the caller repo's job (xcodebuild or `scripts/run-simulator.sh`).
- `info/exclude` wiring `_worktree_sim_gitignore` (`:111-127`): appends `.simulator_id` to `git rev-parse --git-path info/exclude` (shared exclude file, untracked), idempotent via `grep -qxF`.
- Delete path `_worktree_sim_delete` (`:168-196`): prefers UDID from `.simulator_id` (`:172-179`), falls back to matching UDIDs by derived name (`:181-192`); `xcrun simctl shutdown` then `xcrun simctl delete` (`:194-195`), removes the id file on success (`:196`). No boot/headless flags.
- Callers: `takeoff.fish:116-118` and `addworktree.fish:22-24` call `worktree_sim create ../$branch` right after `git worktree add`; teardown in `merge.fish:15` and `mergeworktree.fish:102` call `worktree_sim delete`.
- Boot options/headless flags: **none anywhere in the pipeline.** `worktree_sim.fish` only ever calls `simctl list devices`, `list devicetypes`, `create`, `shutdown`, `delete` (`:74, 104-106, 158, 194-195`). A repo-wide grep of dotfiles for `simctl boot|simctl bootstatus|headless|wait-for-services` returned zero matches (only false positive `gh pr view -w` in `v.fish:6`). Doc confirms: `~/dev/dotfiles/pi/agent/skills/worktree/SKILL.md:57-63` describes the pipeline as create + `.simulator_id` write only; booting is left entirely to the caller repo.

## Q5: What in-repo and sibling-repo evidence exists about simulator boot behavior?

### Findings
- **No headless/`Simulator.app`/background-boot mechanism exists anywhere in the CheckStitch repo.** The only "headless" mentions are this ticket's own task text: `.pi/orksorksorks/…/980…/large.md:5-8, 14-15` (candidates named: "simctl headless flag/env var vs xcodebuild-managed boot vs Simulator.app prefs", explicitly unverified on this Xcode). No README exists (find returned none); `AGENTS.md` has no boot/prefs documentation.
- `project.pbxproj` contains no boot/headless/Simulator.app references — only platform/SDK settings (`:403-461, 430-570`, see Q1).
- Sibling repo `/Users/vardy/dev/SingleThread`:
  - Same destination scheme plus `WATCH_SIM`/`WATCH_TEST_SIM` (`Makefile:1-21`); `export SIM` only on explicit override.
  - `scripts/test.sh:27-48` — `resolve_sim_udid` (`:27-36`), `preboot_sim` (`:39-45`): `xcrun simctl boot "$udid" 2>/dev/null || true` + `xcrun simctl bootstatus "$udid" -b`; comment `:37-38` "Pre-boot the simulator so the first test run doesn't pay a cold boot; matches CI's pre-boot pattern (ci.yml:48-52)". Pre-boot only when `,id=` resolved (`:64-74`).
  - `scripts/simverify.sh:15-19` — same `simctl boot` + `bootstatus -b`; `:39` screenshot via `simctl io`.
  - `scripts/test-one.sh:38, 42` — the only backgrounding in either repo: the xcodebuild *test command* is backgrounded with `&` plus a timed kill watchdog. This is not simulator boot.
  - `.github/workflows/ci.yml:39-43, 107-111` — "Pre-boot simulator" steps (`simctl boot` + `bootstatus -b`); `:268-277` watch simulator create + boot; `-parallel-testing-enabled NO` (`ci.yml:56-71`).
  - **No `headless`, `Simulator.app`, `nohup`, or simulator-background flags anywhere in SingleThread** (zero matches).
- Prior .pi research (same repo lineage) documents the sibling patterns: `.pi/…/var-977-add-tests/research.md:53, 58, 94, 96` and `conventions.md:52`; `.pi/…/var-893-…/research.md:196, 214` (pre-boot pattern; `-maximum-concurrent-test-simulator-destinations` appears only in SingleThread's ci.yml per `research.md:229`).
- **Not findable in budget**: any record of a headless boot switch or Simulator.app preference key — confirmed absent from both repos rather than overlooked.

## Cross-Cutting Observations

- **Two disjoint boot lifecycles, one shared destination string.** `Makefile:4-5` computes the destination once; xcodebuild consumes it directly (`build`, `test-ui`), and `make run` passes it to `run-simulator.sh` which re-resolves it to a UDID. Any windowing control must slot into both consumers or into `SIM` handling itself.
- **No headless option exists in the read simctl surface (Xcode 26.6/17F113)**: `simctl help boot` exposes only `--arch/--disabledJob/--enabledJob/--checked-allocations`; `launch` exposes console/stdio plumbing (`--console`, `--console-pty`, `--stdout`, `--stderr`) but those are about the app's stdio, not host windowing; `simctl help ui` covers only device UI appearance. The `SIMCTL_CHILD_` env prefix is the documented channel for child-process env, so any env-driven control (if it exists) would surface under that family — unverified.
- **Windowed boot is an implicit side effect in both paths** — nothing in the repo opts into a window; the Simulator window presumably comes from the Simulator GUI process each mechanism launches. No prefs file or env toggle is referenced anywhere.
- **The "never bare `name=`" rule is the load-bearing shared convention** (`Makefile:38-39`, `AGENTS.md:35-37`, `addworktree.fish:22-24`, `run-simulator.sh:9-11`) — any change to the gate's boot behavior must not reintroduce shared-device selection.
- **SingleThread is the pattern reference**: it already does simctl pre-boot + `bootstatus -b` in scripts, CI, and simverify — the exact same shape as `run-simulator.sh:40-41`, and it also has no headless handling.

## Open Areas

- The precise windowing control mechanism for this Xcode (simctl env var vs xcodebuild flag vs Simulator.app preferences) is **unverified** — Q2 read the documented help surface only; the full `SIMCTL_*` env-var space, `simctl --set`/`--profiles` semantics, and Simulator.app prefs (e.g. `~/Library/Preferences/com.apple.iOSSimulator…`) were out of budget. This is the spike the ticket names.
- Whether xcodebuild's `test-without-building` boots the simulator through the same Simulator GUI as `simctl boot` (one window per simulator, shared process) is not established from the codebase.
- `_worktree_sim_create`'s reuse check (`worktree_sim.fish:134-141`) verifies registration only — how many simulators are typically left booted/running per host while worktrees park (the ticket's "lots of windows" symptom) is operational behavior, not visible in the repo.