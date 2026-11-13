# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `0be9b52` | Walking skeleton — folded outer portrait, end to end |
| 2     | `8d1f910` | Folded outer landscape, end to end |
| 3     | `c342a22` | Inner display, both poses, end to end |
| 4     | `d8a75fb` | Hardening & documentation |

## Automated Checks
- [x] `make test-unit` passes (712 → 718 tests; new `DuoOuterPortraitTests`, orientation parse tests, forced-policy mapping)
- [x] `bash scripts/tests/run.sh` passes (51 passed, 0 failed; new Duo cases for folded outer portrait/landscape, book/open inner, unknown pose, missing runtime)
- [x] `bash -n` and `/bin/bash -n scripts/appstore-screenshots.sh` pass
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` clean
- [x] Five `iphone-duo-*` wallpaper JPEGs + manifest entries exist (≥5 `iphone-duo-` keys)
- [x] `--help` prints the entire header doc block (sed range updated to the last header line)
- [x] `grep -q 'iphone-duo'` present; default class still `CLASSES=(iphone-6.3)` (opt-in preserved)
- [x] Full gate `./scripts/test.sh` prints `gate: ok`

## Notes / Adaptations
- Phase 1 added `import CheckStitchCore` to `DuoOuterPortraitTests.swift` (plan's snippet omitted it; `ChecklistLayout.Context`/`.standard` live in Core).
- Phase 1 renamed shell locals in `shoot`/`preflight_size` to `display_args` to avoid a shellcheck collision with `duo_shoot_variant`'s `display`, and used `${1:-$DUO_PATTERN}` to clear SC2034.
- Phase 1's `appstore_duo_missing_runtime_warns_and_continues` gained an `rm -rf` of the stale folder so it proves *that* run creates nothing.
- The five `iphone-duo-*` wallpapers were fetched by replicating the script's fetch flow directly (running `--fetch-wallpapers` alone continues into the shared `iPhone 17` capture, which AGENTS.md forbids).
- Phase 4's subagent timed out at 30 min while waiting on the full gate; the parent confirmed the gate log ended in `gate: ok`, checked off the Phase 4 automated items, and committed the (already complete) Phase 4 files.

## Manual Verification Items (from the plan)
- [ ] `xcrun simctl list runtimes | grep iPhone19,4` reports the Duo runtime; Device Hub hinge pose is **folded**
- [ ] `bash scripts/appstore-screenshots.sh --no-build --no-install --duo-pose folded iphone-duo` reports every size accepted; `build/appstore-screenshots/en/iphone-duo-outer-portrait/1-main-dark.png` is 1398 × 2034 and shows the widened Duo card (16 pt inset, `maxContentWidth = min(340, w*0.8)`)
- [ ] Record the resolved Duo UDID — later phases reuse `resolve_udid`
- [ ] `--duo-pose folded` yields both `iphone-duo-outer-portrait` and `iphone-duo-outer-landscape` for every language
- [ ] `iphone-duo-outer-landscape/1-main-dark.png` is genuinely rotated: 2034 × 1398 (if still portrait, STOP and re-open design decision 4)
- [ ] Set pose to **book**; `--duo-pose book iphone-duo` → `iphone-duo-inner-portrait/` = 2007 × 2853, standard 32-inset layout
- [ ] Set pose to **open**; `--duo-pose open iphone-duo` → `iphone-duo-inner-landscape/` = 2853 × 2007 (if not, STOP and re-open design decision 4)
- [ ] Full three-invocation sweep across all six languages — all four variant folders present for every language and every size accepted
- [ ] Temporarily point the script at an inventory without the Duo runtime and confirm the warning prints and the script still exits 0, then restore
