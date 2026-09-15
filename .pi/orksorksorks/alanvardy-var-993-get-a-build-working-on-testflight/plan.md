# Implementation Plan

## Overview

Enable Xcode Cloud for `app.alanvardy.CheckStitch` with one workflow (manual
start, Xcode 26+ image pinned, Archive action for iOS with App Store Connect
deployment preparation, TestFlight Internal Testing post-action), so a build
reaches TestFlight and installs on a real device. The only repository change is
`docs/TestFlight-xcode-cloud.md` (plus committed `.pi/` phase artifacts and the
`DELETEME` placeholder removal); `Makefile`, `scripts/*`, the schemes,
`project.pbxproj` and `CheckStitch/AppGroup.entitlements` are untouched, and
`bash scripts/test.sh` keeps printing `gate: ok`.

**Why there is no code phase**: this ticket's layers are external system state
(portal → ASC record → workflow → signed archive → processing → TestFlight), so
almost every phase produces GUI/ASC evidence rather than a diff. Phase 0 is the
one deliberately horizontal phase (external registration — nothing can go green
before it exists); Phases 1–2 are vertical tracer slices through Apple's
systems, and Phase 3 is the only phase that touches a repo file.

**Evidence convention for Phases 0–2** (no test target exists for any of it):
each phase writes `.pi/orksorksorks/alanvardy-var-993-get-a-build-working-on-testflight/phase<N>-<slug>.md`
with a table of `check | expected | observed | how verified`. Optional
screenshots go in `…/evidence/` as PNG. Phase 0 **contract record** (App ID
capability set + ASC app record existence + the Xcode Cloud image chosen) is
part of that file, so drift is detectable later.

**Pre-existing worktree note**: the tracked placeholder `DELETEME` is already
deleted in this worktree ("git rm before merging" per its own content). Phase 3
commits that deletion with the docs — it is expected, not drift.

---

## Phase 0: Portal + ASC prerequisites (horizontal — cannot be vertical)

No repository files. This phase registers the external state every later phase
assumes, so the first Archive fails for one reason at a time.

### Changes

#### 1. Confirm/create the App Store Connect app record
**Where**: App Store Connect → Apps → **+** → New App
**Details**:
- Platform: **iOS**; Name: `CheckStitch` (globally unique in ASC — if taken,
  pick a display variant and record it in the phase artifact);
  Primary Language: English (U.S.).
- Bundle ID: `app.alanvardy.CheckStitch` — **must be selectable in the dropdown**.
  If it is absent, the App ID does not exist in the portal yet; create it under
  Identifiers first (step 2), then return here.
- SKU: `CHECKSTITCH`; User Access: Full Access.
- Record the resulting App ID (the 10-digit `Apple ID` shown in the app's
  App Information page) in the phase artifact.

#### 2. Verify App ID capabilities (Developer portal)
**Where**: developer.apple.com/account → Certificates, Identifiers & Profiles →
Identifiers
**Details**:
- Under **App Groups**: `group.app.alanvardy.CheckStitch` must exist.
- Under **App IDs** → `app.alanvardy.CheckStitch` → **Capabilities**, both must
  be **enabled**:
  - **App Groups**, with `group.app.alanvardy.CheckStitch` checked;
  - **iCloud**, with **Key-value storage (KVS)** checked.
- This is exactly the set declared in `CheckStitch/AppGroup.entitlements`:
  ```xml
  <key>com.apple.security.application-groups</key>
  <array><string>group.app.alanvardy.CheckStitch</string></array>
  <key>com.apple.developer.ubiquity-kvstore-identifier</key>
  <string>$(TeamIdentifierPrefix)app.alanvardy.CheckStitch</string>
  ```
  The portal set may be a superset; it must not be a subset. Xcode Cloud
  **cannot** repair a mismatch — the first Archive fails if a capability is
  missing here. This is the most likely first failure.
- Under **App IDs**, confirm `app.alanvardy.CheckStitch.watchkitapp` exists
  (the embedded watch slice needs its own App ID). No capabilities required on
  it (the watch target has no entitlements file).

