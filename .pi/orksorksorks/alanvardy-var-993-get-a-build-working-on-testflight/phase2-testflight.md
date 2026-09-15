# Phase 2 — TestFlight internal delivery: an internal tester installs it

> **Status: PENDING — filled by the human owner.** This phase adds the
> TestFlight post-action, answers export compliance, and installs the build on a
> real device via the TestFlight app. Requires an iPhone + Apple ID invitations.
> Complete the checklist below, then fill the *Observed* cells (or paste back
> the values), and the agent will verify gate + commit this file.

## What to do (checklist)

- [ ] **Create the internal tester group** — ASC → CheckStitch → TestFlight →
  Internal Testing: group `Internal` (or use the auto-created one); add testers
  by Apple ID email (≤100; each must be a user in ASC with a role). No Beta App
  Review required for internal testers.
- [ ] **Add the post-action** — Xcode → Cloud tab → `TestFlight – iOS` →
  Edit Workflow → Archive action → **Post-Actions** → **TestFlight Internal
  Testing**: Target group `Internal`; "What to Test" text (e.g. "First internal
  beta of CheckStitch. Create a checklist, add items, run it, and confirm
  reminders are created in the CheckStitch Reminders list."). Start Condition
  stays **Manual**. No other change to this workflow.
- [ ] **Run again + clear first-build gates** — start the workflow manually
  (branch `main`); watch the build go *Processing* → **Ready to Test**; the
  group shows the build assigned.
- [ ] **Export compliance (first upload only)** — because
  `GENERATE_INFOPLIST_FILE = YES` and no `ITSAppUsesNonExemptEncryption` key is
  set, ASC blocks until answered: ASC → CheckStitch → the build → **Manage
  Compliance** / Export Compliance → "Your app does not use encryption"
  (CheckStitch uses no cryptography). Do NOT add the Info.plist key in the repo.
- [ ] **Install** — accept the tester invitation email; install + launch via the
  TestFlight app on a real iPhone; confirm the checkStitch watch app installs
  alongside.

## Contract record

- Internal group name: `________`
- Tester Apple IDs added: `________`
- Build number (ASC, = `CI_BUILD_NUMBER`): `________` (marketing `1.0`)
- Build state: `________`
- Device + iOS version: `________`
- TestFlight install/launch result: `________`
- Watch app installed alongside: `________`
- Export compliance answered: `________` (date)
- Processing email received: `________` (date)

## Evidence

| Check | Expected | Observed | How verified |
|---|---|---|---|
| Post-action config | TestFlight Internal Testing → `Internal` | _pending_ | workflow edit |
| Internal group + testers | group exists, testers listed | _pending_ | ASC → TestFlight |
| Build number | assigned (CI_BUILD_NUMBER) alongside 1.0 | _pending_ | ASC build page |
| Build state | Ready to Test | _pending_ | ASC → TestFlight |
| Processing email | received | _pending_ | inbox |
| Export compliance | answered ("does not use encryption") | _pending_ | ASC build → Manage Compliance |
| Device install | TestFlight app installs + launches | _pending_ | real device |
| Watch app | installed alongside phone app | _pending_ | device / watch app |
