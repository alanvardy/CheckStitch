# Done

- **What was built**: Widened the settings-screen "Done" toolbar button on iPhone/iPad by replacing the `.checkStitchButton()` modifier with `.fixedSize()` in `CheckStitch/SettingsView.swift`, mirroring the existing iOS 26 fix in `ChecklistDetailView.swift` so the system glass bar container doesn't collapse to a circle that clips the title.
- **Commit SHA(s)**: `763481e` (Widen settings Done button with fixedSize)
- **Verification**: `make test-unit` green — 62 tests in 16 suites pass, including `ViewRenderTests.settingsViewListsAllAppearanceModes`; `** TEST SUCCEEDED **`.
- **Reviewer findings**: No blockers. No nits. Merge verdict OK — the change is a faithful, minimal mirror of the in-repo precedent and correctly drops the borderless modifier from the bar item.
- **Remaining manual items**: Visual confirmation on a simulator/device that the rendered button now fits "Done" comfortably (purely a layout change; no test infrastructure exists for this visual tweak).