#### 3. Confirm the enabling account role
**Where**: App Store Connect → Users and Access → the account that will press
"Get Started with Xcode Cloud"
**Details**: role must be **Account Holder** or **Admin** (Xcode Cloud
enablement is one-time and role-gated); **App Manager is not sufficient** for
the initial enablement. If the signed-in account is Developer-only, stop and
report — Phase 1 cannot proceed.

#### 4. Inspect the version train
**Where**: App Store Connect → CheckStitch → TestFlight (and App Store → iOS App
versions)
**Details**: if any `1.0` train already exists and is closed/expired/removed,
record that the first action of Phase 1 is bumping `MARKETING_VERSION` to `1.1`
in `project.pbxproj` **— note**: that would be a build-config change, which this
ticket forbids. In that case stop and report (design Open Risk 7) before
touching anything; the expected state is *no* train yet, since nothing has ever
been uploaded.

#### 5. Write the phase artifact with the contract record
**File**: `.pi/orksorksorks/alanvardy-var-993-get-a-build-working-on-testflight/phase0-portal.md`
**Action**: create
```markdown
# Phase 0 — Portal + ASC prerequisites

| Check | Expected | Observed | Verified by |
|---|---|---|---|
| ASC app record | exists, bundle id app.alanvardy.CheckStitch | … | ASC → App Information, Apple ID … |
| App Group capability | enabled, group.app.alanvardy.CheckStitch assigned | … | portal screenshot / date |
| iCloud KVS capability | enabled with Key-value storage | … | portal screenshot / date |
| watch App ID | app.alanvardy.CheckStitch.watchkitapp exists | … | portal |
| Enabling role | Account Holder or Admin | … | ASC → Users and Access |
| 1.0 train | absent (or bump required — escalate) | … | ASC → TestFlight |
```

### Verification
#### Automated
- [ ] `bash scripts/test.sh` prints `gate: ok`
- [ ] `git status --porcelain` shows no tracked source modification (only the
      pre-existing ` D DELETEME` and untracked `.pi/…` may appear)

#### Manual
- [ ] App Store Connect shows the `CheckStitch` app record with bundle ID
      `app.alanvardy.CheckStitch`
- [ ] Developer portal App ID `app.alanvardy.CheckStitch` shows **App Groups**
      (with `group.app.alanvardy.CheckStitch`) and **iCloud → Key-value storage**
      both enabled
- [ ] `phase0-portal.md` written with the capability set and the enabling role

---

## Phase 1: Walking skeleton — a signed CheckStitch archive reaches App Store Connect

No repository files. Enable Xcode Cloud, create one workflow with a manual start
condition and an Archive action, run it, and see a **Succeeded** build in App
Store Connect. This exercises the thinnest real path and front-loads the
riskiest unknowns (entitlements, builder image, watch slice signing).

### Changes

#### 1. Enable Xcode Cloud and grant repository access
**Where**: Xcode (any recent instance with the `CheckStitch.xcodeproj` open) →
the **Cloud** tab in the Project navigator → **Get Started with Xcode Cloud**
**Details**:
- Sign in with team `6NWX2DHB9Q` (Xcode → Settings → Accounts must already have
  it).
- The setup wizard grants Xcode Cloud access to the GitHub repository. The
  GitHub account used must be an **admin** on `alanvardy/CheckStitch`, otherwise
  the repository cannot be selected — stop and report if so.
- Repository: `https://github.com/alanvardy/CheckStitch.git`; branch to watch:
  `main`.
- If the wizard offers to create the app record and step 0.1 has not been done,
  accept it and then correct the fields (name/bundle id/SKU) in App Store
  Connect.
- The wizard creates a **Default Workflow** — do not delete it before editing;
  open it and rewrite it (step 2). Do **not** install the Xcode Cloud GitHub App
  for any other repository.

#### 2. Configure the single workflow
**Where**: Xcode → Cloud tab → the workflow → **Edit Workflow** (or App Store
Connect → Xcode Cloud → Workflows)
**Details** — set exactly these fields; nothing else:

