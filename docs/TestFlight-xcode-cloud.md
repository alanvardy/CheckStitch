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

   These must include exactly what `CheckStitch/AppGroup.entitlements` declares
   (a superset is fine, never a subset). **Xcode Cloud
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
  (This ticket shipped no `1.0` train, so this is a future-operations note, not
  a fix to apply now.)
- **"Just archive locally instead."** Not a clean escape hatch: this machine's
  Xcode is a 27.0 beta host, and uploads from it can be rejected with
  `ITMS-90111`. Prefer fixing the cloud path.

## Residual risk (accepted)

There is **no committed regression signal**. If the workflow silently starts
failing (signing drift, capability revocation, portal change), nothing in
`bash scripts/test.sh` catches it — the failure surfaces only when someone looks
at Xcode Cloud. This is accepted for now; a future ticket could add a scheduled
workflow or a periodic manual check.

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
