# Task

Add a warnings check to the shared build gate so `scripts/test.sh` fails on
compiler warnings, then eliminate every existing compiler warning across all
build legs (iOS simulator app build, macOS slice, watchOS target, unit-test
and UI-test targets), scoping out known toolchain noise (the AppIntents
metadata warning that appears in three of four legs). The change spans the
gate script, the Makefile xcodebuild legs, the app sources, and the test
suites.