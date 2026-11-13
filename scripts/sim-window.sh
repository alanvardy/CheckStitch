#!/bin/bash
# scripts/sim-window.sh — bring a booted simulator's window to the front.
#
# simctl alone boots a device headlessly: a booted device has no window until a
# GUI attaches to it. Xcode 27 removed Simulator.app in favour of Device Hub
# (`com.apple.dt.Devices`), which focuses a booted device via its
# `devices://device/open?id=` deep link; older Xcode keeps Simulator.app and its
# `--args -CurrentDeviceUDID` launch arg. A visible window is the point of a
# manual run, so a failure here is reported but never fatal — callers must not
# tally it as a failed step.
#
# Sourced by the two scripts that boot a simulator for a human to look at
# (run-simulator.sh for `make run`, run-devices.sh for the simulator legs). The
# Device Hub handling is ported from SingleThread/scripts/run-devices.sh so the
# two runners cannot drift again.

# show_sim_window <udid>
show_sim_window() {
    local udid="${1:?usage: show_sim_window <udid>}"
    if open -b com.apple.dt.Devices 2>/dev/null; then
        open "devices://device/open?id=$udid" 2>/dev/null || true
        return 0
    fi
    if open -a Simulator --args -CurrentDeviceUDID "$udid" 2>/dev/null; then
        return 0
    fi
    echo "  (note: could not open a device window for $udid — it is booted and installed; open Device Hub or Simulator manually to see it)" >&2
}
