# Task

Style the "New Folder" button so it matches the "Edit" button on the main
screen, in both places that button appears while the app is in edit mode:

- **iOS** (`CheckStitch/ContentView.swift`, the in-content header row inside
  `checklistList`): the `Button("New Folder")` (~line 443, shown when
  `isEditing`) is a bare button, whereas the `editToggleButton` right beside it
  is plated with `.padding(.horizontal, 14)/.padding(.vertical, 6)`,
  `.background { RoundedRectangle(cornerRadius: CardPlate.cornerRadius).fill(CardPlate.iconPlateFill(for: colorScheme)) }`
  and an `.overlay(RoundedRectangle(cornerRadius: CardPlate.cornerRadius).stroke(CardPlate.border(for: colorScheme), lineWidth: 2))`.
  Give the New Folder button the same plating so both buttons in that row render
  identically.

- **macOS** (`CheckStitch/ContentView.swift`, the `#if os(iOS)`-else toolbar):
  the `ToolbarItem` New Folder `Button` (~line 78, shown when
  `!listVM.checklists.isEmpty && isEditing`) is bare while the `editToggleButton` /
  `settingsButton` / `createButton` use the `.checkStitchButton()` modifier.
  Apply the same styling (or `.checkStitchButton()` modifier if it produces the
  Edit-button look) so the toolbar's New Folder button matches the Edit button.

Keep `accessibilityIdentifier("newFolderButton")` on both buttons. The "New
Folder" string key is already registered (both code paths exist), so no
`.xcstrings` change is expected unless a l10n check flags it. Run
`scripts/l10n-check.sh` if in doubt, and verify with `make test-unit` then
`bash scripts/test.sh`. This is a styling mirror — no behaviour, model, or
EventKit changes.

## Why SMALL

A single-file, follow-the-existing-pattern UI styling change (A): one module,
≤1 file, mirrors the adjacent Edit button's plating. No unknowns (B), no
schema/migration (C), no new subsystem or shared/convention code (D), no design
decision or sign-off (E), and tests are few/local UI smoke checks (F).

## Key files

- `CheckStitch/ContentView.swift` — the iOS `checklistList` edit header row
  (~line 443) and the macOS toolbar New Folder `ToolbarItem` (~line 78); mirror
  the `editToggleButton` / `.checkStitchButton()` styling. See
  `CardPlate` / `.checkStitchButton()` for the styling helpers.