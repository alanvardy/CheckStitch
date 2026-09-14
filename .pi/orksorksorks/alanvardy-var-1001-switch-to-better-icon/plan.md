# Implementation Plan

## Overview

Mechanically regenerate CheckStitch's two app-icon asset catalogs from the
supplied artwork `~/Downloads/checkstitch2.png` (1254×1254 RGB PNG, no alpha)
using `sips`: the iOS/macOS app icon (`CheckStitch/`) and the watchOS icon set
(`CheckStitchWatch/`). Filenames and both `Contents.json` files stay byte-for-byte
unchanged; no Swift, entitlement, project, or test files are touched. The only
real risk is a malformed/mis-sized asset catalog failing the simulator, macOS,
or watchOS compile legs, so each phase is verified by compiling the catalog it
touches.

### Recon deltas from `medium.md`

- **Watch set has 17 images, not 16.** Besides the 16 legacy `Icon-*.png`
  files, `CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is a
  `watch-marketing` 1024×1024 entry and is regenerated in Phase 2. Leaving it
  stale would ship the old artwork on the watch App Store listing.
- **Alpha**: the source is RGB with no alpha (verified via `sips -g hasAlpha`).
  Rendered icons will have no alpha — correct for an App Store marketing icon.
  The existing app `AppIcon.png` currently *has* alpha; the replacement will
  not, which is a fix, not a regression.
- **No other references**: nothing in `CheckStitch/`, `CheckStitchCore/`,
  `CheckStitchTests/`, `CheckStitchUITests/`, `scripts/`, or the UI tests
  references icon files or `AppIcon` names. `project.pbxproj` already sets
  `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` for the app and watch targets
  and needs no edit. There is no `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`.
- The app target is a single iOS+macOS target (`SUPPORTED_PLATFORMS = "iphoneos
  iphonesimulator macosx"`); both slices compile the same
  `CheckStitch/Assets.xcassets/AppIcon.appiconset`. No separate macOS icon set.
- **`.bak` handling**: `medium.md` requires a `.bak` copy before overwriting.
  The originals are already committed, so `.bak` files are a working-tree safety
  net only — they must **not** be staged/committed, and are deleted once the
  full gate passes.

### Pixel-size mapping (filename number × scale)

| File | px | File | px |
|---|---|---|---|
| `AppIcon.png` (app) | 1024 | `Icon-50@2x.png` | 100 |
| `AppIcon.png` (watch) | 1024 | `Icon-51@2x.png` | 102 |
| `Icon-24@2x.png` | 48 | `Icon-54@2x.png` | 108 |
| `Icon-27.5@2x.png` | 55 | `Icon-86@2x.png` | 172 |
| `Icon-29@2x.png` | 58 | `Icon-98@2x.png` | 196 |
| `Icon-29@3x.png` | 87 | `Icon-108@2x.png` | 216 |
| `Icon-33@2x.png` | 66 | `Icon-117@2x.png` | 234 |
| `Icon-40@2x.png` | 80 | `Icon-129@2x.png` | 258 |
| `Icon-44@2x.png` | 88 | | |
| `Icon-46@2x.png` | 92 | | |

---

## Phase 1: App icon (iOS + macOS)

### Changes

#### 1. Back up the existing app icon

**File**: `CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png.bak`
**Action**: create (untracked copy, never staged)

```bash
cp -p CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
      CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png.bak
```

#### 2. Replace `AppIcon.png` from the source

**File**: `CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
**Action**: overwrite (resize 1254→1024 square; `Contents.json` untouched)

```bash
sips -s format png -z 1024 1024 ~/Downloads/checkstitch2.png \
  --out CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

### Verification

