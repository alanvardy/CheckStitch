# Task

Get CheckStitch building and distributable as a beta via Apple's App Store
Connect / TestFlight pipeline (Linear VAR-993, "Get a build working on
testflight": "We need to get the project building on app store connect").
This means establishing the release path that produces an iOS build of
CheckStitch and makes it installable through TestFlight — most likely a CI
workflow and/or upload scripts plus whatever signing/config changes that
requires. The repo has no CI (no `.github/`), no TestFlight or App Store
Connect references, and only local dev targets (simulator, macOS, watchOS),
so the entire release/integration surface is new, including deciding build
flavor, signing profile, upload mechanism, and credential ownership. The
existing `make build`/gate (`scripts/test.sh`) and signing conventions must
keep working.
