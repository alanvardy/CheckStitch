# Task

Let a checklist's destination be a "prompt" state instead of a concrete
destination, so the user picks the destination at the moment they run the
checklist rather than when configuring it. The prompt must also fire when a
checklist is run through an App Intent / Shortcut, so the persisted destination
model, the run-time UI, and every intent entry point have to agree on the new
state.