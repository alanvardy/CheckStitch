# Task

Implement home-screen widgets for CheckStitch so users can rapidly launch
checklists without opening the app: small widgets bound to a single checklist,
and larger widgets able to trigger multiple checklists at once. This is a new
capability on top of the existing checklist/reminder model.

## Why LARGE
NEW_SURFACE + UNKNOWNS + DESIGN_SIGN-OFF + CROSS_CUTTING — widgets are a brand
new platform interface (which widget framework/size classes the target OS
supports is unknown and must be researched), the small-vs-large widget
behaviour is an unplanned product trade-off needing human sign-off, and the
work spans the core checklist/persistence model, a new widget UI surface, and
per-platform target delivery.