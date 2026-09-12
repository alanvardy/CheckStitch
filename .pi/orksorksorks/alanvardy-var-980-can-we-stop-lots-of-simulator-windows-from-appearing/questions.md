# Research Questions

## Context

The CheckStitch repo builds, tests, and runs an iOS app against the iOS Simulator
through two distinct boot lifecycles: an xcodebuild-managed one (`make build`,
`make test-ui` via `build-for-testing`/`test-without-building`) and a simctl-managed
one (`scripts/run-simulator.sh` using `xcrun simctl boot/install/launch`). Simulator
destination selection is shared between them (`SIM` env var, worktree `.simulator_id`,
Makefile fallback default), and per-worktree simulators are created by dotfiles fish
functions. Research focuses on the Makefile/scripts gate orchestration, the two boot
lifecycles, the simulator destination conventions, and the dotfiles simulator creation
pipeline.

## Questions

1. How does the xcodebuild-managed simulator lifecycle work in the gate path — what do
   the `Makefile` `build` and `test-ui` targets do step by step (destination resolution,
   `build-for-testing`, `test-without-building`), which `xcodebuild` invocations cause a
   simulator to be selected/booted, and what destination-related options exist?
   (codebase-analyzer)

2. How does the simctl-managed lifecycle in `scripts/run-simulator.sh` work — the exact
   boot sequence and arguments (`simctl boot`, `bootstatus`, `install`, `launch`,
   `--terminate-running-process`), destination-to-UDID resolution, error handling, and
   what boot-related options the installed `xcrun simctl` tool exposes (read `xcrun
   simctl --help` / `xcrun simctl boot --help` if cheaply available, and record
   `xcodebuild -version` output)? (codebase-analyzer)

3. What are the simulator destination conventions — where `SIM`, the worktree
   `.simulator_id` file, and the shared default fallback are read and computed
   (`Makefile`, `scripts/run-simulator.sh`, dotfiles), and what documented constraints
   exist about bare `name=` destinations and parallel agents? (codebase-locator)

4. How does the per-worktree simulator creation pipeline in `~/dev/dotfiles` work —
   what `fish/functions/worktree_sim.fish` does on create/delete (arguments passed to
   `xcrun simctl create`, the `.simulator-device` override, `info/exclude` wiring), how
   it is wired into `takeoff.fish` and `addworktree.fish`, and whether any boot options
   or headless flags are set anywhere in that pipeline? (codebase-pattern-finder)

5. What in-repo and sibling-repo evidence exists about simulator boot behavior — grep
   the repo (scripts, Makefile, `.pi`, README, `project.pbxproj` iphonesimulator SDK
   settings) for simulator/boot/headless/Simulator.app references, and check how the
   sibling repo `/Users/vardy/dev/SingleThread` invokes simulators in its build/test
   scripts, including any headless or background handling there?
   (codebase-pattern-finder)