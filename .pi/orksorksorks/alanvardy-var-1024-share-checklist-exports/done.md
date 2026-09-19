# Done

- **Branch / head SHA**: `alanvardy-var-1024-share-checklist-exports` @
  `5c4875c` (`review: scope Share button to iOS, add EOF newlines`); prior tip
  `1e25cac` (`chore: record step artifacts and drop DELETEME placeholder`),
  pushed with `--force-with-lease`.
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` (iOS build, macOS
  build, watch build, unit tests 373/49 suites, 24 shell tests, shellcheck,
  warnings-as-errors). Passed on `1e25cac` (pre-fix) and again on `5c4875c`
  (post-fix). No gate warnings flagged. No rebase conflicts existed.
- **Review outcome**:
  - **Blocker B1 fixed** — the "Share…" button in
    `CheckStitch/ExportChecklistsView.swift` was un-gated, so the macOS export
    sheet showed a button that silently dismissed the sheet (the only
    presenter, the root `.sheet(isPresented: isSharing)`, is `#if os(iOS)`).
    Now wrapped in `#if os(iOS)`, restoring the design requirement that the
    macOS slice is unchanged (`design.md` Q2=B).
  - **F1 applied** — trailing newline added to `CheckStitch/ChecklistShare.swift`
    and `CheckStitchTests/ChecklistShareTests.swift`.
  - **O1 applied** — stale "see the deviation note below" pointer in
    `ChecklistImportExportViewModelTests.swift` now says "in plan.md".
  - **O2 not applied (declined)** — a share-specific error surface would
    contradict `design.md` decision 7; the share path intentionally reuses
    the "Couldn't export" alert and its throw branch is unreachable.
  - **Declined nits** — the "unused `context` param" nit was rejected:
    `makeUIViewController(context:)` / `updateUIViewController(_:context:)`
    must keep the `context` external label for the
    `UIViewControllerRepresentable` requirement.
- **Remaining manual items**: none from `plan.md` were verified in this
  environment; all Phase 1 and Phase 2 manual verification items remain for
  the user (sync/render tickets cannot close on static evidence, `AGENTS.md`):
  - `make run` → Settings → Export: sheet shows **Export** and **Share…**,
    both disabled with nothing selected.
  - Select a checklist → **Share…** → system share sheet appears (not while
    the export sheet is still on screen), attachment named
    `CheckStitch-<today>.json`.
  - Share to Messages, Mail and Save to Files; import the saved file back and
    confirm the round-trip.
  - iPad simulator: **Share…** opens without the popover trap.
  - **Export** still opens the save panel and writes the same file (no
    regression).

## Review round 2 — post-review feedback

- **Head SHA**: `8245bc7` (`ui: outline the export sheet's actions and unblock
  row taps`); prior tip `a221e0e`.
- **Requested (styling)**: the export sheet's "Export" and "Share…" drew as two
  bare words side by side. They now render as outlined plates — the app's
  existing treatment (`CardPlate.cornerRadius` + a 2pt tint stroke over
  `CardPlate.iconPlateFill`) — with 16pt between them. The plate sits inside the
  button's label, so the whole outline is tappable.
- **Found while verifying that render (not requested)**: the multi-select rows
  could not be tapped over most of their width. The row label is an `HStack`
  ending in `Spacer()`, and a `.buttonStyle(.plain)` button hit-tests only its
  drawn subviews, so taps on the row's right side did nothing — including the
  element centre XCUITest targets. `exportSelection` therefore stayed empty and
  Export/Share stayed permanently disabled. Fixed with
  `.contentShape(Rectangle())` on the row label; the checkmark now fills and
  both action buttons enable.
- **Verification**: driven on this worktree's simulator (iOS 26, `.simulator_id`
  UDID) with a throwaway UI test — screenshots before the fix
  (`canExport=false count=0` after a row tap) and after
  (`canExport=true count=1`, checkmark filled, both plates enabled). The probe
  and its debug counters were removed before the commit; nothing temporary
  remains. `./scripts/test.sh` → `gate: ok`.
- **Gap — no automated regression test for the hit-testing fix**: hit regions
  are not reachable from the macOS-hosted unit suites, and `ImageRenderer`
  cannot draw a `Button` with a composed label (it substitutes an unsupported
  placeholder), so the only real regression test is a UI case — tap
  `exportSelectionRow`, assert `confirmExportButton` enables. That needs
  `make test-ui` to run more than the single pinned smoke case. Raised with the
  user rather than applied unilaterally.
- **Still open from round 1**: CheckStitch does not appear as a destination in
  the iOS share sheet. That is a Share Extension (a new app-extension target, an
  activation rule for `UTType.json`, plus an App Group handoff into the app),
  not a settings change. Awaiting the user's decision.