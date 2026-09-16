# Research Questions

## Context

The repo is a Swift/SwiftUI iOS app (CheckStitch) with a local Swift package
`CheckStitchCore` holding the persistent `ChecklistItem` model, a
key-value-backed store, a line-by-line merge, a sync service, and
import/export. This research maps the `ChecklistItem` data model and its
`Codable` codec and per-field sync clocks, the store mutation and merge
machinery, the codec back-compat test patterns, the SwiftUI patterns for
per-row controls and small value pickers, and the test/build gate
conventions.

## Questions

1. How is the `ChecklistItem` struct in
   `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` modeled — its
   fields, its `Codable` `CodingKeys`/`decode`/`encode` behaviour (including
   how absent keys decode, and how optional fields like `relativeDate`
   serialise including `encodeNil`), and how the per-field
   revision/modifiedAt sync clocks are seeded and stamped? Include how
   extension files like `ChecklistItem+DueDate.swift` add behaviour to the
   struct.

2. How do the item mutators and load/save paths in
   `CheckStitch/ChecklistStore.swift` work — what does each of `addItem`,
   `updateItem`, `updateItemDescription`, `updateItem(relativeDate:)`,
   `removeItems`, `moveItems`, `delete` stamp (coarse revision/modifiedAt and
   field clocks), how are the KV persistence and debounced save scheduled,
   and how does `init` classify/migrate on load? Also: how do `duplicate`,
   `freshCopy`, `importInsert` and `importReplace` handle items?

3. How does the line-by-line merge in `CheckStitch/ChecklistMerge.swift`
   resolve concurrent edits — what exactly does `mergedItems` compare per
   field (coarse clock vs field clocks), how does `wins(revision, date,
   device)` pick a winner, how are tombstones and order reconciled, and how
   does `store.apply(remote:)` fold a merged result in?

4. What test patterns and fixtures cover codec/back-compat (old payloads
   still loading, additive optional field with absent key, encoder writing
   every key, codec version classification/migration)? Which test
   files/functions assert these, and are there legacy JSON/Swift payload
   fixtures committed anywhere?

5. What SwiftUI primitives are used across `CheckStitch/` for small value
   pickers and overlay panels: every use of `Picker`, `.overlay`, `.sheet`,
   `CardPlate`, `alert`/`confirmationDialog`, and `NavigationLink` row
   rendering — with accessibility identifiers — and how does
   `ItemEditView` structure its `Form` and get reached from the checklist
   detail screen?

6. What are the canonical build/test/verify commands (Makefile targets,
   `scripts/test.sh`, `scripts/tests/run.sh`) and the test-suite inventory
   with platform gating (`#if os(...)`, `@Suite(.serialized)`, XCTest vs
   Swift Testing, `@MainActor` usage), plus known gotchas (simulator lock,
   `CODE_SIGNING_ALLOWED`, destination pinning)?