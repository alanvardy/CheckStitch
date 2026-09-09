# Structure Outline

## Approach

Horizontally layer the project from static configuration (pbxproj identity,
signing, entitlements, source compatibility) up through a build-and-deploy
automation script — each layer proven green before the next starts.
Configuration is fully declarative (no identity or password in scripts);
`CODE_SIGN_STYLE = Automatic` + `DEVELOPMENT_TEAM` resolves signing from the
keychain exactly as SingleThread does.

---

## Stage 1: Project identity, signing, and source readiness

**What**: Transform the stock Xcode scaffold into a buildable, signable iOS
app with a real reverse-DNS bundle ID, correct deployment-target floor,
App Group entitlements plumbing, and source that compiles against iOS 18.7.
This is the declarative foundation — every change lives in static project
files. The next layer (the script) can assume this layer is green.

**Files**:
- `CheckStitch.xcodeproj/project.pbxproj` — modified
- `CheckStitch/AppGroup.entitlements` — **new**
- `CheckStitch/ContentView.swift` — modified

**Key changes**:

| Change | Before | After |
|---|---|---|
| Bundle ID | `devplaceholder.PL40N1FW.CheckStitch` (pbxproj:273,311) | `app.alanvardy.CheckStitch` (both Debug/Release) |
| iOS deployment target | `IPHONEOS_DEPLOYMENT_TARGET = 27.0` (project-level only: 173,237) | `18.7` at both project-level slots (173,237); target blocks inherit |
| Entitlements wiring | `CODE_SIGN_ENTITLEMENTS` absent | `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] = CheckStitch/AppGroup.entitlements`; `[sdk=iphonesimulator*]` same |
| Entitlements file | None | `CheckStitch/AppGroup.entitlements` — `com.apple.security.application-groups` → `group.app.alanvardy.CheckStitch` |
| Team | `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (unchanged — already present pbxproj:255,293) | **Keep 6NWX2DHB9Q**; if cert missing, fall back to `55PGY6DK44` (the machine's only valid cert) |
| Source | `import Playgrounds` + `#Playground { … }` block (ContentView.swift:4,14-17) | Remove both — Playgrounds requires iOS 27.0+ and `#Playground` is dead code for a device app |

**New type** (AppGroup.entitlements):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "…">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.app.alanvardy.CheckStitch</string>
    </array>
</dict>
</plist>
```

**Pbxproj mutation surface** (target-level Debug block, pbxproj:~246-281;
identical changes in Release block ~283-318):

- `PRODUCT_BUNDLE_IDENTIFIER` — literal replacement
- `IPHONEOS_DEPLOYMENT_TARGET` — 27.0 → 18.7 (target + project level)
- `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` — new key:value
- `CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]` — new key:value
- `DEVELOPMENT_TEAM` — may change to `55PGY6DK44` if 6NWX2DHB9Q has no cert

**Tests / verification**:

1. **Source-only build gate** (fastest feedback loop, catches Playgrounds /
   deployment-target incompatibility):
   ```bash
   xcodebuild -scheme CheckStitch \
     -destination 'generic/platform=iOS' \
     -configuration Debug \
     -derivedDataPath DerivedData \
     build 2>&1 | tee /tmp/build-stage1.log
   grep -q 'BUILD SUCCEEDED' /tmp/build-stage1.log
   ```
   If signing fails at this step (team cert unavailable), switch
   `DEVELOPMENT_TEAM` to `55PGY6DK44` and retry — that is a pre-flight fix,
   not a design change.

2. **Artifact check**: confirm `DerivedData/Build/Products/Debug-iphoneos/CheckStitch.app`
   exists and is a valid bundle (`ls -d` + `plutil -lint Info.plist`).

3. **Entitlements embedded**: confirm the built app carries the App Group
   entitlement:
   ```bash
   codesign -d --entitlements - DerivedData/Build/Products/Debug-iphoneos/CheckStitch.app 2>/dev/null | grep 'application-groups'
   ```

**Verify command**: the build gate above — `BUILD SUCCEEDED` must appear.
No other project gate exists yet (no `scripts/test.sh`, no CI).

---

## Stage 2: Build-and-deploy automation script

**What**: Create `scripts/run-devices.sh` — a minimal script that
builds for a physical iOS device, discovers the paired iPhone, installs the
`.app`, launches it, and reports success or failure. This layer consumes the
proven Stage 1 configuration and adds zero signing material of its own.

**Files**:
- `scripts/run-devices.sh` — **new**

**Key signatures / script contract**:

```bash
#!/bin/bash
set -euo pipefail

# Overridable defaults (consume Stage 1 configuration)
SCHEME="${SCHEME:-CheckStitch}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"

# Derived path (assumes Stage 1 build destination)
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app"
```

**Script structure** (bottom-up within the script):

1. **Setup** — cd to repo root, temp dir + EXIT trap
2. **Build** — `xcodebuild -scheme "$SCHEME" -destination 'generic/platform=iOS' -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA" build`
3. **Discover** — `xcrun devicectl list devices -j` → filter platform=iOS,
   developerModeStatus=enabled, reachable; single-device path (no loop).
   Fail with guidance if zero devices qualify.
4. **Install** — `xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"`
   (`.app` path argument)
5. **Launch** — `xcrun devicectl device process launch --terminate-existing --activate --device "$DEVICE_ID" "$BUNDLE_ID"`
   (bundle ID argument)

**Tests / verification**:

1. **Dry-run parse check** — `bash -n scripts/run-devices.sh` exits 0
2. **End-to-end**: run `bash scripts/run-devices.sh`; the script must:
   - Build successfully (`BUILD SUCCEEDED` in xcodebuild output)
   - Discover the iPhone 16 Pro Max (UDID `00008140-000569890CD2801C`)
   - Install CheckStitch.app
   - Launch the app
   - Exit 0 with a success summary line
3. **Manual confirmation**: "Hello, world!" visible on the iPhone screen

**Verify command**: `bash scripts/run-devices.sh`

---

## Testing Checkpoints

After each stage, the following must pass before advancing:

| Stage | Checkpoint |
|---|---|
| **1. Identity + signing** | `xcodebuild … build` → `BUILD SUCCEEDED`; `codesign -d --entitlements` shows application-groups |
| **2. Script** | `bash scripts/run-devices.sh` → exit 0; app launches on iPhone |

If Stage 1 build fails with a team-cert mismatch, fall back to
`DEVELOPMENT_TEAM = 55PGY6DK44` and retry before declaring Stage 1 broken.

---

## Not in scope

- Test targets, CI, Makefile, linting — out of scope per design
- App icon assets — not needed for on-device launch
- Runtime app-group usage (`UserDefaults(suiteName:)`) — entitlement is
  plumbed but no code exercises it
- macOS/watch/widget targets — iOS-only; `TARGETED_DEVICE_FAMILY` stays `"1,2,7"`
- Deployment-target drift guard — no `test.sh` to host it yet