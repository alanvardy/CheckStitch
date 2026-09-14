# Implementation Plan

## Overview

Restore the background photo on the signed macOS build by enabling outgoing
network for the sandboxed macOS slice (`ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`),
which is the only *verified* macOS-only divergence in the photo path. The design's
container-clear fix is dropped: it cannot compile on macOS, and the macOS
`NavigationStack` is verified transparent, so it was never the cause.

---

## Deviations from `design.md` / `structure.md` (read this first)

Three findings, all verified against the Xcode 26.6 / macOS 27 SDK and the signed
build, invalidate the original mechanism. Each deviation is forced, not preferred.

1. **The designed fix cannot compile on macOS.**
   `ContainerBackgroundPlacement.navigation` is annotated `@available(macOS, unavailable)`
   in `MacOSX27.0.sdk` (`SwiftUI.swiftinterface:16312-16316`); compiling
   `.containerBackground(.clear, for: .navigation)` for macOS fails with
   `error: 'navigation' is unavailable in macOS`. `MACOSX27_DEPLOYMENT_TARGET = 27.0`,
   so no `#available` guard can help — the symbol does not exist on the platform.
   → design Decision 1 and Decision 5 are void; structure Stage 2's seam body
   ("`containerBackground(.clear, for: .navigation)`, no platform branch") is
   unwritable, and Stage 3's unconditional application is impossible.

2. **The macOS container is not opaque — the prime hypothesis is falsified.**
   Rendering ContentView's exact layering in a real `NSHostingView`/`NSWindow`
   (titled window, `ScrollView` rows, card plate, `safeAreaInset`, toolbar) and
   sampling a grid of points shows the photo through the stack at every sample.
   `ImageRenderer` likewise renders `ZStack { photo; NavigationStack { … } }`
   with the photo visible. `.containerBackground(.clear, for: .window)`
   (macOS 15+, the only macOS-available placement) changes nothing.
   The comment at `ContentView.swift:55-58` asserting "macOS's stack is already
   transparent" is therefore **accurate** — it is *not* replaced or deleted.

3. **The real macOS-only divergence is the build configuration, not the view.**
   The signed macOS app is sandboxed and has **no** network entitlement:

   ```
   com.apple.security.app-sandbox        = true
   com.apple.security.application-groups  = [group.app.alanvardy.CheckStitch]
   com.apple.security.files.user-selected.read-only = true
   # com.apple.security.network.client  ← ABSENT
   ```

   `project.pbxproj` sets `ENABLE_APP_SANDBOX = YES` twice (Debug/Release app
   target) and never sets `ENABLE_OUTGOING_NETWORK_CONNECTIONS`. On a fresh
   container `BackgroundImageStore.refreshIfNeeded()` cannot fetch
   `https://vardy.cc/unsplash`, so `imageData` stays `nil` and
   `BackgroundPhotoLayer` renders `EmptyView`. iOS is unaffected because iOS
   requires no such entitlement — hence "works on iPhone/iPad". Research Q3
   missed this because it read only Swift source and correctly found "no
   platform branching"; the divergence is in the build settings.

**Consequences for the staged plan.** Stage 2 (container test seam) and Stage 3
(container fix) are replaced by a regression pin and the entitlement fix. Phase
order and the conditional final stage are preserved.

**One existing test already covers the mechanism.** `BackgroundImageStoreTests`
proves a failed fetch leaves `imageData == nil` (orphaned-jpg block, ~`:122-136`),
so no new Swift test is needed. The genuinely missing pin is the build setting.

---

## Phase 1: Diagnostic baseline — evidence, not inference

Confirm the failure on the signed build and freeze it on record.

### Changes

#### 1. Diagnosis artifact
**File**: `.pi/orksorksorks/alanvardy-var-994-macos-build-shows-no-background-photo-works-on-iphoneipad/diagnosis.md`
**Action**: create

Record, each with the command that produced it:

- Signed entitlements — `codesign -d --entitlements - --xml DerivedData/Build/Products/Debug/CheckStitch.app`
  → `app-sandbox = true`, **no `network.client`**.
- `project.pbxproj` — `ENABLE_APP_SANDBOX = YES;` ×2, no
  `ENABLE_OUTGOING_NETWORK_CONNECTIONS` (grep output).
