# Task

Stop iOS Simulator windows from popping up on the macOS desktop when the developer runs
the CheckStitch test gates (`make build` + `make test`, where `make test-ui` and
`make run` boot the iOS Simulator). Find and verify a headless/background boot mechanism
supported by the installed Xcode, confirm it composes with both the xcodebuild-managed
simulator lifecycle (build + UI smoke) and the simctl-managed lifecycle in
`run-simulator.sh`, and apply it to the gate path — while deciding and getting sign-off on
whether `make run` (the "look at the device" dev flow) stays windowed.