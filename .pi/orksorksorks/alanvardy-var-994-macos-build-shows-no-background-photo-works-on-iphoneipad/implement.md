# Implementation Summary

Ticket: macOS build shows no background photo (works on iPhone/iPad) — restore the photo on the signed macOS build by enabling outgoing network for the sandboxed macOS slice (`ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`).

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| —     | e59743a | chore: remove ticket scaffold placeholder |
| —     | 36241de | docs: add VAR-994 pipeline artifacts |
| 1     | 4f9268e | Phase 1: Diagnostic baseline — evidence, not inference |
| 2     | e31e6dc | Phase 2: Regression pin for the fixed condition |
| 3     | e002837 | Phase 3: Fix — allow outgoing network in the macOS sandbox |
| 4     | f619a1e | Phase 4: Regression gate and manual rendering proof |

Branch was rebased onto `origin/main` (7aacadf) before phase work; the remote was force-aligned with `--force-with-lease` once after Phase 1 (remote still pointed at the pre-rebase scaffold; lineage verified, no foreign commits). Phase 2–4 pushes were fast-forward.

## Automated Checks

- [x] Phase 1 — `codesign -d --entitlements - --xml …/CheckStitch.app | grep -c "com.apple.security.network.client"` prints `0` (pre-fix)
- [x] Phase 1 — `grep -c "ENABLE_APP_SANDBOX = YES;" project.pbxproj` prints `2`
- [x] Phase 1 — `grep -c "ENABLE_OUTGOING_NETWORK_CONNECTIONS" project.pbxproj` prints `0` (pre-fix)
- [x] Phase 2 — `bash scripts/tests/run.sh` red on the new pin: `FAIL: macos_slice_requests_outgoing_network` (16 passed, 1 failed; recorded)
- [x] Phase 2 — `shellcheck scripts/tests/run.sh` clean
- [x] Phase 2 — `make test-unit` green (127 tests / 24 suites)
- [x] Phase 3 — `bash scripts/tests/run.sh` → `ok: macos_slice_requests_outgoing_network` (17/17; pin flipped green)
- [x] Phase 3 — `make build-mac` succeeds
- [x] Phase 3 — `make watch-build` succeeds
- [x] Phase 3 — `make build-mac-signed` succeeds and signed entitlements now contain `<key>com.apple.security.network.client</key><true/>` (grep count 1; was 0 pre-fix)
- [x] Phase 3 — `make test-unit` green
- [x] Phase 4 — `bash scripts/test.sh` prints `gate: ok` (simulator build → pre-boot → unit + UI smoke → unsigned macOS leg → watchOS leg → shell tests 17/17 → shellcheck)
- [x] Phase 4 — no `CheckStitch/*.swift` changes across the ticket (`git diff origin/main..HEAD --stat -- 'CheckStitch/*.swift'` empty); delta is pbxproj (+2 lines) + run.sh pin (+18) + artifacts only

## Manual Verification Items (from the plan)

- [ ] Phase 1 — `make build-mac-signed`, then `open DerivedData/Build/Products/Debug/CheckStitch.app`: the main screen shows the flat `Color.systemBackground` fill and **no photo** (pre-fix visual); skipped as redundant if you already saw the reported bug.
- [ ] Phase 1 (decisive runtime diagnostic) — with `log stream --predicate 'subsystem == "app.alanvardy.CheckStitch"' --style compact --level debug` running, in the app open Settings (gear) and press **Refresh wallpaper**; expect `Background force refresh failed: …` in the stream (the pre-fix data path). **Stop and report** if that failure does *not* appear — the data path would then not be the cause.
- [ ] Phase 3 — signed launch + Settings → **Refresh wallpaper** with the same `log stream` predicate running: no `Background force refresh failed` line, and the photo appears.
- [ ] Phase 4 — `make build-mac-signed` + launch: photo renders behind the content, at default (50) and faded opacity, and stays correct across window resizes.
- [ ] Phase 4 — `make run` on the simulator, UI smoke green: iOS rendering unchanged (iOS received no code change at all).

## Notes / Observations

- **Pre-fix premise re-verified by the parent**: a fresh `make build-mac-signed` from the unfixed tree yields **no** `network.client` (grep 0), and `ENABLE_OUTGOING_NETWORK_CONNECTIONS=YES` (passed as CLI override) synthesizes the entitlement — so the plan's mechanism is confirmed end-to-end, not assumed.
- **Stale-binary anomaly**: at 10:42 PDT the shared `DerivedData/Build/Products/Debug/CheckStitch.app` binary briefly contained `network.client` (re-signed in place, 9 min after the 10:33 build, before the plan was finalized). This contradicted the plan's recorded evidence; a fresh plain build restored the documented no-entitlement state and the diagnosis record uses that. Worth knowing about, but not reproducible and no longer present.
- **Post-gate product dir**: the gate's trailing unsigned `make build-mac` leg overwrites `DerivedData/Build/Products/Debug/CheckStitch.app`; Phase 4 re-ran `make build-mac-signed` afterwards, so the signed app currently in the tree carries `network.client` and is ready for your manual run.
- The signed app also carries `com.apple.security.get-task-allow` (Debug artifact) — harmless, noted in diagnosis.md.
- Nothing else was refactored or "improved" outside the plan; no child tickets created.

## Phase 5 (conditional — not planned work)

Stays dormant. If after Phase 3's manual check the photo is still absent (or `Background force refresh failed` persists on the signed build), re-run the Phase 1 diagnostics; if the fetch succeeds but the photo still does not paint, escalate to `design` for a macOS-specific mechanism rather than guessing a view fix (`.navigation` is uncompilable on macOS; `.window` was measured to have no effect).