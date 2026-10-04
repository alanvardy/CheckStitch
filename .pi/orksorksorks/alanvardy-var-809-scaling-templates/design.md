# Design Discussion

Scaling templates for CheckStitch (VAR-809). Delivery is phased: (1) setting &
persistence, (2) resolution & surfaces, (3) intent override. All work lands on
the main ticket — no child tickets.

## Current State

- `Checklist` (`Checklist.swift:147-190`) carries checklist-level scalars
  (`name`, `destinationListIdentifier`, `prefixesReminderNumbers`,
  `showsOnWatch`, `folderID`) that share **one coarse clock**
  (`revision`/`modifiedAt`, decl ~:182-183; documented at :132-136). Each has a
  `set...` mutator in `ChecklistStore.swift` shaped no-op guard → coarse-clock
  bump → `scheduleSave()` (:311-343 for `setPrefixesReminderNumbers` /
  `setShowsOnWatch`; `rename` :243-256). UI binds these directly, e.g. the
  numbering toggle at `ChecklistDetailView.swift:266`.
- Persistence: `Checklist` implements Codable inline, all additive fields via
  `decodeIfPresent(...) ?? default` (`Checklist.swift:211-243`); encode writes
  every key (:245-263). `ChecklistEnvelope` is versioned at
  `ChecklistCodec.currentVersion = 5` (:476-477); **additive fields need no
  version bump**. `migrated(at:)` (:291-323) seeds legacy field clocks.
- Merge: `ChecklistMerge.merge` copies all coarse scalars wholesale when the
  remote wins the single coarse `wins()` test (`ChecklistMerge.swift:145-157`).
- Run paths: pure resolver `ChecklistTitleNumbering.title(_:position:numbered:itemCount:)`
  (`ChecklistCreator.swift:16-28`) is called at exactly two sites — production
  `ChecklistReminders.create` (`ChecklistReminders.swift:56-57`, also passes raw
  description as notes at :58-59) and test-only `ChecklistCreator.create`
  (`ChecklistCreator.swift:46-68`). Raw `item.title`/`description` are never
  mutated.
- Read-only item renderers: `ItemRow` (`ChecklistDetailView.swift:305-365`,
  title via `displayTitle` :362-365, raw description :343, priority badge HStack
  :326,:339-349) and `WatchChecklistDetailView.swift:57-66`. Editors
  (`ItemEditView.swift`) stay raw. Widget renders no item text.
- Intents: `RunChecklistIntent` has one required `@Parameter checklist`
  (`RunChecklistIntent.swift:20-21`); validation is a `LocalizedError` enum that
  throws before any side effect (`checklistNotFound` guard :52-55, comment :53-55
  on residual TOCTOU), status-only pre-checks :57-66, side effects from :68.
  No `.invalid...` case exists yet.
- Carry points for a new scalar: `duplicate` (:156-189) / `freshCopy` (:195-213)
  carry `destinationListIdentifier`, `prefixesReminderNumbers`, `showsOnWatch`;
  export/share/import flow through the codec (`ChecklistExport.swift:11-19`).
- Localization: 4 Apple xcstrings catalogs (App/Core/Watch/Widget), each key
  needs en/fr/es/de/ja/zh-Hans plus a `LocalizationFixtures.requiredKeys` entry
  (`LocalizationFixtures.swift:8-207`).
- The `((n))` marker and any scaling arithmetic **do not exist** — net-new.

## Desired End State

1. Each `Checklist` has a positive integer `multiple` (default `1`, range
   `1...99`), persisted with the existing codec (no version bump), carried by
   duplicate/import, and editable via a Scaling `Stepper` on the detail screen.
2. A pure resolver replaces every `((n))` marker in an item's title/description
   with `n × multiple` at reminder-creation time; stored text is never rewritten.
   `((n))` is literal `((` + one-or-more digits + `))`; anything else passes
   through byte-for-byte.
3. Read-only surfaces (`ItemRow`, Watch detail) render resolved title **and**
   description; editors render raw. `ItemRow` shows a `×N` badge when
   `multiple > 1`.
4. `RunChecklistIntent` accepts an optional `multiple` override for one run and
   rejects out-of-range values with `.invalidMultiple` before any side effect.

Verify by: `make test-unit` (fast) then `./scripts/test.sh` (gate). Behavioural
proof for surfaces via `ItemRow`/Watch render tests and, for sync/render claims,
the installed bundle per `AGENTS.md`.

## Patterns to Follow

- **New checklist scalar trio** — model field + CodingKeys + `migrated(at:)`
  seeding (`Checklist.swift:147-323`); codec `decodeIfPresent ?? default`
  (:211-243); store mutator with no-op guard → coarse bump → `scheduleSave()`
  (`ChecklistStore.swift:311-343`). Clone `prefixesReminderNumbers` exactly.
- **Pure resolver sibling** — String-in/String-out helper next to
  `ChecklistTitleNumbering.title` in `ChecklistCreator.swift:16-28`; keep the
  existing numbering function and its tests untouched.
- **Validation-before-side-effects** — throwing `LocalizedError` enum, checked
  before `resolveGate()`/`reserveRun()` (`RunChecklistIntent.swift:52-68`);
  runtime message resolved via `LocalizedStringResource(...).resolvedInAppLanguage()`
  in the **Core** catalog.
