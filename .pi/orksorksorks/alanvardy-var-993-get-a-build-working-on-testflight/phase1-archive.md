# Phase 1 — Walking skeleton: a signed CheckStitch archive reaches App Store Connect

> **Status: PENDING — filled by the human owner.** This phase is Xcode Cloud
> enablement + one workflow + a manual build run. Requires Xcode GUI sign-in
> (Apple ID / GitHub OAuth) and pressing Start Build. Complete the checklist
> below, then fill the *Observed* cells (or paste back the values), and the
> agent will verify gate + commit this file.

## What to do (checklist)

- [ ] **Enable Xcode Cloud** — Xcode (project open) → **Cloud** tab → **Get
  Started with Xcode Cloud**; sign in with team `6NWX2DHB9Q` (Settings →
  Accounts must already have it); grant access to
  `https://github.com/alanvardy/CheckStitch.git` (GitHub account must be admin
  on the repo), branch to watch `main`. The wizard creates a **Default
  Workflow** — do not delete before editing it (step 2). Do not install the
  Xcode Cloud GitHub App for any other repository.
- [ ] **Configure the workflow** — exactly these fields, nothing else:

  | Field | Value |
  |---|---|
  | Name | `TestFlight – iOS` |
  | Environment → Xcode Version | newest **non-beta Xcode 26.x** (e.g. `Xcode 26.6`) — never "Latest"/default, never 27 beta |
  | Environment → macOS Version | newest available paired with that Xcode |
  | Start Conditions | **Manual** only (delete branch/tag/PR/schedule conditions) |
  | Actions | delete default **Test** action; add exactly one **Archive** action |
  | Archive → Platform | **iOS** |
  | Archive → Scheme | `CheckStitch` |
  | Archive → Configuration | **Release** |
  | Archive → Deployment Preparation | **App Store Connect** |
  | Post-Actions | **none** in this phase |

  Record the exact Xcode/macOS image strings below — the pinned-environment
  contract. No `ci_scripts/`, no `ci_post_clone.sh`, no `.github/`, no
  `project.pbxproj` / entitlement / scheme / Makefile edits.
- [ ] **Run the workflow manually** — Cloud tab → workflow → **Start Build**
  (branch `main`). Wait for terminal state. In the build log look for:
  - `Embed Watch Content` (or the watch app under the archive's `Watch/`
    products);
  - **no** `ITMS-` lines, no "Provisioning profile … doesn't include" lines,
    no `com.apple.security.application-groups` /
    `ubiquity-kvstore-identifier` errors.

  On failure capture the exact error into this file and stop:
  entitlement/capability error → fix in portal only (Phase 0 step 2); signing
  error naming the watch bundle id → confirm `app.alanvardy.CheckStitch.watchkitapp`
  App ID; Xcode image/deployment-target error → re-pin the image.
- [ ] Confirm the build appears in App Store Connect under version `1.0`
  (*Processing* → processed; Apple's processing email arrives).

## Contract record

- Pinned Xcode image: `________`
- Pinned macOS image: `________`
- Deleted test action name: `________`
- Xcode Cloud build status: `________`
- ASC version showing the build: `________`

## Evidence

| Check | Expected | Observed | How verified |
|---|---|---|---|
| Workflow exists | `TestFlight – iOS`, Manual start only | _pending_ | Cloud tab / ASC → Xcode Cloud |
| Pinned image | newest non-beta Xcode 26.x | _pending_ | workflow Environment |
| Archive action | iOS / CheckStitch / Release / App Store Connect | _pending_ | workflow Actions |
| Build status | Succeeded | _pending_ | Xcode Cloud / ASC |
| Watch embedded | `Embed Watch Content` in log (or `Watch/` product) | _pending_ | build log |
| No ITMS-/provisioning errors | absent | _pending_ | build log |
| Build in ASC | version 1.0 | _pending_ | ASC → TestFlight / processing email |