- SDK unavailability — the `swiftinterface` lines for
  `ContainerBackgroundPlacement.navigation` and the macOS compile error text.
- Container non-cause — the real-window render probe result (photo visible
  through a realistic `NavigationStack`).

### Verification

#### Automated
- [x] `codesign -d --entitlements - --xml DerivedData/Build/Products/Debug/CheckStitch.app | grep -c "com.apple.security.network.client"` prints `0`
- [x] `grep -c "ENABLE_APP_SANDBOX = YES;" CheckStitch.xcodeproj/project.pbxproj` prints `2`
- [x] `grep -c "ENABLE_OUTGOING_NETWORK_CONNECTIONS" CheckStitch.xcodeproj/project.pbxproj` prints `0`

#### Manual
- [ ] `make build-mac-signed`, then `open DerivedData/Build/Products/Debug/CheckStitch.app`:
      the main screen shows the flat `Color.systemBackground` fill and **no photo**.
- [ ] Decisive runtime diagnostic for the data path (bypasses the 24 h freshness
      short-circuit, which otherwise hides the fetch):
      - [ ] start `log stream --predicate 'subsystem == "app.alanvardy.CheckStitch"' --style compact --level debug`
      - [ ] in the app open Settings (gear) and press **Refresh wallpaper** (`forceRefresh()` always hits the network)
      - [ ] expect `Background force refresh failed: …` in the stream; record the message
- [ ] **Stop and report** if that failure does *not* appear — the data path is then
      not the cause and the design needs revisiting (see Phase 5).

---

## Phase 2: Regression pin for the fixed condition

Replaces structure Stage 2 (the container test seam). The seam was to make the
container condition testable; the condition is now a build setting, so the pin is
a shell test. It is genuinely red-first: the counts differ before the fix.

### Changes

#### 1. Gate shell test
**File**: `scripts/tests/run.sh`
**Action**: modify — add after the Phase 3 block, before the summary

```bash
# --- macOS sandbox network entitlement -------------------------------------

# Regression pin for the background-photo regression: the macOS slice runs under
# App Sandbox, so without ENABLE_OUTGOING_NETWORK_CONNECTIONS the signed app
# carries no com.apple.security.network.client entitlement and the URLSession
# fetch of the photo is denied by the sandbox. iOS needs no such entitlement,
# which is why only macOS lost the photo. Every sandboxed app-target
# configuration must also request egress.
macos_slice_requests_outgoing_network() {
    local pbx="CheckStitch.xcodeproj/project.pbxproj"
    local sandboxed network
    sandboxed="$(grep -c 'ENABLE_APP_SANDBOX = YES;' "$pbx")"
    network="$(grep -c 'ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;' "$pbx")"
    [[ "$sandboxed" -gt 0 && "$sandboxed" -eq "$network" ]]
}

run_case macos_slice_requests_outgoing_network macos_slice_requests_outgoing_network
```

No new Swift test: `BackgroundImageStoreTests` already asserts that a failing
fetch leaves `imageData == nil` (orphaned-jpg case, ~`:122-136`), which is exactly
this bug's mechanism.

### Verification

#### Automated
- [x] `bash scripts/tests/run.sh` → `FAIL: macos_slice_requests_outgoing_network` (red before the fix — record this)
- [x] `shellcheck scripts/tests/run.sh` passes
- [x] `make test-unit` still green (unaffected)

#### Manual
- [ ] none

---

## Phase 3: Fix — allow outgoing network in the macOS sandbox

Replaces structure Stage 3 (the container clear). One build setting, applied to
both sandboxed app-target configurations. No Swift source changes.

### Changes

#### 1. macOS entitlement, via the build setting
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify — add `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;` to the two
`PBXNativeTarget "CheckStitch"` configurations that set `ENABLE_APP_SANDBOX = YES;`
(the Debug block headed `000000000000000111000000 /* Debug configuration … */` and
the Release block headed `000000000000000112000000 /* Release configuration … */`).

Both blocks share byte-identical opening lines, so anchor each edit on its config
header. Indentation is tabs (match the surrounding build settings exactly):

