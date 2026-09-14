# Task

Replace CheckStitch's app icons with the new design supplied at
`~/Downloads/checkstitch2.png` (a 1254×1254 RGB PNG, present on disk). The
source `~/Downloads/checkstitch2.png` is the only accepted artwork — do not
redesign or retouch it.

Two icon sets must be regenerated:

1. **App icon (iOS/macOS)** — `CheckStitch/Assets.xcassets/AppIcon.appiconset/`
   currently holds a single `AppIcon.png` plus `Contents.json` (single-size
   set). Replace the icon content from the source PNG, keeping the
   `Contents.json` structure and filenames valid.
2. **Watch app icon (watchOS)** — `CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/`
   currently holds 16 legacy-sized PNGs (`Icon-24@2x.png`, `Icon-27.5@2x.png`,
   `Icon-29@2x.png`, `Icon-29@3x.png`, `Icon-33@2x.png`, `Icon-40@2x.png`,
   `Icon-44@2x.png`, `Icon-46@2x.png`, `Icon-50@2x.png`, `Icon-51@2x.png`,
   `Icon-54@2x.png`, `Icon-86@2x.png`, `Icon-98@2x.png`, `Icon-108@2x.png`,
   `Icon-117@2x.png`, `Icon-129@2x.png`) plus `Contents.json`. Regenerate each
   PNG at its nominal point size ×2 from the source PNG (mechanical `sips`
   resize per existing name/size), leaving filenames and `Contents.json`
   untouched unless a size must change.

Constraints:

- Copy the existing icon files to `.bak` before overwriting (no undo for
  overwritten assets).
- Keep the `.appiconset` structure and `Contents.json` valid; Xcode's build
  must not warn/error on a malformed icon set.
- Touch nothing else: no app code, entitlements, reminder logic, or tests.
  The gate remains `./scripts/test.sh` — the swap must keep `make build`,
  `make build-mac`, and `make watch-build` green (watch assets are compiled
  against the watchOS SDK, so a malformed watch icon fails the gate).
- One PR against `main`, merged with `--rebase`.

## Why MEDIUM

MULTI_MODULE (breadth trigger 7): the swap spans two platform targets'
asset catalogs and ~19 asset files (app icon + 16 watch icons), and the
watchOS build gate checks the result. M1 holds (approach is a known
mechanical regeneration following the existing per-size naming pattern — no
new technology, no unknowns) and M2 holds (no schema/design decision; the
artwork is supplied and the layout is fixed). Not SMALL: breadth trigger 7
fails criterion A.

## Key files

- Source: `~/Downloads/checkstitch2.png` (1254×1254 RGB PNG)
- `CheckStitch/Assets.xcassets/AppIcon.appiconset/` — `AppIcon.png`, `Contents.json`
- `CheckStitchWatch/Assets.xcassets/AppIcon.appiconset/` — 16 `Icon-*.png` files, `Contents.json`