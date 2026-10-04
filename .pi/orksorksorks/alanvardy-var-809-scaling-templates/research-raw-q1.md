# QUESTION 1 — mutable scalar fields on Checklist / ChecklistItem, mutation & convention

## Model declarations
- `ChecklistItem` (Checklist.swift:25-125):
  - Whole-item clocks: `var modifiedAt: Date`, `var revision: Int` (lines 44-45).
  - Per-field clocks: `titleRevision/titleModifiedAt`, `descriptionRevision/descriptionModifiedAt`, `relativeDateRevision/relativeDateModifiedAt`, `priorityRevision/priorityModifiedAt` (lines 50-60).
  - Scalar fields: `title: String`, `description: String` (init line 27, decl 42-43), `relativeDate: Int?` (decl ~47), `priority: ChecklistItemPriority` (decl ~60). `id` is `let` (line ~41).
  - Public init (lines 26-37) seeds each nil field clock from the coarse clock (`titleRevision ?? revision`).
- `Checklist` (Checklist.swift:147-190, impl 195+):
  - Coarse clock `modifiedAt`/`revision` (decl ~182-183) shared by checklist-level scalar fields: `name`, `destinationListIdentifier: String?`, `prefixesReminderNumbers: Bool` (decl ~167), `showsOnWatch: Bool` (decl ~173), `folderID: UUID?` (decl ~179). `itemOrder`/`orderRevision`/`orderModifiedAt` are a separate ordering clock.
  - Checklist doc note (lines 132-136): checklist-level clocks describe the record only; item ops do NOT bump the checklist revision/modifiedAt.

## Codec (each model implements its own Codable init/encode)
- `ChecklistItem.init(from:)` (Checklist.swift:109-143): title/description decode via `decodeIfPresent ?? ""` (lines 115-116); coarse clocks `?? .distantPast`/`?? 0`; per-field clocks seeded `?? revision`/`?? modifiedAt` (lines 122-128); priority `?? .none` (line 131). encode (145-166) writes every key, incl explicit `encodeNil` for optional relativeDate (lines 153-158).
- `Checklist.init(from:)` (Checklist.swift:229-263): date/revision `?? default`; additive optional fields decode to defaults (no version bump). encode (265-289) writes folderID unconditionally via encodeNil when nil.

## Mutation entry points — ChecklistStore (ChecklistStore.swift)
- `rename(id:to:)` (~243-256): guard found; bump `revision += 1` + `modifiedAt = now()`; `scheduleSave()`.
- `setDestination(_:for:)` (~295-306): same coarse-clock bump pattern.
- `setPrefixesReminderNumbers(_:for:id:)` (~311-323): **no-op guard** `guard current != new else { return .updated }` then coarse-clock bump (no spurious LWW win).
- `setShowsOnWatch(_:for:id:)` (~327-343): same no-op guard + coarse-clock bump.
- `moveChecklist(id:toFolder:)` (~486-500): unchanged membership is a no-op; else bumps coarse clock.
- Item field setters:
  - `updateItem(…title:)` (~369-381): bump `revision += 1`, `modifiedAt`, PLUS field-own clock `titleRevision = revision`, `titleModifiedAt = revisedAt`.
  - `updateItemDescription` (~386-399): same, stamps `descriptionRevision/descriptionModifiedAt`.
  - `updateItem(…relativeDate:)` (~405-421): **no-op guard** `guard current != new else { return }`, stamps `relativeDateRevision/relativeDateModifiedAt`.
  - `updateItem(…priority:)` (~427-440): same discrete-pick no-op guard, stamps `priorityRevision/priorityModifiedAt`.
  - Item ops use debounced `scheduleSave()`; create/remove/move use immediate `save()`. Item member mutations never bump the checklist coarse clock.
- Additive field readers on ChecklistItem are computed, not stored: `hasDescription` (lines 63-67), `isBlank` (lines 69-72).

## Bindings (UI layer, CheckStitch app target)
- `ChecklistDetailView.swift`: rename via `store.rename` (lines 214, 227); `setPrefixesReminderNumbers` bound as `set:` (line 267).
- `ItemEditView.swift`: title via `store.updateItem(…title:)` (line 104); priority (line 117); relativeDate (line 162).

## Trio of places a NEW scalar field must touch
1. Model declaration — Checklist.swift: stored `var` field + init param + optional per-field clock vars (+ CodingKeys).
2. Codec — same file init(from:)/encode(to:) (and `migrated(at:)` to seed history).
3. Mutation entry point — ChecklistStore.swift: a set…/updateItem method following no-op-guard + revision/modifiedAt (and per-field clock) bump + scheduleSave/save.

## Note
`migrated(at:)` (Checklist.swift:291-323) seeds each new/legacy field clock from the coarse clock on upgrade — a new scalar field must also be seeded there to avoid granting a spurious LWW win to pre-upgrade payloads.
