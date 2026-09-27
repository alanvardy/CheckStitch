# Task

Add a per-checklist "Show on watch" toggle to the edit-checklist screen(s) of
the CheckStitch iOS app. The toggle is labelled "Show on watch", defaults to
enabled, and when disabled hides that checklist's items on the Apple Watch; a
folder is hidden on the watch when every checklist in it is hidden.

The flag must be persisted in the versioned, iCloud-synced
`ChecklistEnvelope` codec (where absent-key decode-defaults and version-bump
policy are shared, owned conventions), surfaced through the iOS edit-checklist
UI, and honoured by the watch layer when rendering the main list and the folder
detail view.
