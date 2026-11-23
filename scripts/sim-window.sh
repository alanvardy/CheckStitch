#!/bin/bash
# scripts/sim-window.sh — bring the device GUI to the front, once per process.
#
# simctl alone boots a device headlessly: a booted device has no window until a
# GUI attaches to it. Xcode 27 removed Simulator.app in favour of Device Hub
# (`com.apple.dt.Devices`), which shows every booted device in one window;
# older Xcode keeps Simulator.app and its `--args -CurrentDeviceUDID` launch
# arg. Opening the GUI once is enough — Device Hub lists all booted simulators,
# so repeated calls no-op after the first attempt. A visible window is the point
# of a manual run, so a failure here is reported but never fatal — callers must
# not tally it as a failed step.
#
# Sourced by the two scripts that boot a simulator for a human to look at
# (run-simulator.sh for `make run`, run-devices.sh for the simulator legs). The
# Device Hub handling is ported from SingleThread/scripts/run-devices.sh so the
# two runners cannot drift again.

# Set by the first show_sim_window call; default-safe under `set -u`.
_SIM_WINDOW_SHOWN=""

# show_sim_window <udid>
# The udid is only used by the older-Xcode Simulator.app fallback.
show_sim_window() {
    local udid="${1:?usage: show_sim_window <udid>}"
    if [[ -n "${_SIM_WINDOW_SHOWN:-}" ]]; then
        return 0
    fi
    _SIM_WINDOW_SHOWN=1
    if open -b com.apple.dt.Devices 2>/dev/null; then
        return 0
    fi
    if open -a Simulator --args -CurrentDeviceUDID "$udid" 2>/dev/null; then
        return 0
    fi
    echo "  (note: could not open a device window — the simulators are booted and installed; open Device Hub or Simulator manually to see them)" >&2
}
