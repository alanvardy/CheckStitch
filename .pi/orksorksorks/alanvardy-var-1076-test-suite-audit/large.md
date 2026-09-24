# Task

Audit the CheckStitch codebase to improve unit testability and expand valuable unit test coverage. Using parallel subagents, survey the code across `CheckStitchCore`, `CheckStitch`, and the test targets, identify seams that block unit testing (refactoring the code to be "as unit testable as possible"), and write additional high-value unit tests that follow the existing Swift Testing conventions (`@Test`, `#expect`, `@MainActor`, behaviour-named functions, `TestFixtures.swift` fakes). Fall in the test gate with `./scripts/test.sh`, and act as an active partner to the user — surface genuine issues (architecture, testability, coverage gaps, code smells) as they are found rather than silently fixing them.

## Why LARGE

Matched triggers: UNKNOWNS, MULTI_MODULE, BROAD_TEST_SURFACE. The task is an open-ended exploratory audit with no spec'd end-state: the scope of issues/refactors/coverage gaps is unknown up front and is itself the deliverable's research, it touches every module and target in the repo (more than five files, multiple subsystems plus the whole test surface), and the refactor-for-testability decisions are design choices that need human sign-off along the way.