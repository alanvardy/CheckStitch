# Done

## Corrected follow-up (VAR-987)

The first attempt (`2142b06`) added the asset catalog but **shipped no icon**:
`actool` rejected the `Contents.json` entry as an unassigned child, produced no
`Assets.car`, and emitted an empty `assetcatalog_generated_info.plist`. The
watch bundle had no icon data and no `CFBundleIcons`. The original
compile-only verification could not catch this.

- **Root cause**: `{"idiom": "watch", "platform": "watchos", "size": "1024x1024"}` is invalid — the `watch` idiom does not accept a bare 1024×1024 size, and `platform` only applies to the `universal` single-size recipe. `actool` warns *"The app icon set 'AppIcon' has an unassigned child"* and drops it. Reproduced directly against `WatchOS26.5.sdk`: the `watch` variant yields an empty partial Info.plist and no `Assets.car`; the `universal` variant yields `CFBundleIcons` → `CFBundlePrimaryIcon` → `CFBundleIconName = AppIcon` plus `Assets.car`.
- **What was built**: replaced the single-entry recipe with the **complete watchOS `AppIcon` set** (17 slots: `notificationCenter` 38/42/45mm, `companionSettings` 2x/3x, `appLauncher` 38/40/41/44/45/49mm, `quickLook` 38/42/44/45/49mm, `watch-marketing`). Every PNG is generated from the repo's canonical 1024×1024 master (`CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png`) via CoreGraphics, flattened onto the icon's own black background and written **opaque** (`hasAlpha: no`) — the master carried an alpha channel, and watchOS app icons must not.
- **Commit SHA(s)**: `2142b06` — `feat: add app icon to the watch target (VAR-987)` (original, superseded) + this correction commit (pushed to `origin/alanvardy-var-987-watch-app-doesnt-have-an-icon`).
- **Verification**:
  - `actool` (watchOS 26.5 SDK, `--target-device watch --app-icon AppIcon`) → zero warnings, `Assets.car` + `CFBundleIcons`/`CFBundleIconName = AppIcon` in the partial Info.plist.
  - `make watch-build` → BUILD SUCCEEDED; `Debug-watchsimulator/CheckStitchWatch.app/Assets.car` = 1.1 MB, Info.plist carries `CFBundleIcons`, `assetutil` reports **17** `Icon Image` renditions.
  - Device slice: `run-watch.sh` built `Debug-watchos/CheckStitchWatch.app` (BUILD SUCCEEDED) with the same 1.1 MB `Assets.car`, `CFBundleIcons`, and 17 renditions.
  - `sips` confirms all 17 PNGs are the expected pixel size with `hasAlpha: no`.
  - `./scripts/test.sh` → `gate: ok` (16/16 shell tests).
- **On-device confirmation: ✅ done.** After a rebuild + reinstall via `./scripts/run-devices.sh` (the `r` alias) the icon is visible in the iPhone Watch app. Closing note for reviewers below.

## Deployment note (why the fix looked "not working" for a while)

`./scripts/run-devices.sh` installs **only the iOS app** — its device filter is
`if hardware.get("platform") != "iOS": continue`, and it installs
`…-iphoneos/CheckStitch.app`. The watch app travels only as the embedded
`CheckStitch.app/Watch/CheckStitchWatch.app`; `devicectl` does not push an
embedded watch app onto a watch, so the watch keeps whatever build it already had
until the iPhone Watch sync (or the Watch app's *Show App on Apple Watch* toggle)
delivers it. `bash scripts/run-watch.sh` is the direct path and needs the
Mac↔watch developer tunnel (`RemotePairingError 1007/1034` while it was down).

Consequence for verification: a bundle-level check proves the art is correct but
never that it reached the watch — the same trap the original `2142b06` fell into
from the other direction (it asserted the catalog compiled, never that it
contained an icon). On-device eyes are the only real gate for this ticket.