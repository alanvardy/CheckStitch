# Structure Outline

## Approach

Clone the existing checklist-scalar path (`prefixesReminderNumbers`) for a new
`multiple: Int` field, add a sibling pure `ChecklistScaling.resolve` next to
`ChecklistTitleNumbering`, and thread the effective multiple through the two run
paths, the read-only renderers, and the intent. Everything is vertical: field →
store → run/render → user-visible outcome. No schema phase — the field is
additive Codable (`decodeIfPresent ?? 1`, **no** `ChecklistCodec.currentVersion`
bump) and the resolver is net-new, so no horizontal milestone exists.

## Phase 1: Walking skeleton — set a multiple and run a checklist with a scaled marker

**Outcome**: On the detail screen the user sets Scaling to `2`; running the
checklist creates reminders whose titles/notes have `((n))` replaced by
`n × multiple` (title scaled **then** prefixed by the existing positional
number; description scaled directly). Stored text is untouched.
Green tests prove: field persists (codec round-trip), setter bumps the coarse
clock once, resolver is pure, and the production run path consumes it.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`.../ChecklistStore.swift`, `.../ChecklistCreator.swift`,
`.../ChecklistReminders.swift`, `CheckStitch/ChecklistDetailView.swift`,
`CheckStitch/Localizable.xcstrings` + `CheckStitchTests/LocalizationFixtures.swift`.

**Key changes**:
- `Checklist.multiple: Int` — new scalar (init param default `1`, CodingKeys,
  decode `decodeIfPresent(Int.self) ?? 1` then clamp, encode every key,
  `migrated(at:)` seeds its clock).
- `Checklist.multipleRange: ClosedRange<Int> = 1...99` — new shared constant
  (Stepper bound, store clamp, intent validation all read it).
- `enum ChecklistScaling { static func resolve(_ text: String, multiple: Int) -> String }`
  — new; `((` + 1+ ASCII digits + `))` → `n × multiple`, everything else byte-for-byte;
  immediate passthrough when `multiple == 1`; digit overflow treated as non-match.
- `ChecklistStore.setMultiple(_ newValue: Int, for id: UUID) -> MutationOutcome`
  — new; clamp to `multipleRange` → no-op guard → coarse `revision`/`modifiedAt`
  bump → `scheduleSave()` (clone of `setPrefixesReminderNumbers`).
- `ChecklistReminders.create(from:targeting:gate:multipleOverride: Int? = nil)`
  and `ChecklistCreator.create(from:multiple: Int = 1)` — modified; effective
  multiple = `multipleOverride ?? checklist.multiple`; scale-before-prefix.
- `ChecklistDetailView` Scaling `Section` with
  `Stepper(value:in: Checklist.multipleRange, set: { store.setMultiple($0, for: id) })`,
  placed by the numbering toggle.

**Contract**: `ChecklistScaling.resolve(_:multiple:)` (String→String, `1` fast
path), `Checklist.multiple`, `Checklist.multipleRange`,
`ChecklistReminders.create(...multipleOverride:)` (default-nil). Phases 2–4
depend only on these.

**Tests**: `ChecklistCreatorTests` — marker digits, `((0))`→0, unmatched /
non-numeric left literal, overflow left literal, `multiple == 1` passthrough,
scale-then-prefix order. `ChecklistCodecTests` — round-trip, missing key → 1,
out-of-range payload clamped. `ChecklistStoreTests` — `setMultiple` no-op guard,
clamp, coarse revision bump. `ChecklistRemindersTests` — title + description
scaled on Path A; numbering still applied.
**Verify**: `make test-unit` green; `make build`.

---

## Phase 2: Read-only surfaces render scaled text, with a `×N` row badge

**Outcome**: The iOS/macOS row and the Watch detail show resolved title **and**
description without running the checklist; rows show a `×N` badge when
`multiple > 1`; `ItemEditView` still shows raw `((n))`. Value: preview the
scaling before committing a run.

**Files**: `CheckStitch/ChecklistDetailView.swift` (`ItemRow` + its callers),
`CheckStitchWatch/WatchChecklistDetailView.swift`, `CheckStitch/Localizable.xcstrings`,
`CheckStitchTests/LocalizationFixtures.swift`.

**Key changes**:
- `ItemRow(... multiple: Int)` — new parameter; renders
  `ChecklistScaling.resolve(title, multiple:)` /
  `ChecklistScaling.resolve(description, multiple:)`.
