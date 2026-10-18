# Research Questions

## Context

Focus on the CheckStitch iOS/watch app targets, the `CheckStitchCore` package,
the UI test target, the `scripts/` directory and its test harness, localization
state, and the single reference script in the SingleThread checkout. The areas
of interest are app startup and dependency injection, persistence and seeding
of checklist data, the watch app's data path, existing simulator/build tooling
and shell-script conventions.

## Questions

1. How does app startup work in `CheckStitch/MyApp.swift` and
   `CheckStitch/ContentView.swift` — what environment objects and view models
   are constructed, how is the root screen chosen, and what determines whether
   the list, empty state, or settings/options screens are shown?

2. How are checklists persisted and loaded (store type, storage location, app
   group / key-value store usage, codecs), and what initialization path would
   populate the in-memory store at launch?

3. What is the structure and data flow of the watch target (`CheckStitchWatch`)
   — its app entry point, view models, sync adapter, screens, and how it obtains
   checklist data?

4. What launch-argument, environment, or process-info handling exists anywhere
   in the app, core package, or UI test target, and how does the single UI test
   launch the app?

5. How do the existing `scripts/*.sh` files work — the gate driver, simulator
   resolution/boot/install/launch helpers, the shell test harness and its
   stubs, shellcheck expectations, and the Makefile build/test/simulator
   targets?

6. How is the app language selected at runtime (`AppLanguage`, `AppLocaleState`,
   `\.locale`, string catalogs, `.lproj` resources), and how do the six
   supported languages map to locale identifiers?

7. How does the reference script `/Users/vardy/dev/SingleThread/scripts/appstore-screenshots.sh`
   work — its arguments, device/display-class handling, launch-argument seams,
   capture mechanism, per-language loop, and output layout?
