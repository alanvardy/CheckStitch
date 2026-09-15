# Structure Outline

## Approach

One outcome — a CheckStitch build installable from TestFlight — reached by
exercising the real path in the smallest increments that each leave a durable,
verifiable artifact in Apple's systems: portal capability state → Xcode Cloud
Archive → App Store Connect processing → internal tester install. The repo diff
stays documentation-only (`docs/` + `.pi/orksorksorks/…` artifacts); the gate
(`bash scripts/test.sh`) must stay byte-identical in behavior at every phase.

**Honest caveat on slice shape**: this ticket has no code layers. The "stack" is
*Developer portal capability state → ASC app record → Xcode Cloud workflow →
signed archive → ASC processing → TestFlight distribution*. The vertical slices
below cut through that stack. Phase 0 is the one genuine horizontal exception
(external state registration — the equivalent of a migration: nothing can land
green before it exists; see *Rules*).

---

## Phase 0: Portal + ASC prerequisites (horizontal — cannot be vertical)

Register the external state the first Archive depends on, so a later slice
fails for one reason instead of five. Nothing is demoable yet; this phase is
declared horizontal deliberately (design *Open Risks* 1–3).

**Scope (external systems, no repo files)**:
- App Store Connect app record for `app.alanvardy.CheckStitch` exists (create if
  absent; requires Account Holder/Admin/App Manager).
- iOS App ID `app.alanvardy.CheckStitch` has **App Groups**
  (`group.app.alanvardy.CheckStitch`) and **iCloud KVS** enabled — matching
  `CheckStitch/AppGroup.entitlements:5-10` exactly. Xcode Cloud cannot repair a
  mismatch; this is the most likely first failure.
- Confirmed enabling account role is Account Holder or Admin (Xcode Cloud
  enablement is one-time and role-gated).
- `MARKETING_VERSION` train acceptable: if a `1.0` Beta train was already opened
  and closed, note the bump to `1.1` as the first action of Phase 1.

**Contract**: the App ID's capability set and the ASC app record are the fixed
inputs every later phase assumes. Record them (screenshot/notes) in
`.pi/orksorksorks/alanvardy-var-993-get-a-build-working-on-testflight/large.md`
or the phase artifact so drift is detectable.

**Tests**: none testable in-repo. **Verify**: ASC shows the app record; the
portal App ID shows App Groups + iCloud KVS enabled. Repo-side:
`bash scripts/test.sh` prints `gate: ok` and `git status --porcelain` shows no
tracked source modification.

---

## Phase 1: Walking skeleton — a signed CheckStitch archive reaches App Store Connect

Xcode Cloud is enabled for the app, one workflow exists with a manual start
condition and an **Archive** action for iOS (App Store Connect deployment
preparation, Xcode 26+ image pinned), and it reports **Succeeded** with the
build visible in App Store Connect. This is the thinnest real path end to end —
repo → Apple-hosted build → signing → signed archive → ASC — and it front-loads
the riskiest unknowns (entitlements, builder image, watch slice signing).

**Files**: none in-repo. GUI state in Xcode/ASC + a phase artifact under
`.pi/orksorksorks/alanvardy-var-993-get-a-build-working-on-testflight/`.

**Key changes (workflow config, not code)**:
- Workflow: `Start Condition = Manual`, `Environment = newest Xcode 26+ image`
  (pinned explicitly — never "default latest"), `Actions = Archive` only.
- Archive action: `Platform = iOS`, `Scheme = CheckStitch` (as-is),
  `Configuration = Release`, `Deployment Preparation = App Store Connect`.
- Post-actions: **none** in this phase (TestFlight group assignment is Phase 2).
- No `ci_scripts/`, no `.github/`, no `project.pbxproj` / entitlements / Makefile
  / scheme edits.

**Contract**: the workflow exists, is manually triggerable, consumes the
`CheckStitch` scheme unchanged, and produces a signed iOS archive whose embedded
`CheckStitchWatch.app` slice survives signing. Phase 2 adds a post-action to
*this* workflow only.

