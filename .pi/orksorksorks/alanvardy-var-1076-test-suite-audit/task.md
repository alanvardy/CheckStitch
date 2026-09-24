# Task

Audit the CheckStitch codebase to improve unit testability and expand valuable
unit test coverage. Survey the code across `CheckStitchCore`, `CheckStitch`,
and the test targets, identify seams that block unit testing (refactoring the
code to be "as unit testable as possible"), and write additional high-value
unit tests that follow the existing Swift Testing conventions (`@Test`,
`#expect`, `@MainActor`, behaviour-named functions, `TestFixtures.swift`
fakes). Fall in the test gate with `./scripts/test.sh`, and surface genuine
issues (architecture, testability, coverage gaps, code smells) as they are
found rather than silently fixing them.
