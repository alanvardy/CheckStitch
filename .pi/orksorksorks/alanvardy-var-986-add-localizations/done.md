# Done

- **Branch / head SHA**: `alanvardy-var-986-add-localizations` @ `c1fee72`
  (rebased onto `origin/main` @ `922b9a6`; pushed with `--force-with-lease`)
- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok` (sim build + boot,
  `make test`, `make build-mac`, `make watch-build`, 16 shell tests,
  `shellcheck`). `git diff --check main...HEAD` clean; working tree clean.
- **Review outcome**: one fresh-context `reviewer` pass over the source diff,
  the three `.xcstrings` catalogs, the new test files and the 12
  `InfoPlist.strings` files returned **no blockers**.
  - Verified: every runtime lookup key resolves (`.main` vs `.module` routing
    correct per target); interpolation-derived keys match (`%lld%%`,
    `Photo by %@ on Unsplash`, `Another checklist already uses %@ …`);
    `%@` / `%1$@` placeholders preserved in all six languages; App 31/31,
    Core 3/3, Watch 5/5 required keys present with all six non-empty
    translations; canary exclusions correct; no force unwraps / `try!` / `as!`.
  - Nits raised (not applied — no `autofix` in the invocation):
    1. `guardedCatalogs` omits `Watch` (`LocalizationFixtures.swift:6`) — canary
       gap; all five Watch translations genuinely differ, so no exclusion
       needed. **Worth doing now.**
    2. Host-locale coupling in `AppearanceModeTests.swift:26` — `mode.title`
       (unpinned) compared to `String.en(...)`; fails loudly on a non-English
       test host. Optional.
    3. `design.md` still says the watch `.lproj` carries
       `NSRemindersFullAccessUsageDescription` (implementation deliberately
       ships only `CFBundleDisplayName`). Doc-only drift, optional.
    4. `SharedStrings.swift` and the 12 `InfoPlist.strings` files lack a
       trailing newline. Cosmetic, optional.
  - `git diff --check` does not flag item 4; no source change required for a
    green gate.
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