**Tests**: no new tests (design *What We're NOT Doing*). Manual checks that stand
in for them: Xcode Cloud build status = **Succeeded**; archive log shows the
watch app embedded (`Embed Watch Content`); no `ITMS-` signing/entitlement
error; build processed (may show *Processing* then complete) with Apple's
processing email.

**Verify**: Xcode Cloud reports **Succeeded** and the build appears in App Store
Connect under version `1.0`; `bash scripts/test.sh` still prints `gate: ok`.

---

## Phase 2: TestFlight internal delivery — an internal tester installs it

Add the **TestFlight (Internal Testing)** post-action to the Phase 1 workflow,
assign the internal group, and install the resulting build from the TestFlight
app on a real device. This is the ticket's actual deliverable.

**Files**: none in-repo (`docs/` runbook is Phase 3). ASC tester/group state +
phase artifact.

**Key changes (external)**:
- Workflow post-action: `Distribute to TestFlight (Internal Testing)` → the
  internal tester group; supply the required "What to Test" text.
- ASC: internal testers added to the group (≤100; **no** Beta App Review), app
  metadata complete enough for internal distribution.

**Contract**: an ASC build number (Xcode Cloud `CI_BUILD_NUMBER`) assigned to a
named internal group; `MARKETING_VERSION` remains the human-owned ASC join key
(design decision 4). Phase 3 documents exactly this contract.

**Tests**: no new tests. Manual checks: ASC build state reaches **Ready to
Test**; processing email received; the build installs and launches from the
TestFlight app on a device; the watch app installs alongside.

**Verify**: a device running the TestFlight-installed build; ASC shows the build
in the internal group; `bash scripts/test.sh` still prints `gate: ok`.

---

## Phase 3: Repeatable release — the process survives without tribal knowledge

Commit `docs/TestFlight-xcode-cloud.md` recording the Phase 0 prerequisites and
the Phase 1–2 click-path, plus the version policy — so a second release (bump
`MARKETING_VERSION`, press the button) needs no archaeology. Deliverable is the
only repo change this ticket ships.

**Files**: `docs/TestFlight-xcode-cloud.md` (new; `docs/` does not exist yet —
create the directory).

**Key changes**:
- New runbook documenting: portal prerequisites and *why* they are prerequisites
  (capability mismatch = first-Archive failure); Xcode Cloud enablement role;
  the workflow's archive + TestFlight post-action config; the Xcode image pin
  and why; version policy (`MARKETING_VERSION` bumped by humans,
  `CI_BUILD_NUMBER` owned by Xcode Cloud, never `CURRENT_PROJECT_VERSION`);
  internal vs external tester difference; where to look when it fails.
- Explicit non-goals repeated from the design (no `ci_scripts/`, no `.github/`,
  no API keys, no `exportOptions.plist`) so a future reader does not "fix" this
  by adding a second release mechanism.

**Contract**: the runbook is the durable interface for the next release and for
the macOS fast-follow; nothing code-facing changes.

**Tests**: none. **Verify**: a second, independent workflow run is triggered
from the runbook alone (by someone or something not carrying this context) and
reaches TestFlight; `git status` shows only `docs/` + `.pi/…` additions;
`bash scripts/test.sh` prints `gate: ok`.

---

## Phase 4: Hardening — failure modes and decision points, documented

Close out the residual risks with documented detection and escape routes; no new
capability.

**Files**: `docs/TestFlight-xcode-cloud.md` (amend) + completion artifact.

**Key changes**:
- Add a "when it breaks" section: capability revocation / entitlement drift
  (Xcode Cloud *cannot* fix — portal only), builder-image retirement and the
  `MACOSX_DEPLOYMENT_TARGET = 27.0` / `WATCHOS_DEPLOYMENT_TARGET = 26.0`
  exposure, quota consumption and why the start condition stays narrow, invalid
  pre-release train recovery, and the documented non-answer to "just archive
  locally" (`ITMS-90111` on the beta host).
- Record the residual risk from design *Open Risks* 5 explicitly: **no
  committed regression signal** — this is accepted, not solved.
- Scope the macOS fast-follow (separate ticket: macOS App ID/capability state is
  unverified and needs a different always-increasing build-number policy).

**Tests**: none. **Verify**: `bash scripts/test.sh` prints `gate: ok`; diff
scope is docs-only (`git diff --stat de6ddd9..HEAD` touches no
`Makefile`/`scripts/`/`project.pbxproj`/`*.entitlements`/`*.xcscheme`).

---

## Testing Checkpoints

| After | Must be green before advancing |
|---|---|
| Phase 0 | ASC app record exists; App ID shows App Groups + iCloud KVS; `gate: ok`; no tracked source modified |
| Phase 1 | Xcode Cloud build **Succeeded**, no `ITMS-` errors, watch embedded, build visible in ASC; `gate: ok` |
| Phase 2 | Build **Ready to Test**, processing email received, installs+launches from TestFlight on a real device; `gate: ok` |
| Phase 3 | Independent run driven from the runbook alone reaches TestFlight; diff is docs-only; `gate: ok` |
| Phase 4 | Diff touches no build/sign/scheme file; `gate: ok` |

**Ordering rationale**: Phase 0 is dependency (external state) *and* risk
(design risks 1–3). Phase 1 is risk (entitlements, image, watch signing — risks
4, 6, 7) before the end. Phase 2 and 3 are value. Phase 4 is hardening, not baked
into the earlier phases.
