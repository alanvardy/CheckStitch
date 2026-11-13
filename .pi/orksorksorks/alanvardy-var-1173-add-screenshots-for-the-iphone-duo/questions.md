# Research Questions

## Context
This survey covers the App Store screenshot capture pipeline under `scripts/`, the
app-side display and layout detection (including any foldable/outer-display code),
the orientation contract on iOS, the launch-argument / persisted-defaults seams that
drive app state during automated runs, the wallpaper slot and manifest system, and
how the repo's shell and unit tests validate all of it. All questions concern the
current CheckStitch checkout at this branch.

## Questions
1. How does `scripts/appstore-screenshots.sh` currently work end to end: how are
   device classes, screen slots, appearance, languages, CLI flags, output-tree
   layout, manifest writing, and pixel-dimension verification defined and invoked?
   Trace the flow with `file:line` references.
2. What launch-argument and persisted-`UserDefaults` seams exist for priming app
   state during automated runs (content seeds, appearance, language, settings,
   open-screen selection), and how does the screenshot script use them today?
   Include how `LaunchSeams` is parsed, stored, and consumed.
3. Where does the app detect the iPhone Duo outer display and adjust layout, how
   does it identify the machine and size class, and what happens on non-Duo
   hardware? Note whether any inner-panel, pose, hinge, or landscape handling
   exists, with `file:line` references.
4. How does the iOS app declare and control interface orientation: where supported
   orientations are advertised, how the user's landscape preference is persisted
   and applied, how orientation changes are requested at runtime, and how the
   Info.plist / project configuration participates? Trace with `file:line`
   references.
5. How are wallpaper slots and the wallpaper manifest defined, fetched, staged into
   the app container, and referenced per class and per screen? Include the manifest
   schema, slot-naming convention, and the fixture directory layout.
6. What shell-script test infrastructure exists in `scripts/tests/`, and what cases
   currently cover `scripts/appstore-screenshots.sh` (stubs, assertions, dimension
   checks, CLI validation, bash-version constraints)?
7. How are unit tests structured for the launch seams, Duo display detection,
   checklist layout, and orientation preference (file layout, Swift Testing
   conventions, `@MainActor` usage, shared fixtures), and what does the UI-test
   seam coverage look like?
