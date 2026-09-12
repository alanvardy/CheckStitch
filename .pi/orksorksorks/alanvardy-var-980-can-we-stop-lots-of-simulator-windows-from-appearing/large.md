# Task

Stop iOS Simulator windows from popping up on the desktop when the developer runs the
CheckStitch test gates (`bash scripts/test.sh`, i.e. `make build` + `make test`, where
`make test-ui` boots the iOS Simulator via `xcodebuild` and `make run` boots it via
`run-simulator.sh`). The work is to find the headless/background boot mechanism supported
by the installed Xcode, verify it composes with both the xcodebuild-managed simulator
lifecycle (build + UI smoke) and the simctl-managed lifecycle in `run-simulator.sh`, and
apply it to the gate path — while deciding, and getting sign-off on, whether `make run`
(the "look at the device" dev flow) stays windowed.

## Why LARGE
UNKNOWNS + DESIGN_SIGN-OFF (CONVENTION_RISK): the ticket is literally a question —
"Can we stop…" — and the headless mechanism (simctl headless flag/env var vs
xcodebuild-managed boot vs Simulator.app prefs) is unverified on this Xcode and needs a
spike; whether windows stay for the dev `make run` flow is a human trade-off; and any
change touches the shared build/gate convention (Makefile destinations, `scripts/test.sh`,
`scripts/run-simulator.sh`), which AGENTS.md already warns can wedge parallel agents.