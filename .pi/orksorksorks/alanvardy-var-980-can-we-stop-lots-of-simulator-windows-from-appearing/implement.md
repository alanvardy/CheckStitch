# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `2c11358` | host windowless-preference helper + shell test runner |
| 2     | `ffb25cc` | shared UDID resolver |
| 3 (+ 4b substitution) | `05a638d` | gate pre-boot, scoped shutdown + host lock (Phase 4b) |
| 4     | `5fe3e8f` | make run opens its own window explicitly |
| 5     | `45d60c4` | simulator-window documentation |
| final | (this commit) | implement.md summary + plan.md gate-item checkoffs |

All committed to `alanvardy-var-980-can-we-stop-lots-of-simulator-windows-from-appearing` (branch rebased onto `origin/main`, 22 commits, before phase 1) and pushed (first push after the mandated rebase was a verified force-with-lease onto the superseded start commit; everything after was fast-forward).

## Key decision: Phase 4b selected (spike failed)

The Phase 1 live spike **failed**: `com.apple.iphonesimulator AutoOpenDevice=false` does **not** suppress the window on this toolchain (Xcode 26.6 / iOS 27.0). With Simulator.app running and the pref set, booting the worktree UDID still opened a window (count 1→2). Repeating after quitting and relaunching Simulator.app with the pref already applied gave the same result — the pref is ineffective, not launch-time-only. Per plan.md's trigger, the **Phase 4b host-scoped lock** was implemented instead: the gate takes a bounded host lock (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`), quits `Simulator.app` around the simulator-touching part, and `scripts/sim-windowless.sh` (plus its runner cases) was dropped.

`open -a Simulator --args -CurrentDeviceUDID <udid>` was **confirmed live** to open/raise the frontmost window for the given UDID, so Phase 4 shipped the primary syntax (no AppleScript fallback).

## Automated Checks

