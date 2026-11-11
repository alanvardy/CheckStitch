# Task

On the iPhone Duo's outer (folded) screen in portrait, widen the checklist
content by halving the side padding. The change must be scoped strictly to
that device + orientation — every other screen and orientation keeps its
current layout.

The main screen's list/header card width is driven by
`ChecklistWidth.maxContentWidth` (a `min(340, viewportWidth * 0.6)` fraction
cap) while literal `.padding(.horizontal, 32)` also exists on the card and
empty state, and the repo currently has no device/cover-screen detection.
