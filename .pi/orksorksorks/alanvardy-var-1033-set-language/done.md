# Done

- **Branch / head SHA**: `alanvardy-var-1033-set-language` @ `e444a7a`
  (`git status` clean, pushed to `origin`; rebase left no conflicts to
  resolve). Committed the two regenerated artifacts `design.md` /
  `structure.md` (`e444a7a`) so the branch is fully pushed.
- **Mechanical checks**: `bash scripts/test.sh` printed `gate: ok` — `make build`
  (simulator) → headless simulator pre-boot → `make test` → `make build-mac` →
  `make watch-build` → `scripts/tests/run.sh` (17 passed, 0 failed) →
  `shellcheck`. No lint or test warnings flagged as blockers.
- **Review outcome**: one fresh-context `reviewer` over the full `main...HEAD`
  diff (Swift diff + both catalogs + fixtures). **No blockers (P0).**
  - Reviewer confirmed correct: `@MainActor`/`@Observable` model, the
    `resolved(in:)` seam, observation chain for the live `\.locale` flip,
    catalog/fixture coverage, watch unknown-value rejection + persistence,
    `transferUserInfo` channel ownership, and no new force-unwraps/retain
    cycles.
  - **P1 (deferred to user)**: the phone never pushes the language at pick
    time. `pushLanguage()` fires only from `ChecklistSyncCoordinator.start()`,
    `onActivated`, and `.requestChecklists` — and the coordinator is created
    once per phone process, the watch's `requestChecklists` fires once per
    watch process. A change made while both sessions are already active can
    therefore sit on the phone until a process restart, which contradicts the
    Phase 3 manual step "raise/foreground the watch: its UI is Japanese" (the
    plan documented a lag but assumed a re-push that does not actually occur).
    Suggested minimal fix: expose `pushLanguage()`/`languageDidChange()` and
    call it from `.onChange(of: AppLocaleState.current.language)` on the iOS
    root in `MyApp.swift`.
  - **P2 nits (not applied)**: `storedEffectiveLocale` reads `UserDefaults`
    instead of routing through the holder; the empty-string `LocalizedStringResource`
    in `DueDateLabel`; no `ChecklistSyncDiagnostics` record for `.language`
    send/receive; `FakeChecklistSyncTransport.clearSentMessages()` clears only
    `sentMessages`; missing trailing newlines in the new files (repo-wide
    inconsistency, so deferred); no end-to-end cold-launch watch pin; the
    pre-existing app/Core `AppearanceMode` twin remains a drift risk.
  - No fixes were applied — the invocation was not `autofix` and no blockers
    were found.
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