#### Automated
- [x] `sips -g pixelWidth -g pixelHeight -g hasAlpha CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` reports `pixelWidth: 1024`, `pixelHeight: 1024`, `hasAlpha: no`
- [x] `git diff --stat` shows only `CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (binary) changed — `Contents.json` unmodified
- [x] `make build` passes with no asset-catalog `warning:`/`error:` naming `AppIcon.appiconset`
- [x] `make build-mac` passes

#### Manual
- [ ] `make run` launches the simulator app; the new icon is visible on the home screen (spot-check none of the old red/other design remains)

### Commit

```bash
git add CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png
git commit -m "feat: replace app icon with new design (VAR-1001)"
```

(Tick the boxes above, then proceed to Phase 2.)

---

## Phase 2: Watch app icons (watchOS)

### Changes

#### 1. Back up the watch icon set

**File**: `CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/*.png.bak`
**Action**: create (untracked copies, never staged)

```bash
mkdir -p /tmp/checkstitch-watch-backup
cp -p CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/*.png /tmp/checkstitch-watch-backup/
# originals also committed in git history; in-tree .bak copies satisfy the task constraint
for f in CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/*.png; do
  cp -p "$f" "$f.bak"
done
```

#### 2. Regenerate every watch PNG at its exact current pixel size

**File**: `CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/` (17 PNGs)
**Action**: overwrite (one `sips` resize each; names + `Contents.json` untouched)

Run as a single bash script (`/tmp/resize-watch-icons.sh`, then `bash /tmp/resize-watch-icons.sh`) — fish cannot run this loop:

```bash
#!/bin/bash
set -euo pipefail
SRC="$HOME/Downloads/checkstitch2.png"
DIR="CheckStitchWatch/Assets.xcassets/AppIcon.appiconset"
# name:px — px is the current dimension of the file being replaced
resize() { sips -s format png -z "$2" "$2" "$SRC" --out "$DIR/$1" >/dev/null; }
resize AppIcon.png 1024
resize Icon-24@2x.png 48
resize Icon-27.5@2x.png 55
resize Icon-29@2x.png 58
resize Icon-29@3x.png 87
resize Icon-33@2x.png 66
resize Icon-40@2x.png 80
resize Icon-44@2x.png 88
resize Icon-46@2x.png 92
resize Icon-50@2x.png 100
resize Icon-51@2x.png 102
resize Icon-54@2x.png 108
resize Icon-86@2x.png 172
resize Icon-98@2x.png 196
resize Icon-108@2x.png 216
resize Icon-117@2x.png 234
resize Icon-129@2x.png 258
```

Every output is a downscale of a 1254×1254 square to a smaller square, so
aspect ratio and edge quality are preserved; `-s format png` keeps the
container. `Contents.json` lists each existing filename and must not change.

### Verification

#### Automated
- [x] One `sips` pass over the directory shows every PNG at the Phase 2 table sizes (e.g. `Icon-129@2x.png` = 258×258, `Icon-29@3x.png` = 87×87, watch `AppIcon.png` = 1024×1024) and `hasAlpha: no` for all
- [x] `sips -g pixelWidth -g pixelHeight CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/*.png` output counts 17 images with no dimension regressions
- [x] `make watch-build` passes with no asset-catalog `warning:`/`error:` naming the watch `AppIcon.appiconset`
- [x] `git diff --stat` shows only binary PNGs in `CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/` changed — its `Contents.json` unmodified
- [x] Full gate `./scripts/test.sh` prints `gate: ok` (this is the phase that exercises `make build`, `make test`, `make build-mac`, `make watch-build`, shell tests, shellcheck)

#### Manual
- [ ] `bash scripts/run-watch.sh` (or the simulator via `make watch-build` inspector) shows the new icon for the watch app; no old artwork remains

### Cleanup and commit

```bash
# remove the in-tree .bak safety copies (originals remain in git history)
find CheckStitch/Assets.xcassets/AppIcon.appiconset CheckStitchWatch/Assets.xcassets/AppIcon.appiconset -name '*.bak' -delete

git add CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/*.png
git commit -m "feat: replace watch app icons with new design (VAR-1001)"
```

---

## Final: gate and PR

- [x] `./scripts/test.sh` passes end to end (`gate: ok`) on the final commit (ran in Phase 2 on the Phase 2 tree; commit `8e3c7a0` content == gated tree)
- [x] `git status` is clean apart from untracked planning artifacts; no `*.bak` staged or present
- [x] `git diff --stat origin/main...HEAD` touches only the 18 PNGs (1 app + 17 watch) — no code, entitlements, project, or test changes
- [ ] Push the branch and open one PR against `main`; merge with `gh pr merge <n> --rebase --delete-branch`