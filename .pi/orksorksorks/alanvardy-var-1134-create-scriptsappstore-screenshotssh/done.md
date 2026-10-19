# Done

- **Branch / head SHA**: `alanvardy-var-1134-create-scriptsappstore-screenshotssh` @ `5aa346c` (rebased on `origin/main`, pushed)
- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok` (simulator build, macOS build, watchOS build, unit + UI tests, 39 shell tests, shellcheck). The appstore screenshot capture itself is intentionally outside the gate.
- **Review outcome**: one `reviewer` pass, then fixes applied.
  - **B1 fixed (blocker)**: watch captures were not language-pinned (`watch_shot` never passed `--ui-testing-app-language`), so all six `<lang>/watch-46mm/` folders were identical. Both watch shots now pass the language, and the watch shell case asserts every language id.
  - **F1 fixed**: `--terminate-running-process` was after the bundle id (delivered to the app as argv, ignored by simctl); moved before `<device> <bundle>` and the ordered-argv shell assertions updated.
  - **F2 fixed**: watch-leg language assertion added.
  - **N2 fixed**: `AGENTS.md` / `Makefile` corrected — `make test-ui` runs the whole `CheckStitchUITests` class, not one case.
  - **Optional nits applied**: manifests record clean device names (not the resolution regex); unknown class/language now exits 2 (with shell tests; language validation also prevents a `--lang` path-traversal `rm -rf`); per-class capture dirs are replaced instead of wiping all of `build/appstore-screenshots`; `ChecklistSync` extra blank line, missing final newlines and Unsplash licensing notes fixed.
  - **Declined**: `ContentView.seams` stays `var` — changing it to `let` removed the memberwise initializer that `MyApp` and the unit tests use.
  - Reviewer confirmed normal (non-UI-testing) launch behaviour is unchanged, seeds/version match `ChecklistCodec.currentVersion`, wallpaper staging matches `BackgroundImageStore`, and UDIDs are always resolved before `simctl`.
- **Remaining manual items**:
  - Run `make appstore-screenshots` (or `bash scripts/appstore-screenshots.sh`) on real simulator classes and inspect the produced PNGs — especially that `watch-46mm` screens now differ per language and iPhone 17 / iPad Pro 13-inch (M5) are installed on this machine.
  - Confirm the final screenshot dimensions accepted by App Store Connect for the ticket (script pre/post-flight checks 1206×2622, 2064×2752, 416×496).
  - Confirm Unsplash usage/attribution is acceptable for the committed wallpapers (credits in `scripts/fixtures/appstore-wallpapers/manifest.json`).
