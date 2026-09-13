# Done

- **Branch / head SHA**: `alanvardy-var-986-add-localizations` @ `28157b8`
  (rebased onto `origin/main` @ `922b9a6`; pushed with `--force-with-lease`)
- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok` after the review
  fixes (sim build + boot, `make test`, `make build-mac`, `make watch-build`,
  16 shell tests, `shellcheck`); `make test-unit` → 101 tests / 20 suites
  passed. `git diff --check main...HEAD` clean; working tree clean.
- **Review outcome**: one fresh-context `reviewer` pass over the source diff,
  the three `.xcstrings` catalogs, the new test files and the 12
  `InfoPlist.strings` files returned **no blockers**.
  - Verified before the fixes: every runtime lookup key resolves (`.main` vs
    `.module` routing correct per target); interpolation-derived keys match
    (`%lld%%`, `Photo by %@ on Unsplash`, `Another checklist already uses %@ …`);
    `%@` / `%1$@` placeholders preserved in all six languages; App 31/31,
    Core 3/3, Watch 5/5 required keys present with all six non-empty
    translations; canary exclusions correct; no force unwraps / `try!` / `as!`.
  - Fixes applied (user chose option `[2]`):
    1. **Watch canary** — `LocalizationFixtures.swift` `guardedCatalogs` now
       includes `"Watch"` (no exclusions needed; all five Watch translations
       differ from English), so an English regression there is caught.
    2. **Host-locale coupling** — `AppearanceModeTests.swift` now resolves the
       expected title against `Bundle.core` with `String`'s default-locale
       semantics (mirroring `SharedStrings`) instead of pinning `en`, so the
       test is independent of the macOS test host's locale.
    3. **Design drift** — `design.md` corrected to record that the watch
       `.lproj` files carry only `CFBundleDisplayName` (the watch never touches
       EventKit).
    4. **Trailing newlines** — normalized on `SharedStrings.swift`, the three
       new test files and all 12 `InfoPlist.strings`
       (`WatchChecklistDetailView.swift` was already newline-less on `main` and
       was deliberately left untouched to avoid unrelated churn).
- **Remaining manual items** (device/simulator smoke from `implement.md` —
  generated-Info.plist precedence cannot be asserted from unit tests):
  - Set a simulator/device to `de` (`defaults write -g AppleLanguages -array de`
    + `AppleLocale de_DE`, then restart) and confirm translated UI copy
    (`Einstellungen`, `Hintergrund`, `Checkliste bearbeiten`, `Keine
    Checklisten`, `Hell`/`Dunkel`, Unsplash credit) and the German Reminders
    permission prompt.
  - Confirm the home-screen/watch app name still reads **CheckStitch**.
  - Spot-check `ja` / `zh-Hans`.
  - Optionally open each `.xcstrings` in Xcode and confirm six languages with no
    "needs translation" markers.