| Field | Value |
|---|---|
| Name | `TestFlight – iOS` |
| Environment → Xcode Version | newest **non-beta Xcode 26.x** available in the dropdown (e.g. `Xcode 26.6`) — never "Latest"/default, never an Xcode 27 beta. The 28 April 2026 upload rule requires the iOS 26 SDK. |
| Environment → macOS Version | newest available paired with that Xcode |
| Start Conditions | **Manual** only (delete branch/tag/PR/schedule conditions) |
| Actions | delete the default **Test** action; add exactly one **Archive** action |
| Archive → Platform | **iOS** |
| Archive → Scheme | `CheckStitch` (consumed as-is; the shared scheme's `ArchiveAction` is already Release) |
| Archive → Configuration | **Release** |
| Archive → Deployment Preparation | **App Store Connect** |
| Post-Actions | **none** in this phase |

- Save the workflow. Record the exact Xcode/macOS image strings in the phase
  artifact — that is the pinned-environment contract.
- No `ci_scripts/` directory, no `ci_post_clone.sh`, no `.github/`, no
  `project.pbxproj` / entitlement / scheme / Makefile edit. The local
  `CheckStitchCore` package is a file-system reference, so there is no
  dependency-fetch step.

#### 3. Run the workflow manually and read the log
**Where**: Xcode → Cloud tab → workflow → **Start Build**, or App Store Connect
→ Xcode Cloud → workflow → Start Build; choose branch `main`
**Details**:
- Wait for terminal state. Read the build log for these specific signals:
  - `Embed Watch Content` (or the watch app appearing under the archive's
    `Watch/` products) — the `CheckStitchWatch` slice was embedded.
  - **no** `ITMS-` lines, no `Provisioning profile … doesn't include` lines, no
    `com.apple.security.application-groups` / `ubiquity-kvstore-identifier`
    entitlement errors.
- On failure, capture the exact error text into the phase artifact and stop:
  - entitlement/capability error → fix in the developer portal only (Phase 0
    step 2), never in `project.pbxproj` or the entitlements file;
  - signing error naming the watch bundle id → confirm
    `app.alanvardy.CheckStitch.watchkitapp` exists as an App ID;
  - Xcode image/deployment-target error → re-pin the image (do not edit
    deployment targets).

#### 4. Write the phase artifact
**File**: `.pi/orksorksorks/alanvardy-var-993-get-a-build-working-on-testflight/phase1-archive.md`
**Action**: create — record `check | expected | observed` for: workflow exists
with Manual start; pinned image strings; Archive action config; build status;
watch embedded evidence (log line); absence of `ITMS-`/provisioning errors; the
build appearing in ASC under version `1.0`; the name of the test action that was
deleted.

### Verification
#### Automated
- [ ] `bash scripts/test.sh` prints `gate: ok`
- [ ] `git diff --stat de6ddd9..HEAD` touches no
      `Makefile` / `scripts/` / `project.pbxproj` / `*.entitlements` / `*.xcscheme`

#### Manual
- [ ] Xcode Cloud reports the build **Succeeded**
- [ ] Build log shows the watch app embedded and contains no `ITMS-` or
      provisioning/entitlement error
- [ ] App Store Connect shows the build under version `1.0` (state may be
      *Processing* briefly, then processed; Apple's processing email arrives)
- [ ] `phase1-archive.md` written with the pinned image + observed status

---

## Phase 2: TestFlight internal delivery — an internal tester installs it

No repository files. Add the TestFlight post-action to the Phase 1 workflow,
assign an internal group, and install the build from the TestFlight app on a
real device. This is the ticket's deliverable.

### Changes

#### 1. Create the internal tester group
**Where**: App Store Connect → CheckStitch → TestFlight → Internal Testing
**Details**:
- Add group `Internal` (or use the auto-created one).
- Add testers by Apple ID email (≤100). Each internal tester must be a user in
  App Store Connect (Users and Access) with a role; record who was added in the
  phase artifact.
- No Beta App Review is required for internal testers (design decision 8).

#### 2. Add the post-action to the existing workflow
**Where**: Xcode → Cloud tab → `TestFlight – iOS` workflow → Edit Workflow →
Archive action → **Post-Actions** → add **TestFlight Internal Testing**
**Details**:
- Target group: `Internal`.
- Supply the "What to Test" text (e.g. "First internal beta of CheckStitch.
  Create a checklist, add items, run it, and confirm reminders are created in
  the CheckStitch Reminders list.").
- Leave the Start Condition as **Manual** (design decision 8 / Open Risk 8:
  keep compute usage narrow).
- No other change — only the post-action is added to *this* workflow.

#### 3. Run again and clear the first-build gates in App Store Connect
**Where**: start the workflow manually (branch `main`), then App Store Connect
**Details**:
- Watch the build transition `Processing` → **Ready to Test**; the group shows
  the build assigned.
- **Export compliance (first upload only)**: because `GENERATE_INFOPLIST_FILE = YES`
  and no `ITSAppUsesNonExemptEncryption` key is set, ASC blocks the build until
  the encryption question is answered — App Store Connect → CheckStitch →
  the build → **Manage Compliance** / Export Compliance → "Your app does not use
  encryption" (CheckStitch uses no cryptography). Answer it; do **not** add the
  Info.plist key in the repo (design forbids infoplist/project changes).
- Accept the tester invitation email and install via the TestFlight app.

#### 4. Write the phase artifact
**File**: `.pi/orksorksorks/alanvardy-var-993-get-a-build-working-on-testflight/phase2-testflight.md`
**Action**: create — record `check | expected | observed` for: workflow
post-action config; internal group name + tester IDs; build number shown
(`CI_BUILD_NUMBER`, e.g. `1` alongside marketing version `1.0`); build state
`Ready to Test`; processing email received; export-compliance answered; device +
iOS version used; TestFlight install + launch result; watch app installed
alongside.

### Verification
#### Automated
- [ ] `bash scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] App Store Connect shows the build in the `Internal` group in state
      **Ready to Test**
- [ ] Apple's processing email was received
- [ ] The build installs and launches from the TestFlight app on a real iPhone
- [ ] The checkStitch watch app installs alongside the phone app
- [ ] `phase2-testflight.md` written with the assigned build number and device

---

## Phase 3: Repeatable release — the process survives without tribal knowledge

The only repository change this ticket ships: a runbook recording the Phase 0
prerequisites and the Phase 1–2 click-path, plus the version policy.

### Changes

#### 1. Create the runbook
**File**: `docs/TestFlight-xcode-cloud.md`
**Action**: create (the `docs/` directory does not exist yet — create it)
**Content**: full draft below. Copy it verbatim; implementers should adjust only
observed UI labels (e.g. if the dropdown is labelled "Xcode Version" vs
"Xcode"), never the facts.

````markdown
# TestFlight via Xcode Cloud

How a CheckStitch build reaches TestFlight, and how to do it again. There is no
CI config in this repository: Xcode Cloud builds, signs and submits; App Store
Connect distributes. The only local surface this touches is the shared
`CheckStitch` scheme, which is consumed unchanged.

## Prerequisites (one-time)

1. **App Store Connect app record.** Apps → CheckStitch, bundle ID
   `app.alanvardy.CheckStitch`. If the bundle ID is not selectable when creating
   the app, the App ID does not exist in the Developer portal yet.
2. **Portal capabilities** (developer.apple.com → Certificates, Identifiers &
   Profiles → Identifiers → App IDs → `app.alanvardy.CheckStitch`):
   - **App Groups** enabled, with `group.app.alanvardy.CheckStitch` assigned;
   - **iCloud** enabled with **Key-value storage**.

   These must match `CheckStitch/AppGroup.entitlements` exactly. **Xcode Cloud
   cannot repair a capability mismatch** — the first Archive fails with a
   provisioning/entitlement error. Fix it in the portal, never in
   `project.pbxproj` or the entitlements file.
3. **Watch App ID.** `app.alanvardy.CheckStitch.watchkitapp` must exist (the
   watch app is embedded in the iOS archive). It needs no capabilities.
4. **Enabling account role.** Account Holder or Admin. Xcode Cloud enablement
   is one-time and role-gated; a Developer-only role cannot complete setup.
5. **Repository access.** The GitHub account granting Xcode Cloud access must be
   an admin on `alanvardy/CheckStitch`.

## Version policy

- **Humans own `MARKETING_VERSION`** (currently `1.0`). It is the App Store
  Connect join key: uploading `1.0` matches the `1.0` train.
- **Xcode Cloud owns the build number.** Each build gets a per-app, monotonic
  `CI_BUILD_NUMBER` (starting at 1) and App Store Connect records *that* number —
  `CURRENT_PROJECT_VERSION` in `project.pbxproj` is ignored at upload time.
  Do not try to stamp it or run `agvtool`.
- To start a new user-facing version, bump `MARKETING_VERSION` only. To adjust
  the starting build number, use App Store Connect → CheckStitch → Xcode Cloud →
  Settings → Build Number, not the repository.
- If a `1.0` train was ever opened and closed in App Store Connect, the next
  upload is rejected until `MARKETING_VERSION` is bumped.

## The workflow

One workflow, configured in Xcode's Cloud tab (or App Store Connect → Xcode
Cloud → Workflows). Nothing in the repository configures it.

| Field | Value |
|---|---|
| Name | `TestFlight – iOS` |
| Xcode version | pinned to a released **Xcode 26.x** image (never "Latest", never a beta) — uploads require the iOS 26 SDK |
| macOS version | the image paired with that Xcode |
| Start condition | **Manual** |
| Action | **Archive** only (no Test action) |
| Archive platform | iOS |
| Archive scheme | `CheckStitch` |
| Archive configuration | Release |
| Deployment preparation | App Store Connect |
| Post-action | TestFlight Internal Testing → group `Internal` |

The watch app (`CheckStitchWatch`) is embedded in the iOS archive via
`Embed Watch Content`, so there is **one** artifact and **one** workflow — never
a separate watch workflow.

## Running a release

1. Xcode → **Cloud** tab → `TestFlight – iOS` → **Start Build** (or App Store
   Connect → Xcode Cloud → the workflow → Start Build). Pick branch `main`.
2. Wait for **Succeeded**. The archive log should show the watch app embedded
   and no `ITMS-` or provisioning errors.
3. App Store Connect → CheckStitch → TestFlight: the build moves *Processing* →
   **Ready to Test** and is assigned to the `Internal` group. Apple sends a
   processing email.
4. First upload only: answer **Export Compliance** on the build ("does not use
   encryption").
5. Testers install from the TestFlight app.

## Non-goals

Deliberate gaps — do not "fix" them by adding a second release mechanism:

- No `ci_scripts/`, no `ci_post_clone.sh`.
- No `.github/workflows`; Xcode Cloud is the CI.
- No App Store Connect API key, no `altool`/Transporter scripting, no
  `exportOptions.plist`.
- No `Makefile` release target, no build-number automation.
- No macOS TestFlight workflow here (fast-follow).
- No external testers, no App Store submission.

## macOS fast-follow

Deferred to its own ticket. The macOS App ID's capability state is unverified
(the entitlements file is wire per-SDK but the portal state has not been
checked), and macOS needs a different always-increasing build-number policy.
`MACOSX_DEPLOYMENT_TARGET = 27.0` may also exceed what Xcode Cloud's images
ship.
````

#### 2. Commit the deletion of the placeholder plus the runbook
**Files**: `DELETEME` (delete), `docs/TestFlight-xcode-cloud.md` (add),
`.pi/orksorksorks/alanvardy-var-993-get-a-build-working-on-testflight/phase*.md`
**Action**: modify/create
```bash
git rm DELETEME
git add docs/TestFlight-xcode-cloud.md \
  .pi/orksorksorks/alanvardy-var-993-get-a-build-working-on-testflight/
git commit -m "docs: add TestFlight via Xcode Cloud runbook"
```
- Open a PR to `main` and merge with `gh pr merge <n> --rebase --delete-branch`
  (never push to `main` directly; the repo uses rebase merges only).

### Verification
#### Automated
- [x] `bash scripts/test.sh` prints `gate: ok`
- [x] `git status --porcelain` shows only `docs/` and `.pi/…` additions after
      the commit (plus the removed `DELETEME`)
- [x] `git diff --stat de6ddd9..HEAD` touches no `Makefile` / `scripts/` /
      `project.pbxproj` / `*.entitlements` / `*.xcscheme`

#### Manual
- [ ] A second, independent workflow run started from the runbook alone reaches
      TestFlight
- [ ] A reader with no prior context can find the prerequisite capabilities,
      the workflow field table, and the version policy in the runbook

---

## Phase 4: Hardening — failure modes and decision points, documented

No new capability. Amend the runbook with the detection/escape routes for the
residual risks, and record the accepted risk and the macOS follow-up scope in
the completion artifact.

### Changes

#### 1. Add the "When it breaks" section
**File**: `docs/TestFlight-xcode-cloud.md`
**Action**: modify — insert the new section **immediately before
`## Non-goals`** (so the document ends: … Running a release → When it breaks →
Non-goals → macOS fast-follow).

```markdown
## When it breaks

- **Capability revoked / entitlement drift.** Symptom: an Archive that used to
  succeed fails with an `ITMS-…` or "provisioning profile doesn't include"
  error. Xcode Cloud cannot fix this: re-enable App Groups / iCloud KVS on the
  App ID (`app.alanvardy.CheckStitch`) in the Developer portal so it again
  matches `CheckStitch/AppGroup.entitlements`, then re-run.
- **Builder image retired.** Xcode Cloud removes old Xcode images. Symptom: the
  workflow fails because the pinned image no longer exists. Pick the newest
  released **Xcode 26.x** image and re-run. Note the deployment-target exposure:
  `WATCHOS_DEPLOYMENT_TARGET = 26.0` must be ≤ the image's watchOS SDK, and
  `MACOSX_DEPLOYMENT_TARGET = 27.0` limits any future macOS workflow.
- **Quota consumed.** Xcode Cloud compute hours are finite. Keep the start
  condition **Manual**; do not add "any branch change". If builds stop queuing,
  check App Store Connect → Xcode Cloud → Usage.
- **Invalid pre-release train.** If a `1.0` train was opened and closed, uploads
  are rejected until `MARKETING_VERSION` is bumped in `project.pbxproj`. That is
  a build-config change — do it as a deliberate version bump, not as a fix.
- **"Just archive locally instead."** Not a clean escape hatch: this machine's
  Xcode is a 27.0 beta host, and uploads from it can be rejected with
  `ITMS-90111`. Prefer fixing the cloud path.

## Residual risk (accepted)

There is **no committed regression signal**. If the workflow silently starts
failing (signing drift, capability revocation, portal change), nothing in
`bash scripts/test.sh` catches it — the failure surfaces only when someone looks
at Xcode Cloud. This is accepted for now; a future ticket could add a scheduled
workflow or a periodic manual check.
```

#### 2. Write the completion artifact
**File**: `.pi/orksorksorks/alanvardy-var-993-get-a-build-working-on-testflight/implement.md`
**Action**: create at the end of implementation
**Details**: implementation summary following the repo convention — a commit
table (Phase 3 commit + Phase 4 commit + step-artifact commits), automated
checks (gate output), manual verification items from Phases 0–3 with observed
results, the accepted residual risk, and the **macOS fast-follow scope** for the
separate ticket (macOS App ID/capability state unverified; a different
always-increasing build-number policy; `MACOSX_DEPLOYMENT_TARGET = 27.0`
exposure). Do not file the follow-up ticket.

### Verification
#### Automated
- [x] `bash scripts/test.sh` prints `gate: ok`
- [x] `git diff --stat de6ddd9..HEAD` touches no `Makefile` / `scripts/` /
      `project.pbxproj` / `*.entitlements` / `*.xcscheme`
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` clean (unchanged scripts;
      confirms the diff really is docs-only)

#### Manual
- [ ] The "When it breaks" section is present before `## Non-goals` and covers
      capability drift, image retirement, quota, invalid train, and the
      local-archive non-answer
- [ ] `implement.md` names the accepted residual risk and the macOS follow-up
      scope