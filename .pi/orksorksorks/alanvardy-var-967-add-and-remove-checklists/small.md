# Task

Add a "Remove Checklist" button to the `EditChecklistView` that dismisses the view and closes the checklist. The button should be placed in the "Items" section alongside the existing "Add Item" button.

## Why SMALL

Single module UI change with no schema changes, no unknowns, and follows the existing pattern already in the codebase.

## Key files (if the recon found any)

- `CheckStitch/ContentView.swift` - Main view that opens `EditChecklistView`
- `CheckStitch/ContentView.swift` - `EditChecklistView` struct where the "Remove Checklist" button should be added