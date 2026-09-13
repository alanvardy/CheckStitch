# Task

The Apple Watch companion app (target `CheckStitchWatch`, bundle id
`app.alanvardy.CheckStitch.watchkitapp`) shows no icon in the Watch app on
iPhone. Give it an app icon: add a watch `Assets.xcassets` asset catalog under
`CheckStitchWatch/` containing an `AppIcon.appiconset` (a universal 1024×1024
`idiom: "watch"` `AppIcon.png` + trimmed `Contents.json`, mirroring the
existing iOS recipe), and set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
on the watch Debug/Release build configs if the project-level setting
(`project.pbxproj:353`/`:424`) proves insufficient once a catalog exists.

This is the follow-up VAR-951 explicitly deferred: its plan kept
`ASSETCATALOG_COMPILER_APPICON_NAME` unset "until a catalog exists"
(`.pi/orksorksorks/alanvardy-var-951-get-the-apple-watch-app-running-on-device/plan.md`).
Do not touch `CheckStitchCore`, the iOS target, scripts, or tests; the
`make watch-build` step in the gate is the verification that the watch target
still compiles. Derive the icon artwork from the existing 1024×1024 master
`CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (prefer the
repo's canonical master over external sources). Reference the sibling repo
`/Users/vardy/dev/SingleThread/SingleThreadWatch/Assets.xcassets/AppIcon.appiconset/`
for the exact watch recipe (idiom `"watch"`, per-size roles, marketing icon)
and its watch-target pbxproj `ASSETCATALOG_COMPILER_APPICON_NAME` setting.

## Why SMALL
A–F all hold: single target, ~3–5 files following the repo's own VAR-899 icon
wiring pattern; 0–2 mechanical unknowns (target-level vs inherited setting,
single-size vs multi-role recipe) with a concrete reference implementation in
SingleThread; no schema, no new subsystem or shared-code risk; no human
sign-off; no new test surface (the existing gate's watch-build covers it).

## Key files (found by recon)
- `CheckStitch.xcodeproj/project.pbxproj` — watch Debug/Release configs
  (`:664–690`, `:692–718`) for the `ASSETCATALOG_COMPILER_APPICON_NAME`
  setting; project-level setting currently at `:353`/`:424`; synchronized
  group `:78–82`, `:221–223` auto-picks up new files under `CheckStitchWatch/`.
- `CheckStitch/Assets.xcassets/AppIcon.appiconset/` — the iOS recipe to copy
  (single `idiom: "ios"`, `1024x1024` universal entry + `Contents.json`).
- `CheckStitchWatch/` — currently 4 Swift files, no asset catalog; new
  `Assets.xcassets/` lives here.
- `/Users/vardy/dev/SingleThread/SingleThreadWatch/Assets.xcassets/AppIcon.appiconset/` —
  reference watch recipe (18 per-size `idiom: "watch"` PNGs + watch-marketing
  `AppIcon.png`) and its pbxproj `ASSETCATALOG_COMPILER_APPICON_NAME` wiring.
- Verification: the gate's `make watch-build` (scripts/test.sh) compiles the
  watch target for watchOS.