# Done

- **What was built**: Verified that all production creation/decoding/intent/UI paths already default scaling to `.fixed(1)`. Added a regression test assertion in `CheckStitchTests/ChecklistStoreTests.swift` (line 82) to assert `created.scaling == .fixed(1)` on the creation path, guarding against future regressions to `.prompt(lastFixed: 1)`.
- **Commit SHA(s)**: `c380752f0392b46b0b9dd1c2c5a18dec272d862c`
- **Verification**: `make test-unit` passed 688 tests in 71 suites (23.2s).
- **Reviewer findings**: No blockers. Two P2 nits noted (optional follow-up): (1) broader coverage for the plain `create(name:)` overload and the decode path; (2) the existing test name `testCreateWithItemTitlesKeepsInputOrderAndTitleOnlyShape` now also asserts scaling mode, a minor naming drift.
- **Remaining manual items**: None. The two P2 nits are optional follow-up items.
