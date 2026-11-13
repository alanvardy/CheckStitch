# Task

Extend CheckStitch's App Store screenshot pipeline (`scripts/appstore-screenshots.sh`
plus its wallpaper manifest/fixtures) with an `iphone-duo` device class that
captures the same five screens as the existing `iphone-6.3` class in four
variants: Duo outer portrait, outer landscape, inner portrait, inner landscape.
The Duo's inner/outer panels and poses (`folded` / `book` / `open`) and
orientation control do not exist in this repo's script or app seams, so the
work also needs the supporting app-side launch seams (forced Duo-outer context,
forced orientation) and their tests. `/Users/vardy/dev/SingleThread` (branch
`alanvardy-var-1172-add-screenshots-for-the-iphone-duo`, notes at
`.pi/orksorksorks/alanvardy-var-1172-add-screenshots-for-the-iphone-duo/done.md`)
holds a completed implementation of the same shape to port from, adapted to
CheckStitch's five-screen set (`main-dark`, `empty`, `settings`, `main-light`,
`detail`) rather than SingleThread's six.

## Why LARGE

Triggers: **UNKNOWNS**, **NEW_SURFACE**, **CONVENTION_RISK**, **CROSS_CUTTING
(unknown ordering)**. The screenshot pipeline has no orientation, `--display`,
or pose concept at all — inner/outer capture and forced orientation are a new
integration surface requiring research (the Duo panel/pose behaviour, which
parts are pose-driven vs orientation-driven, and whether the existing
`DuoDisplay`/`DuoOuterPortrait`/`ChecklistLayout` code already suffices); the
change spans the script, the shared wallpaper-manifest/fixture format, and the
app's `LaunchSeams`/`AppDelegate` orientation contract, with no existing
pattern in this repo to dictate the layering.
