# Task

Add a **Create Checklist** App Intent to CheckStitch: a Shortcuts.app action that creates a *stored* checklist (a template: name + item rows) in `ChecklistStore` from a required `name: String` and an `items: [String]` parameter. It must not touch Reminders or run anything — the existing Run Checklist intent runs it later. Full, binding decisions are in VAR-1116's "Decisions" (1–12); the plan step should follow them and the ticket's "Implementation notes" conventions.

Key behaviours to build:
- `CheckStitchCore/Sources/CheckStitchCore/CreateChecklistIntent.swift` holding `CreateChecklistIntent: AppIntent`, `CreateChecklistIntentError: LocalizedError` (`.blankName`, `.noItems`, `resolvedInAppLanguage()` like `RunChecklistIntentError`), and `CreateChecklistDialogue`. No `CheckStitchShortcuts.swift` change.
- A single-save store entry point `create(name:itemTitles:)` (one encode / one `onChange`, not N) — touches the store's public API and its tests.
- `ChecklistStore.reconcileFromDefaults()` reusing the existing `apply(remote:)` / `ChecklistMerge` seam and honouring `canAcceptRemoteChanges`; called from `MyApp`'s `scenePhase == .active` branch on **iOS and macOS** to fold in an App Group payload written while the app was backgrounded (decision 9). Suppress `onChange` while applying, then push explicitly; watch push rides the existing SwiftUI `store.checklists` change. Idempotent on cold launch.
- Name disambiguation via existing `uniqueName` ("Groceries" → "Groceries 2", case/trim-insensitive); blank/whitespace `name` throws `.blankName`; trim each item, drop empties, and throw `.noItems` if none survive. Never append, never dedup, no title-length clamp, items title-only matching `addItem(to:title:)`, store-default checklist fields. No purchase gate / free-run consumption.
- New keys in `Localizable.xcstrings` (all six languages) + `LocalizationFixtures.requiredKeys` (run `scripts/l10n-check.sh` first); exact text contract per Decision 10 (success dialog reports the *actual disambiguated* name + item count).
- New `CreateChecklistIntentTests` (Swift Testing, `@MainActor`, isolated defaults) and store tests for `reconcileFromDefaults()` (merges external write, idempotent cold launch, respects `canAcceptRemoteChanges`).

Two unverified facts to compile-verify first, with fallbacks: (a) `@Parameter var items: [String]` compiling/rendering as a Shortcuts list (else multiline String split on newline + comma); (b) an App Intents metadata entry being emitted for a `CheckStitchCore`-declared intent with no `AppShortcutsProvider` reference (else move the intent type into the app target — the only piece that moves). Verification: `make test-unit`, full gate `./scripts/test.sh` → `gate: ok`, signed build exercised through Shortcuts.app on a real device, plus duplicate/blank-name/no-items re-run checks.

## Why MEDIUM

MULTI_MODULE (and likely BROAD_TEST_SURFACE): touches the `CheckStitchCore` store's public API + `MyApp.swift` lifecycle on iOS and macOS + localization + multiple test suites — broad, but approach is fully known (M1: 0–2 unknowns, both with prescribed fallbacks) and no design decision is needed (M2: no schema/migration, no new subsystem, additive changes following existing `RunChecklistIntent` / `apply(remote:)` / `scenePhase` seams).

## Key files

- `CheckStitchCore/Sources/CheckStitchCore/CreateChecklistIntent.swift` (new) — `RunChecklistIntent`/`ListChecklistsIntent` are the pattern; `RunChecklistIntent`'s optional-injected-store seam.
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift` — add `create(name:itemTitles:)` and `reconcileFromDefaults()`.
- `CheckStitch/MyApp.swift` — `scenePhase == .active` reconcile hook (iOS + macOS).
- `Localizable.xcstrings` + `CheckStitchTests/LocalizationFixtures.swift` (`requiredKeys`).
- `CheckStitchTests/` — new `CreateChecklistIntentTests`, store `reconcileFromDefaults` tests; `TestFixtures.swift` for fakes.
- Reference: `/Users/vardy/dev/SingleThread` for `NSReminders*UsageDescription` keys (GENERATE_INFOPLIST_FILE = YES).