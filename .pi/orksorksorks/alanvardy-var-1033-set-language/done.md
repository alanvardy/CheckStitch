# Done

- **Branch / head SHA**: `alanvardy-var-1033-set-language` (rebased onto
  `main`; no conflicts to resolve). Code head after the review fixes:
  `e444a7a` → review fixes committed on top. `git status` clean, all commits
  pushed to `origin`.
- **Mechanical checks**: `bash scripts/test.sh` printed `gate: ok` both before
  and after the review fixes — `make build` (simulator) → headless simulator
  pre-boot → `make test` → `make build-mac` → `make watch-build` →
  `scripts/tests/run.sh` (17 passed, 0 failed) → `shellcheck`. `make test-unit`
  after the fixes: 321 tests / 41 suites passed. No lint or test warnings
  flagged as blockers.
- **Review outcome**: one fresh-context `reviewer` over the full `main...HEAD`
  diff (Swift diff + both catalogs + fixtures). **No blockers (P0).**
  - Reviewer confirmed correct: `@MainActor`/`@Observable` model, the
    `resolved(in:)` seam, observation chain for the live `\.locale` flip,
    catalog/fixture coverage, watch unknown-value rejection + persistence,
    `transferUserInfo` channel ownership, and no new force-unwraps/retain
    cycles.
  - **P1 (fixed, user-approved)**: the phone never pushed the language at pick
    time. `pushLanguage()` only fired from `ChecklistSyncCoordinator.start()`,
    `onActivated`, and `.requestChecklists` — and the coordinator is created once
    per phone process, the watch's `requestChecklists` fires once per watch
    process. A change made while both sessions were already active could
    therefore sit on the phone until a process restart, which contradicted the
    Phase 3 manual step "raise/foreground the watch: its UI is Japanese" (the
    plan documented a lag but assumed a re-push that never occurred). Applied
    fix: `ChecklistSyncCoordinator.languageDidChange()` (public) invoked from
    `.onChange(of: AppLocaleState.current.language)` on the iOS root in
    `MyApp.swift`, with a new `ChecklistSyncCoordinatorTests
    .languageChangePushesImmediately` covering it.
  - **P2 nits: partially applied, rest declined.** Applied: `pushLanguage()` now
    logs a `[phoneSend]` record (accepted/dropped) so a dropped delivery is
    observable; `clearSentMessages()` gained a comment documenting that it
    clears only `sentMessages`, not `sentContexts`. Declined/deferred:
    `storedEffectiveLocale` reading `UserDefaults` directly (cannot route
    through the `@MainActor` holder from a nonisolated context); the
    empty-string `LocalizedStringResource` in `DueDateLabel` (works and is
    pinned); the `.language` receive log (already emitted by
    `WatchSyncAdapter`'s `.watchReceive`); missing trailing newlines in new
    files (the repo already has many such files, so not a real convention);
    the cold-launch pin (blocked by the `.current` singleton); the pre-existing
    app/Core `AppearanceMode` twin (out of scope).
- **Remaining manual items** (all device/simulator-bound, from `plan.md` and
  `implement.md`; none are automated):
  - Live flip on this worktree's simulator (`D6D3CD6F-F7EF-4265-8E93-389ED04891EB`):
    select Deutsch and confirm the Settings sheet, checklist list, detail row,
    item editor and priority rows re-render without relaunch; record the
    `xcrun simctl io` screenshot digests in `verify-language.md`.
  - Force-quit/relaunch persistence, and `.system` restoring the device language.
  - Paired-watch pass (`bash scripts/run-watch.sh`): the watch follows the
    phone's language — **this is the P1 gap above; verify whether it updates on
    a plain foreground or only after a process restart**.
  - macOS runtime leg (`make build-mac-signed` manual run); `make build-mac` is
    the only macOS evidence the gate provides.
