# Done

- **Branch / head SHA**: `alanvardy-var-1183-sentry-error-app-hang-fully-blocked` @ `357193d`
  (`test: pin the app-path in-app fallback and document the whole-event drop`).
  Feature commits: `aa2961e` (Phase 1), `722d55c` (Phase 2); review fixes `357193d`.
  Pushed to `origin` with `--force-with-lease` (no rebase conflicts — `main` was already
  an ancestor of HEAD; the pre-session "rebase" was a no-op reset, so all pushes were
  fast-forwards).
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` (simulator build → pre-boot →
  `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh` → shellcheck;
  54 shell tests, 0 failed). `make test-unit` green: **729 tests in 74 suites**
  (728 before the review fix + 1 new fallback test). Warnings-as-errors leg clean.
- **Review outcome**: one bounded `reviewer` pass found **no P0/P1 blockers**. Four P2
  notes were returned; the user chose option [2] (fixes worth doing now plus optional
  improvements), so all were addressed or resolved:
  - *Fixed* — the type doc (`SentryScrubber.swift:11-14`) only described breadcrumb
    dropping; it now documents that `scrub(_ event:)` returns `nil` for a matched
    system-stall app hang.
  - *Fixed* — the `|| image.contains(".app/")` fallback was untested (every `.app/`
    fixture also set `inApp: true`). Added `keepsEventWhenAppPathFrameLacksInAppFlag`
    (app-path frame inserted at index 7 with `inApp: false`); the test fails if the
    fallback is removed.
  - *Optional, applied* — `isSystemStall`'s doc now states `frames` is ordered
    outermost → innermost, matching sentry-cocoa's serialization.
  - *Optional, resolved* — the `guard mechanismType == "AppHang"` redundancy (also in
    `appHangStack`) is now explained by a comment rather than removed, preserving the
    self-contained predicate ported verbatim from the SingleThread VAR-1165 precedent.
- **Remaining manual items**: none. No production behaviour outside
  `SentryScrubber.scrub(_ event:)` changed, and Sentry intake is not observable from CI —
  the captured-stack fixture in `SentryScrubberTests` is the evidence. The `SentryBootstrap`
  `beforeSend`/`beforeBreadcrumb` wiring (`SentryBootstrap.swift:38-39`) makes the drop
  path reachable in production.
