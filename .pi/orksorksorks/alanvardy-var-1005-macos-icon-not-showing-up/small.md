# Task

On macOS, the CheckStitch app shows a generic app icon, while iOS (and watchOS)
show the proper icon. Root cause: the shared app-target asset catalog
`CheckStitch/Assets.xcassets/AppIcon.appiconset/Contents.json` declares only an
iOS icon:

```json
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

But the `CheckStitch` target also builds a macOS slice
(`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` and the shared
build setting `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`), so the asset
catalog has no macOS icon to compile — macOS ends up with a generic icon.

Fix: add a macOS icon entry to that same `Contents.json` so the compiled asset
catalog serves a macOS icon (same 1024×1024 source `AppIcon.png`, or verify
whether macOS needs a dedicated opaque image), following the existing iOS
entry's pattern. Verify the fix by building the macOS slice (e.g. through the
existing `make` legs) and confirming the compiled app carries/renders the icon
(inspect the built .app's asset catalog / Info.plist icon keys, and that the
icon displays in Finder/Dock). Keep watchOS (`CheckStitchWatch`, its own
separate `AppIcon.appiconset`) and iOS untouched and passing the gate
(`bash scripts/test.sh`).

## Why SMALL

Single-file, localized change to an existing asset-catalog entry, following the
already-present platform-entry pattern; no schema, no new subsystem/integration
or shared convention risk, no design decision, and verification rides the
existing build/gate legs (no new test infrastructure).

## Key files

- `CheckStitch/Assets.xcassets/AppIcon.appiconset/Contents.json` — the only
  file that needs the change (add the `mac` idiom entry).
- `CheckStitch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` — the 1024×1024
  source image to reuse for macOS.
- `CheckStitch.xcodeproj/project.pbxproj` — read-only context: the shared
  `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` setting and
  `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` that make the fix
  apply to macOS; do not change the build settings themselves.
- Reference for how icons are declared per platform: the separate
  `CheckStitchWatch/Assets.xcassets/AppIcon.appiconset` (working, watchOS-only).
- Verify via `make build-mac` / `make run` and `bash scripts/test.sh` (gate).