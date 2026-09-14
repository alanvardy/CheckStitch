# Diagnosis — background photo absent on the signed macOS build

Phase 1 of the implementation plan. Freezes the pre-fix failure on record,
evidence before inference. Recorded 2026-09-14 11:06 PDT.

Every entry below is followed by the command that produced it.

---

## 1. Signed entitlements — the sandboxed macOS slice has no network client

```
$ codesign -d --entitlements - --xml DerivedData/Build/Products/Debug/CheckStitch.app
Executable=.../DerivedData/Build/Products/Debug/CheckStitch.app/Contents/MacOS/CheckStitch
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.application-identifier</key>          <string>6NWX2DHB9Q.app.alanvardy.CheckStitch</string>
  <key>com.apple.developer.team-identifier</key>       <string>6NWX2DHB9Q</string>
  <key>com.apple.developer.ubiquity-kvstore-identifier</key> <string>6NWX2DHB9Q.app.alanvardy.CheckStitch</string>
  <key>com.apple.security.app-sandbox</key>            <true/>
  <key>com.apple.security.application-groups</key>     <array><string>group.app.alanvardy.CheckStitch</string></array>
  <key>com.apple.security.files.user-selected.read-only</key> <true/>
  <key>com.apple.security.get-task-allow</key>         <true/>
</dict></plist>
```

The signed app is sandboxed (`com.apple.security.app-sandbox = true`) and carries
**no** `com.apple.security.network.client` entitlement. Every outgoing-URL request
by the sandboxed macOS slice is therefore denied — including the
`BackgroundImageStore` `GET https://vardy.cc/unsplash` fetch, so `imageData` stays
`nil` and `BackgroundPhotoLayer` renders `EmptyView` (its gate at
`BackgroundPhotoLayer.swift:14`). Confirmed by:

```
$ codesign -d --entitlements - --xml DerivedData/Build/Products/Debug/CheckStitch.app 2>&1 | grep -c "com.apple.security.network.client"
0
```

(The checked build is a fresh `make build-mac-signed` from this worktree's current
HEAD — signed macOS binary mtime Sep 14 11:04 PDT.)

## 2. project.pbxproj — sandbox enabled, egress never requested

```
$ grep -n "ENABLE_APP_SANDBOX" CheckStitch.xcodeproj/project.pbxproj
497:				ENABLE_APP_SANDBOX = YES;
541:				ENABLE_APP_SANDBOX = YES;
```

`ENABLE_APP_SANDBOX = YES;` is set once each for the Debug configuration (block
headed `000000000000000111000000 /* Debug configuration for PBXNativeTarget "CheckStitch" */ = {`) and
the Release configuration (block headed
`000000000000000112000000 /* Release configuration for PBXNativeTarget "CheckStitch" */ = {`).

`ENABLE_OUTGOING_NETWORK_CONNECTIONS` appears nowhere:

```
$ grep -n "ENABLE_OUTGOING_NETWORK_CONNECTIONS" CheckStitch.xcodeproj/project.pbxproj
(no matches — verified count 0)
```

Confirmed by:
```
$ grep -c "ENABLE_OUTGOING_NETWORK_CONNECTIONS" CheckStitch.xcodeproj/project.pbxproj
0
```

Under App Sandbox, Xcode's macOS app-sandbox entitlements synthesis emits
`com.apple.security.network.client` only when
`ENABLE_OUTGOING_NETWORK_CONNECTIONS` is set. It is not set here, matching §1's
sandbox profile. iOS requires no such entitlement, which is why the photo still
loads on iPhone/iPad.

## 3. SDK unavailability — `ContainerBackgroundPlacement.navigation` does not exist on macOS

```
$ sed -n '16305,16320p' /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface
public struct ContainerBackgroundPlacement : Swift.Sendable, Swift.Hashable {
  @available(watchOS 10.0, *)
  @available(iOS, unavailable)
  @available(macOS, unavailable)
  @available(tvOS, unavailable)
  @available(visionOS, unavailable)
  public static let tabView: SwiftUI.ContainerBackgroundPlacement
  @available(watchOS 10.0, iOS 18.0, *)
  @available(macOS, unavailable)
  @available(tvOS, unavailable)
  @available(visionOS, unavailable)
  public static let navigation: SwiftUI.ContainerBackgroundPlacement
  @available(watchOS 11.0, iOS 18.0, *)
  @available(macOS, unavailable)
  @available(tvOS, unavailable)
  @available(visionOS, unavailable)
```

The `.navigation` placement's availability block is exactly the lines
`SwiftUI.swiftinterface:16312-16316` cited in `plan.md` deviation 1:
`@available(macOS, unavailable)` on line 16313 makes the symbol unusable on the
macOS platform — not merely deployment-target-gated, so no `#available` guard can
rescue it (`MACOSX27_DEPLOYMENT_TARGET = 27.0`).

The compile error recorded during the design step (plan.md deviation 1, captured
when compiling `.containerBackground(.clear, for: .navigation)` for macOS):

```
error: 'navigation' is unavailable in macOS
```

is the direct consequence of that annotation: the symbol does not exist on the
platform, so the designed `.navigation` container-clear is unbuildable on macOS
and is dropped from the plan (a `.window` placement exists on macOS 15+ but was
measured to change nothing — see §4).

## 4. Container non-cause — the macOS container is transparent (prime hypothesis falsified)

Recorded from the deviations verification (plan.md deviation 2; not re-run in
this phase — GUI/window probes):

- **Real-window render probe**: ContentView's exact layering rendered in a real
  `NSHostingView`/`NSWindow` (titled window, `ScrollView` rows, card plate,
  `safeAreaInset`, toolbar), sampling a grid of points, shows the photo through
  the stack **at every sample** — no opaque container is painting over it.