- **Badge/overlay pattern** — the priority marker's title-HStack badge
  (`ChecklistDetailView.swift:326,:339-349`), hidden when absent.
- **Localization** — App catalog for detail-screen copy, Core for intent
  messages; all 6 languages + `LocalizationFixtures.requiredKeys`; run
  `scripts/l10n-check.sh` first (`conventions.md`).
- **Tests** — Swift Testing structs, behaviour-named functions, `@MainActor` on
  suites touching EventKit/view models; fakes in `TestFixtures.swift`; `@testable
  import CheckStitchCore`.

Patterns **not** to follow: do not add per-field clocks to `multiple` (checklist
scalars intentionally share the coarse clock, `Checklist.swift:132-136`); do not
bump `ChecklistCodec.currentVersion`; do not start a second editing view model
(mutations go straight to the store).

## Design Decisions

1. **Marker grammar** — exact `\(\((\d+)\)\)`: literal `((` + one-or-more ASCII
   digits + `))`, no whitespace/decimal/sign tolerance. Unmatched or non-numeric
   markers are left byte-for-byte unchanged. Applies to **both** title and
   description. Narrowness is safe because stored text is never rewritten.
2. **Scaling arithmetic & bounds** — result is plain `n × multiple`; `((0))` →
   `0`; no upper clamp on the result; a digit string that overflows `Int`
   parsing is treated as a non-match and left literal. `multiple` is bounded by
   the Stepper's `1...99`.
3. **Clamp location** — clamp into `1...99` at **both** ingress points: codec
   (`decodeIfPresent(Int.self) ?? 1` then clamp) and
   `ChecklistStore.setMultiple` (clamp before the no-op guard). Defense in depth
   for hand-edited / imported payloads.
4. **Pure resolver shape & ordering** — new sibling
   `ChecklistScaling.resolve(_ text: String, multiple: Int) -> String` in
   `ChecklistCreator.swift`; String-in/String-out, no model dependency. Each run
   site scales the raw title **before** `ChecklistTitleNumbering.title(...)`
   (scale-then-prefix), and scales the raw description directly. Numbering logic
   unchanged.
5. **Surfaces & badge scope** — resolve title **and** description in `ItemRow`
   and in the Watch detail. `×N` badge only in `ItemRow`'s title HStack, only
   when `multiple > 1`. Watch shows scaled text with no badge. Widget and all
   editors unchanged (raw).
6. **Intent override contract** — `@Parameter public var multiple: Int?`;
   absent → use the checklist's stored value; applies to this run only, never
   persisted. A provided value outside `1...99` throws `.invalidMultiple`, in
   `perform()` after the `checklistNotFound` guard and before the status
   pre-check / any side effect.
7. **Scaling section** — dedicated localized `Section` in `ChecklistDetailView`
   with `Stepper(value:in: 1...99)` wired `set:` → `store.setMultiple`, placed
   adjacent to the existing numbering toggle section (`:266`).
8. **Localization keys** — **App** catalog: scaling section title and a
   `×%lld` factor-badge format string. **Core** catalog: `.invalidMultiple`
   message. No new Watch/Widget keys. Each new key: 6 languages +
   `LocalizationFixtures.requiredKeys`.
9. **Persistence carry points** — carry `multiple` unchanged in `duplicate` and
   `freshCopy` carry lists (`ChecklistStore.swift:156-244`); rely on the codec
   for export/share/import and wholesale coarse copy for merge. No envelope
   version bump; no dedicated merge branch.
10. **Fast path & no-op** — `resolve` returns input unchanged immediately when
    `multiple == 1`; badge hidden at `multiple == 1`; `setMultiple` follows the
    standard no-op guard (`new == current` → `.updated`, no bump); an actual
    change bumps the coarse `revision`/`modifiedAt` and `scheduleSave()`.

## What We're NOT Doing

- Not adding per-field clocks or a dedicated merge branch for `multiple`.
- Not bumping `ChecklistCodec.currentVersion` (additive field only).
- Not rewriting stored titles/descriptions at rest — resolution is read-time
  only.
- Not scaling the checklist `name`, folder names, or anything other than item
  title/description markers.
- Not adding a badge to the Watch detail or the widget.
- Not persisting the intent's `multiple` override.
- Not clamping the scaled result or the marker's `n` to an artificial ceiling.
- Not creating child tickets — all phases ship on the main ticket.

## Open Risks

- **Marker collision**: a user typing a literal `((5))` intending it as text
  will get it scaled; there is no escape syntax. Accepted given "stored text is
  never rewritten" and narrow grammar — flag if it proves surprising.
- **Description on Path B**: the test-only `ChecklistCreator.create` passes no
  descriptions, so description-scaling is only exercised through
  `ChecklistReminders` (Path A) and render tests.
- **Watch render verification**: Watch detail scaling cannot be proven by static
  evidence; AGENTS.md requires installed-bundle verification and a stated
  expected outcome for render/sync tickets.
- **Merge wholesale semantics**: because `multiple` rides the coarse clock, a
  remote win overwrites `multiple` alongside every other checklist scalar; this
  is the intended existing behaviour but means unrelated edits can move
  `multiple` across devices.