```diff
 		000000000000000111000000 /* Debug configuration for PBXNativeTarget "CheckStitch" */ = {
 			isa = XCBuildConfiguration;
 			buildSettings = {
 				CODE_SIGN_STYLE = Automatic;
 				"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]" = CheckStitch/AppGroup.entitlements;
 				"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = CheckStitch/AppGroup.entitlements;
 				"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = CheckStitch/AppGroup.entitlements;
 				"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";
 				CURRENT_PROJECT_VERSION = 1;
 				DEVELOPMENT_TEAM = 6NWX2DHB9Q;
 				ENABLE_APP_SANDBOX = YES;
+				ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;
 				ENABLE_PREVIEWS = YES;
```
(identical insertion in the `000000000000000112000000` Release block)

**Why this setting and not the entitlements file**: Xcode synthesizes
`com.apple.security.network.client` from `ENABLE_OUTGOING_NETWORK_CONNECTIONS`
(verified — see Verification below). `CheckStitch/AppGroup.entitlements` is shared
by the iOS and watch slices and must not gain a macOS-sandbox key.

**What must NOT change**:
- `CheckStitch/ContentView.swift` — the `#if os(iOS)` container clear at `:54-60`
  stays; iOS needs it, macOS has no equivalent API, and macOS does not need one.
- The comment at `ContentView.swift:55-58` — verified accurate, keep it.
- `CheckStitch/BackgroundPhotoLayer.swift`, `BackgroundImageStore.swift`,
  `SettingsBindings.swift`, the ZStack, `BackgroundFade` — untouched.

### Verification

#### Automated
- [ ] `bash scripts/tests/run.sh` → `ok: macos_slice_requests_outgoing_network` (was red, now green)
- [ ] `make build-mac` succeeds (unsigned compile leg — unaffected by the setting)
- [ ] `make watch-build` succeeds
- [ ] `make build-mac-signed`, then
      `codesign -d --entitlements - --xml DerivedData/Build/Products/Debug/CheckStitch.app`
      now contains `<key>com.apple.security.network.client</key><true/>`
      (confirmed to build without provisioning changes; `-allowProvisioningUpdates` is already in the target)
- [ ] `make test-unit` green

#### Manual
- [ ] Signed launch + Settings → **Refresh wallpaper** with
      `log stream --predicate 'subsystem == "app.alanvardy.CheckStitch"'` running:
      no `Background force refresh failed` line, and the photo appears.

---

## Phase 4: Regression gate and manual rendering proof

### Changes

#### 1. Diagnosis artifact
**File**: `.pi/orksorksorks/alanvardy-var-994-macos-build-shows-no-background-photo-works-on-iphoneipad/diagnosis.md`
**Action**: modify — append the post-fix record

### Verification

#### Automated
- [ ] `bash scripts/test.sh` prints `gate: ok`
      (simulator build → UI smoke → unsigned macOS leg → watchOS leg → shell tests → shellcheck)
- [ ] `git diff --stat` shows no change under `CheckStitch/*.swift` (build config + shell test only)

#### Manual
- [ ] `make build-mac-signed` + launch: photo renders behind the content, at
      default (50) and faded opacity, and stays correct across window resizes —
      recorded as the post-fix counterpart to Phase 1.
- [ ] `make run` on the simulator, UI smoke green: iOS rendering unchanged
      (iOS receives no code change at all).

---

## Phase 5 (conditional): if the photo is still absent after Phase 3

Not planned work. If Phase 3's signed run still shows no photo — or the
force-refresh failure persists — the entitlement was not the whole story:

1. Re-run the Phase 1 diagnostic to see which layer now fails
   (`Background force refresh failed` vs. no fetch at all vs. fetch OK but no photo).
2. If the fetch succeeds and the photo is still not painted, the remaining
   candidate is the macOS window/container — but **do not guess a view fix**:
   `.navigation` is uncompilable on macOS (Phase 1 finding) and `.window` was
   measured to have no effect. Escalate to `design` for a macOS-specific
   mechanism rather than bundling a speculative change here.

---

## Testing checkpoints

- After Phase 1: signed-run evidence recorded; fetch-failure log captured (else stop).
- After Phase 2: `scripts/tests/run.sh` red for the new pin; shellcheck clean.
- After Phase 3: pin green; `make build-mac` + `make watch-build` compile;
  `network.client` present in the signed entitlements; `make test-unit` green.
- After Phase 4: `bash scripts/test.sh` → `gate: ok`; signed macOS resize check
  recorded; no Swift-source changes.
