# Task

`ChecklistMerge.mergedItems` resolves an item conflict by replacing the whole
`ChecklistItem` with the last-write-wins winner. That was safe while `title`
was the only user-editable item field; since `description` (VAR-999), an item
has two independent editable fields, so whole-item LWW makes a title edit on
one device clobber a description edit on another (or resurrect an older value)
based solely on which revision is higher. The two edits are logically
independent and should both survive.

The ticket proposes three designs and leaves the choice open: (1) field-level
LWW with per-field sync state (`titleRevision`/`titleModifiedAt`,
`descriptionRevision`/`descriptionModifiedAt`) — correct but a schema/codec
change plus merge logic and tests; (2) keep whole-item LWW for deletion and
identity, add per-field clocks only for the mutable text fields; (3) accept
and document the limitation (cheapest, user-visible data loss). Recommend and
implement option 1 or 2; whichever is chosen needs merge tests covering
concurrent title+description edits from two devices.