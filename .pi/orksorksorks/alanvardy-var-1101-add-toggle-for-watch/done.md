# Done

- **Branch / head SHA**: `alanvardy-var-1101-add-toggle-for-watch` @ `95254be`
  (pre-review head `7db2bae`; rebase against `origin/main` had no conflicts,
  tree was clean and already pushed).
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` (`GATE_EXIT=0`),
  run twice — once on the reviewed head and once after the applied fix. The
  gate covers `make build` (simulator), headless pre-boot of this worktree's
  simulator, `make test`, `make build-mac`, `make watch-build`,
  `scripts/tests/run.sh` (warnings-as-errors pinned per leg) and
  `shellcheck`. No warnings flagged.
- **Review outcome**:
  - One bounded `reviewer` (fresh context) reviewed the full source diff plus
    the cited files; parent did an independent narrow scan. **No blockers.**
    Verified sound: default-`true` decode only on an absent key and a decoded
    `false` survives the self-heal + round trip; winner-only
    `showsOnWatch` copy in `ChecklistMerge`; no-op-on-unchanged store setter
    with no spurious revision bump; `visibleFolders`/`visibleLooseChecklists`/
    `visibleChecklists` semantics for unknown/tombstoned folder ids and empty
    folders; both new localization keys present in all 6 languages and in
    `LocalizationFixtures.requiredKeys`.
  - **Fixes applied**: `WatchChecklistListView.swift` empty-state gate changed
    from `viewModel.checklists.isEmpty` to `viewModel.visibleFolders.isEmpty &&
    viewModel.looseChecklists.isEmpty`, so hiding every checklist shows the
    `ContentUnavailableView` instead of a blank `List`. Committed as
    `95254be` and pushed (`--force-with-lease`).
  - **Optional improvements**: none suggested beyond the above.
- **Remaining manual items** (required — static evidence cannot close this
  sync/hide ticket, per `AGENTS.md`): the paired-Apple-Watch pass from
  `plan.md` is **not** done.
  - [ ] `make run`: open a checklist's detail screen — "Show on watch" appears
        in its own section, default **on**, with the footer text; toggling it
        off and re-entering the screen keeps it off; toggling back on flips it.
  - [ ] `bash scripts/run-watch.sh`: with the watch app open, toggle
        "Show on watch" **off** for a loose checklist — the row disappears from
        the watch main list; toggle back **on** — the row returns.
  - [ ] Put two hidden checklists in one folder — the folder row disappears
        from the watch root; re-enabling one member brings the folder back.
  - [ ] Leave an empty folder — its row stays on the watch root.
  - [ ] With every checklist hidden, the watch root shows "No checklists /
        Open CheckStitch on your iPhone." (the applied fix).
  - What the user should see on the watch: only checklists whose iPhone
    "Show on watch" toggle is on; a folder whose members are all hidden
    vanishes, an empty folder stays; iOS lists are unchanged.
