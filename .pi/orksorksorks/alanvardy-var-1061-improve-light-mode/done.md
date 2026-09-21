# Done

- **What was built**: Threaded the main-screen card border color through a new `CardPlate.border(for colorScheme:)` per-scheme decision — black in light mode, blue (reproducing the prior `.tint` accent) in dark mode — and swapped all 5 `.stroke(.tint, lineWidth: 2)` border sites in `CheckStitch/ContentView.swift` (createButton, settingsButton, edit ring, checklistList plate, emptyState plate) to `.stroke(CardPlate.border(for: colorScheme), lineWidth: 2)`. Added two headless CardPlate assertions.
- **Commit SHA(s)**: `72d4f0e` (`Make main-screen card borders black in light mode`)
- **Verification**: `make test-unit` → **TEST SUCCEEDED**, 390 tests / 50 suites passed (includes new `borderIsBlackInLightMode` / `borderIsBlueInDarkMode`). Full gate `bash scripts/test.sh` not run this session (targeted verify per small-workflow bounds; render/icon changes pending manual confirmation).
- **Reviewer findings**: No blockers, no nits. Merge verdict OK.
- **Remaining manual items**: Run `bash scripts/test.sh` full gate, and visually confirm the light-mode borders are black (and dark mode unchanged/legible) on a real device/simulator, since rendered paint can't be asserted headlessly.