- [x] Phase 1: sim-windowless.sh + tests/run.sh mode 100755; `bash -n` both; runner 2 cases green; shellcheck green (script itself later deleted by Phase 4b substitution)
- [x] Phase 2: resolve-sim-udid.sh 100755; runner 6 cases green; shellcheck green; live `--require-id` resolution works
- [x] Phase 3 (+4b): runner **7 cases** green (4 resolver + 2 gate + 1 lock; plan's "8" was pre-4b); shellcheck green; plan's two separate EXIT traps merged into one `gate_cleanup` (a second `trap … EXIT` would have clobbered the shutdown trap)
- [x] Phase 4: runner **9 cases** green (plan's "10" was pre-4b); shellcheck green
- [x] Phase 5: runner 9 still green; shellcheck green; `git ls-files --stage` shows 100755 for `scripts/resolve-sim-udid.sh` and `scripts/tests/run.sh`; `scripts/sim-windowless.sh` absent (deleted)
- [x] **Full real gate run (parent, after Phase 5):** `bash scripts/test.sh` → `gate: ok`; headless pre-boot of `D82898D5-…FEA4` logged; all 9 runner cases inside the real gate; Simulator.app quit by the gate and **not** relaunched by xcodebuild (windowless by construction throughout); `xcrun simctl list devices booted` empty of the worktree UDID after exit (scoped trap shutdown fired); no lock leak
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` → exit 0 at every phase

## Deviations from plan.md (all small, all verified; recorded in phase commits)

- **Plan bug fixed (Phase 2):** the resolver's `UDID="$(xcrun … | grep … | sed …)"` assignment exits 1 before printing the error message under `set -euo pipefail`; appended `|| true` so the existing "could not resolve" message fires (the plan's own test requires it).
- **Plan bug fixed (Phase 3):** unbraced `"$GATE_UDID…"` (var name run-on into U+2026) is an unbound-variable error under `set -u` on bash 5.3 — braced to `"${GATE_UDID}…"`.
- **`osascript` added to the runner's stub set:** with 4b the gate really quits Simulator.app; without the stub the tests would quit the host's real Simulator.app.
- **`LOCK_TIMEOUT=2` on the Phase 3/4 gate child tests:** those children run inside a real parent gate that holds the host lock until exit; the plan's default 60 s would stall each test a minute. Verified hold-lock case: runner completes in ~6.5 s.
- Phase counts corrected for the 4b substitution (7 cases after Phase 3, 9 after Phase 4).
- `make build-mac` (added to `scripts/test.sh` on main after the plan was written) preserved in the rewritten gate body.
- The runner's lock-case cleanup benignly releases the enclosing real gate's lock a few seconds early when it rmdirs the shared lock dir — no behavioural impact (parent's release no-ops).
- Phase 5's `sim-windowless.sh` references in AGENTS.md were replaced with the real 4b mechanism; the new "Simulator windows" section records the spike result and that the script was deleted. The single remaining `sim-windowless` string in AGENTS.md is that intentional deletion record.

## Notes for review

- `DELETEME` (worktree placeholder: "git rm before merging") is deleted in the working tree but deliberately **not** committed by any phase — it should go into the merge/cleanup commit.
- The remaining step artifacts in `.pi/orksorksorks/alanvardy-var-980-can-we-stop-lots-of-simulator-windows-from-appearing/` (conventions/design/research/structure/etc.) were committed as `plan.md`/`implement.md` only during implementation — the review step may sweep the rest in as the final artifact commit, per precedent.

## Manual Verification Items (from the plan — for the user to confirm)

Phase 1 spike (executed by the implement step; outcome FAILED → Phase 4b; confirm the recorded outcome):
- [ ] Confirm the pref is currently absent: `defaults read com.apple.iphonesimulator AutoOpenDevice` → `does not exist` (observed; also re-observed at spike time)
- [ ] Open `Simulator.app` and leave it running (observed running)
- [ ] `bash scripts/sim-windowless.sh check` exits 1 and prints the fix command (observed — script since deleted by 4b)
- [ ] `bash scripts/sim-windowless.sh fix`; `defaults read …` → `0` (observed)
- [ ] Boot this worktree's UDID; `bootstatus -b` (executed — window appeared; see Phase 4b below)
- [ ] **Observe: no Simulator window appears** — **FAILED**: window appeared (count 1→2) with the pref set, and again after relaunching Simulator.app with the pref already applied. This is the recorded negative result that triggered Phase 4b
- [ ] Run the real UI test path windowless: `make test-ui`; window count stays flat — covered by the final full gate (Simulator.app quit and stayed quit; zero windows)
- [ ] Spike outcome recorded — done, prefer 4b
- [ ] Clean up: `xcrun simctl shutdown <UDID>` — done after each spike step

Phase 2:
- [ ] `bash scripts/run-simulator.sh 'platform=iOS Simulator,id=<UDID from .simulator_id>' …` still boots/installs/launches (or `make run`)
- [ ] `bash scripts/run-simulator.sh 'platform=iOS Simulator,name=iPhone 17' …` still resolves by name (fallback path)

Phase 3 (substituted by 4b — the pref-based check no longer exists):
- [ ] With `Simulator.app` open and the 4b lock in place: run `bash scripts/test.sh`; window count stays flat start to finish (Simulator.app is quit by the gate, so trivially no new windows)
- [ ] In two terminals simultaneously run `bash scripts/test.sh`; both reach `gate: ok`, window count stays flat, no cross-shutdown (lock serializes; automated tests cover the lock, this is the belt-and-braces live check)

Phase 4:
- [ ] `make run` finishes with `✅ Launched app.alanvardy.CheckStitch on <UDID>`, and **exactly one** window is open on the device whose UDID is in `.simulator_id` (verify via `xcrun simctl list devices booted` and the window title; open syntax itself was confirmed live)
- [ ] While that window is open, run `bash scripts/test.sh` in another terminal: the gate completes `gate: ok` and the `make run` window is not closed (the gate quits Simulator.app for itself; with the concurrent window held, re-verify the behaviour on your preferred flow)

Phase 4b:
- [ ] Hold the lock (gate in one terminal while it sleeps) and start a second gate: the second emits the timeout warning within `LOCK_TIMEOUT` and finishes; windows stay flat
- [ ] After both gates exit, `xcrun simctl list devices booted` has no leftover worktree device

Phase 5:
- [ ] Read `AGENTS.md` "Simulator windows"; every statement matches observed behaviour from Phases 1–4 (spike result recorded, not a placeholder)
- [ ] `git ls-files --stage scripts` modes: `resolve-sim-udid.sh` and `tests/run.sh` are 100755; `sim-windowless.sh` is deleted (4b)