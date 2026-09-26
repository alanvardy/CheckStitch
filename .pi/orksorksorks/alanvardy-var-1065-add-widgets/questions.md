# Research Questions

## Context

CheckStitch is a Swift/SwiftUI app (iOS, macOS, and watchOS targets) that turns
checklists into Reminders. Focus areas: the checklist domain model and
persistence, the flow that turns a checklist into reminders, the existing
out-of-app invocation surface (Siri/App Intents) and checklist-selection UI,
the per-platform build/delivery and entitlement model, and the platform widget
framework available on the target OS. Do not reference the goal of the task;
answer only what exists and how it works.

## Questions

1. Trace the full flow from a stored checklist id to created reminders:
   how `ChecklistStore`, the run view model, the run gate (purchase + run
   counter), `ChecklistCreator`, and the EventKit reminder destination
   connect. What are the entry points, thread-model / `@MainActor`
   constraints, and side effects at each stage?

2. How does the existing out-of-app invocation surface work — the Siri/App
   Intents (`RunChecklistIntent`, `ListChecklistsIntent`, `ChecklistEntity`)
   and anything similar that runs a checklist without the main ContentView?
   How do they construct and access the checklist store, run a checklist, and
   what are their `@MainActor`, lifecycle, and error-handling requirements?

3. What persistence and ownership patterns exist for the checklist store —
   how `ChecklistStore` is constructed, whether there is a shared/singleton
   instance or an owned lifetime, and how the App-Group KV store (UserDefaults)
   and the KVS sync (`ChecklistSyncService` / coordinator) are initialized and
   owned? What would an independent caller need to open the same store?

4. What UI patterns exist for selecting and launching checklists —
   `ChecklistSelectionView`, the list-picker, `ContentView` navigation, and
   how single-selection versus multi-item selection is handled? How are
   checklist names/entities surfaced to the user?

5. What widget frameworks exist on the target OS (iOS and/or macOS) that
   provide user-visible "widgets" with fixed small and large size classes and
   that can be bound to an app action? Cover the SDK/API, size classes,
   packaging/model, and whether the app runs in-process or via the widget
   host. This is a web-research question about the platform's own offering.

6. How is the project built and delivered for each target (iOS app, macOS app,
   watchOS), and what runtime/entitlement constraints apply (App Group,
   key-value store identifier, signing, provisioning flags, Makefile targets)?
   Where would a new per-platform surface be introduced and how is it gated?