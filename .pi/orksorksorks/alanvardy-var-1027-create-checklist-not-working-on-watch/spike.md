# Spike — one-tap chain on hardware (Phase 1 decision gate)

Date: 2026-09-16 (PDT) — branch `alanvardy-var-1027-create-checklist-not-working-on-watch` @ `7180def`
Builds: `CheckStitchWatch` (watchOS, installed via `scripts/run-watch.sh`) + iPhone
`CheckStitch` (installed via `scripts/run-devices.sh`), both with the Phase 1
diagnostics (Logger + `Documents/checklist-sync.log` file sink, pullable via
`devicectl device copy from --domain-type appDataContainer`).

Devices: watch `6EF5C1CD-A890-559B-98D5-8F7F5A5A699A` ("Alan's Apple Watch",
localNetwork), phone `6C1EA973-3762-58B4-B04E-062FE6C3EB9F` ("Alan's iPhone",
localNetwork). Phone app foreground (WCSession activated) while tapping.

## Watch log (`Documents/checklist-sync.log`, watch container)

```
[watchSend] activationState=WCSessionActivationState(rawValue: 0) message=requestChecklists
[watchActivation] error=none state=WCSessionActivationState(rawValue: 2)
[watchSend] activationState=WCSessionActivationState(rawValue: 2) message=requestChecklists
[watchSend] activationState=WCSessionActivationState(rawValue: 2) message=runChecklist(id:E3418F18-1390-443A-9EE2-977742C1505D,run:E82D2848-A126-424F-8917-3E22111A7986)
[watchSend] accepted=true checklist=E3418F18-1390-443A-9EE2-977742C1505D run=E82D2848-A126-424F-8917-3E22111A7986
```

## Phone log (`Documents/checklist-sync.log`, phone container)

```
[phoneReceive] message=requestChecklists source=userInfo
[phoneHandle] message=requestChecklists
[phoneReceive] message=runChecklist(id:E3418F18-1390-443A-9EE2-977742C1505D,run:E82D2848-A126-424F-8917-3E22111A7986) source=userInfo
[phoneHandle] message=runChecklist(id:E3418F18-1390-443A-9EE2-977742C1505D,run:E82D2848-A126-424F-8917-3E22111A7986)
[snapshotLookup] checklist=E3418F18-1390-443A-9EE2-977742C1505D result=hit run=E82D2848-A126-424F-8917-3E22111A7986
[createOutcome] checklist=E3418F18-1390-443A-9EE2-977742C1505D outcome=created(count: 11) run=E82D2848-A126-424F-8917-3E22111A7986
```

## Reconstruction (one tap, correlated by `run=E82D2848-…`)

| Gate | Device | Verdict |
|---|---|---|
| watchSend (requestChecklists, cold) | watch | dropped, `activationState=0` — known race; the store re-requests on `onActivated` by design |
| watchActivation | watch | `state=2 (activated), error=none` |
| watchSend (requestChecklists, after activation) | watch | accepted |
| watchSend (runChecklist) | watch | accepted (`accepted=true`) |
| phoneReceive / phoneHandle | phone | fired for `requestChecklists` and `runChecklist` |
| snapshotLookup | phone | `result=hit` |
| createOutcome | phone | `outcome=created(count: 11)` — EventKit created 11 reminders |

## Reading

The chain is **clean end to end** with the phone app running and foreground:
the tap reaches the phone, the snapshot hits, and the phone's existing
`ChecklistReminders.create` path returns `created(11)`. There is **no
code-level drop** in the sync seam on this run (Phase 1's suspected
`snapshotLookup result=miss` silent drop did not occur).

The user-visible failure the ticket describes (button reports success, no
reminders) reproduced earlier in this session as a **phone-app-not-running
case**: the watch taps while the CheckStitch iPhone app is not active —
`transferUserInfo` is only *queued* by the watch and the phone is not alive to
act on it — yet the Phase 1 watch UI still flips the button to `Sent` on
acceptance. That is exactly the Phase 2 (honest phone-confirmed feedback,
`.runResult` channel) + Phase 4 (retain-and-resend across the non-running
phone / activation race) family; Phase 3 (unknown/stale id recovery) is the
safety net.

Per the plan's decision gate: the chain is mechanically clean, so the fix
scope is NOT "repair a broken wire" — it is the honest-feedback +
retain-and-resend family (Phases 2–4), which the design already scoped.

## Tooling notes (for future spikes)

- Neither device's syslog is pullable from the host on this machine (Xcode 27
  ships no `idevicesyslog`; `device sysdiagnose`/`diagnose` fail with
  `DiagnoseError`; crash-logs domains hold only analytics dumps). Console.app
  is the only live viewer; `Documents/checklist-sync.log` (app data container)
  is the agent-reachable copy.
- `devicectl device copy from --domain-type appDataContainer --domain-identifier
  <bundle-id> --source Documents/checklist-sync.log --destination <local>` works
  on both devices; remote paths are relative to the container root. Watch pulls
  can transiently fail with error 4000 (tunnel blip) — retry.