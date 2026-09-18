# Research Questions

## Context

The repository is a Swift/SwiftUI project with iOS, macOS, and watchOS targets
plus two test targets, whose shared build gate lives in `scripts/test.sh` and
drives five xcodebuild legs defined in the `Makefile`. Focus exploration on
the gate's structure and output handling, the exact Swift constructs in app
sources and test suites that produce compiler warnings, and toolchain-
generated warning noise that appears across build legs.

## Questions

1. [codebase-analyzer] How does `scripts/test.sh` drive the build and test
   legs — what does each step invoke and how are failures detected (set -e,
   explicit checks, exit codes)? Where does the gate script itself emit text
   containing the string "warning" (as opposed to compiler warnings from
   xcodebuild), and how is xcodebuild output currently captured or not
   captured anywhere in the gate?

2. [codebase-analyzer] Which exact lines in `CheckStitch/ContentView.swift`
   and `CheckStitch/ChecklistStore.swift` produce the two compiler warning
   kinds reported by the build legs — "trailing closure in this context is
   confusable with the body of the statement" and "result of call to
   refresh() is unused"? Trace each construct: where refresh()/refreshable is
   called with its result discarded, and which trailing closures have empty
   bodies or ambiguous formatting.

3. [codebase-analyzer] Which exact lines in `CheckStitchTests/`
   (ChecklistStoreTests.swift, WatchChecklistStoreTests.swift,
   ChecklistImportSessionTests.swift) produce the compiler warnings
   "redundant #require(_:_:)" and "unused immutable-value initialization"?
   How is the Swift Testing framework's #require used (try #require binding
   patterns, macro-produced annotations), and which bound values are never
   referenced afterwards? Note which suites are Swift Testing vs XCTest and
   what they import.

4. [codebase-pattern-finder] Across the remaining build legs and config —
   the CheckStitchUITests target, the CheckStitchWatch target, and any CI
   workflow files under `.github/` — what exists? Find: the "AppIntents
   metadata extraction skipped, no AppIntents.framework dependency found"
   warning text and which build legs produce it; any existing patterns of
   capturing or redirecting xcodebuild output to log files in scripts, the
   Makefile, or CI; and any compiler-warning-related flags or settings in
   project.pbxproj, CheckStitchCore/Package.swift, or CI config.

5. [codebase-locator] What does the shell-level test harness
   `scripts/tests/run.sh` cover and how does it work — which scripts and
   behaviors it stubs and asserts, how it invokes `scripts/test.sh`, and how
   it is wired into the gate? Also inventory the committed shared test scheme
   and how deterministic test execution is achieved, plus any other files in
   the repo that emit or match the literal string "warning".