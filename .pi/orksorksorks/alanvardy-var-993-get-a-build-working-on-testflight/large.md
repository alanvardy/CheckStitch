# Task

Get CheckStitch building and distributable as a beta via Apple's App Store
Connect / TestFlight pipeline. The ticket (VAR-993, "Get a build working on
testflight") says only: "We need to get the project building on app store
connect". This means creating the release path that produces an iOS build of
CheckStitch and makes it installable through TestFlight on App Store Connect —
most likely a CI workflow and/or upload scripts plus whatever signing/config
changes that requires. The repo has no CI (no `.github/`), no TestFlight or
App Store Connect references, and only local dev targets (simulator, macOS,
watchOS), so the whole release/integration surface has to be established from
scratch — including deciding whether Apple builds via a cloud step or the repo
uploads a prebuilt artifact, which build flavor (device/simulator) and signing
profile TestFlight accepts, and who owns the App Store Connect credentials.
The existing `make build`/gate (`scripts/test.sh`) and signing conventions must
keep working.

## Why LARGE

UNKNOWNS + NEW_SURFACE + CONVENTION_RISK. App Store Connect/TestFlight is a
brand-new integration with an underspecified one-line goal — unknown build
flavor, signing, auth/credentials, and upload mechanism — so the work needs
research and a spike; it also touches shared build/CI config (Makefile,
signing/entitlements, a new workflow) whose backward compatibility the gate
enforces.
