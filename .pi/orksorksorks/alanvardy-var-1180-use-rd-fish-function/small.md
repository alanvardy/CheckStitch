# Task

Make CheckStitch's `scripts/run-devices.sh` compatible with the `rd` fish function already used by SingleThread. The dotfiles `rd` function is:

```fish
function rd --wraps=./scripts/run-devices.sh --description 'alias rd=IOS_TARGET=duo ./scripts/run-devices.sh'
    env IOS_TARGET=duo ./scripts/run-devices.sh $argv
end
```

It hardcodes `IOS_TARGET=duo`, but CheckStitch's script currently rejects anything except `sim` or `device`:

```bash
if [[ "$IOS_TARGET" != "sim" && "$IOS_TARGET" != "device" ]]; then
    echo "❌ IOS_TARGET must be 'sim' or 'device' (got '$IOS_TARGET')." >&2
    exit 1
fi
```

Add a `duo` target that mirrors SingleThread's `scripts/run-devices.sh` behaviour: when `IOS_TARGET=duo`, deploy only to the physical iPhone Duo, default `RUN_WATCH=0` and `RUN_MAC=0` (explicit `RUN_WATCH=1`/`RUN_MAC=1` still opts back in), and skip the simulator legs. Update the script's header comment and add/adjust the shell test cases in `scripts/tests/run.sh` so the new target is covered. If `AGENTS.md` documents the `run-devices.sh` targets, mention `duo` there too.

## Why SMALL

Single script change plus its local shell-test file: one module, follows the existing SingleThread pattern, no schema/migration, no new subsystem, no design decision, and tests are local to the script.

## Key files (if the recon found any)

- `scripts/run-devices.sh` — the script to extend (`IOS_TARGET` validation at ~line 88, mode branches throughout; `DUO_DEVICE_ID` already exists).
- `scripts/tests/run.sh` — shell tests for `run-devices.sh`; add a `run_devices_duo_targets_only_the_duo_physically` case.
- `AGENTS.md` — may need a one-line note about `IOS_TARGET=duo`.
- Reference: `/Users/vardy/dev/SingleThread/scripts/run-devices.sh` (duo handling at lines 73–80, 179, 220, 280–285, 338, 529–552).
