# Done

- **Branch / reviewed SHA**: `alanvardy-var-903-add-an-about-modal` @ `9663678a9d6d5135cb9600320e4eda72678d3a7a` (reviewed revision; post-review test-hardening and marker commits follow on the same branch — see `git log`). Pushed via `--force-with-lease`; PR #33, draft, merge state CLEAN.
- **Mechanical checks**: `make test-unit` — 135 tests / 26 suites passed. Full gate `./scripts/test.sh` — `gate: ok` (simulator build → `make test` incl. UI smoke → `make build-mac` → `make watch-build` → 16 shell tests → shellcheck). No warnings flagged.
- **Rebase conflicts**: none — the rebase had already completed cleanly; working tree clean, only the untracked `medium.md` artifact remained (now committed).
- **Review outcome**: reviewer (single bounded pass, Swift angles) found **no blockers**. The localization machinery (positional `%1$@`/`%2$@` formats, `extractionState: manual`, canary exclusions, `Bundle.module` vs the tests' `Bundle.core` pointing at the same embedded `CheckStitchCore_CheckStitchCore.bundle`), the `Sendable`/`@unchecked Sendable` handling in `AppInfo`/`StubBundle`, and the NavigationLink/Section structure all verified correct.
- **Fixes applied** (optional improvements, per user selection):
  1. `CheckStitchTests/LocalizationTests.swift` — `coreCatalogValuesAreEmbeddedInTheResourceBundle` now also asserts the compiled `de.lproj` table carries `"Version %@ (%@)"` and `"Version %@"` against the source catalog, closing the compiled-bundle gap for the new Version keys.
  2. `CheckStitchTests/AppInfoTests.swift` — replaced the tautological `String.en(...)` assertions and the `marketingVersion!`/`buildNumber!` force unwraps with concrete English output (`"Version 1.0 (1)"` / `"Version 1.0"`), so a fixture regression fails instead of crashing and the assertion no longer relies on fallback text.
  3. `CheckStitchTests/AppInfoTests.swift` — corrected the doc comment to state the assertions use concrete output and that catalog embedding is covered by `LocalizationTests`.
- **Remaining manual items** (from `plan.md` / `implement.md`, still unverified):
  1. `make run` → Settings (gear) → confirm the **About** row (`info.circle`) under Background, pushing a Form with display name, "Copyright 2026 Alan Vardy", developer credit, "Version x (y)", and an `alan@vardy.cc` mailto link.
  2. Switch simulator/app language to German and confirm the About row/screen render German (no raw keys).
  3. `make build-mac-signed` → confirm the About screen fills and top-aligns on macOS rather than vertically centring.
