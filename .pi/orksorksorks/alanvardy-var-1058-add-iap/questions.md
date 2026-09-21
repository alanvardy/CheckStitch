# Research Questions

## Context

CheckStitch is a Swift/SwiftUI iOS (plus macOS and watchOS) app that
bulk-creates Reminders checklists. It has a thin `CheckStitch/` app target, a
`CheckStitchCore/` sources-only SPM package (models, an EventKit seam, sync, and
view models), and a coordinated sync/run path used across iOS, macOS and watchOS.
Focus on the checklist execution flow, the durable state/sync mechanisms, and how
app-level state is layered and injected across targets.

## Questions

1. How does the checklist "run" flow work end-to-end? Trace every code path and
   call site that turns checklist items into reminders — the UI button, the voice
   intent, and the remote/sync coordinator — through `ChecklistCreator` /
   `ChecklistReminders`, including the returned success/failure outcomes and any
   in-flight guards. Where is a run defined as completed?

2. What durable persistence mechanisms exist in the app and core for storing
   small state (like counters or booleans)? Describe the App Group /
   `UserDefaults` wrapper (`AppGroup.swift`, entitlements), the
   `NSUbiquitousKeyValueStore`-backed `UbiquitousChecklistSync` (key
   `checklists.v1`), and `ChecklistStore`'s own persistence — how each is
   configured, what read/write/observe conventions they use, and which
   entitlements enable them.

3. How is application-level state layered and shared across the iOS, macOS, and
   watchOS targets? How does `MyApp.swift` construct and inject view models and
   services via `.environment(...)`, how do views observe and react to that
   shared state, and are there any existing examples of state-driven gating,
   locked/unlockable UI, or a dedicated purchase/entitlement surface?

4. What conventions exist for adding new stateful services/components and testing
   them? Describe the seams used (protocols vs concrete types, injection), the
   test suite layout and fixtures (`CheckStitchTests/`, `CheckStitchUITests/`),
   and how per-platform (iOS/macOS/watchOS) code and tests are gated. Where would
   a new cross-cutting service naturally live in the package/type structure?