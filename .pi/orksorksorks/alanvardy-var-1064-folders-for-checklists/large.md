# Task

In the CheckStitch app, add Folders: allow the user to create folders on the
main page (folder creation is only revealed via the edit menu), and allow
checklists to be moved in and out of folders. This introduces a new Folder
data entity that checklists belong to, plus UI to create folders and relocate
checklists between "in a folder" and "loose" states on the main checklist
screen.

## Why LARGE

SCHEMA + CROSS_CUTTING (data model/storage and UI surfaces): adding a Folder
entity and a folder relationship on checklists is a data-model/persistence
change, and it ships together with main-page and edit-menu UI across the same
app — a layering/sequence decision with no existing pattern to copy, plus
product trade-offs (how folders display, naming, move menu) that warrant a
design step.

## Key files (recon not run — triggers already met)

Suggested starting points for the design step: the `CheckStitchCore` model layer
(models/checklist list store, persistence) and `CheckStitch/ContentView.swift`
(the sole screen). Confirm exact file layout during design.