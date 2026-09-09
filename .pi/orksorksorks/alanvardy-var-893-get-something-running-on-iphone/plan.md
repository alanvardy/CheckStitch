# Implementation Plan

## Overview

Transform the bare Xcode 26.6 scaffold into a buildable, signable iOS app
that installs and launches on the developer's physical iPhone 16 Pro Max
via a single script. Two stages: declarative project configuration (pbxproj
identity, signing, entitlements, source fixes), then a build-and-deploy
automation script.

---

## Phase 1: Project identity, signing, and source readiness

### Changes

#### 1. Fix bundle identifier — Debug config
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify — literal replacement at line 273

```
PRODUCT_BUNDLE_IDENTIFIER = "devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)";
```
→
```
PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitch;
```

#### 2. Fix bundle identifier — Release config
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify — literal replacement at line 311

Same replacement as above.

#### 3. Lower iOS deployment target — project Debug
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify — literal replacement at line 173

```
IPHONEOS_DEPLOYMENT_TARGET = 27.0;
```
→
```
IPHONEOS_DEPLOYMENT_TARGET = 18.7;
```

#### 4. Lower iOS deployment target — project Release
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify — literal replacement at line 237

Same replacement as above.

**Note**: `IPHONEOS_DEPLOYMENT_TARGET` appears only at project level (2 occurrences), not in the target-level config blocks. The target blocks inherit from project level. This corrects the structure.md assumption of "three levels."

Other platform deployment targets (`APPLETVOS`, `DRIVERKIT`, `MACOSX`, `WATCHOS`, `XROS`) are left at 27.0 — they do not affect iOS device builds.

#### 5. Add CODE_SIGN_ENTITLEMENTS — target Debug
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify — add two new lines after line 253 (`CODE_SIGN_STYLE = Automatic;`)

Insert after `CODE_SIGN_STYLE = Automatic;`:
```
				"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]" = CheckStitch/AppGroup.entitlements;
				"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = CheckStitch/AppGroup.entitlements;
```

#### 6. Add CODE_SIGN_ENTITLEMENTS — target Release
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify — same two lines added after line 291 (`CODE_SIGN_STYLE = Automatic;`)

Same insertion as above.

#### 7. Create App Group entitlements file
**File**: `CheckStitch/AppGroup.entitlements`
**Action**: create

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.app.alanvardy.CheckStitch</string>
	</array>
</dict>
</plist>
```

#### 8. Remove Playgrounds imports and dead code
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Remove `import Playgrounds` (line 2) and the `#Playground { … }` block (lines 14-17).

**Before**:
```swift
import SwiftUI
import Playgrounds

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
```

**After**:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}

#Preview {
    ContentView()
}
```

**Rationale**: `import Playgrounds` requires iOS 27.0+ SDK and `#Playground` is dead code for a device-targeted app. Removing both lets the project compile against iOS 18.7.

#### 9. (Fallback) Switch DEVELOPMENT_TEAM if no cert for 6NWX2DHB9Q
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: conditional modify — only if Phase 1 build fails with a signing error

If the Step 1 verification build fails with a team-cert mismatch, change `DEVELOPMENT_TEAM = 6NWX2DHB9Q;` → `DEVELOPMENT_TEAM = 55PGY6DK44;` at both occurrences (lines 255 and 293).

**Decision gate**: run the build first, then decide. Do not change the team preemptively.

### Verification

#### Automated
- [x] `xcodebuild -scheme CheckStitch -destination 'generic/platform=iOS' -configuration Debug -derivedDataPath DerivedData build 2>&1 | tee /tmp/build-stage1.log` — confirm `grep -q 'BUILD SUCCEEDED' /tmp/build-stage1.log`
- [x] `ls -d DerivedData/Build/Products/Debug-iphoneos/CheckStitch.app` — app bundle exists
- [x] `plutil -lint DerivedData/Build/Products/Debug-iphoneos/CheckStitch.app/Info.plist` — valid plist
- [x] `codesign -d --entitlements - DerivedData/Build/Products/Debug-iphoneos/CheckStitch.app 2>/dev/null | grep 'application-groups'` — entitlement embedded

#### Manual
- [ ] If build fails with team-cert error, switch `DEVELOPMENT_TEAM` to `55PGY6DK44` and retry

---

## Phase 2: Build-and-deploy automation script

### Changes

#### 1. Create run-devices.sh
**File**: `scripts/run-devices.sh`
**Action**: create

```bash
#!/bin/bash
set -euo pipefail

# === Configuration (overridable) ===
SCHEME="${SCHEME:-CheckStitch}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"

# === Derived paths ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app"

# === Temp dir + cleanup ===
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$REPO_ROOT"

# === Build ===
echo "==> Building $SCHEME for iOS device..."
xcodebuild -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: App bundle not found at $APP_PATH" >&2
  exit 1
fi

# === Discover device ===
echo "==> Discovering iOS device..."
DEVICES_JSON="$TMPDIR/devices.json"
xcrun devicectl list devices -j > "$DEVICES_JSON"

# jq filter: platform=iOS, developerModeStatus=enabled, reachable
DEVICE_ID=$(jq -r '
  .devices[]
  | select(.platform == "iOS")
  | select(.developerModeStatus == "enabled")
  | select(
      (.connectionProperties.reachable == true) or
      (.connectionProperties.tunnelState == "connected")
    )
  | .identifier
' "$DEVICES_JSON" | head -n1)

if [ -z "$DEVICE_ID" ]; then
  echo "ERROR: No iOS device with Developer Mode enabled and reachable." >&2
  echo "       Ensure the device is unlocked, on Wi-Fi, and Developer Mode is on." >&2
  exit 1
fi

DEVICE_NAME=$(jq -r --arg id "$DEVICE_ID" '
  .devices[] | select(.identifier == $id) | .name
' "$DEVICES_JSON")
echo "   Device: $DEVICE_NAME ($DEVICE_ID)"

# === Install ===
echo "==> Installing $SCHEME.app..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

# === Launch ===
echo "==> Launching $BUNDLE_ID..."
xcrun devicectl device process launch \
  --terminate-existing \
  --activate \
  --device "$DEVICE_ID" \
  "$BUNDLE_ID"

echo ""
echo "✅ Installed and launched $SCHEME on $DEVICE_NAME"
```

### Verification

#### Automated
- [x] `bash -n scripts/run-devices.sh` — no syntax errors

#### Manual
- [ ] `bash scripts/run-devices.sh` — exits 0; app builds, installs, and launches on iPhone
- [ ] "Hello, world!" visible on the iPhone screen

---

## Deviations from Structure Outline

1. **`IPHONEOS_DEPLOYMENT_TARGET` is project-level only (2 occurrences)**, not "three levels" as structure.md claimed. The target-level config blocks (Debug and Release) do not contain the key — they inherit from project level. The plan changes only lines 173 and 237.

2. **`DEVELOPMENT_TEAM` change is conditional, not decided upfront.** The plan keeps `6NWX2DHB9Q` and only falls back to `55PGY6DK44` if the build fails. This matches the design's "Open Risk #1" mitigation.

---

## Testing Checkpoints

| Stage | Checkpoint |
|---|---|
| **1. Identity + signing** | `xcodebuild … build` → `BUILD SUCCEEDED`; `codesign -d --entitlements` shows application-groups |
| **2. Script** | `bash scripts/run-devices.sh` → exit 0; app launches on iPhone |

---

## Not in Scope

- Test targets, CI, Makefile, linting
- App icon assets
- Runtime app-group usage (`UserDefaults(suiteName:)`)
- macOS/watch/widget targets
- Deployment-target drift guard
- Simulator build support