- `×%lld` factor badge (new App key), in the title HStack, only when
  `multiple > 1` (priority-marker pattern).
- `WatchChecklistDetailView` renders resolved title/description; no badge.

**Contract**: `ItemRow` init shape; `ChecklistScaling.resolve` reused unchanged.

**Tests**: `ChecklistDetailViewTests`/`ViewRenderTests` — resolved
title+description, badge present `>1` / absent at `1`, badge hidden at `1`;
Watch render suite — scaled text; `LocalizationTests` — badge key in 6 languages.
**Verify**: `make test-unit`; `make watch-build`; `scripts/l10n-check.sh`;
`make test-ui`/visual `make run` check.

---

## Phase 3: Persistence integrity — multiple survives duplicate, export/import, merge

**Outcome**: Duplicating a scaled checklist, sharing/exporting it, re-importing
it, or receiving a remote merge keeps its multiple (out-of-range payloads clamp
to `1...99`).

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
(`duplicate`/`freshCopy` carry lists); tests only elsewhere.

**Key changes**:
- `duplicate(id:name:)` / `freshCopy(...)` carry `multiple` alongside
  `destinationListIdentifier` / `prefixesReminderNumbers` / `showsOnWatch`.
- Merge: no branch — the wholesale coarse-LWW copy already carries it (coverage only).

**Contract**: no new API; every reconstructed checklist carries a valid `multiple`.

**Tests**: `ChecklistStoreTests` duplicate carries multiple; `ChecklistExportTests`
+ `ChecklistImportSessionTests` export→import round-trip + clamp;
`ChecklistMergeTests`/`UbiquitousChecklistSyncTests` remote win copies multiple.
**Verify**: `make test-unit`.

---

## Phase 4: Intent override — one-run multiple with side-effect-free validation

**Outcome**: Running the checklist via the Shortcut with an optional `multiple`
uses that value for this run only; absent → stored value; out-of-range (`0`,
`100`) throws `.invalidMultiple` with a localized message **before** any gate
reserve or reminder creation.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift`,
`CheckStitchCore/.../Resources/Localizable.xcstrings` (Core),
`CheckStitchTests/RunChecklistIntentTests.swift` + `LocalizationFixtures.swift`.

**Key changes**:
- `@Parameter(title: "Multiple") public var multiple: Int?` — new optional.
- `RunChecklistIntentError.invalidMultiple` — new `LocalizedError` case.
- `perform()`: after the `checklistNotFound` guard,
  `if let m = multiple, !Checklist.multipleRange.contains(m) { throw .invalidMultiple }`
  before status pre-check; pass `multipleOverride: multiple` into
  `ChecklistReminders.create`.

**Contract**: `checklistNotFound` unchanged; validation ordering unchanged
(no side effect before throwing).

**Tests**: `RunChecklistIntentTests` — absent → stored, valid override applied,
`0`/`100` → `.invalidMultiple` with no run; `LocalizationTests` Core key.
**Verify**: `make test-unit`; manual Shortcut run.

---

## Phase 5: Hardening — edge cases, i18n completeness, full gate

**Outcome**: No new capability; sad paths and residual risks are pinned and the
whole tree is provably green.

**Files**: resolver/render/intent test suites; `ChecklistScaling` and catalogs
only if a sad path surfaces a fix.

**Key changes**: none new — pin overflow/unmatched/`((0))`/collision behaviour,
Stepper bounds + accessibility label, all 6 languages present.

**Tests**: resolver sad paths, `multiple == 1` fast path, Stepper bounds,
l10n fixtures.
**Verify**: `scripts/l10n-check.sh`; `./scripts/test.sh` → `gate: ok`;
`make watch-build`; installed-bundle Watch render check per AGENTS.md.

---

## Testing Checkpoints

- After **Phase 1**: `make test-unit` green (field/codec/store/resolver/run-path) → advance.
- After **Phase 2**: `make test-unit` + `make watch-build` + `scripts/l10n-check.sh` green → advance.
- After **Phase 3**: `make test-unit` green (duplicate/export/import/merge) → advance.
- After **Phase 4**: `make test-unit` green (intent override + validation) → advance.
- After **Phase 5**: full `./scripts/test.sh` prints `gate: ok`; Watch verified on the installed bundle.
- Never start the next slice while the current slice's tests fail; the full gate runs once, at the end.
