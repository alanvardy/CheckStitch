# Research Questions

## Context

CheckStitch is a Swift/SwiftUI iOS app structured as a thin `CheckStitch` app
target (views + platform delegates), a local sources-only SPM package
`CheckStitchCore` (models, store-adjacent logic, EventKit seam, checklist
creator, sync codec), and a macOS-hosted Swift Testing suite plus a single
XCTest UI smoke. Unit-test coverage and testability are spread across these
layers. The test infrastructure (Makefile targets, `scripts/test.sh`,
fixtures) and the seams used to isolate side effects are the aspects of the
codebase in scope.

## Questions

1. What side-effect seams and abstractions exist in the code for EventKit /
   Reminders and StoreKit, what protocols and default implementations define
   them, how do the concrete adapters (`EventKitReminderDestination`,
   `StoreKitPurchaseService`) conform, and how are these seams exercised by
   the existing unit suite?

2. How does the non-Core app-side logic layer (concrete `@Observable` stores
   and supporting types such as `ChecklistStore`, `BackgroundImageStore`, the
   sync service/merge/import classes, and the view models) work and how is it
   tested? Are there protocols between the app target and the store types, or
   are they concrete classes taken directly as dependencies?

3. Which source files across `CheckStitchCore` and `CheckStitch` are
   currently exercised by the unit-test suite, and which are not covered at
   all? Map each source file to the test file(s) that cover it and identify
   sources with no corresponding unit tests.

4. How are the thick app-side views and their supporting logic structured?
   Specifically, how much logic lives inside SwiftUI view bodies versus
   extracted view models, and what does the existing view-testing approach
   (SwiftUI render tests vs behaviour tests on view models) look like?

5. What are the test-convention and test-infrastructure specifics: the shared
   fixtures (`TestFixtures.swift`, `StubBundle.swift`, localization
   fixtures), the use of `@MainActor` and platform gating across suites, how
   tests are declared/run (Makefile `test-unit`, `scripts/test.sh`,
   `scripts/tests/run.sh`), and the Swift Testing style rules that a new
   suite is expected to follow (`@Test`, `#expect`, behaviour-named
   functions, `@Test(arguments:)`)?
