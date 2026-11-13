# Task

Extend CheckStitch's App Store screenshot pipeline (`scripts/appstore-screenshots.sh`
plus its wallpaper manifest/fixtures) with an `iphone-duo` device class that captures
the same five screens as the existing `iphone-6.3` class in four variants: Duo outer
portrait, outer landscape, inner portrait, and inner landscape. Because the Duo's
inner/outer panels, poses, and forced orientation do not exist in this repo's script
or app launch seams, the work also adds the supporting app-side launch seams (forced
Duo-outer context, forced orientation) and their tests. `/Users/vardy/dev/SingleThread`
(branch `alanvardy-var-1172-add-screenshots-for-the-iphone-duo`, notes at
`.pi/orksorksorks/alanvardy-var-1172-add-screenshots-for-the-iphone-duo/done.md`)
holds a completed implementation of the same shape to port from, adapted to
CheckStitch's five-screen set (`main-dark`, `empty`, `settings`, `main-light`, `detail`).
