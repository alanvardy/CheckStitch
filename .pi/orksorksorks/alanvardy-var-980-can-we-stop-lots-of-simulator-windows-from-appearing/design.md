# Design Discussion

## Current State

CheckStitch reaches the iOS Simulator through two disjoint lifecycles that share one
destination string:

- **xcodebuild-managed** (`Makefile:14-50`). `build` only selects the iphonesimulator
  platform; only `test-ui` phase 2 (`test-without-building`, `Makefile:45-50`) actually
  boots/runs a device. `test-unit` is macOS-hosted and never touches a simulator
  (`Makefile:26-35`). The gate is `scripts/test.sh:8-15` (`make build` → `make test`).
- **simctl-managed** (`scripts/run-simulator.sh:39-47`): `simctl boot` (errors swallowed)
  → `bootstatus -b` → `install` → `launch`, for `make run` (`Makefile:21-22`).

Destination is computed once in `Makefile:1-5` (explicit `SIM=` > worktree
`.simulator_id` > shared `name=iPhone 17`); each worktree has its **own dedicated
simulator UDID** (dotfiles `worktree_sim.fish:130-165`, reused if still registered), so
parallel agents never contend for a device. `run-simulator.sh:20-28` re-resolves the
destination to a UDID.

**Root cause (verified live on this host, Xcode 26.6/17F113).** Neither `simctl boot`
nor `xcodebuild test` opens a GUI — both are headless by default and there is **no
`--headless` flag to find** (`simctl help boot` has no graphics option; `simctl help ui`
covers device appearance only). Windows appear because a single, host-global
`Simulator.app` process was running (pid `10617`) and attaches a window to every device
booted while it is alive, from any worktree. Evidence at probe time: `Simulator.app`
running, `xcrun simctl list devices booted` = **0** — i.e. the windows are not leftover
booted devices; they are the running GUI attaching to each new boot. Worktree-per-sim
does not isolate this: one `Simulator.app` renders a window for *all* devices.

## Desired End State

1. Running the gate (`bash scripts/test.sh`) produces **no Simulator window**, even while
   `Simulator.app` remains open and other agents run gates concurrently.
2. `make run` still shows a window, explicitly, on **its own** worktree device.
3. No global destructive simulator operation is introduced: no `shutdown all`, no bare
   `booted`, no `name=` destination, no unguarded `killall Simulator`.
4. The guarantee is asserted, not silent: the gate detects a missing host precondition
   and reports it.
5. Verification: with `Simulator.app` open and multiple agents running gates, the window
   count stays flat; `make run` opens exactly one window for the calling worktree's UDID.

## Patterns to Follow

- **Headless pre-boot, then attach** — `SingleThread/scripts/test.sh:39-45`:
  `simctl boot "$udid" 2>/dev/null || true` then `simctl bootstatus "$udid" -b`; same
  shape already in `run-simulator.sh:40-41` and in sibling CI
  (`SingleThread/.github/workflows/ci.yml:39-43`). Reuse it, keyed to our own UDID.
- **Single destination computation point** — `Makefile:1-5`; re-resolve via
  `run-simulator.sh:20-28` (`,id=` direct, else `name=` lookup). Do not add a second
  resolver.
- **Per-worktree UDID discipline** — `Makefile:38-39`, `AGENTS.md:35-37`,
  `run-simulator.sh:9-11`, `addworktree.fish:22-24`.
- **Script style** — `#!/bin/bash`, `set -euo pipefail`, mode `100755`
  (`AGENTS.md:31-32`); `scripts/test.sh` prints `gate: ok`.
- **Test/verify commands** — `make test-unit` (fast) before `bash scripts/test.sh` (full
  gate); `shellcheck scripts/*.sh` is part of the gate (`scripts/test.sh:10-14`).

Patterns **not** to follow:

- `xcrun simctl shutdown all` / `xcrun simctl list devices booted` as a target selector —
  with N parallel agents this destroys N-1 other runs.
- Unguarded `killall Simulator` / `osascript quit` — host-global, races concurrent
  `make run` and other agents' gates.
- `singleThread/scripts/test-one.sh:38-42` background-`&`-watchdog: not applicable here;
  we are controlling GUI attachment, not timing out a build.

## Design Decisions