- **`ImageRenderer` probe**: `ZStack { photo; NavigationStack { … } }` renders
  with the photo visible.
- **`.containerBackground(.clear, for: .window)`** (macOS 15+, the only
  macOS-available placement) **changes nothing**.
- Conclusion: the comment at `ContentView.swift:55-58` ("macOS's stack is already
  transparent") is accurate and is retained. The failing layer is not the
  container.

## 5. Automated verification (Phase 1)

All three automated checks hold against the current tree:

| command | expected | actual |
|---|---|---|
| `codesign -d --entitlements - --xml DerivedData/Build/Products/Debug/CheckStitch.app \| grep -c "com.apple.security.network.client"` | `0` | `0` |
| `grep -c "ENABLE_APP_SANDBOX = YES;" CheckStitch.xcodeproj/project.pbxproj` | `2` | `2` |
| `grep -c "ENABLE_OUTGOING_NETWORK_CONNECTIONS" CheckStitch.xcodeproj/project.pbxproj` | `0` | `0` |

## 6. Standing evidence summary

The only *verified* macOS-only divergence in the photo path is the build
configuration: sandboxed macOS slice with no `ENABLE_OUTGOING_NETWORK_CONNECTIONS`,
hence no `com.apple.security.network.client` entitlement, hence the sandbox
blocks the photo fetch. The container hypothesis is falsified (§4) and the
`.navigation` container-clear is uncompilable on macOS (§3). The fix is therefore
one build setting (both sandboxed app-target configurations), pinned by a shell
regression test (Phase 2) and proven by the Phase 3/4 verifications.

⚠ Manual (user-run) items not recorded here: the signed-run visual check and the
`log stream` + **Refresh wallpaper** runtime diagnostic (`Background force
refresh failed: …` expected) belong to the manual verification list — see
`plan.md` Phase 1 Manual section and the implementation summary.

## 7. Post-fix record (Phase 4) — egress now requested and granted

Counterpart to §1–§2, recorded after the Phase 3 fix. The signed binary is a
fresh `make build-mac-signed` (mtime Sep 14 11:34 PDT) — the trailing unsigned
`make build-mac` gate leg overwrites the shared Debug product app, so this final
signed build is re-run after the gate to freeze the post-fix state.

### 7a. project.pbxproj — egress now set on both sandboxed app configurations

```
$ grep -n "ENABLE_OUTGOING_NETWORK_CONNECTIONS" CheckStitch.xcodeproj/project.pbxproj
498:				ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;
543:				ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;
```

Set once in the Debug block (header `000000000000000111000000`) and once in the
Release block (header `000000000000000112000000`), each a sibling of the existing
`ENABLE_APP_SANDBOX = YES;` (count 2 unchanged):

```
$ grep -c "ENABLE_APP_SANDBOX = YES;" CheckStitch.xcodeproj/project.pbxproj
2
```

```
$ grep -c "ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;" CheckStitch.xcodeproj/project.pbxproj
2
```

### 7b. Signed entitlements — `com.apple.security.network.client` now present

```
$ codesign -d --entitlements - --xml DerivedData/Build/Products/Debug/CheckStitch.app 2>&1 | grep -c "com.apple.security.network.client"
1
```

Xcode synthesizes `com.apple.security.network.client` from
`ENABLE_OUTGOING_NETWORK_CONNECTIONS`, so the sandboxed macOS slice can now open
outgoing URL connections — the `BackgroundImageStore` `GET https://vardy.cc/unsplash`
fetch is no longer denied, and `imageData` can populate so `BackgroundPhotoLayer`
paints the photo. iOS is unaffected (it never required the entitlement, and the
setting is a macOS app-sandbox synthesis knob with no effect on the iOS slices).

### 7c. Full gate — `gate: ok`

```
$ bash scripts/test.sh
…
ok: macos_slice_requests_outgoing_network
tests: 17 passed, 0 failed
gate: ok
```

Exit status 0. All legs green, in order: simulator `make build` (BUILD SUCCEEDED)
→ headless pre-boot of this worktree's simulator (`57260A5D-0A6E-40E0-B5FB-10491A2C1C8E`)
→ `make test` (unit: 127 tests in 24 suites, TEST SUCCEEDED; UI smoke: 1
CheckStitchUITests case, TEST EXECUTE SUCCEEDED via build-for-testing →
test-without-building) → unsigned macOS leg (BUILD SUCCEEDED) → watchOS
`make watch-build` (BUILD SUCCEEDED) → shell tests (`scripts/tests/run.sh`,
17/17 including the new `macos_slice_requests_outgoing_network` pin) → shellcheck.

### 7d. No Swift source changes across the whole ticket

The regression is fixed at the build-configuration layer; no Swift changed:

```
$ git diff origin/main..HEAD --stat -- 'CheckStitch/*.swift'
(empty)
```

The full ticket delta is `project.pbxproj` (+2: the egress setting), the Phase 2
shell pin in `scripts/tests/run.sh` (+18), and the step artifacts.

### 7e. Standing post-fix summary

Before: sandboxed macOS slice with no `ENABLE_OUTGOING_NETWORK_CONNECTIONS` (§1–§2)
→ no `com.apple.security.network.client` (§1) → photo fetch denied. After: the
setting is present in both app-target configurations (§7a), the signed
entitlements carry the network client key (§7b), the regression pin is green
(Phases 2/3), and the full gate passes (§7c) with zero Swift-source churn (§7d).
The only remaining items are manual (user-run) rendering proofs — plan.md Phase 4
Manual → the implementation summary.