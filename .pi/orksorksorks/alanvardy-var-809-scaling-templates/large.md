# Task

Add template **scaling** to CheckStitch: each `Checklist` carries a positive
integer `multiple` (default `1`), and at reminder-creation time each `((n))`
marker in an item's title/description is replaced with `n × multiple` (the
stored text is never rewritten). Add a Scaling `Stepper` (1...99) section on
the detail screen, render scaled text on read-only surfaces while editors stay
raw, and add a "×N" factor badge (only when `multiple > 1`) on rows. Extend the
`RunChecklistIntent` with an optional `multiple` override (+ `.invalidMultiple`
validation with side-effect-free ordering).

## Why LARGE

Matched triggers: **SCHEMA**, **CONVENTION_RISK**, **CROSS_CUTTING**.

A genuine data-model change: `multiple` is persisted on `Checklist` and must be
threaded through the codec (`decodeIfPresent ?? 1`, clamp `≤0` to `1`, no
envelope bump), merge (remote-wins), duplicate, `freshCopy`/import, export and
share. It touches shared persistence formats and **both** creator run paths
(`ChecklistReminders.create`, `ChecklistCreator.create`), and spans data
model/storage, iOS/macOS/watch UI surfaces, and the App Intents contract in one
PR — LARGE per the design-class decision rule even though the spec is
well-prescribed. Delivery is deliberately phased (setting/persistence →
resolution/surfaces → intent override) and heavily tested.

## Delivery phases

1. **Setting & persistence** — `multiple` field + `setMultiple` (no-op guard,
   revision/`modifiedAt` bump), Scaling section, codec / merge / duplicate /
   import / export / share, localization baseline.
2. **Resolution & surfaces** — pure resolution function (sibling of
   `ChecklistTitleNumbering`), both run paths wired, read-only surfaces
   resolve (iOS/macOS/watch) while editors stay raw, factor badge, scale-then-prefix order.
3. **Intent override** — `multiple` parameter, `.invalidMultiple`, validation-first ordering.