1. **Keep `Simulator.app` alive; suppress auto-open at the host level.** The window is an
   artefact of a shared GUI process attaching to booted devices. Setting a
   `com.apple.iphonesimulator` preference (candidate: `AutoOpenDevice -bool false`) is
   per-`Simulator.app`, hence applies to every worktree's device at once and requires no
   per-worktree plumbing. **This is unverified on Xcode 26.6 and is the first spike**
   (see Open Risks); implementation must confirm the effect on a real boot before
   building on it. Chosen over quitting `Simulator.app`, which is a racy host-global act
   under concurrent agents.
2. **Pre-boot our own UDID headlessly before `make test`.** In `scripts/test.sh`, after
   `make build` and before `make test`, resolve the destination to this worktree's UDID
   and run `simctl boot … || true` + `bootstatus -b`. This makes the boot independent of
   `Simulator.app` and follows `SingleThread/scripts/test.sh:39-45`. `make test-ui`'s
   `test-without-building` then attaches to the booted device. `make build` is untouched
   (it does not boot, `Makefile:14-18`).
3. **Trap-shutdown only this agent's UDID on gate exit.** `trap` a
   `simctl shutdown "$UDID"` at gate exit so booted sims do not accumulate across
   parallel agents. Scoped strictly to the resolved UDID, never `all`/`booted`.
4. **`make run` stays windowed and explicitly UDID-pinned.** Because auto-open is off,
   the window must be requested: `open -a Simulator` selecting this worktree's
   `-CurrentDeviceUDID` (candidate syntax; spike), then the existing
   `run-simulator.sh:43-47` install/launch. Plain `open -a Simulator` is insufficient —
   it can surface another worktree's selected device. The "look at the device" flow is
   preserved but becomes explicit.
5. **Gate asserts the host precondition, and it is documented.** `scripts/test.sh`
   checks the preference and prints a clear warning (with the exact fix command) when it
   is absent, rather than failing silently. The one-time host setup is recorded in this
   repo's `AGENTS.md` (and, if useful, a dotfiles setup function). The gate does not
   write shared user preferences on every run.
6. **Fallback if the preference spike fails (approved).** Take a short host-scoped
   `flock`, quit `Simulator.app`, run the gate, release. Best-effort and explicitly
   time-bounded so it degrades gracefully instead of serialising all agents. If even
   that is unsupported, re-scope rather than fake a guarantee.
7. **No new resolution logic.** Any UDID the new steps need comes from the existing
   `,id=` / `name=` handling (`run-simulator.sh:20-28`), factored only if duplication
   would otherwise occur.

## What We're NOT Doing

- Not touching `~/dev/dotfiles`' `worktree_sim.fish` creation/teardown pipeline or the
  `.simulator_id` convention — devices stay as they are.
- Not adding `simctl shutdown all`, `booted` targets, or unguarded `killall`.
- Not searching for an `xcodebuild` headless flag — none exists; the GUI attachment is
  the only lever.
- Not serialising agents behind a global lock as the primary design.
- Not changing destination precedence, the `name=iPhone 17` fallback, signing, or the
  macOS-hosted unit-test path.
- Not changing `make run`'s install/launch semantics beyond opening the window.
- Not removing windows that another agent's concurrent `make run` legitimately opened.

## Open Risks

- **`AutoOpenDevice` may not exist / may not work on Xcode 26.6.** Not present in the
  current plist. If a device boot with `Simulator.app` running still shows a window, fall
  back to Decision 6.
- **`open -a Simulator --args -CurrentDeviceUDID <udid>` syntax unverified**; may need
  an alternative selection mechanism.
- **`Simulator.app` rewrites its prefs on quit** and `cfprefsd` caches, so a preference
  set while it is running can be lost or ignored — the spike must test set/verify/reboot
  under a running GUI.
- **`xcodebuild test-without-building` may relaunch or attach the GUI** even after our
  pre-boot; the spike must observe an actual `make test-ui` run, not just a `simctl boot`.
- **Concurrent `make run`** will still add one window while another agent's gate runs —
  accepted; the gate only guarantees its own path is windowless.
- `.simulator_id` fallback: if it is missing, `SIM` degrades to the shared
  `name=iPhone 17` (`Makefile:5`); the pre-boot/shutdown steps must skip cleanly rather
  than pick a shared device.