# Task

CheckStitch lets a user create Checklists of items and run a checklist to
bulk-create one Reminder per item. This ticket adds a priority to checklist
items: an info button on the right of each item row in the edit-checklist
screen opens an overlay for selecting the item's priority. The priority must
persist on the synced `ChecklistItem` model, so it must flow through the
`Codable` codec, store, sync/merge, and import/export surfaces while
preserving back-compat with existing payloads.