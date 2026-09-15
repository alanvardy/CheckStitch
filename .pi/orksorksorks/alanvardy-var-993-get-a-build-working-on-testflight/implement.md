# Implementation Summary

## Status

Ticket VAR-993 ("Get a build working on testflight"). This ticket's layers are
external system state (Developer portal → App Store Connect record → Xcode
Cloud workflow → signed archive → TestFlight internal distribution), so Phases
0–2 are **manual owner work** (portal/ASC/Xcode-GUI/real-device) with evidence
recorded in `phase0-portal.md`, `phase1-archive.md`, `phase2-testflight.md`
(currently PENDING templates — observed cells `_pending_`). Phases 3–4 (the only
repository changes) are committed here.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 3     | `54c24b2` | docs: add TestFlight via Xcode Cloud runbook (`docs/TestFlight-xcode-cloud.md`, `DELETEME` removal, `.pi/` step artifacts) |
| 4     | `ef30161` | Phase 4: Hardening — failure modes and decision points, documented (when-it-breaks section) |
| 4     | (this file) | implementation summary record |
| 0–2 evidence | *pending* | `phase0-portal.md` / `phase1-archive.md` / `phase2-testflight.md` — filled by owner, then committed |

## Automated Checks

- [x] `bash scripts/test.sh` prints `gate: ok` — run after Phase 3 (`gate: ok`, 17 shell tests) and after Phase 4 (`gate: ok`, 17 shell tests); includes simulator build + tests, macOS build leg, watchOS build, shell tests, shellcheck
- [x] `git diff --stat de6ddd9..HEAD` touches no `Makefile` / `scripts/` / `project.pbxproj` / `*.entitlements` / `*.xcscheme` — docs- and artifact-only diff
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` clean (run as part of the gate; scripts unchanged)
- [x] `git status --porcelain` after the Phase 3 commit: only `docs/` and `.pi/…` additions (plus the removed `DELETEME`); working tree clean at end of Phase 4

## Manual Verification Items (from the plan)

Observed results are pending owner action for Phases 0–2; Phase 3–4 items below
marked accordingly.

### Phase 0 — Portal + ASC prerequisites (owner)
- [ ] App Store Connect shows the `CheckStitch` app record with bundle ID `app.alanvardy.CheckStitch`
- [ ] Developer portal App ID `app.alanvardy.CheckStitch` shows **App Groups** (with `group.app.alanvardy.CheckStitch`) and **iCloud → Key-value storage** both enabled
- [ ] `phase0-portal.md` written with the capability set and the enabling role

### Phase 1 — Walking skeleton (owner)
- [ ] Xcode Cloud reports the build **Succeeded**
- [ ] Build log shows the watch app embedded and contains no `ITMS-` or provisioning/entitlement error
- [ ] App Store Connect shows the build under version `1.0` (state may be *Processing* briefly, then processed; Apple's processing email arrives)
- [ ] `phase1-archive.md` written with the pinned image + observed status

### Phase 2 — TestFlight internal delivery (owner)
- [ ] App Store Connect shows the build in the `Internal` group in state **Ready to Test**
- [ ] Apple's processing email was received
- [ ] The build installs and launches from the TestFlight app on a real iPhone
- [ ] The checkStitch watch app installs alongside the phone app
- [ ] `phase2-testflight.md` written with the assigned build number and device

### Phase 3 — Repeatable release
- [ ] A second, independent workflow run started from the runbook alone reaches TestFlight (owner)
- [ ] A reader with no prior context can find the prerequisite capabilities, the workflow field table, and the version policy in the runbook (owner)

### Phase 4 — Hardening
- [ ] The "When it breaks" section is present before `## Non-goals` and covers capability drift, image retirement, quota, invalid train, and the local-archive non-answer
- [ ] `implement.md` names the accepted residual risk and the macOS follow-up scope

## Accepted Residual Risk

There is **no committed regression signal** for the Xcode Cloud workflow: if it
silently starts failing, `bash scripts/test.sh` cannot catch it — the failure
surfaces only when someone looks at Xcode Cloud (documented in the runbook's
"When it breaks" / "Residual risk (accepted)"). Accepted for this ticket.

## macOS Fast-Follow Scope (separate ticket, not filed)

- macOS App ID `app.vardy.CheckStitch`-equivalent capability state is
  **unverified** (the entitlements file is wired per-SDK, but the portal state
  has not been checked);
- macOS needs a **different always-increasing build-number policy** (separate
  from ASC `CI_BUILD_NUMBER`);
- `MACOSX_DEPLOYMENT_TARGET = 27.0` may exceed what Xcode Cloud's images ship
  (this machine's Xcode is a 27.0 beta host; cloud uploads from it can be
  rejected with `ITMS-90111`).