# Phase 0 — Portal + ASC prerequisites

> **Status: PENDING — filled by the human owner.** This phase is external state
> registration (Developer portal + App Store Connect). No agent can complete it
> (browser sign-in, 2FA, portal clicks). Complete the checklist below, then fill
> the table's *Observed* cells (or paste back the observed values and the agent
> will fill them), and the agent will verify gate + commit this file.

## What to do (checklist)

- [ ] **ASC app record** — App Store Connect → Apps → **+** → New App:
  Platform **iOS**, Name `CheckStitch` (globally unique; if taken, pick a
  display variant and record it below), Primary Language English (U.S.),
  Bundle ID `app.alanvardy.CheckStitch` (must be selectable — if absent, create
  the App ID under Identifiers first), SKU `CHECKSTITCH`, User Access Full
  Access. Record the 10-digit Apple ID from App Information below.
- [ ] **Portal capabilities** — developer.apple.com → Certificates, Identifiers
  & Profiles → Identifiers: App Groups `group.app.alanvardy.CheckStitch` exists;
  App ID `app.alanvardy.CheckStitch` → Capabilities → **App Groups**
  (group checked) and **iCloud → Key-value storage (KVS)** both enabled. Must
  match `CheckStitch/AppGroup.entitlements` — may be a superset, never a subset.
- [ ] **Watch App ID** — `app.alanvardy.CheckStitch.watchkitapp` exists (no
  capabilities required).
- [ ] **Enabling role** — ASC → Users and Access: the account that will press
  "Get Started with Xcode Cloud" is **Account Holder or Admin** (App Manager is
  NOT sufficient). If Developer-only, stop — Phase 1 cannot proceed.
- [ ] **Version train** — ASC → CheckStitch → TestFlight (and App Store → iOS
  App versions): no closed/expired `1.0` train. If a `1.0` train exists and is
  closed, STOP and report — that would require a `MARKETING_VERSION` bump (a
  build-config change this ticket forbids).

## Contract record

- ASC App ID (10-digit Apple ID): `________`
- Bundle ID: `app.alanvardy.CheckStitch`
- App Group: `group.app.alanvardy.CheckStitch`
- Capabilities on the App ID: App Groups ✓ / iCloud KVS ✓
- Enabling account + role: `________`
- Watch App ID present: `________`

## Evidence

| Check | Expected | Observed | Verified by |
|---|---|---|---|
| ASC app record | exists, bundle id app.alanvardy.CheckStitch | _pending_ | ASC → App Information, Apple ID … |
| App Group capability | enabled, group.app.alanvardy.CheckStitch assigned | _pending_ | portal screenshot / date |
| iCloud KVS capability | enabled with Key-value storage | _pending_ | portal screenshot / date |
| watch App ID | app.alanvardy.CheckStitch.watchkitapp exists | _pending_ | portal |
| Enabling role | Account Holder or Admin | _pending_ | ASC → Users and Access |
| 1.0 train | absent (or bump required — escalate) | _pending_ | ASC → TestFlight |