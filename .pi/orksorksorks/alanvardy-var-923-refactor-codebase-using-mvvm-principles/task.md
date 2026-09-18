# Task

Refactor the CheckStitch Swift/SwiftUI codebase to follow MVVM
(Model-View-ViewModel) principles, mirroring the completed SingleThread
refactor (VAR-697 / PR #100). Today the app's logic-heavy screen
(CheckStitch/ContentView.swift, ~757 lines) holds a large amount of
presentation and domain behaviour in-place via @State and @Environment,
while the CheckStitchCore SPM package already holds models, the EventKit
seam, the checklist creator and a partial ChecklistViewModel.swift. The
refactor moves presentation/domain behaviour out of the views into view
models (keeping only presentation in the views), threading the same
layering through the app target, CheckStitchCore, the test suites
(CheckStitchTests, CheckStitchUITests) and the watchOS target
(CheckStitchWatch), following the SingleThread MVVM shape. No real refactor
has landed yet on this branch.