# Research Questions

## Context

CheckStitch is a Swift/SwiftUI iOS app (plus macOS and watchOS) with two
code layers: a thin app target (views + platform delegates) and a local
SPM package, CheckStitchCore, holding models, the EventKit seam and a
partial view model. The purpose of this research is to establish exactly
how presentation vs domain behaviour is currently separated across the
views, the core package, the watch target and the test suites, and to
capture the MVVM shape used by a mirror repo (SingleThread) for comparison.
Nothing is being proposed or built; this is a factual survey of what exists
and how the layers connect.

## Questions

1. How does CheckStitch/ContentView.swift currently hold presentation and
   domain behaviour together? Trace its @State/@Environment usage, its
   list-mutating functions, the settings bridge, and the import/export
   flow, and map each point where it calls into the CheckStitchCore
   package. Also describe how CheckStitch/MyApp.swift wires the core
   objects into the view.

2. What does the CheckStitchCore package contain and how is it structured?
   Describe the models, the EventKit seam (ReminderCreating,
   ReminderDestinationTargeting), the checklist creator, the preference and
   state/width/numbering types (AppLanguagePreference, ChecklistWidth,
   SettingsBindings, SettingsDataActionQueue), and in particular the current
   partial ChecklistViewModel.swift — what it holds and how it relates to
   the views.

3. What MVVM shapes does the SingleThread mirror repo use? Trace its view
   model files (AppViewModel, ContentViewModel, WatchAppViewModel,
   WatchReminderViewModel, and any smaller view models), what state and
   handler methods each holds, how its ContentView delegates to view
   models, and how the app target, core package and watch target lay out
   their view-model code.

4. How are the CheckStitch test suites structured? For CheckStitchTests
   (Swift Testing) list the suite files, what each covers, and any
   platform gating (e.g. @MainActor, os(...) gating, whole-file gating);
   describe the single CheckStitchUITests XCTest smoke case. Note the
   naming/conventions used in the suites.

5. How is the CheckStitchWatch watchOS target structured? Describe what each
   of its files (the app, the two views, and the sync adapter) does and how
   its view logic relates to the CheckStitchCore package.

6. What are the project's canonical build, test, lint and gate commands and
   conventions? Trace the Makefile targets and scripts/test.sh gate
   ordering, the unit/vs UI test invocation (`make test-unit`, `make
   test-ui`) and any build/verify gotchas (simulator/destination pinning,
   macOS vs iOS platform legs, signing).